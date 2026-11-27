//! nutsty-discord: keeps the user's Discord status ("Listening to Nutsty") in step with the player.
//!
//! Nutsty starts it while the Settings switch is on and writes one JSON line per change to stdin:
//! the song (`details`, `state`, `cover`, `position`, `duration`, `playing`, ...) or `{"clear":true}`.
//! It answers with status lines on stdout (`{"status":"live"|"waiting"|"idle"}`) for the line
//! under the switch. When stdin closes (switch off, app quit) it clears the status and exits;
//! if it is killed instead, Discord drops the status itself when the socket closes.

mod ipc;
mod presence;

use presence::{Activity, SendBudget, KEEP_PAUSED_MS};
use serde_json::Value;
use std::io::Write;
use std::sync::mpsc::RecvTimeoutError;
use std::time::{Duration, SystemTime, UNIX_EPOCH};

/// The "Nutsty" application on Discord's developer portal. Its name is what Discord shows.
const CLIENT_ID: &str = "1575722061588856832";
/// Waits between tries while Discord is closed, longer each time.
const BACKOFF_MS: [i64; 5] = [2_000, 5_000, 15_000, 30_000, 60_000];

fn now_ms() -> i64 {
    SystemTime::now().duration_since(UNIX_EPOCH).map(|d| d.as_millis() as i64).unwrap_or(0)
}

fn say(status: &str) {
    let mut out = std::io::stdout().lock();
    let _ = writeln!(out, "{{\"status\":\"{status}\"}}");
    let _ = out.flush();
}

struct Presence {
    client_id: String,
    conn: Option<ipc::Connection>,
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
            match ipc::Connection::open(&self.client_id) {
                Ok(c) => {
                    self.conn = Some(c);
                    self.failures = 0;
                    self.shown = None;
                }
                Err(_) => {
                    self.retry_later(now);
                    self.status("waiting");
                    return 1_000;
                }
            }
        }
        let wait = self.budget.wait_ms(now);
        if wait > 0 {
            return wait.min(1_000);
        }
        let payload = self.wanted.as_ref().map(Activity::to_json);
        let sent = self.conn.as_ref().map(|c| c.set_activity(payload));
        match sent {
            Some(Ok(())) => {
                self.budget.record(now);
                self.shown = Some(self.wanted.clone());
                self.status(if self.wanted.is_some() { "live" } else { "idle" });
            }
            _ => self.drop_connection(now),
        }
        1_000
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
    let mut p = Presence {
        client_id,
        conn: None,
        wanted: None,
        shown: None,
        paused_since: None,
        failures: 0,
        next_try_at: 0,
        budget: SendBudget::new(),
        last_status: "",
    };
    p.status("idle");
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
        wait_ms = p.sync(now_ms());
    }
    // clear first: closing alone can leave the old song up for a moment
    if let Some(c) = p.conn.take() {
        let _ = c.set_activity(None);
        std::thread::sleep(Duration::from_millis(100));
    }
}
