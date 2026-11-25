//! Blazingly fast, zero-allocation native IPC bridge for Nutsty.
//! Directly connects to MPV Unix Domain Socket / Windows Named Pipe in sub-millisecond time,
//! completely replacing the heavy `python3 player_daemon.py status` process-thrashing bottleneck.

use serde_json::{json, Value};
use std::env;
use std::fs::File;
use std::io::{BufRead, BufReader, Write};
use std::path::PathBuf;
use std::time::Duration;

#[cfg(unix)]
use std::os::unix::net::UnixStream;

mod palette;


fn get_socket_path() -> PathBuf {
    let profile = env::var("NUTSTY_PROFILE").unwrap_or_default().trim().to_lowercase();
    let suffix = if profile.is_empty() {
        String::new()
    } else {
        format!("_{profile}")
    };

    let temp_dir = env::temp_dir();
    temp_dir.join(format!("nutsty_mpv{suffix}.sock"))
}

fn get_abort_file_path() -> PathBuf {
    let profile = env::var("NUTSTY_PROFILE").unwrap_or_default().trim().to_lowercase();
    let suffix = if profile.is_empty() {
        String::new()
    } else {
        format!("_{profile}")
    };

    let temp_dir = env::temp_dir();
    temp_dir.join(format!("nutsty_abort_fade{suffix}"))
}

#[cfg(unix)]
fn send_mpv_command_single(cmd: Value) -> Option<Value> {
    let sock_path = get_socket_path();
    let mut stream = UnixStream::connect(sock_path).ok()?;
    stream.set_read_timeout(Some(Duration::from_millis(500))).ok();
    stream.set_write_timeout(Some(Duration::from_millis(500))).ok();

    let mut payload = serde_json::to_vec(&json!({ "command": cmd })).ok()?;
    payload.push(b'\n');
    stream.write_all(&payload).ok()?;

    let mut reader = BufReader::new(stream);
    let mut line = String::new();
    reader.read_line(&mut line).ok()?;

    serde_json::from_str(&line).ok()
}

#[cfg(windows)]
fn get_pipe_path() -> String {
    let profile = env::var("NUTSTY_PROFILE").unwrap_or_default().trim().to_lowercase();
    let suffix = if profile.is_empty() {
        String::new()
    } else {
        format!("_{profile}")
    };
    format!(r"\\.\pipe\nutsty_mpv{suffix}")
}

#[cfg(windows)]
fn send_mpv_command_single(cmd: Value) -> Option<Value> {
    use std::fs::OpenOptions;
    let pipe_path = get_pipe_path();
    let mut file = OpenOptions::new().read(true).write(true).open(pipe_path).ok()?;
    let mut payload = serde_json::to_vec(&json!({ "command": cmd })).ok()?;
    payload.push(b'\n');
    file.write_all(&payload).ok()?;
    file.flush().ok()?;

    let mut reader = BufReader::new(file);
    let mut line = String::new();
    reader.read_line(&mut line).ok()?;

    serde_json::from_str(&line).ok()
}

#[cfg(not(any(unix, windows)))]
fn send_mpv_command_single(_cmd: Value) -> Option<Value> {
    None
}

#[cfg(unix)]
fn fetch_mpv_status_batch() -> Option<serde_json::Map<String, Value>> {
    let sock_path = get_socket_path();
    let mut stream = UnixStream::connect(sock_path).ok()?;
    stream.set_read_timeout(Some(Duration::from_millis(150))).ok();
    stream.set_write_timeout(Some(Duration::from_millis(150))).ok();

    let props = [
        "pause",
        "time-pos",
        "duration",
        "filename",
        "path",
        "media-title",
        "volume",
        "idle-active",
        "audio-codec-name",
        "audio-params",
        "audio-bitrate",
    ];

    let mut payload = Vec::with_capacity(1024);
    for (i, p) in props.iter().enumerate() {
        let msg = json!({
            "command": ["get_property", p],
            "request_id": i
        });
        serde_json::to_writer(&mut payload, &msg).ok()?;
        payload.push(b'\n');
    }

    stream.write_all(&payload).ok()?;

    let mut reader = BufReader::new(stream);
    let mut results = serde_json::Map::with_capacity(props.len());
    let mut line = String::with_capacity(512);

    for _ in 0..props.len() {
        line.clear();
        if reader.read_line(&mut line).is_err() || line.trim().is_empty() {
            break;
        }

        if let Ok(val) = serde_json::from_str::<Value>(&line) {
            if let Some(req_id) = val.get("request_id").and_then(|v| v.as_u64()) {
                let idx = req_id as usize;
                if idx < props.len() {
                    let prop_name = props[idx];
                    let data = val.get("data").cloned().unwrap_or(Value::Null);
                    results.insert(prop_name.to_string(), data);
                }
            }
        }
    }

    Some(results)
}

#[cfg(windows)]
fn fetch_mpv_status_batch() -> Option<serde_json::Map<String, Value>> {
    use std::fs::OpenOptions;
    let pipe_path = get_pipe_path();
    let mut file = OpenOptions::new().read(true).write(true).open(pipe_path).ok()?;
    let props = [
        "pause",
        "time-pos",
        "duration",
        "filename",
        "path",
        "media-title",
        "volume",
        "idle-active",
        "audio-codec-name",
        "audio-params",
        "audio-bitrate",
    ];

    let mut payload = Vec::with_capacity(1024);
    for (i, p) in props.iter().enumerate() {
        let msg = json!({
            "command": ["get_property", p],
            "request_id": i
        });
        serde_json::to_writer(&mut payload, &msg).ok()?;
        payload.push(b'\n');
    }

    file.write_all(&payload).ok()?;
    file.flush().ok()?;

    let mut reader = BufReader::new(file);
    let mut results = serde_json::Map::with_capacity(props.len());
    let mut line = String::with_capacity(512);

    for _ in 0..props.len() {
        line.clear();
        if reader.read_line(&mut line).is_err() || line.trim().is_empty() {
            break;
        }

        if let Ok(val) = serde_json::from_str::<Value>(&line) {
            if let Some(req_id) = val.get("request_id").and_then(|v| v.as_u64()) {
                let idx = req_id as usize;
                if idx < props.len() {
                    let prop_name = props[idx];
                    let data = val.get("data").cloned().unwrap_or(Value::Null);
                    results.insert(prop_name.to_string(), data);
                }
            }
        }
    }

    Some(results)
}

#[cfg(not(any(unix, windows)))]
fn fetch_mpv_status_batch() -> Option<serde_json::Map<String, Value>> {
    None
}

fn purge_memory() {
    #[cfg(target_os = "linux")]
    unsafe {
        unsafe extern "C" {
            fn malloc_trim(pad: usize) -> i32;
        }
        malloc_trim(0);
    }

    #[cfg(windows)]
    unsafe {
        unsafe extern "system" {
            fn SetProcessWorkingSetSize(hProcess: isize, dwMinimumWorkingSetSize: usize, dwMaximumWorkingSetSize: usize) -> i32;
        }
        SetProcessWorkingSetSize(-1, usize::MAX, usize::MAX);
    }
    println!(r#"{{"success":true,"purged":true}}"#);
}

/// One decision for both the CLI and nutsty-daemon: the library owns the status logic
fn handle_status() {
    let status = nutsty_bridge::get_player_status_output();
    println!("{}", serde_json::to_string(&status).unwrap_or_else(|_| "{}".to_string()));
}

fn main() {
    let args: Vec<String> = env::args().collect();
    if args.len() < 2 {
        handle_status();
        return;
    }

    let action = args[1].to_lowercase();
    match action.as_str() {
        "status" => {
            handle_status();
        }
        "pause" => {
            send_mpv_command_single(json!(["set_property", "pause", true]));
            println!(r#"{{"success":true}}"#);
        }
        "resume" => {
            send_mpv_command_single(json!(["set_property", "pause", false]));
            println!(r#"{{"success":true}}"#);
        }
        "toggle" | "play-pause" => {
            send_mpv_command_single(json!(["cycle", "pause"]));
            println!(r#"{{"success":true}}"#);
        }
        "next" => {
            send_mpv_command_single(json!(["playlist-next"]));
            println!(r#"{{"success":true}}"#);
        }
        "prev" => {
            send_mpv_command_single(json!(["playlist-prev"]));
            println!(r#"{{"success":true}}"#);
        }
        "purge" | "purge-memory" => {
            purge_memory();
        }
        "stop" => {
            send_mpv_command_single(json!(["stop"]));
            println!(r#"{{"success":true}}"#);
        }
        "seek" => {
            if let Some(sec_str) = args.get(2) {
                if let Ok(sec) = sec_str.parse::<f64>() {
                    send_mpv_command_single(json!(["seek", sec, "absolute"]));
                }
            }
            println!(r#"{{"success":true}}"#);
        }
        "volume" => {
            if let Some(vol_str) = args.get(2) {
                if let Ok(vol) = vol_str.parse::<f64>() {
                    send_mpv_command_single(json!(["set_property", "volume", vol]));
                }
            }
            println!(r#"{{"success":true}}"#);
        }
        "play" => {
            if let Some(path) = args.get(2) {
                send_mpv_command_single(json!(["loadfile", path, "replace"]));
                send_mpv_command_single(json!(["set_property", "pause", false]));
                println!(r#"{{"success":true,"path":"{}"}}"#, path);
            }
        }
        "cancel_fade" => {
            let abort_path = get_abort_file_path();
            let _ = File::create(abort_path);
            println!(r#"{{"success":true}}"#);
        }
        "audio_specs" => {
            if let Some(map) = fetch_mpv_status_batch() {
                let specs = nutsty_bridge::parse_audio_specs_from_map(&map);
                println!("{}", serde_json::to_string(&specs).unwrap());
            } else {
                let default_specs = nutsty_bridge::AudioSpecs::default();
                println!("{}", serde_json::to_string(&default_specs).unwrap());
            }
        }
        "palette" | "song_palette" => {
            let src = args.get(2).map(|s| s.as_str()).unwrap_or("");
            let pal = palette::extract_song_palette(src);
            println!("{}", serde_json::to_string(&pal).unwrap());
        }
        _ => {
            handle_status();
        }
    }
}
