//! Core shared library for Nutsty native bridge & daemon.
//! Provides low-latency MPV socket IPC, memory purging, and OKLAB palette extraction.

use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use std::env;
use std::fs::File;
use std::io::{BufRead, BufReader, Write};
use std::path::PathBuf;
use std::time::Duration;

#[cfg(unix)]
use std::os::unix::net::UnixStream;

pub mod audio_specs;
pub mod palette;

#[derive(Debug, Serialize, Deserialize)]
pub struct PlaybackState {
    #[serde(default)]
    pub state: String,
    #[serde(default)]
    pub path: String,
    #[serde(default)]
    pub target_vid: String,
    #[serde(default)]
    pub timestamp: f64,
    /// mpv's path when the play request was made: until mpv reports another file, status
    /// describes the previous song (paused while the new stream resolves)
    #[serde(default)]
    pub prev_mpv_path: String,
}

pub use audio_specs::AudioSpecs;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PlayerStatusOutput {
    pub is_playing: bool,
    pub is_paused: bool,
    pub time_pos: f64,
    pub duration: f64,
    pub filename: String,
    pub path: String,
    pub media_title: String,
    pub volume: f64,
    pub is_loading: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub target_vid: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub audio_specs: Option<AudioSpecs>,
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

thread_local! {
    static PROFILE_OVERRIDE: std::cell::RefCell<Option<String>> = const { std::cell::RefCell::new(None) };
}

/// Profile whose mpv socket and state files this thread talks to: an override set by
/// `with_profile` (the shared daemon serves every profile window), else `NUTSTY_PROFILE`.
fn current_profile() -> String {
    PROFILE_OVERRIDE
        .with(|p| p.borrow().clone())
        .unwrap_or_else(|| env::var("NUTSTY_PROFILE").unwrap_or_default())
        .trim()
        .to_lowercase()
}

/// Runs `f` against another profile's mpv. Names outside [a-z0-9_-] are ignored, so a query
/// parameter can never point the socket path outside the temp dir.
pub fn with_profile<T>(profile: &str, f: impl FnOnce() -> T) -> T {
    let clean = profile.trim().to_lowercase();
    let valid = clean.chars().all(|c| c.is_ascii_alphanumeric() || c == '_' || c == '-');
    if !valid {
        return f();
    }
    let prev = PROFILE_OVERRIDE.with(|p| p.replace(Some(clean)));
    let out = f();
    PROFILE_OVERRIDE.with(|p| *p.borrow_mut() = prev);
    out
}

pub fn get_socket_path() -> PathBuf {
    let profile = current_profile();
    let suffix = if profile.is_empty() {
        String::new()
    } else {
        format!("_{profile}")
    };

    let temp_dir = env::temp_dir();
    temp_dir.join(format!("nutsty_mpv{suffix}.sock"))
}

pub fn get_state_file_path() -> PathBuf {
    let profile = current_profile();
    let suffix = if profile.is_empty() {
        String::new()
    } else {
        format!("_{profile}")
    };

    let temp_dir = env::temp_dir();
    temp_dir.join(format!("nutsty_playback_state{suffix}.json"))
}

pub fn get_abort_file_path() -> PathBuf {
    let profile = current_profile();
    let suffix = if profile.is_empty() {
        String::new()
    } else {
        format!("_{profile}")
    };

    let temp_dir = env::temp_dir();
    temp_dir.join(format!("nutsty_abort_fade{suffix}"))
}

#[cfg(unix)]
pub fn send_mpv_command_single(cmd: Value) -> Option<Value> {
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
pub fn get_pipe_path() -> String {
    let profile = current_profile();
    let suffix = if profile.is_empty() {
        String::new()
    } else {
        format!("_{profile}")
    };
    format!(r"\\.\pipe\nutsty_mpv{suffix}")
}

#[cfg(windows)]
pub fn send_mpv_command_single(cmd: Value) -> Option<Value> {
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
pub fn send_mpv_command_single(_cmd: Value) -> Option<Value> {
    None
}

#[cfg(unix)]
pub fn fetch_mpv_status_batch() -> Option<serde_json::Map<String, Value>> {
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
pub fn fetch_mpv_status_batch() -> Option<serde_json::Map<String, Value>> {
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
pub fn fetch_mpv_status_batch() -> Option<serde_json::Map<String, Value>> {
    None
}

pub fn purge_memory() -> bool {
    #[cfg(target_os = "linux")]
    unsafe {
        unsafe extern "C" {
            fn malloc_trim(pad: usize) -> i32;
        }
        malloc_trim(0) == 1
    }

    #[cfg(windows)]
    unsafe {
        unsafe extern "system" {
            fn SetProcessWorkingSetSize(hProcess: isize, dwMinimumWorkingSetSize: usize, dwMaximumWorkingSetSize: usize) -> i32;
        }
        SetProcessWorkingSetSize(-1, usize::MAX, usize::MAX) != 0
    }

    #[cfg(not(any(target_os = "linux", windows)))]
    false
}

pub fn read_playback_state() -> Option<PlaybackState> {
    let path = get_state_file_path();
    let file = File::open(path).ok()?;
    serde_json::from_reader(file).ok()
}

pub fn update_playback_state_playing(current_path: &str) {
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

/// Quality label data for the current profile, read from mpv plus player_daemon.py's files.
pub fn parse_audio_specs_from_map(map: &serde_json::Map<String, Value>) -> AudioSpecs {
    let profile = current_profile();
    let suffix = if profile.is_empty() { String::new() } else { format!("_{profile}") };
    audio_specs::audio_specs_for(map, &suffix)
}

/// What mpv reports right now, as far as the "is the requested song loaded" decision needs.
pub struct MpvSnapshot<'a> {
    pub path: &'a str,
    pub idle: bool,
    pub pause: bool,
    pub time_pos: f64,
    pub duration: f64,
}

#[derive(Debug, PartialEq, Eq)]
pub enum LoadingVerdict {
    /// The state file is not "loading"
    NotLoading,
    /// Still waiting for the requested song
    StillLoading,
    /// The requested song is open (or the wait timed out): the state file becomes "playing"
    Finished,
}

/// Seconds a request may keep mpv on the previous file before "loading" is dropped (a stream
/// that never resolves). The front end's own limit is 25 s.
pub const STALE_FILE_LOADING_LIMIT_SEC: f64 = 25.0;
/// Seconds before "loading" is dropped when there is no previous file to tell apart
pub const LOADING_LIMIT_SEC: f64 = 5.0;

/// While the next song resolves, mpv still holds the previous file, paused: its position and
/// length are not the requested song's. Only a different file (or idle -> a file) ends loading.
pub fn loading_verdict(state: Option<&PlaybackState>, mpv: &MpvSnapshot, now: f64) -> LoadingVerdict {
    let Some(sf) = state else { return LoadingVerdict::NotLoading };
    if sf.state != "loading" {
        return LoadingVerdict::NotLoading;
    }
    let age = if sf.timestamp > 0.0 { now - sf.timestamp } else { 0.0 };
    if !sf.prev_mpv_path.is_empty() && mpv.path == sf.prev_mpv_path {
        return if age > STALE_FILE_LOADING_LIMIT_SEC { LoadingVerdict::Finished } else { LoadingVerdict::StillLoading };
    }
    let opened = (!mpv.idle && (mpv.time_pos > 0.2 || mpv.duration > 0.0))
        || (!mpv.path.is_empty() && !mpv.idle && !mpv.pause);
    if opened || (sf.timestamp > 0.0 && age > LOADING_LIMIT_SEC) {
        LoadingVerdict::Finished
    } else {
        LoadingVerdict::StillLoading
    }
}

pub fn get_player_status_output() -> PlayerStatusOutput {
    let batch = fetch_mpv_status_batch();
    if batch.is_none() {
        return PlayerStatusOutput::default();
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
    let now = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_secs_f64())
        .unwrap_or(0.0);
    let snap = MpvSnapshot { path: &path, idle, pause, time_pos, duration };
    let is_loading = match loading_verdict(state_file.as_ref(), &snap, now) {
        LoadingVerdict::NotLoading => false,
        LoadingVerdict::StillLoading => true,
        LoadingVerdict::Finished => {
            update_playback_state_playing(&path);
            false
        }
    };

    let has_file = (!path.is_empty() || !filename.is_empty()) && !idle && (!is_loading || time_pos > 0.0);

    let is_playing = !pause && has_file;
    let is_paused = pause && has_file;

    let audio_specs = if has_file {
        Some(parse_audio_specs_from_map(&map))
    } else {
        None
    };

    PlayerStatusOutput {
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
    }
}

#[cfg(test)]
mod loading_tests {
    use super::*;

    const OLD: &str = "https://rr1.googlevideo.com/videoplayback?id=A";
    const NEW: &str = "https://rr2.googlevideo.com/videoplayback?id=B";

    fn loading(prev: &str, ts: f64) -> PlaybackState {
        PlaybackState {
            state: "loading".into(),
            path: "ytdl://BBBBBBBBBBB".into(),
            target_vid: "BBBBBBBBBBB".into(),
            timestamp: ts,
            prev_mpv_path: prev.into(),
        }
    }

    fn mpv(path: &str, pause: bool, time_pos: f64, duration: f64) -> MpvSnapshot<'_> {
        MpvSnapshot { path, idle: false, pause, time_pos, duration }
    }

    #[test]
    fn previous_file_still_open_keeps_loading() {
        // The bug: the old song (paused at 120 s of 260 s) used to end "loading" at once
        let sf = loading(OLD, 1000.0);
        assert_eq!(loading_verdict(Some(&sf), &mpv(OLD, true, 120.0, 260.0), 1000.5), LoadingVerdict::StillLoading);
        // ...and past the 5 s generic limit, since yt-dlp can take longer
        assert_eq!(loading_verdict(Some(&sf), &mpv(OLD, true, 120.0, 260.0), 1012.0), LoadingVerdict::StillLoading);
    }

    #[test]
    fn new_file_opening_ends_loading() {
        let sf = loading(OLD, 1000.0);
        assert_eq!(loading_verdict(Some(&sf), &mpv(NEW, false, 0.4, 200.0), 1002.0), LoadingVerdict::Finished);
    }

    #[test]
    fn stream_that_never_resolves_times_out() {
        let sf = loading(OLD, 1000.0);
        let t = 1000.0 + STALE_FILE_LOADING_LIMIT_SEC + 1.0;
        assert_eq!(loading_verdict(Some(&sf), &mpv(OLD, true, 120.0, 260.0), t), LoadingVerdict::Finished);
    }

    #[test]
    fn without_previous_path_behaves_as_before() {
        // Older daemon (no prev_mpv_path) or mpv was idle: any open file ends loading
        let sf = loading("", 1000.0);
        assert_eq!(loading_verdict(Some(&sf), &mpv(OLD, true, 120.0, 260.0), 1000.5), LoadingVerdict::Finished);
        let idle = MpvSnapshot { path: "", idle: true, pause: true, time_pos: 0.0, duration: 0.0 };
        assert_eq!(loading_verdict(Some(&sf), &idle, 1002.0), LoadingVerdict::StillLoading);
        assert_eq!(loading_verdict(Some(&sf), &idle, 1006.0), LoadingVerdict::Finished);
    }

    #[test]
    fn not_loading_states_are_left_alone() {
        assert_eq!(loading_verdict(None, &mpv(OLD, false, 1.0, 9.0), 0.0), LoadingVerdict::NotLoading);
        let mut sf = loading(OLD, 1000.0);
        sf.state = "playing".into();
        assert_eq!(loading_verdict(Some(&sf), &mpv(OLD, false, 1.0, 9.0), 1001.0), LoadingVerdict::NotLoading);
    }

    #[test]
    fn state_file_from_daemon_parses() {
        let sf: PlaybackState = serde_json::from_str(
            r#"{"state":"loading","path":"ytdl://B","target_vid":"B","timestamp":5.0,"epoch":7,"prev_mpv_path":"x"}"#,
        ).unwrap();
        assert_eq!(sf.prev_mpv_path, "x");
        let old: PlaybackState = serde_json::from_str(r#"{"state":"loading","path":"p","timestamp":5.0}"#).unwrap();
        assert!(old.prev_mpv_path.is_empty());
    }
}
