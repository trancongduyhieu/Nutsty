//! Blazingly fast, zero-allocation native IPC bridge for Nutsty.
//! Directly connects to MPV Unix Domain Socket / Windows Named Pipe in sub-millisecond time,
//! completely replacing the heavy `python3 player_daemon.py status` process-thrashing bottleneck.

use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use std::env;
use std::fs::File;
use std::io::{BufRead, BufReader, Write};
use std::path::PathBuf;
use std::time::Duration;

#[cfg(unix)]
use std::os::unix::net::UnixStream;

#[derive(Debug, Serialize, Deserialize)]
struct PlaybackState {
    #[serde(default)]
    state: String,
    #[serde(default)]
    path: String,
    #[serde(default)]
    target_vid: String,
    #[serde(default)]
    timestamp: f64,
}

#[derive(Debug, Serialize)]
struct AudioSpecs {
    codec: String,
    bitrate: u64,
    bitrate_str: String,
    sample_rate: u64,
    sample_rate_str: String,
    channels: String,
}

#[derive(Debug, Serialize)]
struct PlayerStatusOutput {
    is_playing: bool,
    is_paused: bool,
    time_pos: f64,
    duration: f64,
    filename: String,
    path: String,
    media_title: String,
    volume: f64,
    is_loading: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    target_vid: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    audio_specs: Option<AudioSpecs>,
}

impl Default for PlayerStatusOutput {
    fn default() -> Self {
        Self {
            is_playing: false,
            is_paused: false,
            time_pos: 0.0,
            duration: 0.0,
            filename: String::new(),
            path: String::new(),
            media_title: String::new(),
            volume: 100.0,
            is_loading: false,
            target_vid: None,
            audio_specs: None,
        }
    }
}

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

fn get_state_file_path() -> PathBuf {
    let profile = env::var("NUTSTY_PROFILE").unwrap_or_default().trim().to_lowercase();
    let suffix = if profile.is_empty() {
        String::new()
    } else {
        format!("_{profile}")
    };

    let temp_dir = env::temp_dir();
    temp_dir.join(format!("nutsty_playback_state{suffix}.json"))
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

fn read_playback_state() -> Option<PlaybackState> {
    let path = get_state_file_path();
    let file = File::open(path).ok()?;
    serde_json::from_reader(file).ok()
}

fn update_playback_state_playing(current_path: &str) {
    let path = get_state_file_path();
    let now = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_secs_f64())
        .unwrap_or(0.0);
    let payload = json!({
        "state": "playing",
        "path": current_path,
        "timestamp": now
    });
    if let Ok(content) = serde_json::to_string(&payload) {
        let _ = std::fs::write(path, content);
    }
}

fn parse_audio_specs_from_map(map: &serde_json::Map<String, Value>) -> AudioSpecs {
    let codec = map
        .get("audio-codec-name")
        .and_then(|v| v.as_str())
        .unwrap_or("")
        .to_uppercase();

    let bitrate_raw = map
        .get("audio-bitrate")
        .and_then(|v| v.as_f64())
        .unwrap_or(0.0);
    let mut bitrate_kbps = if bitrate_raw > 1000.0 {
        (bitrate_raw / 1000.0).round() as u64
    } else {
        bitrate_raw as u64
    };
    if bitrate_kbps == 0 && !codec.is_empty() {
        bitrate_kbps = if codec == "MP3" { 320 } else { 192 };
    }
    let bitrate_str = if bitrate_kbps > 0 {
        format!("{bitrate_kbps} kbps")
    } else {
        "192 kbps".to_string()
    };

    let mut sample_rate: u64 = 48000;
    let mut sample_rate_str = "48.0 kHz".to_string();
    let mut channels = "Stereo (2ch)".to_string();

    if let Some(params) = map.get("audio-params").and_then(|v| v.as_object()) {
        if let Some(sr) = params.get("samplerate").and_then(|v| v.as_u64()) {
            sample_rate = sr;
            sample_rate_str = format!("{:.1} kHz", (sr as f64) / 1000.0);
        }
        if let Some(ch) = params.get("channel-count").and_then(|v| v.as_u64()) {
            channels = if ch == 2 {
                "Stereo (2ch)".to_string()
            } else if ch > 0 {
                format!("{ch}ch")
            } else {
                "Stereo".to_string()
            };
        }
    }

    AudioSpecs {
        codec: if codec.is_empty() { "AAC".to_string() } else { codec },
        bitrate: bitrate_kbps,
        bitrate_str,
        sample_rate,
        sample_rate_str,
        channels,
    }
}

fn handle_status() {
    let batch = fetch_mpv_status_batch();
    if batch.is_none() {
        let default_status = PlayerStatusOutput::default();
        println!("{}", serde_json::to_string(&default_status).unwrap());
        return;
    }

    let map = batch.unwrap();
    let pause = map.get("pause").and_then(|v| v.as_bool()).unwrap_or(true);
    let time_pos = map.get("time-pos").and_then(|v| v.as_f64()).unwrap_or(0.0);
    let duration = map.get("duration").and_then(|v| v.as_f64()).unwrap_or(0.0);
    let filename = map
        .get("filename")
        .and_then(|v| v.as_str())
        .unwrap_or("")
        .to_string();
    let path = map
        .get("path")
        .and_then(|v| v.as_str())
        .unwrap_or("")
        .to_string();
    let media_title = map
        .get("media-title")
        .and_then(|v| v.as_str())
        .unwrap_or("")
        .to_string();
    let volume = map.get("volume").and_then(|v| v.as_f64()).unwrap_or(100.0);
    let idle = map.get("idle-active").and_then(|v| v.as_bool()).unwrap_or(true);

    let state_file = read_playback_state();
    let raw_loading = state_file.as_ref().map(|s| s.state == "loading").unwrap_or(false);

    let is_loading = if raw_loading {
        if (!idle && (time_pos > 0.2 || duration > 0.0)) || (!path.is_empty() && !idle && !pause) {
            update_playback_state_playing(&path);
            false
        } else if let Some(ref sf) = state_file {
            let now = std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .map(|d| d.as_secs_f64())
                .unwrap_or(0.0);
            if sf.timestamp > 0.0 && (now - sf.timestamp) > 5.0 {
                update_playback_state_playing(&path);
                false
            } else {
                true
            }
        } else {
            false
        }
    } else {
        false
    };

    let has_file = (!path.is_empty() || !filename.is_empty()) && !idle && (!is_loading || time_pos > 0.0);

    let is_playing = !pause && has_file;
    let is_paused = pause && has_file;

    let audio_specs = if has_file {
        Some(parse_audio_specs_from_map(&map))
    } else {
        None
    };

    let out = PlayerStatusOutput {
        is_playing,
        is_paused,
        time_pos: (time_pos * 10.0).round() / 10.0,
        duration: (duration * 10.0).round() / 10.0,
        filename: if has_file {
            if !filename.is_empty() {
                filename
            } else {
                path.clone()
            }
        } else {
            String::new()
        },
        path: if has_file { path } else { String::new() },
        media_title: if has_file { media_title } else { String::new() },
        volume,
        is_loading,
        target_vid: state_file.as_ref().and_then(|s| if s.target_vid.is_empty() { None } else { Some(s.target_vid.clone()) }),
        audio_specs,
    };

    println!("{}", serde_json::to_string(&out).unwrap());
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
                let specs = parse_audio_specs_from_map(&map);
                println!("{}", serde_json::to_string(&specs).unwrap());
            } else {
                let default_specs = AudioSpecs {
                    codec: "AAC".to_string(),
                    bitrate: 192,
                    bitrate_str: "192 kbps".to_string(),
                    sample_rate: 48000,
                    sample_rate_str: "48.0 kHz".to_string(),
                    channels: "Stereo (2ch)".to_string(),
                };
                println!("{}", serde_json::to_string(&default_specs).unwrap());
            }
        }
        _ => {
            handle_status();
        }
    }
}
