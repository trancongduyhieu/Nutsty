//! Discord's local IPC: the desktop app listens on `discord-ipc-0..9` (a Unix socket on Linux,
//! a named pipe on Windows). Each frame is opcode (u32 LE) + length (u32 LE) + JSON. No login:
//! the running Discord client shows whatever activity the connected app sets.

use serde_json::{json, Value};
use std::io::{self, Read, Write};
use std::path::PathBuf;
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::mpsc::{self, Receiver};
use std::sync::{Arc, Mutex};
use std::thread;
use std::time::Duration;

const OP_HANDSHAKE: u32 = 0;
const OP_FRAME: u32 = 1;
const OP_CLOSE: u32 = 2;
const OP_PING: u32 = 3;
const OP_PONG: u32 = 4;

/// A frame bigger than this is not Discord talking; stop reading rather than allocate it.
const FRAME_MAX: usize = 64 * 1024;
const READY_WAIT: Duration = Duration::from_secs(4);

#[cfg(unix)]
type Pipe = std::os::unix::net::UnixStream;
#[cfg(windows)]
type Pipe = std::fs::File;

/// The places Discord (and its Flatpak / Snap / Vesktop builds) put the socket.
#[cfg(unix)]
fn candidates() -> Vec<PathBuf> {
    let mut roots: Vec<PathBuf> = ["XDG_RUNTIME_DIR", "TMPDIR", "TMP", "TEMP"]
        .iter()
        .filter_map(std::env::var_os)
        .map(PathBuf::from)
        .collect();
    roots.push(PathBuf::from("/tmp"));
    let subdirs = [
        "",
        "app/com.discordapp.Discord",
        "app/com.discordapp.DiscordCanary",
        "app/dev.vencord.Vesktop",
        ".flatpak/dev.vencord.Vesktop/xdg-run",
        "snap.discord",
        "snap.discord-canary",
    ];
    let mut out = Vec::new();
    for i in 0..10 {
        for root in &roots {
            for sub in subdirs {
                let p = root.join(sub).join(format!("discord-ipc-{i}"));
                if !out.contains(&p) {
                    out.push(p);
                }
            }
        }
    }
    out
}

#[cfg(windows)]
fn candidates() -> Vec<PathBuf> {
    (0..10).map(|i| PathBuf::from(format!(r"\\.\pipe\discord-ipc-{i}"))).collect()
}

#[cfg(unix)]
fn open(path: &PathBuf) -> io::Result<Pipe> {
    let s = Pipe::connect(path)?;
    // a Discord that stopped reading must not hang Nutsty's helper forever
    s.set_write_timeout(Some(Duration::from_secs(3)))?;
    Ok(s)
}

#[cfg(windows)]
fn open(path: &PathBuf) -> io::Result<Pipe> {
    std::fs::OpenOptions::new().read(true).write(true).open(path)
}

/// Blocks until a frame header can be read. On Windows a blocking read on a synchronous pipe
/// handle also blocks writes through its clone, so the reader peeks first and only reads once
/// Discord has sent something.
#[cfg(windows)]
fn wait_readable(pipe: &Pipe) -> io::Result<()> {
    use std::os::windows::io::AsRawHandle;
    unsafe extern "system" {
        fn PeekNamedPipe(
            pipe: *mut std::ffi::c_void,
            buffer: *mut std::ffi::c_void,
            size: u32,
            read: *mut u32,
            avail: *mut u32,
            left: *mut u32,
        ) -> i32;
    }
    loop {
        let mut avail: u32 = 0;
        let ok = unsafe {
            PeekNamedPipe(
                pipe.as_raw_handle() as *mut _,
                std::ptr::null_mut(),
                0,
                std::ptr::null_mut(),
                &mut avail,
                std::ptr::null_mut(),
            )
        };
        if ok == 0 {
            return Err(io::Error::last_os_error());
        }
        if avail >= 8 {
            return Ok(());
        }
        thread::sleep(Duration::from_millis(50));
    }
}

#[cfg(unix)]
fn wait_readable(_pipe: &Pipe) -> io::Result<()> {
    Ok(())
}

fn encode(op: u32, payload: &Value) -> Vec<u8> {
    let body = payload.to_string().into_bytes();
    let mut buf = Vec::with_capacity(8 + body.len());
    buf.extend_from_slice(&op.to_le_bytes());
    buf.extend_from_slice(&(body.len() as u32).to_le_bytes());
    buf.extend_from_slice(&body);
    buf
}

fn read_frame(r: &mut impl Read) -> io::Result<(u32, Value)> {
    let mut head = [0u8; 8];
    r.read_exact(&mut head)?;
    let op = u32::from_le_bytes([head[0], head[1], head[2], head[3]]);
    let len = u32::from_le_bytes([head[4], head[5], head[6], head[7]]) as usize;
    if len > FRAME_MAX {
        return Err(io::Error::new(io::ErrorKind::InvalidData, "frame too big"));
    }
    let mut body = vec![0u8; len];
    r.read_exact(&mut body)?;
    Ok((op, serde_json::from_slice(&body).unwrap_or(Value::Null)))
}

/// One live connection. A reader thread answers pings, reports errors and notices the close.
pub struct Connection {
    writer: Arc<Mutex<Pipe>>,
    closed: Arc<AtomicBool>,
    nonce: AtomicU64,
}

impl Connection {
    /// Finds a running Discord and says hello. Err while Discord is closed or refuses the id.
    pub fn open(client_id: &str) -> io::Result<Connection> {
        let mut last = io::Error::new(io::ErrorKind::NotFound, "Discord is not running");
        for path in candidates() {
            match Self::open_at(&path, client_id) {
                Ok(c) => return Ok(c),
                Err(e) => last = e,
            }
        }
        Err(last)
    }

    fn open_at(path: &PathBuf, client_id: &str) -> io::Result<Connection> {
        let pipe = open(path)?;
        let mut reader = pipe.try_clone()?;
        let writer = Arc::new(Mutex::new(pipe));
        let closed = Arc::new(AtomicBool::new(false));
        let (ready_tx, ready_rx) = mpsc::channel::<Result<(), String>>();

        writer.lock().unwrap().write_all(&encode(OP_HANDSHAKE, &json!({ "v": 1, "client_id": client_id })))?;

        let (w, c) = (writer.clone(), closed.clone());
        thread::spawn(move || {
            let mut ready_tx = Some(ready_tx);
            loop {
                if wait_readable(&reader).is_err() {
                    break;
                }
                match read_frame(&mut reader) {
                    Ok((OP_FRAME, msg)) => {
                        let evt = msg.get("evt").and_then(Value::as_str).unwrap_or("");
                        if evt == "READY" {
                            if let Some(tx) = ready_tx.take() {
                                let _ = tx.send(Ok(()));
                            }
                        } else if evt == "ERROR" {
                            eprintln!("nutsty-discord: Discord said {}", msg["data"]);
                        }
                    }
                    Ok((OP_PING, msg)) => {
                        let _ = w.lock().unwrap().write_all(&encode(OP_PONG, &msg));
                    }
                    Ok((OP_CLOSE, msg)) => {
                        if let Some(tx) = ready_tx.take() {
                            let _ = tx.send(Err(msg["message"].as_str().unwrap_or("closed").to_string()));
                        }
                        break;
                    }
                    Ok(_) => {}
                    Err(_) => break,
                }
            }
            c.store(true, Ordering::SeqCst);
        });

        let failed = |m: String| io::Error::new(io::ErrorKind::ConnectionRefused, m);
        match ready_rx.recv_timeout(READY_WAIT) {
            Ok(Ok(())) => Ok(Connection { writer, closed, nonce: AtomicU64::new(1) }),
            Ok(Err(m)) => Err(failed(m)),
            Err(_) => Err(failed("no READY from Discord".into())),
        }
    }

    pub fn is_closed(&self) -> bool {
        self.closed.load(Ordering::SeqCst)
    }

    /// Shows `activity` on the profile, or takes the status down when it is None.
    pub fn set_activity(&self, activity: Option<Value>) -> io::Result<()> {
        if self.is_closed() {
            return Err(io::Error::new(io::ErrorKind::BrokenPipe, "Discord closed the connection"));
        }
        let nonce = self.nonce.fetch_add(1, Ordering::SeqCst);
        let mut args = json!({ "pid": std::process::id() });
        if let Some(a) = activity {
            args["activity"] = a;
        }
        let frame = json!({ "cmd": "SET_ACTIVITY", "args": args, "nonce": nonce.to_string() });
        let result = self.writer.lock().unwrap().write_all(&encode(OP_FRAME, &frame));
        if result.is_err() {
            self.closed.store(true, Ordering::SeqCst);
        }
        result
    }
}

/// Lines from stdin, read on their own thread so the worker never blocks on Nutsty.
pub fn stdin_lines() -> Receiver<Option<String>> {
    let (tx, rx) = mpsc::channel();
    thread::spawn(move || {
        let stdin = io::stdin();
        let mut buf = String::new();
        loop {
            buf.clear();
            match stdin.read_line(&mut buf) {
                Ok(0) | Err(_) => {
                    let _ = tx.send(None);
                    break;
                }
                Ok(_) => {
                    if tx.send(Some(buf.trim().to_string())).is_err() {
                        break;
                    }
                }
            }
        }
    });
    rx
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn frames_round_trip() {
        let bytes = encode(OP_FRAME, &json!({ "cmd": "SET_ACTIVITY" }));
        assert_eq!(&bytes[..4], &1u32.to_le_bytes());
        let (op, v) = read_frame(&mut &bytes[..]).unwrap();
        assert_eq!(op, OP_FRAME);
        assert_eq!(v["cmd"], "SET_ACTIVITY");
    }
}
