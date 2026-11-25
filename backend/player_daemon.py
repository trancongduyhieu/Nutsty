#!/usr/bin/env python3
"""
Nutsty MPV Audio Controller & IPC Bridge
Controls playback losslessly via MPV socket and status polling
"""
import os
import sys
import json
import time
import math
import socket
import subprocess
import threading

try:
    from . import platform_compat as pc
except (ImportError, ValueError):
    import platform_compat as pc

try:
    from . import crossfade_engine as xf
except (ImportError, ValueError):
    import crossfade_engine as xf

try:
    from . import ytmusic_helper
except (ImportError, ValueError):
    try:
        import ytmusic_helper
    except Exception:
        ytmusic_helper = None

PROFILE_NAME = os.getenv("NUTSTY_PROFILE", "").strip().lower()
PROFILE_SUFFIX = f"_{PROFILE_NAME}" if PROFILE_NAME else ""

TEMP_DIR = pc.get_temp_dir()
CONFIG_DIR = pc.get_config_dir()
IPC_TYPE, IPC_TARGET = pc.get_mpv_ipc_target(PROFILE_SUFFIX)

MPV_SOCKET = IPC_TARGET if IPC_TYPE == "unix" else f"{IPC_TARGET[0]}:{IPC_TARGET[1]}"
STATUS_FILE = os.path.join(TEMP_DIR, f"nutsty_status{PROFILE_SUFFIX}.json")
COMMAND_FILE = os.path.join(TEMP_DIR, f"nutsty_cmd{PROFILE_SUFFIX}.pipe")
LOG_FILE = os.path.join(TEMP_DIR, f"nutsty_mpv{PROFILE_SUFFIX}.log")
LAST_PATH_FILE = os.path.join(TEMP_DIR, f"nutsty_last_path{PROFILE_SUFFIX}")
ABORT_FILE = os.path.join(TEMP_DIR, f"nutsty_abort_fade{PROFILE_SUFFIX}")
PLAYBACK_STATE_FILE = os.path.join(TEMP_DIR, f"nutsty_playback_state{PROFILE_SUFFIX}.json")
PLAYLIST_FILE = os.path.join(TEMP_DIR, f"nutsty_playlist{PROFILE_SUFFIX}.m3u")
CURRENT_TRACK_FILE = os.path.join(TEMP_DIR, f"nutsty_current_track{PROFILE_SUFFIX}.json")
PLAY_REQ_FILE = os.path.join(TEMP_DIR, f"nutsty_active_play{PROFILE_SUFFIX}.json")
MPV_TITLE = f"nutsty-audio{PROFILE_SUFFIX}"
# Lossless (Tidal): Listen Along suspension flag, what the main mpv is playing now, songs to keep off Tidal
LOSSLESS_SUSPEND_FILE = os.path.join(TEMP_DIR, f"nutsty_lossless_suspended{PROFILE_SUFFIX}")
NOW_SOURCE_FILE = os.path.join(TEMP_DIR, f"nutsty_now_source{PROFILE_SUFFIX}.json")
TIDAL_SKIP_FILE = os.path.join(TEMP_DIR, f"nutsty_tidal_skip{PROFILE_SUFFIX}.json")
TIDAL_SKIP_AFTER_FAILURE_S = 600

def record_active_play_epoch(epoch, file_path, target_vid):
    payload = {
        "epoch": epoch,
        "pid": os.getpid(),
        "target_vid": target_vid,
        "file_path": file_path,
        "timestamp": time.time()
    }
    try:
        with open(PLAY_REQ_FILE, "w", encoding="utf-8") as f:
            json.dump(payload, f)
    except Exception:
        pass

def get_active_play_epoch():
    try:
        if not os.path.exists(PLAY_REQ_FILE):
            return 0
        with open(PLAY_REQ_FILE, "r", encoding="utf-8") as f:
            data = json.load(f)
            return data.get("epoch", 0)
    except Exception:
        return 0

def is_play_epoch_active(my_epoch):
    if my_epoch <= 0:
        return True
    active = get_active_play_epoch()
    if active <= 0:
        return True
    # Prevent dropping play request if active was millisecond timestamp while my_epoch was counter
    if active > 1e11 and my_epoch < 1e9:
        return True
    return my_epoch >= active

YTDL_FORMAT_MAP = {
    "high_opus": "774/251/250/249/141/140/bestaudio/best",
    "high_aac": "141/140/774/251/250/bestaudio/best",
    "medium": "251/140/bestaudio/best",
    "low": "250/ba[abr<=70]/bestaudio/best"
}

def _read_settings():
    settings_path = os.path.join(CONFIG_DIR, f"nutsty_settings{PROFILE_SUFFIX}.json")
    if not os.path.exists(settings_path) and not PROFILE_SUFFIX:
        settings_path = os.path.join(CONFIG_DIR, "nutsty_settings.json")
    if os.path.exists(settings_path):
        try:
            with open(settings_path, "r", encoding="utf-8") as f:
                data = json.load(f)
                return data if isinstance(data, dict) else {}
        except Exception:
            pass
    return {}

def get_current_streaming_quality():
    return _read_settings().get("streamingQuality", "high_opus")

def get_lossless_settings():
    s = _read_settings()
    quality = s.get("losslessQuality")
    dac_mode = s.get("dacOutputMode")
    if dac_mode not in ("shared", "rate_match", "exclusive") or (dac_mode == "rate_match" and pc.IS_WINDOWS):
        dac_mode = "shared"
    return {
        "enabled": bool(s.get("losslessEnabled", False)),
        "quality": quality if quality in ("lossless", "hires") else "lossless",
        "dac_mode": dac_mode,
    }

def _load_tidal():
    import tidal_source
    return tidal_source

def is_lossless_suspended():
    return os.path.exists(LOSSLESS_SUSPEND_FILE)

def _read_json_file(path, default):
    try:
        with open(path, "r", encoding="utf-8") as f:
            return json.load(f)
    except Exception:
        return default

def _write_json_file(path, data):
    try:
        tmp = path + ".tmp"
        with open(tmp, "w", encoding="utf-8") as f:
            json.dump(data, f)
        os.replace(tmp, path)
    except Exception:
        pass

def record_now_source(target_vid, source, tidal=None):
    """What the main mpv plays: "tidal" | "youtube" | "local", with the TidalStream when Tidal."""
    _write_json_file(NOW_SOURCE_FILE, {"target_vid": target_vid or "", "source": source,
                                       "tidal": tidal, "timestamp": time.time()})

def read_now_source():
    return _read_json_file(NOW_SOURCE_FILE, {}) or {}

def _tidal_skipped(vid):
    until = (_read_json_file(TIDAL_SKIP_FILE, {}) or {}).get(vid, 0)
    return float(until or 0) > time.time()

def _skip_tidal_for(vid, seconds):
    now = time.time()
    data = {k: v for k, v in (_read_json_file(TIDAL_SKIP_FILE, {}) or {}).items() if float(v or 0) > now}
    data[vid] = now + seconds
    _write_json_file(TIDAL_SKIP_FILE, data)

def _try_tidal(vid, title, artist, duration_s):
    """TidalStream when lossless is on, not suspended for Listen Along, and Tidal finds the song."""
    try:
        settings = get_lossless_settings()
        if not settings["enabled"] or is_lossless_suspended() or _tidal_skipped(vid):
            return None
        tidal = _load_tidal()
        if not tidal.status().get("logged_in"):
            return None
        return tidal.resolve(vid, title, artist, duration_s, settings["quality"])
    except Exception as e:
        sys.stderr.write(f"[player_daemon] Tidal lookup failed, using YouTube: {type(e).__name__}\n")
        return None

DEFAULT_UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/147.0.0.0 Safari/537.36"

_MPV_LOCK = threading.Lock()
_PLAY_REQ_LOCK = threading.Lock()
_ACTIVE_PLAY_REQ_ID = 0
_CURRENT_PLAYING_VID = ""
_CURRENT_PLAYING_PATH = ""

def is_mpv_running():
    if pc.IS_WINDOWS:
        return pc.is_process_running("mpv.exe")
    return pc.is_process_running(MPV_TITLE)

def _mpv_stream_args(ytdl_fmt, user_agent=DEFAULT_UA):
    """Network/ytdl flags shared by the main mpv and the crossfade tail mpv."""
    args = [
        f"--ytdl-format={ytdl_fmt}",
        "--ytdl-raw-options=extractor-args=youtube:player_client=android",
        f"--user-agent={user_agent}",
        "--referrer=https://www.youtube.com/",
    ]
    ytdl_bin = pc.get_binary_path("yt-dlp")
    if ytdl_bin and os.path.exists(ytdl_bin):
        safe_ytdl = ytdl_bin.replace("\\", "/")
        args.append(f"--script-opts=ytdl_hook-ytdl_path={safe_ytdl}")
    try:
        import ytmusic_helper as _yh
        cookie_file = _yh.get_exported_cookie_file()
        if cookie_file and os.path.exists(cookie_file):
            safe_cookie = cookie_file.replace("\\", "/")
            args.append(f"--cookies-file={safe_cookie}")
            args.append(f"--ytdl-raw-options=cookies={safe_cookie},extractor-args=youtube:player_client=android")
    except Exception:
        pass
    return args

def ensure_mpv(force_shared=False):
    """Ensure background MPV process is running with IPC socket safely without process thrashing.
    force_shared: start without the bit-perfect flag (the DAC refused exclusive access)."""
    with _MPV_LOCK, pc.InterprocessLock(os.path.join(TEMP_DIR, f"nutsty_mpv_spawn{PROFILE_SUFFIX}.lock")):
        # 1. If socket responds, we are good
        try:
            s = pc.connect_mpv_socket(IPC_TYPE, IPC_TARGET, timeout=0.8)
            s.close()
            return True
        except Exception:
            pass

        # 2. If MPV process is alive, give it time to initialize before considering it dead
        if is_mpv_running():
            for _ in range(8):
                time.sleep(0.2)
                try:
                    s = pc.connect_mpv_socket(IPC_TYPE, IPC_TARGET, timeout=0.5)
                    s.close()
                    return True
                except Exception:
                    pass
            try:
                if pc.IS_WINDOWS:
                    pc.kill_process("mpv.exe")
                else:
                    pc.kill_process(MPV_TITLE)
                time.sleep(0.15)
            except Exception:
                pass

        # 3. Only if MPV process is definitely not running, clean up stale socket file (if Unix socket)
        if IPC_TYPE == "unix" and os.path.exists(IPC_TARGET):
            try:
                os.remove(IPC_TARGET)
            except Exception:
                pass

        streaming_quality = get_current_streaming_quality()
        ytdl_fmt = YTDL_FORMAT_MAP.get(streaming_quality, "774/141/251/140/bestaudio/best")

        mpv_bin = pc.get_binary_path("mpv")
        ipc_arg = pc.get_mpv_ipc_arg(IPC_TYPE, IPC_TARGET)

        mpv_cache_dir = os.path.join(pc.get_cache_dir(), "mpv_stream_cache")
        os.makedirs(mpv_cache_dir, exist_ok=True)
        safe_cache_dir = mpv_cache_dir.replace("\\", "/")

        cmd = [
            mpv_bin,
            "--no-config",
            "--idle=yes",
            "--pause=no",
            "--no-video",
            "--no-terminal",
            "--force-window=no",
            ipc_arg,
            "--cache=yes",
            f"--demuxer-cache-dir={safe_cache_dir}",
            "--cache-on-disk=yes",
            "--demuxer-max-bytes=64M",
            "--demuxer-max-back-bytes=32M",
            "--demuxer-readahead-secs=60",
            "--cache-secs=120",
            "--audio-buffer=0.8",
            "--network-timeout=10",
            f"--title={MPV_TITLE}",
            "--loop-playlist=no",
            "--gapless-audio=yes",
            f"--log-file={LOG_FILE}"
        ]
        cmd.extend(_mpv_stream_args(ytdl_fmt))
        import audio_output
        dac_args = [] if force_shared else audio_output.mpv_output_args(get_lossless_settings())
        if dac_args:
            # Bit-perfect: in-app volume stays at 100%, the DAC or the headphones set the level
            cmd.extend(dac_args + ["--volume=100"])

        popen_kwargs = pc.get_daemon_popen_kwargs()
        proc = subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, **popen_kwargs)

        # Wait for socket to appear and accept connection
        for _ in range(25):
            time.sleep(0.1)
            if dac_args and proc.poll() is not None:
                break
            try:
                s = pc.connect_mpv_socket(IPC_TYPE, IPC_TARGET, timeout=1.0)
                s.close()
                return True
            except Exception:
                pass
        if dac_args and proc.poll() is not None:
            _mark_exclusive_failed()
        else:
            return False
    # mpv quit at once with the exclusive flag: start it again the normal way
    return ensure_mpv(force_shared=True)


EXCLUSIVE_FAILED_FILE = os.path.join(TEMP_DIR, f"nutsty_exclusive_failed{PROFILE_SUFFIX}")
AO_FAILURE_MARKERS = ("Failed to initialize audio driver", "Could not open/initialize audio device")


def _mark_exclusive_failed():
    try:
        open(EXCLUSIVE_FAILED_FILE, "w").close()
    except OSError:
        pass


def _take_exclusive_failed():
    """True once after ensure_mpv had to drop the exclusive flag."""
    try:
        os.remove(EXCLUSIVE_FAILED_FILE)
        return True
    except OSError:
        return False


def _ao_failed_in_log(wait_s=2.5):
    """The audio output could not open the device (another app holds it in exclusive mode)."""
    deadline = time.time() + wait_s
    while time.time() < deadline:
        try:
            with open(LOG_FILE, "r", encoding="utf-8", errors="replace") as f:
                text = f.read()
            if any(m in text for m in AO_FAILURE_MARKERS):
                return True
        except OSError:
            pass
        if get_mpv_property("current-ao"):
            return False
        time.sleep(0.25)
    return False


def _stop_main_mpv():
    try:
        send_mpv_cmd(["quit"], timeout=1.0)
    except Exception:
        pass
    for _ in range(20):
        if not is_mpv_running():
            return
        time.sleep(0.1)
    pc.kill_process("mpv.exe" if pc.IS_WINDOWS else MPV_TITLE)
    time.sleep(0.15)


def restart_mpv_keep_position():
    """Apply a new DAC mode: start mpv again with the right flags and carry on from the same spot.
    Nothing happens when mpv already runs with the wanted mode."""
    import audio_output
    want_exclusive = bool(audio_output.mpv_output_args(get_lossless_settings()))
    try:
        s = pc.connect_mpv_socket(IPC_TYPE, IPC_TARGET, timeout=0.8)
        s.close()
        alive = True
    except Exception:
        alive = False
    if alive and bool(get_mpv_property("audio-exclusive")) == want_exclusive:
        return {"restarted": False, "exclusive_failed": _take_exclusive_failed()}
    path = get_mpv_property("path") if alive else None
    pos = (get_mpv_property("time-pos") or 0.0) if alive else 0.0
    paused = (get_mpv_property("pause") is True) if alive else False
    volume = get_mpv_property("volume") if alive else None
    # Streams resolved with a client-specific UA (YouTube android) 403 on a fresh mpv without it
    user_agent = get_mpv_property("user-agent") if alive else None
    if alive:
        _stop_main_mpv()

    def _load():
        if path:
            if user_agent:
                send_mpv_cmd(["set_property", "user-agent", user_agent])
            send_mpv_cmd({"name": "loadfile", "url": path, "flags": "replace", "index": -1,
                          "options": {"start": f"{max(0.0, float(pos)):.3f}", "pause": "yes" if paused else "no"}})
        if volume is not None and not (want_exclusive and not failed):
            send_mpv_cmd(["set_property", "volume", volume])

    failed = False
    ensure_mpv()
    failed = _take_exclusive_failed()
    _load()
    if want_exclusive and not failed and path and _ao_failed_in_log():
        failed = True
        _stop_main_mpv()
        ensure_mpv(force_shared=True)
        _load()
    return {"restarted": True, "exclusive_failed": failed}

def send_mpv_cmd(command_args, timeout=2.0):
    """Send JSON IPC command to MPV"""
    ensure_mpv()
    with _MPV_LOCK:
        try:
            s = pc.connect_mpv_socket(IPC_TYPE, IPC_TARGET, timeout=timeout)
            payload = json.dumps({"command": command_args}) + "\n"
            s.sendall(payload.encode("utf-8"))
            data = s.recv(4096)
            s.close()
            return json.loads(data.decode("utf-8"))
        except Exception as e:
            return {"error": str(e)}

def get_mpv_properties_batch(props):
    """Retrieve multiple MPV properties in a single socket connection (non-destructive read-only query)"""
    s = None
    try:
        s = pc.connect_mpv_socket(IPC_TYPE, IPC_TARGET, timeout=0.6)
    except Exception:
        # Non-destructive: Never kill MPV during read-only status poll!
        return {}

    try:
        payload = "".join(json.dumps({"command": ["get_property", p], "request_id": i}) + "\n" for i, p in enumerate(props))
        s.sendall(payload.encode("utf-8"))
        buf = ""
        results = {}
        deadline = time.time() + 0.6
        while len(results) < len(props) and time.time() < deadline:
            data = s.recv(4096)
            if not data:
                break
            try:
                chunk = data.decode("utf-8", errors="ignore")
            except Exception:
                chunk = ""
            buf += chunk
            while "\n" in buf:
                line, buf = buf.split("\n", 1)
                if line.strip():
                    try:
                        obj = json.loads(line)
                        idx = obj.get("request_id")
                        if idx is not None and idx < len(props):
                            results[props[idx]] = obj.get("data")
                    except Exception:
                        pass
        return results
    except Exception:
        return {}
    finally:
        if s is not None:
            try:
                s.close()
            except Exception:
                pass

def get_mpv_property(prop):
    res = send_mpv_cmd(["get_property", prop])
    return res.get("data")

def find_local_downloaded_file(vid="", title="", artist=""):
    """Check audio_cache, download_state.json, and library.json for an already downloaded local audio file (0ms latency)."""
    if vid and vid.startswith("yt_"):
        vid = vid[3:]

    # 0. Priority 0: Check SSD Disk Audio Cache (~/.cache/nutsty/audio_cache/<vid>.opus) -> 0ms local SSD playback!
    if vid:
        try:
            try:
                from .stream_resolver import find_audio_disk_cache
            except (ImportError, ValueError):
                from stream_resolver import find_audio_disk_cache
            cached_disk = find_audio_disk_cache(vid)
            if cached_disk and os.path.exists(cached_disk):
                return cached_disk
        except Exception:
            try:
                import ytmusic_helper
                if hasattr(ytmusic_helper, "find_audio_disk_cache"):
                    cached_disk = ytmusic_helper.find_audio_disk_cache(vid)
                    if cached_disk and os.path.exists(cached_disk):
                        return cached_disk
            except Exception:
                pass

    # 1. Check download_state.json
    state_candidates = [
        os.path.expanduser("~/.config/noctalia/download_state.json"),
        os.path.join(pc.get_config_dir(), "download_state.json")
    ]
    for st_path in state_candidates:
        if os.path.exists(st_path):
            try:
                with open(st_path, "r", encoding="utf-8") as f:
                    st_data = json.load(f)
                tasks = st_data.get("tasks", {}) if isinstance(st_data, dict) else {}
                if vid and vid in tasks:
                    t_info = tasks[vid]
                    p = t_info.get("path", "")
                    if t_info.get("status") == "completed" and p and os.path.exists(p):
                        return p
            except Exception:
                pass

    # 2. Check library.json
    app_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    lib_json = os.path.join(app_dir, "library.json")
    if os.path.exists(lib_json):
        try:
            with open(lib_json, "r", encoding="utf-8") as f:
                tracks = json.load(f)
            t_title_clean = (title or "").strip().lower()
            t_artist_clean = (artist or "").strip().lower()
            for t in tracks:
                p = t.get("path", "")
                if not p or not os.path.exists(p):
                    continue
                if vid and (t.get("videoId") == vid or vid in str(t.get("image", ""))):
                    return p
                lib_title = str(t.get("title") or t.get("name") or "").strip().lower()
                lib_artist = str(t.get("artist") or "").strip().lower()
                if t_title_clean and lib_title == t_title_clean:
                    if not t_artist_clean or not lib_artist or (t_artist_clean in lib_artist) or (lib_artist in t_artist_clean):
                        return p
        except Exception:
            pass
    return None

def resolve_media_path(file_path, title="", artist="", force_fresh=False, my_epoch=0, ua_out=None,
                       skip_tidal=False, source_out=None, duration_s=0.0):
    """ua_out: pass a dict to receive the stream user-agent instead of applying it to the main mpv.
    source_out: pass a dict to receive {"source": "tidal"|"youtube"|"local", "tidal": TidalStream|None}."""
    if not file_path:
        return file_path
    if isinstance(source_out, dict):
        source_out.update({"source": "youtube", "tidal": None})
    if file_path.startswith("ytdl://") or "youtube.com/watch" in file_path or "youtu.be/" in file_path:
        try:
            sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
            import ytmusic_helper
            vid = file_path.replace("ytdl://", "")
            if "watch?v=" in vid:
                vid = vid.split("watch?v=")[1].split("&")[0]

            # 0. Priority #1: Check if track is already downloaded locally on disk!
            local_file = find_local_downloaded_file(vid, title, artist)
            if local_file and os.path.exists(local_file):
                if isinstance(source_out, dict):
                    source_out["source"] = "local"
                return local_file

            if my_epoch > 0 and not is_play_epoch_active(my_epoch):
                sys.stderr.write(f"[player_daemon] Early abort resolve for superseded epoch #{my_epoch}\n")
                return ""

            # Priority #2: lossless from the user's own Tidal account (falls through to YouTube on None)
            if not skip_tidal:
                tidal = _try_tidal(vid, title, artist, duration_s)
                if my_epoch > 0 and not is_play_epoch_active(my_epoch):
                    sys.stderr.write(f"[player_daemon] Abort after Tidal lookup for superseded epoch #{my_epoch}\n")
                    return ""
                if tidal and tidal.get("url") and is_lossless_suspended():
                    tidal = None   # Listen Along began while Tidal was answering
                if tidal and tidal.get("url"):
                    if isinstance(source_out, dict):
                        source_out.update({"source": "tidal", "tidal": tidal})
                    return tidal["url"]

            streaming_quality = get_current_streaming_quality()

            if force_fresh:
                try:
                    ytmusic_helper.invalidate_cached_stream_url(vid)
                except Exception:
                    pass
            else:
                # Instant cache lookup with quality fallback (20 minutes TTL)
                cache = ytmusic_helper.load_json(ytmusic_helper.STREAM_CACHE_FILE, {})
                cached = cache.get(f"{vid}_{streaming_quality}") or cache.get(vid)
                if not cached:
                    for k, v in cache.items():
                        if k.startswith(f"{vid}_") and isinstance(v, dict) and v.get("stream_url"):
                            cached = v
                            break
                if cached and (time.time() - cached.get("timestamp", 0)) < 1200:
                    if streaming_quality == "high_opus" and (str(cached.get("itag")) == "18" or "mp4a" in str(cached.get("codec", ""))):
                        cached = None
                    else:
                        ua = cached.get("user_agent")
                        if ua and isinstance(ua_out, dict):
                            ua_out["user_agent"] = ua
                        elif ua:
                            try:
                                send_mpv_cmd(["set_property", "user-agent", ua])
                            except Exception:
                                pass
                        return cached.get("stream_url")

            if my_epoch > 0 and not is_play_epoch_active(my_epoch):
                sys.stderr.write(f"[player_daemon] Early abort before network resolve for superseded epoch #{my_epoch}\n")
                return ""

            # Resolve direct stream URL using authenticated format picker
            res = ytmusic_helper.resolve_stream_url(vid, streaming_quality, force_fresh=force_fresh)
            if my_epoch > 0 and not is_play_epoch_active(my_epoch):
                sys.stderr.write(f"[player_daemon] Abort after network resolve for superseded epoch #{my_epoch}\n")
                return ""

            if res and res.get("stream_url"):
                ua = res.get("user_agent")
                if ua and isinstance(ua_out, dict):
                    ua_out["user_agent"] = ua
                elif ua:
                    try:
                        send_mpv_cmd(["set_property", "user-agent", ua])
                    except Exception:
                        pass
                return res.get("stream_url")

            return f"ytdl://{vid}"
        except Exception as e:
            sys.stderr.write(f"[player_daemon resolve error]: {e}\n")
            return file_path
    return file_path

def update_current_track_metadata(file_path, title="", artist="", art_url=""):
    if not file_path:
        return
    try:
        if not title:
            app_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
            lib_json = os.path.join(app_dir, "library.json")
            if os.path.exists(lib_json):
                with open(lib_json, "r", encoding="utf-8") as f:
                    tracks = json.load(f)
                    for t in tracks:
                        p = t.get("path", "")
                        fn = t.get("filename", "")
                        if p == file_path or (fn and file_path.endswith(fn)):
                            art_url = t.get("image", "")
                            title = t.get("title", "") or t.get("name", "")
                            artist = t.get("artist", "")
                            break

        # Fallback to online tracks cache if not in local library
        if not title:
            online_json = os.path.join(pc.get_cache_dir(), "online_tracks.json")
            if os.path.exists(online_json):
                try:
                    with open(online_json, "r", encoding="utf-8") as f:
                        on_data = json.load(f)
                        vid = file_path.replace("ytdl://", "")
                        t = on_data.get(file_path) or on_data.get(vid)
                        if t:
                            art_url = t.get("image", "")
                            title = t.get("title", "") or t.get("name", "")
                            artist = t.get("artist", "")
                except Exception:
                    pass

        # If still no title and artist, do not overwrite existing valid metadata
        if not title and not artist:
            return

        meta = {
            "title": title,
            "artist": artist,
            "artUrl": art_url,
            "image": art_url,
            "cover": art_url,
            "path": file_path
        }
        for track_file in [CURRENT_TRACK_FILE]:
            try:
                with open(track_file, "w", encoding="utf-8") as f:
                    json.dump(meta, f, ensure_ascii=False)
            except Exception:
                pass

        session_file = os.path.expanduser(f"~/.config/noctalia/nutsty_session{PROFILE_SUFFIX}.json")
        os.makedirs(os.path.dirname(session_file), exist_ok=True)
        with open(session_file, "w", encoding="utf-8") as f:
            json.dump(meta, f, ensure_ascii=False)
        return meta
    except Exception:
        pass
def fade_out_and_pause(duration=5.0):
    """Gradually lowers volume using a smooth Cosine fade curve, then pauses and restores volume."""
    abort_file = ABORT_FILE
    if os.path.exists(abort_file):
        try:
            os.remove(abort_file)
        except Exception:
            pass

    current_vol = get_mpv_property("volume")
    if current_vol is None:
        current_vol = 100.0
    else:
        try:
            current_vol = float(current_vol)
        except Exception:
            current_vol = 100.0

    if current_vol <= 0:
        send_mpv_cmd(["set_property", "pause", True])
        return

    # Short fades step every 50ms; long ones (a sleep timer fading along its whole length)
    # every 500ms, so an hour-long ramp is ~7k IPC writes instead of ~72k.
    interval = 0.05 if duration <= 60 else 0.5
    start = time.monotonic()

    while True:
        if os.path.exists(abort_file):
            try:
                os.remove(abort_file)
            except Exception:
                pass
            send_mpv_cmd(["set_property", "volume", current_vol])
            return

        # Progress comes from the clock, not the step count, so IPC latency cannot stretch the fade
        t = min(1.0, (time.monotonic() - start) / duration) if duration > 0 else 1.0
        # Cosine S-curve: factor = (1 + cos(pi * t)) / 2 (starts at 1.0, ends at 0.0)
        factor = (1.0 + math.cos(math.pi * t)) / 2.0
        v = round(current_vol * factor, 1)
        send_mpv_cmd(["set_property", "volume", v])
        if t >= 1.0:
            break
        time.sleep(interval)

    # Pause playback once volume touches 0
    send_mpv_cmd(["set_property", "pause", True])
    # Restore original volume safely so next session starts normal
    send_mpv_cmd(["set_property", "volume", current_vol])

def _is_online_path(file_path):
    return file_path.startswith("ytdl://") or "youtube.com" in file_path or "youtu.be" in file_path


def _target_vid_of(file_path):
    vid = file_path.replace("ytdl://", "") if _is_online_path(file_path) else ""
    if "watch?v=" in vid:
        vid = vid.split("watch?v=")[1].split("&")[0]
    return vid


def _resolve_for_crossfade(file_path, title, artist, my_epoch=0, source_out=None, duration_s=0.0):
    """Resolve the incoming track without touching the main mpv's user-agent.
    Returns (stream_url, user_agent, local_or_original_path, target_vid)."""
    target_vid = _target_vid_of(file_path)
    if isinstance(source_out, dict):
        source_out.update({"source": "local", "tidal": None})
    if target_vid:
        local_match = find_local_downloaded_file(target_vid, title, artist)
        if local_match and os.path.exists(local_match):
            return local_match, DEFAULT_UA, local_match, target_vid
        ua_box = {}
        url = resolve_media_path(file_path, title, artist, my_epoch=my_epoch, ua_out=ua_box,
                                 source_out=source_out, duration_s=duration_s)
        return url, ua_box.get("user_agent") or DEFAULT_UA, file_path, target_vid
    return file_path, DEFAULT_UA, file_path, ""


def _media_duration(url):
    """Duration of the incoming track without opening it: the 'dur' parameter of a
    googlevideo stream URL, or the tags of a local file. 0.0 when unknown."""
    if not url:
        return 0.0
    try:
        if os.path.exists(url):
            try:
                import mutagen
                info = mutagen.File(url)
                if info and info.info and info.info.length:
                    return float(info.info.length)
            except Exception:
                pass
            # Cached streams are WebM, which mutagen cannot read: ask mpv (always bundled)
            kwargs = pc.get_daemon_popen_kwargs()
            kwargs.pop("start_new_session", None)
            out = subprocess.run([pc.get_binary_path("mpv"), "--no-config", "--no-video", "--ao=null",
                                  "--length=0.05", "--term-playing-msg=NUTSTY_DUR=${=duration}", url],
                                 capture_output=True, text=True, timeout=6, **kwargs).stdout
            for line in out.splitlines():
                if line.startswith("NUTSTY_DUR="):
                    return float(line.split("=", 1)[1] or 0.0)
            return 0.0
        from urllib.parse import urlparse, parse_qs
        dur = parse_qs(urlparse(url).query).get("dur")
        return float(dur[0]) if dur else 0.0
    except Exception:
        return 0.0


def automix_plan(next_path, title, artist, base_seconds):
    """Analyse the end of the playing track and the start of the next one."""
    main = get_mpv_properties_batch(["path", "duration", "user-agent"])
    out_url = main.get("path") or ""
    out_dur = float(main.get("duration") or 0.0)
    if not out_url or out_dur < 20.0:
        return {"ok": False, "reason": "no-track"}
    fmt = YTDL_FORMAT_MAP.get(get_current_streaming_quality(), "774/141/251/140/bestaudio/best")
    window = min(45.0, out_dur)
    out_levels = xf.decode_levels(out_url, out_dur - window, window,
                                  _mpv_stream_args(fmt, main.get("user-agent") or DEFAULT_UA), TEMP_DIR, "out")
    in_levels = []
    in_duration = 0.0
    if next_path:
        in_url, in_ua, _, _ = _resolve_for_crossfade(next_path, title, artist)
        if in_url:
            in_levels = xf.decode_levels(in_url, 0.0, 25.0, _mpv_stream_args(fmt, in_ua), TEMP_DIR, "in")
            in_duration = _media_duration(in_url)
    plan = xf.build_plan(out_levels, out_dur - window, out_dur, in_levels, base_seconds)
    plan["out_duration"] = out_dur
    plan["in_duration"] = round(in_duration, 2)
    return plan


def _switch_main_to(stream_target, in_ua, file_path, target_vid, meta, fade_in, in_start, my_epoch, keep_paused=False):
    """Load the incoming track on the main mpv with a sample-accurate fade-in."""
    global _CURRENT_PLAYING_VID, _CURRENT_PLAYING_PATH
    is_online = bool(target_vid) and not os.path.exists(stream_target)
    try:
        with open(PLAYBACK_STATE_FILE, "w", encoding="utf-8") as f:
            json.dump({"state": "loading" if is_online else "playing", "path": file_path,
                       "target_vid": target_vid, "timestamp": time.time(), "epoch": my_epoch}, f)
    except Exception:
        pass
    if in_ua:
        send_mpv_cmd(["set_property", "user-agent", in_ua])
    opts = {"af": xf.fade_filter("in", in_start, fade_in)}
    if in_start > 0:
        opts["start"] = f"{in_start:.2f}"
    res = xf.loadfile_with_options(IPC_TYPE, IPC_TARGET, stream_target, opts)
    if res.get("error") != "success":
        send_mpv_cmd(["loadfile", stream_target, "replace"])
    send_mpv_cmd(["set_property", "loop-file", "no"])
    if not keep_paused:
        send_mpv_cmd(["set_property", "pause", False])
    _CURRENT_PLAYING_VID = target_vid
    _CURRENT_PLAYING_PATH = file_path
    if meta and meta.get("title"):
        send_mpv_cmd(["set_property", "force-media-title", f"{meta['title']} - {meta.get('artist', '')}".strip(" -")])
    else:
        send_mpv_cmd(["set_property", "force-media-title", ""])


def crossfade_play(file_path, title, artist, art, my_epoch, fade_at, fade_dur, in_start, track_dur=0.0):
    """Blend the playing track into file_path.

    Timeline: the tail mpv opens the outgoing stream paused at the blend point,
    the main mpv keeps playing until it reaches that point, then the tail takes
    over the outgoing audio (fading out) and the main mpv switches to the
    incoming track (fading in). Any pause, skip or seek drops the tail and
    keeps the incoming track, the way SimpMusic does.
    """
    def plain_play():
        execute_command(["play", file_path, title, artist, art, str(my_epoch)])

    main = get_mpv_properties_batch(["path", "time-pos", "duration", "volume", "mute", "pause", "user-agent"])
    out_url = main.get("path") or ""
    out_dur = float(main.get("duration") or 0.0)
    if not out_url or main.get("pause") is True or out_dur < 20.0 or main.get("time-pos") is None:
        return plain_play()

    record_active_play_epoch(my_epoch, file_path, _target_vid_of(file_path))
    src_box = {}
    stream_target, in_ua, file_path, target_vid = _resolve_for_crossfade(file_path, title, artist, my_epoch,
                                                                         source_out=src_box, duration_s=track_dur)
    if not is_play_epoch_active(my_epoch) or not stream_target:
        return
    record_now_source(target_vid, src_box.get("source", "local"), src_box.get("tidal"))
    meta = update_current_track_metadata(file_path, title, artist, art)

    pos = float(get_mpv_property("time-pos") or 0.0)
    tail_start = max(float(fade_at), pos + 1.6)
    dur = min(float(fade_dur), out_dur - tail_start - 0.2)
    in_start = max(0.0, float(in_start))
    if dur < 1.5:
        # Too close to the end for a blend: switch now with a short fade-in
        _switch_main_to(stream_target, in_ua, file_path, target_vid, meta, 1.5, in_start, my_epoch)
        return

    fmt = YTDL_FORMAT_MAP.get(get_current_streaming_quality(), "774/141/251/140/bestaudio/best")
    tail_type, tail_addr = xf.tail_target(PROFILE_SUFFIX)
    tail_ready = xf.spawn_tail(TEMP_DIR, PROFILE_SUFFIX, _mpv_stream_args(fmt, main.get("user-agent") or DEFAULT_UA),
                               main.get("volume") or 100.0, bool(main.get("mute")))
    if tail_ready:
        xf.loadfile_with_options(tail_type, tail_addr, out_url, {
            "start": f"{tail_start:.3f}", "af": xf.fade_filter("out", tail_start, dur)})
        tail_ready = False
        deadline = time.time() + 6.0
        while time.time() < deadline:
            if xf.ipc_get(tail_type, tail_addr, "time-pos", 0.3) is not None:
                tail_ready = True
                break
            cur = get_mpv_property("time-pos")
            if cur is None or float(cur) > tail_start - 0.05 or not is_play_epoch_active(my_epoch):
                break
            time.sleep(0.05)

    try:
        # Hold until the main mpv reaches the blend point
        while is_play_epoch_active(my_epoch):
            cur = get_mpv_properties_batch(["time-pos", "pause"])
            if cur.get("pause") is True:
                # Paused before the blend: line up the next track, still paused
                xf.kill_tail(TEMP_DIR, PROFILE_SUFFIX)
                _switch_main_to(stream_target, in_ua, file_path, target_vid, meta, 0.3, in_start, my_epoch, keep_paused=True)
                return
            t = cur.get("time-pos")
            if t is None or float(t) >= tail_start - 0.02:
                break
            time.sleep(max(0.004, min(0.05, (tail_start - float(t)) * 0.5)))
        if not is_play_epoch_active(my_epoch):
            return

        if tail_ready:
            xf.ipc_call(tail_type, tail_addr, ["set_property", "pause", False], timeout=0.3)
        _switch_main_to(stream_target, in_ua, file_path, target_vid, meta, dur, in_start, my_epoch)
        if not tail_ready:
            return

        # Ride the blend: mirror the user's volume, drop the tail on pause/skip/seek
        switched = time.time()
        while time.time() - switched < dur + 0.6:
            time.sleep(0.05)
            if not is_play_epoch_active(my_epoch):
                break
            cur = get_mpv_properties_batch(["pause", "volume", "mute", "time-pos"])
            if cur.get("pause") is True:
                break
            t = cur.get("time-pos")
            if t is not None and abs(float(t) - (in_start + time.time() - switched)) > 3.0:
                break
            if cur.get("volume") is not None:
                xf.ipc_call(tail_type, tail_addr, ["set_property", "volume", cur.get("volume")], timeout=0.2)
                xf.ipc_call(tail_type, tail_addr, ["set_property", "mute", bool(cur.get("mute"))], timeout=0.2)
    finally:
        xf.kill_tail(TEMP_DIR, PROFILE_SUFFIX)


def _reload_youtube_at(pos):
    """Swap the Tidal stream the main mpv plays for the YouTube one at the same position.
    Only when the song playing is still the one last requested. Returns True when reloaded."""
    now = read_now_source()
    vid = now.get("target_vid") or ""
    if now.get("source") != "tidal" or not vid:
        return False
    active = _read_json_file(PLAY_REQ_FILE, {}) or {}
    if active.get("target_vid") and active.get("target_vid") != vid:
        return False
    url = resolve_media_path(f"ytdl://{vid}", skip_tidal=True)
    if not url:
        return False
    paused = get_mpv_property("pause") is True
    send_mpv_cmd({"name": "loadfile", "url": url, "flags": "replace", "index": -1,
                  "options": {"start": f"{max(0.0, float(pos or 0.0)):.3f}", "pause": "yes" if paused else "no"}})
    record_now_source(vid, "youtube")
    return True


def enforce_listen_along_suspension():
    """Close the race with lossless_suspend: that command writes the flag, then reads the source;
    play writes the source, then calls this to read the flag. One of the two always sees the other."""
    if not is_lossless_suspended() or read_now_source().get("source") != "tidal":
        return False
    return _reload_youtube_at(get_mpv_property("time-pos") or 0.0)


def _clear_prev_mpv_path(epoch):
    """loadfile has been sent: from here a file with the same path (cached stream URL when going back
    to the song mpv held) is the requested one. Only touches the state of this request's epoch."""
    try:
        with open(PLAYBACK_STATE_FILE, "r", encoding="utf-8") as f:
            st = json.load(f)
        if st.get("epoch") != epoch or "prev_mpv_path" not in st:
            return
        st.pop("prev_mpv_path", None)
        with open(PLAYBACK_STATE_FILE, "w", encoding="utf-8") as f:
            json.dump(st, f)
    except Exception:
        pass


def _prev_track_ident(new_path=""):
    """target_vid/path of the last state write, so pause/resume keep the track identity
    (only when the track itself is unchanged)."""
    try:
        with open(PLAYBACK_STATE_FILE, "r", encoding="utf-8") as f:
            st = json.load(f)
        if new_path and st.get("path", "") != new_path:
            return {}
        return {"path": st.get("path", ""), "target_vid": st.get("target_vid", "")}
    except Exception:
        return {}


def get_status_dict():
    is_loading = False
    target_vid = ""
    target_path = ""
    loading_ts = 0.0
    if os.path.exists(PLAYBACK_STATE_FILE):
        try:
            with open(PLAYBACK_STATE_FILE, "r", encoding="utf-8") as f:
                st = json.load(f)
                loading_ts = st.get("timestamp", 0)
                target_vid = st.get("target_vid", "")
                target_path = st.get("path", "")
                if st.get("state") == "loading" and (time.time() - loading_ts) < 8.0:
                    is_loading = True
        except Exception:
            pass

    props = ["pause", "time-pos", "duration", "filename", "path", "volume", "idle-active"]
    batch = get_mpv_properties_batch(props)

    pause = batch.get("pause")
    time_pos = batch.get("time-pos") or 0.0
    duration = batch.get("duration") or 0.0
    filename = batch.get("filename") or ""
    path = batch.get("path") or ""
    vol = batch.get("volume") if batch.get("volume") is not None else 100
    idle = batch.get("idle-active")

    # Detect failed playback / 403 / demux error: MPV is idle and loading was requested > 6.0s ago
    if is_loading and idle and (time.time() - loading_ts) > 6.0:
        is_loading = False
        if target_vid:
            try:
                import ytmusic_helper
                ytmusic_helper.invalidate_cached_stream_url(target_vid)
            except Exception:
                pass
        try:
            with open(PLAYBACK_STATE_FILE, "w", encoding="utf-8") as f:
                json.dump({"state": "idle", "path": target_path, "target_vid": target_vid, "timestamp": time.time()}, f)
        except Exception:
            pass

    global _CURRENT_PLAYING_VID, _CURRENT_PLAYING_PATH
    is_direct_stream = bool(path.startswith("http://") or path.startswith("https://") or "googlevideo.com" in path or filename.startswith("videoplayback"))
    is_target_active = True
    if is_direct_stream or (time_pos > 0.1 and not idle):
        is_target_active = True
    elif target_vid:
        is_target_active = bool((_CURRENT_PLAYING_VID and _CURRENT_PLAYING_VID == target_vid) or (target_vid in path) or (target_vid in filename))
    elif target_path:
        is_target_active = bool((_CURRENT_PLAYING_PATH and _CURRENT_PLAYING_PATH == target_path) or (path == target_path) or (filename and target_path.endswith(filename)))

    if is_loading and (is_target_active or (time_pos is not None and time_pos > 0.5)):
        if duration is not None and duration > 0 and pause is True:
            send_mpv_cmd(["set_property", "pause", False])
            pause = False

    has_audio_flowing = (time_pos is not None and time_pos > 0) or (duration is not None and duration > 0 and pause is False)
    if is_loading and (is_target_active or (time_pos is not None and time_pos > 0.5)) and has_audio_flowing:
        is_loading = False
        try:
            with open(PLAYBACK_STATE_FILE, "w", encoding="utf-8") as f:
                json.dump({"state": "playing", "path": path, "target_vid": target_vid, "timestamp": time.time()}, f)
        except Exception:
            pass

    has_file = bool((path or filename) and not idle and is_target_active) and (not is_loading or (time_pos is not None and time_pos > 0))

    st = {
        "is_playing": (pause is False) and has_file,
        "is_paused": (pause is True) and bool((path or filename) and not idle and is_target_active),
        "time_pos": round(time_pos, 1) if (has_file and is_target_active) else 0.0,
        "duration": round(duration, 1) if (has_file and is_target_active) else 0.0,
        "filename": (filename or path) if (has_file and is_target_active) else "",
        "path": path if (has_file and is_target_active) else "",
        "target_vid": target_vid,
        "volume": vol,
        "is_loading": is_loading
    }
    if has_file:
        st["audio_specs"] = get_audio_specs_dict()
    return st

def get_audio_specs_dict():
    """Truthful quality label data. Fields the player cannot know yet stay None or empty."""
    import audio_output
    props = {k: get_mpv_property(k) for k in ("audio-codec-name", "audio-bitrate", "audio-params", "path")}
    alsa_rate = None if pc.IS_WINDOWS else audio_output.read_alsa_running_rate()
    return audio_output.build_audio_specs(props, read_now_source(), get_lossless_settings()["dac_mode"],
                                          is_lossless_suspended(), pc.IS_WINDOWS, alsa_rate)

def get_status_json():
    return json.dumps(get_status_dict())

def _float_arg(args, i, default=0.0):
    try:
        return float(args[i]) if len(args) > i else default
    except (TypeError, ValueError):
        return default

def handle_cli(args):
    """Entry point for thread-safe in-process execution without modifying sys.argv."""
    execute_command(list(args))

def main():
    execute_command(sys.argv[1:])

def execute_command(args):
    if len(args) < 1:
        print("Usage: player_daemon.py [play <path> [title] [artist] [art_url] | pause | resume | toggle | seek <sec> | stop | status]")
        return

    action = args[0].lower()

    if action == "play" and len(args) > 1:
        xf.kill_tail(TEMP_DIR, PROFILE_SUFFIX)
        epoch_arg = 0
        if len(args) > 5:
            try:
                epoch_arg = int(args[5])
            except ValueError:
                epoch_arg = 0
        if epoch_arg <= 0:
            epoch_arg = int(time.time() * 1000)

        my_req_id = epoch_arg

        file_path = args[1]
        if not file_path or file_path in ("undefined", "null", "None"):
            sys.stderr.write(f"[player_daemon] Aborted invalid file_path: {file_path}\n")
            return
        title_arg = args[2] if len(args) > 2 else ""
        artist_arg = args[3] if len(args) > 3 else ""
        art_arg = args[4] if len(args) > 4 else ""

        is_online = file_path.startswith("ytdl://") or "youtube.com" in file_path or "youtu.be" in file_path
        target_vid = file_path.replace("ytdl://", "") if is_online else ""
        if "watch?v=" in target_vid:
            target_vid = target_vid.split("watch?v=")[1].split("&")[0]

        # Record this request as the active epoch across all OS processes
        record_active_play_epoch(my_req_id, file_path, target_vid)

        # Priority #1: Check if online track is ALREADY downloaded locally on disk
        if is_online:
            local_match = find_local_downloaded_file(target_vid, title_arg, artist_arg)
            if local_match and os.path.exists(local_match):
                file_path = local_match
                is_online = False

        req_ts = time.time()
        initial_state = "loading" if is_online else "playing"
        state_file = PLAYBACK_STATE_FILE
        state_payload = {"state": initial_state, "path": file_path, "target_vid": target_vid, "timestamp": req_ts, "epoch": my_req_id}
        if is_online:
            # mpv keeps the previous file (paused) while the stream resolves: the bridge must not
            # take that file's position for the new song (nutsty-bridge loading_verdict)
            try:
                state_payload["prev_mpv_path"] = get_mpv_property("path") or ""
            except Exception:
                pass
        try:
            with open(state_file, "w", encoding="utf-8") as f:
                json.dump(state_payload, f)
        except Exception:
            pass

        # Pause previous audio immediately while network resolves; do NOT stop to avoid race conditions with loadfile
        if is_online:
            send_mpv_cmd(["set_property", "pause", True])

        meta = update_current_track_metadata(file_path, title_arg, artist_arg, art_arg)
        src_box = {"source": "local", "tidal": None}
        stream_target = resolve_media_path(file_path, title_arg, artist_arg, my_epoch=my_req_id,
                                           source_out=src_box, duration_s=_float_arg(args, 6)) if is_online else file_path

        # Guard against stale concurrent play requests across all OS processes
        if not is_play_epoch_active(my_req_id) or not stream_target:
            sys.stderr.write(f"[player_daemon] Aborted superseded play request #{my_req_id} (active is #{get_active_play_epoch()}) for: {file_path}\n")
            return

        send_mpv_cmd(["loadfile", stream_target, "replace"])
        record_now_source(target_vid, src_box.get("source", "local"), src_box.get("tidal"))
        if src_box.get("source") == "tidal":
            enforce_listen_along_suspension()
        if is_online and state_payload.get("prev_mpv_path"):
            _clear_prev_mpv_path(my_req_id)
        send_mpv_cmd(["set_property", "loop-playlist", "no"])
        send_mpv_cmd(["set_property", "loop-file", "no"])
        send_mpv_cmd(["set_property", "pause", False])

        _CURRENT_PLAYING_VID = target_vid
        _CURRENT_PLAYING_PATH = file_path

        if meta and meta.get("title"):
            disp_title = f"{meta['title']} - {meta.get('artist', '')}".strip(" -")
            send_mpv_cmd(["set_property", "force-media-title", disp_title])
        else:
            send_mpv_cmd(["set_property", "force-media-title", ""])

        if not is_online:
            try:
                with open(state_file, "w", encoding="utf-8") as f:
                    json.dump({"state": "playing", "path": file_path, "target_vid": target_vid, "timestamp": time.time()}, f)
            except Exception:
                pass
        print("Playing:", file_path)


    elif action == "next":
        send_mpv_cmd(["playlist-next"])
        print("Next track")

    elif action == "prev":
        send_mpv_cmd(["playlist-prev"])
        print("Previous track")

    elif action == "set_playlist" and len(args) > 1:
        idx = int(args[1])
        m3u_file = PLAYLIST_FILE
        tracks = []
        meta = None
        if len(args) > 2:
            try:
                tracks = json.loads(args[2])
                if len(tracks) > idx:
                    meta = update_current_track_metadata(tracks[idx])
            except Exception as e:
                pass

        if len(tracks) > idx and (tracks[idx].startswith("ytdl://") or "youtube.com" in tracks[idx]):
            req_ts = time.time()
            state_file = PLAYBACK_STATE_FILE
            try:
                with open(state_file, "w", encoding="utf-8") as f:
                    json.dump({"state": "loading", "path": tracks[idx], "timestamp": req_ts}, f)
            except Exception:
                pass

            send_mpv_cmd(["stop"])
            stream_target = resolve_media_path(tracks[idx])
            send_mpv_cmd(["loadfile", stream_target, "replace"])
            send_mpv_cmd(["set_property", "pause", False])
            if meta and meta.get("title"):
                disp_title = f"{meta['title']} - {meta.get('artist', '')}".strip(" -")
                send_mpv_cmd(["set_property", "force-media-title", disp_title])
            print("Playing online track:", tracks[idx])
        elif tracks:
            send_mpv_cmd(["set_property", "force-media-title", ""])
            with open(m3u_file, "w", encoding="utf-8") as f:
                for t in tracks:
                    f.write(t + "\n")
            if os.path.exists(m3u_file):
                send_mpv_cmd(["loadlist", m3u_file, "replace"])
                send_mpv_cmd(["set_property", "loop-playlist", "inf"])
                send_mpv_cmd(["playlist-play-index", idx])
                send_mpv_cmd(["set_property", "pause", False])
                print("Set playlist and playing index:", idx)

    elif action == "toggle":
        ensure_mpv()
        path = get_mpv_property("path")
        idle = get_mpv_property("idle-active")
        target_file = args[1] if len(args) > 1 else ""

        # Check if daemon is already loading a track to prevent duplicate loading loops
        is_already_loading = False
        if os.path.exists(PLAYBACK_STATE_FILE):
            try:
                with open(PLAYBACK_STATE_FILE, "r", encoding="utf-8") as f:
                    st = json.load(f)
                    if st.get("state") == "loading" and (time.time() - st.get("timestamp", 0)) < 4.0:
                        is_already_loading = True
            except Exception:
                pass

        if is_already_loading:
            print("Track is currently loading, skipping duplicate toggle")
            return

        if not path or idle:
            if target_file:
                is_online = target_file.startswith("ytdl://") or "youtube.com" in target_file or "youtu.be" in target_file
                initial_state = "loading" if is_online else "playing"
                target_vid = target_file.replace("ytdl://", "") if is_online else ""
                state_payload = {"state": initial_state, "path": target_file, "target_vid": target_vid, "timestamp": time.time()}
                try:
                    with open(PLAYBACK_STATE_FILE, "w", encoding="utf-8") as f:
                        json.dump(state_payload, f)
                except Exception:
                    pass
                stream_target = resolve_media_path(target_file, force_fresh=True)
                send_mpv_cmd(["loadfile", stream_target, "replace"])
                send_mpv_cmd(["set_property", "pause", False])
                update_current_track_metadata(target_file)
                print("Loaded and playing:", target_file)
            else:
                print("MPV is idle and no track specified")
        else:
            is_paused = get_mpv_property("pause")
            new_paused = not is_paused
            send_mpv_cmd(["set_property", "pause", new_paused])
            print("Toggled pause to:", new_paused)

    elif action == "pause":
        ensure_mpv()
        try:
            with open(PLAYBACK_STATE_FILE, "w", encoding="utf-8") as f:
                json.dump({**_prev_track_ident(), "state": "paused", "timestamp": time.time()}, f)
        except Exception:
            pass
        send_mpv_cmd(["set_property", "pause", True])
        xf.kill_tail(TEMP_DIR, PROFILE_SUFFIX)
        print("Paused playback")

    elif action == "resume":
        ensure_mpv()
        target_file = args[1] if len(args) > 1 else ""
        idle = get_mpv_property("idle-active")
        path = get_mpv_property("path")

        # Mark state file as playing
        try:
            if os.path.exists(PLAYBACK_STATE_FILE):
                with open(PLAYBACK_STATE_FILE, "w", encoding="utf-8") as f:
                    json.dump({**_prev_track_ident(target_file), "state": "playing", "path": target_file or path or "", "timestamp": time.time()}, f)
        except Exception:
            pass

        if (not path or idle) and target_file:
            is_online = target_file.startswith("ytdl://") or "youtube.com" in target_file or "youtu.be" in target_file
            initial_state = "loading" if is_online else "playing"
            target_vid = target_file.replace("ytdl://", "") if is_online else ""
            state_payload = {"state": initial_state, "path": target_file, "target_vid": target_vid, "timestamp": time.time()}
            try:
                with open(PLAYBACK_STATE_FILE, "w", encoding="utf-8") as f:
                    json.dump(state_payload, f)
            except Exception:
                pass
            stream_target = resolve_media_path(target_file)
            send_mpv_cmd(["loadfile", stream_target, "replace"])
            update_current_track_metadata(target_file)

        send_mpv_cmd(["set_property", "pause", False])
        print("Resumed playback")

    elif action == "stop":
        xf.kill_tail(TEMP_DIR, PROFILE_SUFFIX)
        send_mpv_cmd(["stop"])

    elif action == "seek" and len(args) > 1:
        sec = float(args[1])
        send_mpv_cmd(["seek", sec, "absolute"])

    elif action == "volume" and len(args) > 1:
        vol = float(args[1])
        send_mpv_cmd(["set_property", "volume", vol])

    elif action == "fade_out_and_pause":
        dur = float(args[1]) if len(args) > 1 else 5.0
        fade_out_and_pause(dur)

    elif action == "cancel_fade":
        try:
            with open(ABORT_FILE, "w") as f:
                f.write("1")
        except Exception:
            pass

    elif action == "prewarm" and len(args) > 1:
        vid = args[1]
        if vid and ytmusic_helper and hasattr(ytmusic_helper, "resolve_stream_url"):
            try:
                ytmusic_helper.resolve_stream_url(vid)
            except Exception:
                pass

    elif action == "crossfade_play" and len(args) > 8:
        try:
            ep = int(args[5])
        except ValueError:
            ep = int(time.time() * 1000)
        try:
            crossfade_play(args[1], args[2], args[3], args[4], ep, float(args[6]), float(args[7]), float(args[8]),
                           _float_arg(args, 9))
        except Exception as e:
            sys.stderr.write(f"[player_daemon] crossfade failed, falling back: {e}\n")
            xf.kill_tail(TEMP_DIR, PROFILE_SUFFIX)
            execute_command(["play", args[1], args[2], args[3], args[4], args[5]])

    elif action == "media_duration" and len(args) > 1:
        # Length of an upcoming track, so the player can show it the moment a blend switches to it
        try:
            url, _, _, _ = _resolve_for_crossfade(args[1], args[2] if len(args) > 2 else "", args[3] if len(args) > 3 else "")
            dur = _media_duration(url) if url else 0.0
        except Exception:
            dur = 0.0
        print(json.dumps({"duration": round(dur, 2)}))

    elif action == "automix_plan" and len(args) > 1:
        base = float(args[4]) if len(args) > 4 else 6.0
        try:
            plan = automix_plan(args[1], args[2] if len(args) > 2 else "", args[3] if len(args) > 3 else "", base)
        except Exception as e:
            plan = {"ok": False, "reason": str(e)}
        print(json.dumps(plan))

    elif action == "status":
        print(get_status_json())


    elif action == "audio_specs":
        ensure_mpv()
        specs = get_audio_specs_dict()
        print(json.dumps(specs))
    elif action == "lossless_suspend" and len(args) > 1:
        # Listen Along: both sides must hear the same YouTube version (Tidal's cut can differ)
        on = args[1].lower() in ("1", "on", "true", "yes")
        reloaded = False
        if on:
            try:
                open(LOSSLESS_SUSPEND_FILE, "w").close()
            except OSError:
                pass
            if read_now_source().get("source") == "tidal":
                reloaded = _reload_youtube_at(get_mpv_property("time-pos") or 0.0)
        else:
            try:
                os.remove(LOSSLESS_SUSPEND_FILE)
            except OSError:
                pass
        print(json.dumps({"suspended": on, "reloaded": reloaded}))
    elif action == "restart_mpv_keep_position":
        print(json.dumps(restart_mpv_keep_position()))
    elif action == "rate_dropin" and len(args) > 1:
        import audio_output
        conf_dir = audio_output.PIPEWIRE_DROPIN.parent
        if args[1] == "write":
            print(json.dumps(audio_output.write_rate_dropin(conf_dir)))
        elif args[1] == "remove":
            print(json.dumps({"removed": audio_output.remove_rate_dropin(conf_dir)}))
        else:
            print(json.dumps({"installed": audio_output.PIPEWIRE_DROPIN.exists(), "path": str(audio_output.PIPEWIRE_DROPIN),
                              "conflicts": audio_output.find_existing_allowed_rates(conf_dir)}))
    elif action == "stream_failed":
        # The Tidal stream stopped mid-song (expired link, network): carry on with YouTube from there
        pos = _float_arg(args, 1)
        reloaded = False
        now = read_now_source()
        if now.get("source") == "tidal" and now.get("target_vid"):
            _skip_tidal_for(now["target_vid"], TIDAL_SKIP_AFTER_FAILURE_S)
            reloaded = _reload_youtube_at(pos)
        print(json.dumps({"reloaded": reloaded}))
    elif action == "set_streaming_quality" and len(args) > 1:
        ensure_mpv()
        qual = args[1]
        ytdl_fmt = YTDL_FORMAT_MAP.get(qual, "774/141/251/140/bestaudio/best")
        send_mpv_cmd(["set_property", "ytdl-format", ytdl_fmt])
        print(json.dumps({"success": True, "quality": qual, "ytdl_format": ytdl_fmt}))

if __name__ == "__main__":
    main()
