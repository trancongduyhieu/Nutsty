//! Truthful quality label data, the same schema as backend/audio_output.py build_audio_specs.
//! Unknown values stay None or empty so the UI shows a dash, never a made-up number.
use serde::{Deserialize, Serialize};
use serde_json::{Map, Value};
use std::ffi::OsString;
use std::path::{Path, PathBuf};

const LOSSLESS_CODECS: [&str; 7] = ["flac", "alac", "wavpack", "ape", "tta", "truehd", "mlp"];

#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
pub struct AudioSpecs {
    pub source: String,
    pub codec: String,
    pub bit_depth: Option<u64>,
    pub sample_rate: Option<u64>,
    pub bitrate_kbps: Option<u64>,
    pub channels: Option<u64>,
    pub lossless: bool,
    pub output_rate: Option<u64>,
    pub via_windows_mixer: bool,
    pub lossless_suspended: bool,
    pub bitrate_str: String,
    pub sample_rate_str: String,
    pub channels_str: String,
}

pub fn is_lossless_codec(codec: &str) -> bool {
    let c = codec.to_lowercase();
    LOSSLESS_CODECS.contains(&c.as_str()) || c.starts_with("pcm")
}

fn bit_depth_from_format(fmt: &str, lossless: bool) -> Option<u64> {
    let f = fmt.to_lowercase();
    if f.starts_with("s16") {
        Some(16)
    } else if lossless && (f.starts_with("s24") || f.starts_with("s32")) {
        Some(24)
    } else {
        None
    }
}

fn source_of(path: &str, now_source: &Value) -> String {
    let tidal_url = now_source.pointer("/tidal/url").and_then(Value::as_str).unwrap_or("");
    let is_tidal = now_source.get("source").and_then(Value::as_str) == Some("tidal");
    if !path.is_empty() && is_tidal && tidal_url == path {
        return "tidal".into();
    }
    if path.is_empty() {
        return String::new();
    }
    let lower = path.to_lowercase();
    if ["http://", "https://", "ytdl://", "edl://"].iter().any(|p| lower.starts_with(p)) {
        "youtube".into()
    } else {
        "local".into()
    }
}

fn rate_str(rate: Option<u64>) -> String {
    match rate {
        Some(r) if r > 0 => {
            let khz = (r as f64 / 100.0).round() / 10.0;
            if khz.fract() == 0.0 { format!("{} kHz", khz as u64) } else { format!("{khz} kHz") }
        }
        _ => String::new(),
    }
}

fn channels_str(n: Option<u64>) -> String {
    match n {
        Some(1) => "Mono (1ch)".into(),
        Some(2) => "Stereo (2ch)".into(),
        Some(n) if n > 0 => format!("{n}ch"),
        _ => String::new(),
    }
}

fn positive(v: Option<&Value>) -> Option<u64> {
    v.and_then(Value::as_f64).filter(|x| *x > 0.0).map(|x| x as u64)
}

/// map: mpv properties audio-codec-name, audio-bitrate, audio-params, path.
pub fn build_audio_specs(
    map: &Map<String, Value>,
    now_source: &Value,
    dac_mode: &str,
    suspended: bool,
    is_windows: bool,
    alsa_rate: Option<u64>,
) -> AudioSpecs {
    let codec = map.get("audio-codec-name").and_then(Value::as_str).unwrap_or("").to_lowercase();
    let path = map.get("path").and_then(Value::as_str).unwrap_or("");
    let empty = Map::new();
    let params = map.get("audio-params").and_then(Value::as_object).unwrap_or(&empty);
    let lossless = is_lossless_codec(&codec);
    let source = source_of(path, now_source);

    let sample_rate = positive(params.get("samplerate"));
    let channels = positive(params.get("channel-count"));
    let bitrate_kbps = map
        .get("audio-bitrate")
        .and_then(Value::as_f64)
        .filter(|b| *b > 0.0)
        .map(|b| (b / 1000.0).round() as u64)
        .filter(|k| *k > 0);

    let mut bit_depth = None;
    if source == "tidal" {
        bit_depth = positive(now_source.pointer("/tidal/bit_depth"));
    }
    if bit_depth.is_none() {
        bit_depth = bit_depth_from_format(params.get("format").and_then(Value::as_str).unwrap_or(""), lossless);
    }

    let output_rate = match (is_windows, alsa_rate, sample_rate) {
        (false, Some(a), Some(s)) if a != s => Some(a),
        _ => None,
    };

    AudioSpecs {
        source,
        codec: codec.to_uppercase(),
        bit_depth,
        sample_rate,
        bitrate_kbps,
        channels,
        lossless,
        output_rate,
        via_windows_mixer: is_windows && dac_mode != "exclusive",
        lossless_suspended: suspended,
        bitrate_str: bitrate_kbps.map(|k| format!("{k} kbps")).unwrap_or_default(),
        sample_rate_str: rate_str(sample_rate),
        channels_str: channels_str(channels),
    }
}

/// Rate of the first playback stream in state RUNNING under /proc/asound, or None.
pub fn read_alsa_running_rate(proc_root: &Path) -> Option<u64> {
    let mut cards: Vec<PathBuf> = std::fs::read_dir(proc_root).ok()?.flatten().map(|e| e.path())
        .filter(|p| p.file_name().and_then(|n| n.to_str()).is_some_and(|n| n.starts_with("card")))
        .collect();
    cards.sort();
    for card in cards {
        let Ok(pcms) = std::fs::read_dir(&card) else { continue };
        let mut pcms: Vec<PathBuf> = pcms.flatten().map(|e| e.path())
            .filter(|p| p.file_name().and_then(|n| n.to_str()).is_some_and(|n| n.starts_with("pcm") && n.ends_with('p')))
            .collect();
        pcms.sort();
        for pcm in pcms {
            let Ok(subs) = std::fs::read_dir(&pcm) else { continue };
            let mut subs: Vec<PathBuf> = subs.flatten().map(|e| e.path())
                .filter(|p| p.file_name().and_then(|n| n.to_str()).is_some_and(|n| n.starts_with("sub")))
                .collect();
            subs.sort();
            for sub in subs {
                let running = std::fs::read_to_string(sub.join("status")).map(|s| s.contains("RUNNING")).unwrap_or(false);
                if !running {
                    continue;
                }
                let hw = std::fs::read_to_string(sub.join("hw_params")).unwrap_or_default();
                if let Some(rate) = hw.lines().find_map(|l| l.strip_prefix("rate:")).and_then(|r| r.split_whitespace().next()?.parse().ok()) {
                    return Some(rate);
                }
            }
        }
    }
    None
}

/// Where player_daemon.py keeps its temp files: /tmp on Linux, %TEMP%\nutsty on Windows.
pub fn python_temp_dir() -> PathBuf {
    if cfg!(windows) { std::env::temp_dir().join("nutsty") } else { PathBuf::from("/tmp") }
}

/// Home the way Python's `expanduser("~")` sees it: Windows uses USERPROFILE even when a
/// shell (Git Bash, MSYS) also sets HOME, so both sides read the same settings file.
fn pick_home(is_windows: bool, home: Option<OsString>, userprofile: Option<OsString>) -> Option<PathBuf> {
    let (first, second) = if is_windows { (userprofile, home) } else { (home, userprofile) };
    first.filter(|v| !v.is_empty()).or(second.filter(|v| !v.is_empty())).map(PathBuf::from)
}

fn config_dir() -> Option<PathBuf> {
    let xdg = std::env::var_os("XDG_CONFIG_HOME").filter(|v| !v.is_empty()).map(PathBuf::from);
    let home = pick_home(cfg!(windows), std::env::var_os("HOME"), std::env::var_os("USERPROFILE"));
    Some(xdg.or_else(|| home.map(|h| h.join(".config")))?.join("noctalia"))
}

fn read_json(path: &Path) -> Value {
    std::fs::read_to_string(path).ok().and_then(|s| serde_json::from_str(&s).ok()).unwrap_or(Value::Null)
}

/// Same rule as `get_lossless_settings` in player_daemon.py: the DAC mode stands alone, but one
/// saved before that (no `dacModeStandalone`) only counted while lossless was on.
pub fn effective_dac_mode(settings: &Value) -> String {
    let flag = |k: &str| settings.get(k).and_then(Value::as_bool) == Some(true);
    let mode = settings.get("dacOutputMode").and_then(Value::as_str).unwrap_or("shared");
    let known = matches!(mode, "shared" | "rate_match" | "exclusive");
    if (flag("dacModeStandalone") || flag("losslessEnabled")) && known { mode.into() } else { "shared".into() }
}

/// Reads the files player_daemon.py writes (now source, suspend flag, settings) for `suffix`.
pub fn audio_specs_for(map: &Map<String, Value>, suffix: &str) -> AudioSpecs {
    let tmp = python_temp_dir();
    let now_source = read_json(&tmp.join(format!("nutsty_now_source{suffix}.json")));
    let suspended = tmp.join(format!("nutsty_lossless_suspended{suffix}")).exists();
    let dac_mode = config_dir()
        .map(|d| effective_dac_mode(&read_json(&d.join(format!("nutsty_settings{suffix}.json")))))
        .unwrap_or_else(|| "shared".into());
    let is_windows = cfg!(windows);
    let alsa = if is_windows { None } else { read_alsa_running_rate(Path::new("/proc/asound")) };
    build_audio_specs(map, &now_source, &dac_mode, suspended, is_windows, alsa)
}

#[cfg(test)]
mod tests {
    #[test]
    fn windows_home_is_userprofile_like_python() {
        use std::ffi::OsString;
        let h = || Some(OsString::from("/c/Users/duy"));
        let u = || Some(OsString::from("C:\\Users\\duy"));
        assert_eq!(super::pick_home(true, h(), u()), Some(PathBuf::from("C:\\Users\\duy")));
        assert_eq!(super::pick_home(false, h(), u()), Some(PathBuf::from("/c/Users/duy")));
        assert_eq!(super::pick_home(true, h(), None), Some(PathBuf::from("/c/Users/duy")));
    }

    #[test]
    fn dac_mode_stands_alone_but_old_saves_need_lossless() {
        use serde_json::json;
        assert_eq!(super::effective_dac_mode(&json!({"dacOutputMode": "exclusive", "dacModeStandalone": true})), "exclusive");
        assert_eq!(super::effective_dac_mode(&json!({"dacOutputMode": "exclusive", "losslessEnabled": true})), "exclusive");
        assert_eq!(super::effective_dac_mode(&json!({"dacOutputMode": "exclusive"})), "shared");
        assert_eq!(super::effective_dac_mode(&json!({"dacOutputMode": "weird", "dacModeStandalone": true})), "shared");
    }

    use super::*;
    use serde_json::json;

    fn m(v: Value) -> Map<String, Value> {
        v.as_object().unwrap().clone()
    }

    #[test]
    fn unknown_is_not_made_up() {
        let s = build_audio_specs(&Map::new(), &Value::Null, "shared", false, false, None);
        assert_eq!(s.codec, "");
        assert_eq!((s.sample_rate, s.bitrate_kbps, s.bit_depth, s.channels), (None, None, None, None));
        assert!(!s.lossless);
        assert_eq!((s.bitrate_str.as_str(), s.sample_rate_str.as_str(), s.channels_str.as_str()), ("", "", ""));
    }

    #[test]
    fn local_flac_24bit() {
        let map = m(json!({"audio-codec-name": "flac", "path": "/m/a.flac",
            "audio-params": {"samplerate": 96000, "format": "s32", "channel-count": 2}}));
        let s = build_audio_specs(&map, &Value::Null, "shared", false, false, Some(96000));
        assert_eq!((s.codec.as_str(), s.bit_depth, s.sample_rate, s.lossless), ("FLAC", Some(24), Some(96000), true));
        assert_eq!((s.source.as_str(), s.channels, s.output_rate), ("local", Some(2), None));
        assert_eq!((s.sample_rate_str.as_str(), s.channels_str.as_str()), ("96 kHz", "Stereo (2ch)"));
    }

    #[test]
    fn opus_is_lossy() {
        let map = m(json!({"audio-codec-name": "opus", "audio-bitrate": 141000.0, "path": "https://rr1.googlevideo.com/x",
            "audio-params": {"samplerate": 48000, "format": "floatp", "channel-count": 2}}));
        let s = build_audio_specs(&map, &Value::Null, "shared", false, false, None);
        assert!(!s.lossless);
        assert_eq!((s.codec.as_str(), s.bitrate_kbps, s.bit_depth, s.source.as_str()), ("OPUS", Some(141), None, "youtube"));
        assert_eq!(s.bitrate_str, "141 kbps");
    }

    #[test]
    fn tidal_bit_depth_only_for_matching_url() {
        let url = "file:///tmp/nutsty_tidal/t.mpd";
        let now = json!({"source": "tidal", "tidal": {"url": url, "bit_depth": 24}});
        let map = m(json!({"audio-codec-name": "flac", "path": url, "audio-params": {"samplerate": 192000, "format": "floatp"}}));
        let s = build_audio_specs(&map, &now, "shared", false, false, None);
        assert_eq!((s.source.as_str(), s.bit_depth, s.sample_rate_str.as_str()), ("tidal", Some(24), "192 kHz"));
        let other = m(json!({"audio-codec-name": "opus", "path": "https://yt/x"}));
        assert_eq!(build_audio_specs(&other, &now, "shared", false, false, None).source, "youtube");
    }

    #[test]
    fn output_rate_and_windows_mixer() {
        let map = m(json!({"audio-codec-name": "flac", "path": "/m/b.flac", "audio-params": {"samplerate": 44100, "format": "s16"}}));
        let s = build_audio_specs(&map, &Value::Null, "shared", false, false, Some(48000));
        assert_eq!((s.output_rate, s.bit_depth, s.sample_rate_str.as_str()), (Some(48000), Some(16), "44.1 kHz"));
        let w = build_audio_specs(&map, &Value::Null, "shared", true, true, Some(48000));
        assert!(w.via_windows_mixer && w.lossless_suspended);
        assert_eq!(w.output_rate, None);
        assert!(!build_audio_specs(&map, &Value::Null, "exclusive", false, true, None).via_windows_mixer);
    }

    #[test]
    fn alsa_running_rate() {
        let root = std::env::temp_dir().join(format!("nutsty_asound_test_{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&root);
        for (card, state, hw) in [("card0", "closed", "closed\n"), ("card1", "state: RUNNING\n", "format: S32_LE\nrate: 48000 (48000/1)\n")] {
            let d = root.join(card).join("pcm0p").join("sub0");
            std::fs::create_dir_all(&d).unwrap();
            std::fs::write(d.join("status"), state).unwrap();
            std::fs::write(d.join("hw_params"), hw).unwrap();
        }
        assert_eq!(read_alsa_running_rate(&root), Some(48000));
        std::fs::write(root.join("card1/pcm0p/sub0/status"), "state: PREPARED\n").unwrap();
        assert_eq!(read_alsa_running_rate(&root), None);
        assert_eq!(read_alsa_running_rate(&root.join("missing")), None);
        let _ = std::fs::remove_dir_all(&root);
    }
}
