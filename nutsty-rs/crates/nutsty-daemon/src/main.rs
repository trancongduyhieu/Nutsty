//! Nutsty High-Performance Native Resident Daemon (`nutsty-daemon`)
//! Ultra-lightweight HTTP router (< 5MB RAM) listening on 127.0.0.1:17890.
//! Handles hot-path routes (MPV status, RAM purge, palette, library) natively with 0ms overhead,
//! and dispatches external routes (YouTube Music, Social, Spotify) to a small pool of warm
//! Python workers (`route_dispatcher.py --serve`), falling back to a one-shot subprocess.

mod social;

use serde_json::json;
use std::env;
use std::fs;
use std::io::{BufRead, BufReader, Read, Write};
use std::path::{Path, PathBuf};
use std::process::{Child, ChildStdin, Command, Stdio};
use std::sync::mpsc::{self, Receiver, RecvTimeoutError};
use std::sync::{Arc, Mutex};
use std::thread;
use std::time::Duration;
use tiny_http::{Header, Method, Response, Server, StatusCode};
use url::Url;

const PORT: u16 = 17890;
const HOST: &str = "127.0.0.1";

#[inline(always)]
fn trim_system_memory() {
    #[cfg(target_os = "linux")]
    unsafe {
        unsafe extern "C" {
            fn malloc_trim(pad: usize) -> i32;
        }
        malloc_trim(0);
    }
}

// ── Warm Python worker pool ─────────────────────────────────────────────────
// Spawning python3 per request cost ~0.8 s (interpreter + ytmusicapi imports) and lost every
// in-process cache. Workers stay warm, take one JSON line per request and answer with one line.
// A worker exits by itself when idle (10 min) or recycled (500 requests); it is respawned lazily.
const POOL_SIZE: usize = 2;
// Worker 0 stays warm for the session; the spare returns its RAM soon after a burst of parallel loads
const PRIMARY_IDLE_EXIT_SECS: u64 = 600;
const SPARE_IDLE_EXIT_SECS: u64 = 90;
const WORKER_TIMEOUT: Duration = Duration::from_secs(120);
const BUSY_WAIT: Duration = Duration::from_millis(400);
const SPARE_SPAWN_WAIT: Duration = Duration::from_millis(150);

fn python_cmd() -> &'static str {
    if cfg!(windows) { "python" } else { "python3" }
}

fn no_console(cmd: &mut Command) {
    #[cfg(windows)]
    {
        use std::os::windows::process::CommandExt;
        cmd.creation_flags(0x0800_0000); // CREATE_NO_WINDOW
    }
    #[cfg(not(windows))]
    let _ = cmd;
}

struct Worker {
    child: Child,
    stdin: ChildStdin,
    lines: Receiver<String>,
}

impl Worker {
    fn spawn(script: &Path, idle_exit_secs: u64) -> Option<Worker> {
        let mut cmd = Command::new(python_cmd());
        cmd.arg(script)
            .arg("--serve")
            .env("NUTSTY_WORKER_IDLE_SEC", idle_exit_secs.to_string())
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::inherit());
        no_console(&mut cmd);
        let mut child = cmd.spawn().ok()?;
        let stdin = child.stdin.take()?;
        let stdout = child.stdout.take()?;
        let (tx, rx) = mpsc::channel();
        thread::spawn(move || {
            for line in BufReader::new(stdout).lines() {
                match line {
                    Ok(l) => {
                        if tx.send(l).is_err() {
                            break;
                        }
                    }
                    Err(_) => break,
                }
            }
        });
        Some(Worker { child, stdin, lines: rx })
    }

    /// Ok(line) on success; Err(true) when the worker died before reading the request (safe to
    /// retry), Err(false) when it failed mid-request.
    fn call(&mut self, payload: &str) -> Result<String, bool> {
        if self.stdin.write_all(payload.as_bytes()).is_err() || self.stdin.write_all(b"\n").is_err() || self.stdin.flush().is_err() {
            return Err(true);
        }
        match self.lines.recv_timeout(WORKER_TIMEOUT) {
            Ok(line) => Ok(line),
            // EOF right away: the worker had just exited (idle / recycled) and never saw it
            Err(RecvTimeoutError::Disconnected) => Err(true),
            Err(RecvTimeoutError::Timeout) => Err(false),
        }
    }

    fn kill(&mut self) {
        let _ = self.child.kill();
        let _ = self.child.wait();
    }
}

struct WorkerPool {
    script: PathBuf,
    slots: Vec<Mutex<Option<Worker>>>,
}

impl WorkerPool {
    fn new(script: PathBuf) -> Self {
        WorkerPool { script, slots: (0..POOL_SIZE).map(|_| Mutex::new(None)).collect() }
    }

    fn prewarm(&self) {
        if let Ok(mut slot) = self.slots[0].lock()
            && slot.is_none()
        {
            *slot = Worker::spawn(&self.script, PRIMARY_IDLE_EXIT_SECS);
        }
    }

    fn call_slot(&self, index: usize, slot: &mut Option<Worker>, payload: &str) -> Option<String> {
        for _attempt in 0..2 {
            if slot.is_none() {
                let idle = if index == 0 { PRIMARY_IDLE_EXIT_SECS } else { SPARE_IDLE_EXIT_SECS };
                *slot = Worker::spawn(&self.script, idle);
            }
            let worker = slot.as_mut()?;
            match worker.call(payload) {
                Ok(line) => return Some(line),
                Err(retry) => {
                    worker.kill();
                    *slot = None;
                    if !retry {
                        return None;
                    }
                }
            }
        }
        None
    }

    /// Stateful routes (update download, Spotify import progress) live in worker 0's memory, so
    /// they always go there; others take any idle worker. None when every worker stays busy for BUSY_WAIT.
    fn dispatch(&self, payload: &str, pinned: bool) -> Option<String> {
        if pinned {
            let mut slot = self.slots[0].lock().ok()?;
            return self.call_slot(0, &mut slot, payload);
        }
        // Most answers come from caches in a few ms: wait briefly for a free worker before
        // paying a cold one-shot interpreter
        let start = std::time::Instant::now();
        let deadline = start + BUSY_WAIT;
        loop {
            // Worker 0 first. A spare that is not running yet only spawns (~40 MB) once worker 0
            // stayed busy past SPARE_SPAWN_WAIT, so routine poll overlaps never keep two alive
            let may_spawn_spare = start.elapsed() >= SPARE_SPAWN_WAIT;
            for (index, m) in self.slots.iter().enumerate() {
                if let Ok(mut slot) = m.try_lock() {
                    if index > 0 && slot.is_none() && !may_spawn_spare {
                        continue;
                    }
                    return self.call_slot(index, &mut slot, payload);
                }
            }
            if std::time::Instant::now() >= deadline {
                return None;
            }
            thread::sleep(Duration::from_millis(5));
        }
    }
}

fn is_pinned_route(raw_url: &str) -> bool {
    let path = raw_url.split('?').next().unwrap_or("");
    path.starts_with("/api/update") || path == "/api/check_update" || path.starts_with("/api/spotify")
}

struct AppState {
    app_dir: PathBuf,
    pending_ui_action: Mutex<Option<serde_json::Value>>,
    pool: WorkerPool,
}

fn resolve_app_dir() -> PathBuf {
    if let Ok(dir) = env::var("NUTSTY_APP_DIR") {
        let p = PathBuf::from(dir);
        if p.exists() {
            return p;
        }
    }

    if let Ok(exe) = env::current_exe() {
        if let Some(parent) = exe.parent() {
            if parent.ends_with("bin") {
                if let Some(root) = parent.parent() {
                    return root.to_path_buf();
                }
            }
            if let Some(target) = parent.parent() {
                if let Some(rs_root) = target.parent() {
                    if let Some(root) = rs_root.parent() {
                        return root.to_path_buf();
                    }
                }
            }
        }
    }

    if let Ok(home) = env::var("HOME") {
        let p = PathBuf::from(home).join("Applications").join("FrostifyLocal");
        if p.exists() {
            return p;
        }
    }

    PathBuf::from(".")
}

fn add_cors_headers<R: Read>(response: Response<R>) -> Response<R> {
    response
        .with_header(Header::from_bytes(&b"Access-Control-Allow-Origin"[..], &b"*"[..]).unwrap())
        .with_header(Header::from_bytes(&b"Access-Control-Allow-Methods"[..], &b"POST, GET, OPTIONS"[..]).unwrap())
        .with_header(Header::from_bytes(&b"Access-Control-Allow-Headers"[..], &b"Content-Type, Authorization"[..]).unwrap())
}

fn send_json(request: tiny_http::Request, status_code: u16, data: &serde_json::Value) {
    let body = serde_json::to_string(data).unwrap_or_else(|_| "{}".to_string());
    let resp = Response::from_string(body)
        .with_status_code(StatusCode(status_code))
        .with_header(Header::from_bytes(&b"Content-Type"[..], &b"application/json"[..]).unwrap());
    let _ = request.respond(add_cors_headers(resp));
}

fn send_raw_json(request: tiny_http::Request, status_code: u16, raw_str: String) {
    let resp = Response::from_string(raw_str)
        .with_status_code(StatusCode(status_code))
        .with_header(Header::from_bytes(&b"Content-Type"[..], &b"application/json"[..]).unwrap());
    let _ = request.respond(add_cors_headers(resp));
}

fn handle_clipboard() -> String {
    #[cfg(target_os = "linux")]
    {
        if let Ok(out) = Command::new("wl-paste").arg("-n").output() {
            if out.status.success() && !out.stdout.is_empty() {
                return String::from_utf8_lossy(&out.stdout).to_string();
            }
        }
        if let Ok(out) = Command::new("xclip").args(["-selection", "clipboard", "-o"]).output() {
            if out.status.success() && !out.stdout.is_empty() {
                return String::from_utf8_lossy(&out.stdout).to_string();
            }
        }
    }

    #[cfg(windows)]
    {
        // On Windows, clipboard can be queried via PowerShell or native user32 API
        if let Ok(out) = Command::new("powershell").args(["-NoProfile", "-Command", "Get-Clipboard"]).output() {
            if out.status.success() {
                return String::from_utf8_lossy(&out.stdout).trim().to_string();
            }
        }
    }

    String::new()
}

fn handle_open_url(url_str: &str) -> bool {
    if url_str.is_empty() {
        return false;
    }

    #[cfg(target_os = "linux")]
    {
        if let Ok(mut child) = Command::new("xdg-open").arg(url_str).spawn() {
            let _ = child.wait();
            return true;
        }
    }

    #[cfg(windows)]
    {
        if let Ok(mut child) = Command::new("cmd").args(["/c", "start", "", url_str]).spawn() {
            let _ = child.wait();
            return true;
        }
    }

    false
}

fn parse_dispatch_output(stdout_str: &str) -> (u16, String) {
    if let Ok(parsed) = serde_json::from_str::<serde_json::Value>(stdout_str) {
        let status = parsed.get("status").and_then(|s| s.as_u64()).unwrap_or(200) as u16;
        let body = parsed.get("body").and_then(|b| b.as_str()).unwrap_or("{}");
        (status, body.to_string())
    } else {
        (200, stdout_str.trim().to_string())
    }
}

fn dispatch_to_python(state: &AppState, method: &str, raw_url: &str, body_str: &str) -> (u16, String) {
    let script_path = state.app_dir.join("backend").join("route_dispatcher.py");
    if !script_path.exists() {
        return (500, json!({"error": "backend/route_dispatcher.py not found"}).to_string());
    }

    let payload = json!({
        "method": method,
        "url": raw_url,
        "body": body_str
    });

    if let Some(line) = state.pool.dispatch(&payload.to_string(), is_pinned_route(raw_url)) {
        return parse_dispatch_output(&line);
    }

    // Every warm worker busy (or failing): one-shot subprocess, the original path
    let mut cmd = Command::new(python_cmd());
    cmd.arg(&script_path)
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped());
    no_console(&mut cmd);
    let mut child = match cmd.spawn()
    {
        Ok(c) => c,
        Err(e) => {
            return (500, json!({"error": format!("Failed to spawn python dispatcher: {e}")}).to_string());
        }
    };

    if let Some(mut stdin) = child.stdin.take() {
        let _ = serde_json::to_writer(&mut stdin, &payload);
        let _ = stdin.write_all(b"\n");
    }

    let output = match child.wait_with_output() {
        Ok(o) => o,
        Err(e) => {
            return (500, json!({"error": format!("Python dispatcher execution failed: {e}")}).to_string());
        }
    };

    if !output.status.success() {
        let err_msg = String::from_utf8_lossy(&output.stderr);
        return (500, json!({"error": format!("Python dispatcher error: {err_msg}")}).to_string());
    }

    parse_dispatch_output(&String::from_utf8_lossy(&output.stdout))
}

fn handle_request(state: Arc<AppState>, mut request: tiny_http::Request) {
    // 1. Handle CORS preflight OPTIONS
    if request.method() == &Method::Options {
        let resp = Response::empty(StatusCode(204));
        let _ = request.respond(add_cors_headers(resp));
        return;
    }

    let raw_url = request.url().to_string();
    let parsed_url = match Url::parse(&format!("http://{HOST}:{PORT}{raw_url}")) {
        Ok(u) => u,
        Err(_) => {
            send_json(request, 400, &json!({"error": "Malformed URL"}));
            return;
        }
    };

    let path = parsed_url.path().to_string();
    let method = request.method().as_str().to_string();

    // Read body if POST
    let mut body_str = String::new();
    if method == "POST" {
        let _ = request.as_reader().read_to_string(&mut body_str);
    }

    // 2. Dispatch Native Rust Hot-Path Routes (< 0.5ms, zero subprocess)
    if method == "GET" {
        match path.as_str() {
            "/api/player/status" => {
                let profile = parsed_url
                    .query_pairs()
                    .find(|(k, _)| k == "profile")
                    .map(|(_, v)| v.into_owned())
                    .unwrap_or_default();
                let status = nutsty_bridge::with_profile(&profile, nutsty_bridge::get_player_status_output);
                let body = serde_json::to_string(&status).unwrap_or_else(|_| "{}".to_string());
                send_raw_json(request, 200, body);
                return;
            }
            "/api/system/purge_ram" | "/api/purge_ram" => {
                let freed = nutsty_bridge::purge_memory();
                let plat = if cfg!(target_os = "linux") { "linux" } else { "windows" };
                send_json(request, 200, &json!({"success": freed, "platform": plat}));
                return;
            }
            "/api/palette" => {
                let url_param = parsed_url
                    .query_pairs()
                    .find(|(k, _)| k == "url")
                    .map(|(_, v)| v.into_owned())
                    .unwrap_or_default();
                let pal = nutsty_bridge::palette::extract_song_palette(&url_param);
                let body = serde_json::to_string(&pal).unwrap_or_else(|_| "{}".to_string());
                send_raw_json(request, 200, body);
                trim_system_memory();
                return;
            }
            "/api/library" => {
                let lib_path = state.app_dir.join("library.json");
                if lib_path.exists() {
                    match fs::read_to_string(&lib_path) {
                        Ok(content) => send_raw_json(request, 200, content),
                        Err(e) => send_json(request, 500, &json!({"error": format!("Cannot read library.json: {e}")})),
                    }
                } else {
                    send_json(request, 200, &json!({"tracks": [], "playlists": []}));
                }
                return;
            }
            "/api/clipboard" => {
                let text = handle_clipboard();
                send_json(request, 200, &json!({"text": text}));
                return;
            }
            "/api/ui/pending_action" => {
                let act = state.pending_ui_action.lock().unwrap().take();
                send_json(request, 200, &act.unwrap_or_else(|| json!({})));
                return;
            }
            "/api/ui/open_settings" | "/api/open_settings" => {
                let tab = parsed_url
                    .query_pairs()
                    .find(|(k, _)| k == "tab")
                    .and_then(|(_, v)| v.parse::<i32>().ok())
                    .unwrap_or(0);
                let mock = parsed_url
                    .query_pairs()
                    .find(|(k, _)| k == "mock")
                    .map(|(_, v)| v == "1" || v.eq_ignore_ascii_case("true"))
                    .unwrap_or(false);

                let action_obj = json!({
                    "action": "open_settings",
                    "tab": tab,
                    "mock_update": mock,
                    "current_version": "2.0.0",
                    "latest_version": "v2.0.0",
                    "release_url": "https://github.com/trancongduyhieu/Nutsty/releases"
                });

                *state.pending_ui_action.lock().unwrap() = Some(action_obj);
                send_json(request, 200, &json!({"success": true}));
                return;
            }
            _ => {}
        }
    } else if method == "POST" {
        match path.as_str() {
            "/api/open_url" => {
                let target_url = if let Ok(parsed) = serde_json::from_str::<serde_json::Value>(&body_str) {
                    parsed.get("url").and_then(|v| v.as_str()).unwrap_or("").to_string()
                } else {
                    String::new()
                };
                let success = handle_open_url(&target_url);
                send_json(request, 200, &json!({"success": success}));
                return;
            }
            "/api/ui/open_settings" | "/api/open_settings" => {
                let tab = if let Ok(parsed) = serde_json::from_str::<serde_json::Value>(&body_str) {
                    parsed.get("tab").and_then(|v| v.as_i64()).unwrap_or(0) as i32
                } else {
                    0
                };
                let action_obj = json!({
                    "action": "open_settings",
                    "tab": tab,
                    "mock_update": false,
                    "current_version": "2.0.0",
                    "latest_version": "v2.0.0",
                    "release_url": "https://github.com/trancongduyhieu/Nutsty/releases"
                });
                *state.pending_ui_action.lock().unwrap() = Some(action_obj);
                send_json(request, 200, &json!({"success": true}));
                return;
            }
            _ => {}
        }
    }

    // 3. Social polls (friends, notes, events, presence) go straight to the relay; uncommon
    //    cases (identity setup, 401, local events) return None and fall through to Python
    if let Some(body) = social::try_handle(&method, &path, &parsed_url, &body_str) {
        send_raw_json(request, 200, body);
        return;
    }

    // 4. Fallback: Dispatch to Python subprocess (YouTube Music, Social, Spotify, Updater)
    let (status_code, response_body) = dispatch_to_python(&state, &method, &raw_url, &body_str);
    send_raw_json(request, status_code, response_body);
    trim_system_memory();
}

fn main() {
    #[cfg(target_os = "linux")]
    unsafe {
        unsafe extern "C" {
            fn mallopt(param: i32, value: i32) -> i32;
        }
        // M_ARENA_MAX = -8: restrict glibc to 1 heap arena, preventing 6.5MB per-thread bloating
        mallopt(-8, 1);
        // M_TRIM_THRESHOLD = -1: aggressively return dirty heap memory to OS
        mallopt(-1, 64 * 1024);
        // M_MMAP_THRESHOLD = -3: directly mmap large buffers to unmap immediately on free
        mallopt(-3, 64 * 1024);
    }

    let app_dir = resolve_app_dir();
    let state = Arc::new(AppState {
        app_dir: app_dir.clone(),
        pending_ui_action: Mutex::new(None),
        pool: WorkerPool::new(app_dir.join("backend").join("route_dispatcher.py")),
    });

    // NUTSTY_DAEMON_PORT lets a test build run beside the live daemon
    let port: u16 = env::var("NUTSTY_DAEMON_PORT").ok().and_then(|p| p.parse().ok()).unwrap_or(PORT);
    let addr = format!("{HOST}:{port}");
    let server = match Server::http(&addr) {
        Ok(s) => Arc::new(s),
        Err(e) => {
            // If port 17890 is already occupied by a running daemon, exit cleanly with code 0
            if std::net::TcpStream::connect(&addr).is_ok() {
                println!("nutsty-daemon: Port {port} already active, exiting cleanly.");
                std::process::exit(0);
            }
            eprintln!("nutsty-daemon: Failed to bind to {addr}: {e}");
            std::process::exit(1);
        }
    };

    println!("nutsty-daemon: Ready on http://{addr} (AppDir: {})", app_dir.display());

    // Warm the first worker now so the first Home / Mood request does not pay the Python start
    {
        let st = Arc::clone(&state);
        thread::spawn(move || st.pool.prewarm());
    }

    // One thread per request: a slow YouTube Music call no longer queues every other route behind it
    for request in server.incoming_requests() {
        let st = Arc::clone(&state);
        thread::spawn(move || {
            handle_request(st, request);
            trim_system_memory();
        });
    }
}
