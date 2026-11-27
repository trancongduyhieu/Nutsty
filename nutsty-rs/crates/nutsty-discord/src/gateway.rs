//! The status straight on Discord's servers, for when the Discord app is not on this computer
//! (Discord in a browser, on a phone, or not open at all). Signed in with the OAuth token from
//! auth.rs, the way Discord's Social SDK does it: a gateway websocket, IDENTIFY, then op 3
//! PRESENCE_UPDATE. The status lasts as long as the connection, so a killed helper takes it down.
//!
//! One thread owns the socket; the rest of the helper talks to it over a channel.

use rustls::pki_types::ServerName;
use serde_json::{json, Value};
use std::io;
use std::net::{TcpStream, ToSocketAddrs};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::mpsc::{channel, Receiver, RecvTimeoutError, Sender};
use std::sync::{Arc, OnceLock};
use std::time::{Duration, Instant};
use tungstenite::protocol::frame::coding::CloseCode;
use tungstenite::{Message, WebSocket};

const HOST: &str = "gateway.discord.gg";
const URL: &str = "wss://gateway.discord.gg/?v=10&encoding=json";
const READY_WAIT: Duration = Duration::from_secs(20);
/// How often the socket thread looks up from a read to send what is queued.
const TICK: Duration = Duration::from_millis(200);

/// Discord closes with this when the token is no good any more.
const CLOSE_AUTH_FAILED: u16 = 4004;

// What the Social SDK sends (Mochy's numbers); friends' presence is left out on purpose.
const CAPABILITIES: u64 = (1 << 4) | (1 << 5) | (1 << 12) | (1 << 16);
const INTENTS: u64 = (1 << 12) | (1 << 18) | (1 << 19) | (1 << 22) | (1 << 27) | (1 << 28) | (1 << 29);

type Tls = rustls::StreamOwned<rustls::ClientConnection, TcpStream>;

#[derive(Debug, PartialEq)]
pub enum OpenError {
    /// the token was turned down: renew it, or sign in again
    Auth,
    Other,
}

enum Cmd {
    Set(Option<Value>),
    Close,
}

pub struct Session {
    tx: Sender<Cmd>,
    closed: Arc<AtomicBool>,
    thread: Option<std::thread::JoinHandle<()>>,
}

fn tls_config() -> Arc<rustls::ClientConfig> {
    static CONFIG: OnceLock<Arc<rustls::ClientConfig>> = OnceLock::new();
    CONFIG
        .get_or_init(|| {
            let roots = rustls::RootCertStore { roots: webpki_roots::TLS_SERVER_ROOTS.to_vec() };
            let provider = Arc::new(rustls::crypto::ring::default_provider());
            Arc::new(
                rustls::ClientConfig::builder_with_provider(provider)
                    .with_safe_default_protocol_versions()
                    .expect("ring supports the default TLS versions")
                    .with_root_certificates(roots)
                    .with_no_client_auth(),
            )
        })
        .clone()
}

fn connect() -> io::Result<WebSocket<Tls>> {
    let addr = (HOST, 443)
        .to_socket_addrs()?
        .next()
        .ok_or_else(|| io::Error::new(io::ErrorKind::NotFound, "gateway has no address"))?;
    let tcp = TcpStream::connect_timeout(&addr, Duration::from_secs(10))?;
    tcp.set_read_timeout(Some(Duration::from_secs(15)))?;
    tcp.set_write_timeout(Some(Duration::from_secs(10)))?;
    let name = ServerName::try_from(HOST).map_err(|e| io::Error::other(e.to_string()))?;
    let conn = rustls::ClientConnection::new(tls_config(), name).map_err(io::Error::other)?;
    let tls = rustls::StreamOwned::new(conn, tcp);
    let (ws, _) = tungstenite::client(URL, tls).map_err(|e| io::Error::other(e.to_string()))?;
    // from here on a read gives up after a short while, so queued updates go out on time
    ws.get_ref().sock.set_read_timeout(Some(TICK))?;
    Ok(ws)
}

fn is_timeout(e: &tungstenite::Error) -> bool {
    matches!(e, tungstenite::Error::Io(io) if matches!(io.kind(), io::ErrorKind::WouldBlock | io::ErrorKind::TimedOut))
}

/// A number in 0..1, for the first heartbeat's random delay.
fn unit_random() -> f64 {
    let mut b = [0u8; 4];
    let _ = getrandom::fill(&mut b);
    u32::from_le_bytes(b) as f64 / u32::MAX as f64
}

fn presence(activity: &Option<Value>) -> Value {
    json!({
        "op": 3,
        "d": {
            "since": Value::Null,
            "activities": activity.iter().cloned().collect::<Vec<_>>(),
            "status": "online",
            "afk": false,
        }
    })
}

fn identify(token: &str) -> Value {
    let os = if cfg!(windows) { "Windows" } else { "Linux" };
    json!({
        "op": 2,
        "d": {
            "token": format!("Bearer {token}"),
            "capabilities": CAPABILITIES,
            "intents": INTENTS,
            "properties": { "os": os, "browser": "Nutsty", "device": "Nutsty" },
        }
    })
}

fn send(ws: &mut WebSocket<Tls>, v: &Value) -> bool {
    ws.send(Message::text(v.to_string())).is_ok()
}

/// The socket thread: HELLO, IDENTIFY, heartbeats, and whatever status is asked for.
fn run(mut ws: WebSocket<Tls>, token: String, rx: Receiver<Cmd>, ready: Sender<Result<(), OpenError>>, closed: Arc<AtomicBool>) {
    let mut ready = Some(ready);
    let mut is_ready = false;
    let mut sequence: Option<i64> = None;
    let mut interval: Option<Duration> = None;
    let mut next_beat = Instant::now() + Duration::from_secs(3600);
    let mut acked = true;
    let mut pending: Option<Option<Value>> = None;
    let fail = |ready: &mut Option<Sender<Result<(), OpenError>>>, e: OpenError| {
        if let Some(r) = ready.take() {
            let _ = r.send(Err(e));
        }
    };
    let mut deadline = Some(Instant::now() + READY_WAIT);
    'outer: loop {
        // what the rest of the helper asked for since the last look
        loop {
            match rx.try_recv() {
                Ok(Cmd::Set(a)) => pending = Some(a),
                Ok(Cmd::Close) | Err(std::sync::mpsc::TryRecvError::Disconnected) => {
                    if is_ready {
                        let _ = send(&mut ws, &presence(&None));
                    }
                    let _ = ws.close(None);
                    let _ = ws.flush();
                    break 'outer;
                }
                Err(std::sync::mpsc::TryRecvError::Empty) => break,
            }
        }
        if is_ready
            && let Some(a) = pending.take()
            && !send(&mut ws, &presence(&a)) {
                break;
            }
        if deadline.is_some_and(|d| Instant::now() >= d) {
            fail(&mut ready, OpenError::Other);
            break;
        }
        if let Some(every) = interval
            && Instant::now() >= next_beat {
            if !acked {
                // no answer to the last beat: the connection is dead even if the socket isn't
                break;
            }
            acked = false;
            if !send(&mut ws, &json!({ "op": 1, "d": sequence })) {
                break;
            }
            next_beat = Instant::now() + every;
        }
        let msg = match ws.read() {
            Ok(m) => m,
            Err(e) if is_timeout(&e) => continue,
            Err(_) => break,
        };
        let text = match msg {
            Message::Text(t) => t.to_string(),
            Message::Close(frame) => {
                let code = frame.map(|f| u16::from(f.code)).unwrap_or(1000);
                fail(&mut ready, if code == CLOSE_AUTH_FAILED { OpenError::Auth } else { OpenError::Other });
                break;
            }
            _ => continue,
        };
        let Ok(v) = serde_json::from_str::<Value>(&text) else { continue };
        if let Some(s) = v.get("s").and_then(Value::as_i64) {
            sequence = Some(s);
        }
        match v.get("op").and_then(Value::as_i64) {
            Some(10) => {
                let ms = v["d"]["heartbeat_interval"].as_u64().unwrap_or(41_250);
                interval = Some(Duration::from_millis(ms));
                // Discord asks for a random first beat, so reconnecting clients spread out
                next_beat = Instant::now() + Duration::from_millis((ms as f64 * unit_random()) as u64);
                if !send(&mut ws, &identify(&token)) {
                    break;
                }
            }
            Some(11) => acked = true,
            Some(1) => {
                if !send(&mut ws, &json!({ "op": 1, "d": sequence })) {
                    break;
                }
            }
            // Discord wants a fresh connection; the owner makes one
            Some(7) | Some(9) => break,
            Some(0) if v.get("t").and_then(Value::as_str) == Some("READY") => {
                is_ready = true;
                deadline = None;
                if let Some(r) = ready.take() {
                    let _ = r.send(Ok(()));
                }
            }
            _ => {}
        }
    }
    fail(&mut ready, OpenError::Other);
    closed.store(true, Ordering::Relaxed);
    let _ = ws.close(Some(tungstenite::protocol::CloseFrame { code: CloseCode::Normal, reason: "".into() }));
    let _ = ws.flush();
}

impl Session {
    /// Connects and waits until Discord says the session is ready.
    pub fn open(token: &str) -> Result<Session, OpenError> {
        let ws = connect().map_err(|e| {
            eprintln!("[nutsty-discord] gateway: {e}");
            OpenError::Other
        })?;
        let (tx, rx) = channel();
        let (ready_tx, ready_rx) = channel();
        let closed = Arc::new(AtomicBool::new(false));
        let thread_closed = closed.clone();
        let token = token.to_string();
        let thread = std::thread::spawn(move || run(ws, token, rx, ready_tx, thread_closed));
        let session = Session { tx, closed, thread: Some(thread) };
        match ready_rx.recv_timeout(READY_WAIT + Duration::from_secs(2)) {
            Ok(Ok(())) => Ok(session),
            Ok(Err(e)) => Err(e),
            Err(RecvTimeoutError::Timeout) | Err(RecvTimeoutError::Disconnected) => Err(OpenError::Other),
        }
    }

    pub fn is_closed(&self) -> bool {
        self.closed.load(Ordering::Relaxed)
    }

    pub fn set_activity(&self, activity: Option<Value>) -> io::Result<()> {
        if self.is_closed() {
            return Err(io::Error::new(io::ErrorKind::BrokenPipe, "gateway closed"));
        }
        self.tx.send(Cmd::Set(activity)).map_err(|_| io::Error::new(io::ErrorKind::BrokenPipe, "gateway closed"))
    }

    /// Takes the status down and closes, waiting a moment for that to go out.
    pub fn close(mut self) {
        let _ = self.tx.send(Cmd::Close);
        if let Some(t) = self.thread.take() {
            let until = Instant::now() + Duration::from_millis(1500);
            while !t.is_finished() && Instant::now() < until {
                std::thread::sleep(Duration::from_millis(20));
            }
        }
    }
}

impl Drop for Session {
    fn drop(&mut self) {
        let _ = self.tx.send(Cmd::Close);
    }
}

// ---------------------------------------------------------------------------------------------
// Pictures
// ---------------------------------------------------------------------------------------------

/// Over the gateway a picture has to be an asset Discord knows; a web address becomes one by
/// registering it (`mp:external/...`). Answers are kept, and turned-down addresses remembered.
pub struct Pictures {
    known: std::collections::HashMap<String, Option<String>>,
}

impl Pictures {
    pub fn new() -> Self {
        Pictures { known: Default::default() }
    }

    /// The asset for each address, registering the new ones in one call. None: Discord said no
    /// (or could not be asked), and the picture is left out.
    pub fn assets(&mut self, client_id: &str, token: &str, urls: &[&str]) -> Vec<Option<String>> {
        let fresh: Vec<&str> = urls.iter().copied().filter(|u| !self.known.contains_key(*u)).collect();
        if !fresh.is_empty() {
            let reply = crate::auth::agent()
                .post(format!("https://discord.com/api/v10/applications/{client_id}/external-assets"))
                .header("Authorization", format!("Bearer {token}"))
                .header("Content-Type", "application/json")
                .send(json!({ "urls": fresh }).to_string());
            match reply {
                Ok(mut resp) if resp.status().as_u16() == 200 => {
                    let v: Value = serde_json::from_str(&resp.body_mut().read_to_string().unwrap_or_default()).unwrap_or(Value::Null);
                    for (i, url) in fresh.iter().enumerate() {
                        let path = v.get(i).and_then(|o| o.get("external_asset_path")).and_then(Value::as_str);
                        self.known.insert(url.to_string(), path.map(|p| format!("mp:{p}")));
                    }
                }
                // a 401 means the token went stale; the next connection renews it, try again then
                Ok(resp) if resp.status().as_u16() == 401 => {}
                Ok(resp) => {
                    eprintln!("[nutsty-discord] pictures turned down: HTTP {}", resp.status().as_u16());
                    for url in &fresh {
                        self.known.insert(url.to_string(), None);
                    }
                }
                Err(_) => {}
            }
        }
        urls.iter().map(|u| self.known.get(*u).cloned().flatten()).collect()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Reaches the real gateway (network): TLS, the websocket, HELLO, IDENTIFY and the close code.
    /// Run with `cargo test -p nutsty-discord -- --ignored`.
    #[test]
    #[ignore]
    fn gateway_turns_down_a_bad_token() {
        assert_eq!(Session::open("not-a-real-token").err(), Some(OpenError::Auth));
    }
}
