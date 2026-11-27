//! nutsty-discord: keeps the user's Discord status ("Listening to Nutsty") in step with the player.
//!
//! Nutsty starts it while the Settings switch is on and writes one JSON line per change to stdin:
//! the song (`details`, `state`, `cover`, `position`, `duration`, `playing`, ...) or `{"clear":true}`.
//! It answers with status lines on stdout (`{"status":"live"|"waiting"|"idle"}`) for the line
//! under the switch. When stdin closes (switch off, app quit) it clears the status and exits;
//! if it is killed instead, Discord drops the status itself when the socket closes.
//!
//! Two ways to reach Discord. The Discord app on this computer (local IPC) comes first and needs
//! no sign-in. When it is not there and the user signed in with "Sign in with Discord"
//! (`{"login":true}`), the status goes straight to Discord's servers over the gateway instead,
//! which works with Discord open in a browser, on a phone, or not open at all.
//! Account lines on stdout: `{"account":{"name":...}}` / `{"account":null}`,
//! `{"open_url":...}` for the sign-in page, `{"login":"failed","reason":...}`.

mod auth;
mod gateway;
mod ipc;
mod presence;

use presence::{Activity, SendBudget, KEEP_PAUSED_MS};
use serde_json::{json, Value};
use std::io::Write;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::mpsc::{channel, Receiver, RecvTimeoutError, Sender};
use std::sync::Arc;
use std::time::{Duration, SystemTime, UNIX_EPOCH};

/// The "Nutsty" application on Discord's developer portal. Its name is what Discord shows.
const CLIENT_ID: &str = "1575722061588856832";
/// Waits between tries while Discord is closed, longer each time.
const BACKOFF_MS: [i64; 5] = [2_000, 5_000, 15_000, 30_000, 60_000];
/// While on the gateway, how often to look whether the Discord app has opened on this computer.
const APP_CHECK_MS: i64 = 15_000;

fn now_ms() -> i64 {
    SystemTime::now().duration_since(UNIX_EPOCH).map(|d| d.as_millis() as i64).unwrap_or(0)
}

fn say_json(v: &Value) {
    let mut out = std::io::stdout().lock();
    let _ = writeln!(out, "{v}");
    let _ = out.flush();
}

fn say(status: &str) {
    say_json(&json!({ "status": status }));
}

fn say_account(token: Option<&auth::Token>) {
    say_json(&json!({ "account": token.map(|t| json!({ "name": t.user_name, "avatar": t.avatar_url })) }));
}

/// The way the status is reaching Discord right now.
enum Link {
    App(ipc::Connection),
    Account { session: gateway::Session, token: String, next_app_check: i64 },
}

impl Link {
    fn is_closed(&self) -> bool {
        match self {
            Link::App(c) => c.is_closed(),
            Link::Account { session, .. } => session.is_closed(),
        }
    }

    fn close(self) {
        match self {
            Link::App(c) => {
                // clear first: closing alone can leave the old song up for a moment
                let _ = c.set_activity(None);
                std::thread::sleep(Duration::from_millis(100));
            }
            Link::Account { session, .. } => session.close(),
        }
    }
}

/// What the sign-in thread tells the main loop.
enum AccountEvent {
    SignedIn,
    SignedOut,
}

struct Presence {
    client_id: String,
    conn: Option<Link>,
    pictures: gateway::Pictures,
    account_tx: Sender<AccountEvent>,
    login_cancel: Option<Arc<AtomicBool>>,
    /// what Discord should show now; None means nothing
    wanted: Option<Activity>,
    /// what Discord was last told on this connection
    shown: Option<Option<Activity>>,
    paused_since: Option<i64>,
    failures: usize,
    next_try_at: i64,
    budget: SendBudget,
    last_status: &'static str,
}

impl Presence {
    fn status(&mut self, s: &'static str) {
        if self.last_status != s {
            self.last_status = s;
            say(s);
        }
    }

    fn take(&mut self, line: &str, now: i64) {
        let Ok(v) = serde_json::from_str::<Value>(line) else { return };
        if v.get("login").and_then(Value::as_bool) == Some(true) {
            let vi = v.get("lang").and_then(Value::as_str) != Some("en");
            self.start_login(vi);
            return;
        }
        if v.get("login_cancel").and_then(Value::as_bool) == Some(true) {
            if let Some(c) = self.login_cancel.take() {
                c.store(true, Ordering::Relaxed);
            }
            return;
        }
        if v.get("logout").and_then(Value::as_bool) == Some(true) {
            self.sign_out();
            return;
        }
        if v.get("clear").and_then(Value::as_bool) == Some(true) {
            self.wanted = None;
            self.paused_since = None;
            return;
        }
        let next = Activity::from_report(&v, now);
        // the pause clock starts when the song stops moving, and keeps running while it stays put
        let still_paused = |a: &Activity| self.wanted.as_ref().is_some_and(|w| !w.playing && w.details == a.details);
        self.paused_since = match &next {
            Some(a) if !a.playing => self.paused_since.filter(|_| still_paused(a)).or(Some(now)),
            _ => None,
        };
        self.wanted = next;
    }

    fn up_to_date(&self) -> bool {
        match (&self.shown, &self.wanted) {
            (Some(None), None) => true,
            (Some(Some(a)), Some(b)) => a.looks_like(b),
            (None, None) => self.conn.is_none(),
            _ => false,
        }
    }

    /// Brings Discord in line with `wanted`. Returns how long to wait before looking again.
    fn sync(&mut self, now: i64) -> i64 {
        if let Some(since) = self.paused_since
            && now - since >= KEEP_PAUSED_MS {
                self.wanted = None;
                self.paused_since = None;
            }
        if self.conn.as_ref().is_some_and(|c| c.is_closed()) {
            self.drop_connection(now);
        }
        self.prefer_app(now);
        if self.up_to_date() {
            if self.wanted.is_none() {
                self.status("idle");
            }
            return 1_000;
        }
        if self.conn.is_none() {
            if self.wanted.is_none() {
                self.shown = None;
                self.status("idle");
                return 1_000;
            }
            if now < self.next_try_at {
                return (self.next_try_at - now).min(1_000);
            }
            match self.open_link() {
                Some(link) => {
                    self.conn = Some(link);
                    self.failures = 0;
                    self.shown = None;
                }
                None => {
                    self.retry_later(now_ms());
                    self.status("waiting");
                    return 1_000;
                }
            }
        }
        let wait = self.budget.wait_ms(now);
        if wait > 0 {
            return wait.min(1_000);
        }
        let sent = match self.conn.as_ref() {
            Some(Link::App(c)) => Some(c.set_activity(self.wanted.as_ref().map(Activity::to_json))),
            Some(Link::Account { session, token, .. }) => {
                let payload = self.wanted.as_ref().map(|a| {
                    let pics = self.pictures.assets(&self.client_id, token, &a.picture_urls());
                    a.to_gateway_json(&self.client_id, pics.first().cloned().flatten(), pics.get(1).cloned().flatten())
                });
                Some(session.set_activity(payload))
            }
            None => None,
        };
        match sent {
            Some(Ok(())) => {
                self.budget.record(now);
                self.shown = Some(self.wanted.clone());
                self.status(self.live_status());
            }
            _ => self.drop_connection(now),
        }
        1_000
    }

    fn live_status(&self) -> &'static str {
        match (&self.wanted, &self.conn) {
            (None, _) => "idle",
            (Some(_), Some(Link::Account { .. })) => "live_web",
            _ => "live",
        }
    }

    /// The Discord app on this computer first; else the signed-in account over the gateway.
    fn open_link(&mut self) -> Option<Link> {
        if let Ok(c) = ipc::Connection::open(&self.client_id) {
            return Some(Link::App(c));
        }
        let token = match auth::usable(&self.client_id) {
            Ok(t) => t,
            Err(auth::Fail::SignedOut) => return None,
            Err(_) => return None,
        };
        match gateway::Session::open(&token.access) {
            Ok(session) => Some(self.account_link(session, token.access)),
            // turned down: one renewal, then the token is gone for good
            Err(gateway::OpenError::Auth) => match auth::renew(&self.client_id, &token) {
                Ok(fresh) => {
                    let _ = auth::save(&fresh);
                    let session = gateway::Session::open(&fresh.access).ok()?;
                    Some(self.account_link(session, fresh.access))
                }
                Err(auth::Fail::SignedOut) => {
                    auth::forget();
                    say_account(None);
                    None
                }
                Err(_) => None,
            },
            Err(gateway::OpenError::Other) => None,
        }
    }

    fn account_link(&self, session: gateway::Session, token: String) -> Link {
        Link::Account { session, token, next_app_check: now_ms() + APP_CHECK_MS }
    }

    /// On the gateway, the Discord app opening on this computer takes over: it is what people
    /// expect, and two sessions would show the song twice.
    fn prefer_app(&mut self, now: i64) {
        let Some(Link::Account { next_app_check, .. }) = self.conn.as_mut() else { return };
        if now < *next_app_check {
            return;
        }
        *next_app_check = now + APP_CHECK_MS;
        if let Ok(c) = ipc::Connection::open(&self.client_id)
            && let Some(old) = self.conn.replace(Link::App(c)) {
                old.close();
                self.shown = None;
            }
    }

    fn start_login(&mut self, vi: bool) {
        if let Some(c) = self.login_cancel.take() {
            c.store(true, Ordering::Relaxed);
        }
        let cancel = Arc::new(AtomicBool::new(false));
        self.login_cancel = Some(cancel.clone());
        let client_id = self.client_id.clone();
        let tx = self.account_tx.clone();
        std::thread::spawn(move || {
            // a sign-in that is still waiting gives its port up within a moment
            std::thread::sleep(Duration::from_millis(400));
            let result = auth::login(&client_id, vi, cancel, |url| say_json(&json!({ "open_url": url })));
            let mut detail = String::new();
            let reason = match result {
                Ok(token) => {
                    say_account(Some(&token));
                    let _ = tx.send(AccountEvent::SignedIn);
                    return;
                }
                Err(auth::LoginError::Cancelled) => return,
                Err(auth::LoginError::Port) => "port",
                Err(auth::LoginError::Denied(why)) => {
                    detail = why;
                    "denied"
                }
                Err(auth::LoginError::Timeout) => "timeout",
                Err(auth::LoginError::Network) => "network",
            };
            say_json(&json!({ "login": "failed", "reason": reason, "detail": detail }));
        });
    }

    fn sign_out(&mut self) {
        if let Some(c) = self.login_cancel.take() {
            c.store(true, Ordering::Relaxed);
        }
        if matches!(self.conn, Some(Link::Account { .. })) {
            if let Some(link) = self.conn.take() {
                link.close();
            }
            self.shown = None;
        }
        let client_id = self.client_id.clone();
        let tx = self.account_tx.clone();
        std::thread::spawn(move || {
            auth::sign_out(&client_id);
            let _ = tx.send(AccountEvent::SignedOut);
        });
        say_account(None);
    }

    fn account_event(&mut self, e: AccountEvent) {
        match e {
            // a new sign-in is worth trying at once, not after the backoff
            AccountEvent::SignedIn => {
                self.failures = 0;
                self.next_try_at = 0;
            }
            AccountEvent::SignedOut => {}
        }
    }

    fn drop_connection(&mut self, now: i64) {
        self.conn = None;
        self.shown = None;
        self.retry_later(now);
        self.status("waiting");
    }

    fn retry_later(&mut self, now: i64) {
        self.next_try_at = now + BACKOFF_MS[self.failures.min(BACKOFF_MS.len() - 1)];
        self.failures += 1;
    }
}

fn main() {
    let client_id = std::env::var("NUTSTY_DISCORD_CLIENT_ID").unwrap_or_else(|_| CLIENT_ID.to_string());
    let lines = ipc::stdin_lines();
    let (account_tx, account_rx): (Sender<AccountEvent>, Receiver<AccountEvent>) = channel();
    let mut p = Presence {
        client_id,
        conn: None,
        pictures: gateway::Pictures::new(),
        account_tx,
        login_cancel: None,
        wanted: None,
        shown: None,
        paused_since: None,
        failures: 0,
        next_try_at: 0,
        budget: SendBudget::new(),
        last_status: "",
    };
    p.status("idle");
    let saved = auth::load();
    say_account(saved.as_ref());
    // the name and picture may have changed on Discord since the sign-in
    if saved.is_some() {
        std::thread::spawn(|| {
            if let Some(t) = auth::refresh_profile() {
                say_account(Some(&t));
            }
        });
    }
    let mut wait_ms = 1_000;
    loop {
        let mut ended = false;
        match lines.recv_timeout(Duration::from_millis(wait_ms.max(10) as u64)) {
            Ok(Some(line)) => {
                p.take(&line, now_ms());
                // a burst of lines (a skip, a seek drag) settles before anything is sent
                let settle_until = now_ms() + 1_000;
                while now_ms() < settle_until {
                    match lines.recv_timeout(Duration::from_millis(150)) {
                        Ok(Some(more)) => p.take(&more, now_ms()),
                        Ok(None) | Err(RecvTimeoutError::Disconnected) => {
                            ended = true;
                            break;
                        }
                        Err(RecvTimeoutError::Timeout) => break,
                    }
                }
            }
            Ok(None) | Err(RecvTimeoutError::Disconnected) => ended = true,
            Err(RecvTimeoutError::Timeout) => {}
        }
        if ended {
            break;
        }
        while let Ok(e) = account_rx.try_recv() {
            p.account_event(e);
        }
        wait_ms = p.sync(now_ms());
    }
    if let Some(c) = p.login_cancel.take() {
        c.store(true, Ordering::Relaxed);
    }
    if let Some(link) = p.conn.take() {
        link.close();
    }
}
