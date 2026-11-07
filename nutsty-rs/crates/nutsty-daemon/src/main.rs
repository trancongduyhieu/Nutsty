//! Nutsty High-Performance Native Resident Daemon (`nutsty-daemon`)
//! Ultra-lightweight HTTP router (< 5MB RAM) listening on 127.0.0.1:17890.
//! Handles hot-path routes (MPV status, RAM purge, palette, library) natively with 0ms overhead,
//! and dispatches external routes (YouTube Music, Social, Spotify) to Python subprocesses.

use serde_json::json;
use std::env;
use std::fs;
use std::io::Read;
use std::path::PathBuf;
use std::process::{Command, Stdio};
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

struct AppState {
    app_dir: PathBuf,
    pending_ui_action: Mutex<Option<serde_json::Value>>,
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

    let python_cmd = if cfg!(windows) { "python" } else { "python3" };
    let mut child = match Command::new(python_cmd)
        .arg(&script_path)
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
    {
        Ok(c) => c,
        Err(e) => {
            return (500, json!({"error": format!("Failed to spawn python dispatcher: {e}")}).to_string());
        }
    };

    if let Some(mut stdin) = child.stdin.take() {
        use std::io::Write;
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

    let stdout_str = String::from_utf8_lossy(&output.stdout);
    if let Ok(parsed) = serde_json::from_str::<serde_json::Value>(&stdout_str) {
        let status = parsed.get("status").and_then(|s| s.as_u64()).unwrap_or(200) as u16;
        let body = parsed.get("body").and_then(|b| b.as_str()).unwrap_or("{}");
        (status, body.to_string())
    } else {
        (200, stdout_str.trim().to_string())
    }
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
                let status = nutsty_bridge::get_player_status_output();
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
                    "current_version": "1.0.7",
                    "latest_version": "v1.0.7",
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
                    "current_version": "1.0.7",
                    "latest_version": "v1.0.7",
                    "release_url": "https://github.com/trancongduyhieu/Nutsty/releases"
                });
                *state.pending_ui_action.lock().unwrap() = Some(action_obj);
                send_json(request, 200, &json!({"success": true}));
                return;
            }
            _ => {}
        }
    }

    // 3. Fallback: Dispatch to Python subprocess (YouTube Music, Social, Spotify, Updater)
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
    });

    let addr = format!("{HOST}:{PORT}");
    let server = match Server::http(&addr) {
        Ok(s) => Arc::new(s),
        Err(e) => {
            // If port 17890 is already occupied by a running daemon, exit cleanly with code 0
            if std::net::TcpStream::connect(&addr).is_ok() {
                println!("nutsty-daemon: Port {PORT} already active, exiting cleanly.");
                std::process::exit(0);
            }
            eprintln!("nutsty-daemon: Failed to bind to {addr}: {e}");
            std::process::exit(1);
        }
    };

    println!("nutsty-daemon: Ready on http://{addr} (AppDir: {})", app_dir.display());

    for request in server.incoming_requests() {
        handle_request(Arc::clone(&state), request);
        trim_system_memory();
    }
}
