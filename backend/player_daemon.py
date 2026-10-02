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
MPV_TITLE = f"nutsty-audio{PROFILE_SUFFIX}"

YTDL_FORMAT_MAP = {
    "high_opus": "774/141/251/140/bestaudio/best",
    "high_aac": "141/774/140/251/bestaudio/best",
    "medium": "251/140/bestaudio/best",
    "low": "250/ba[abr<=70]/bestaudio/best"
}

def get_current_streaming_quality():
    settings_path = os.path.join(CONFIG_DIR, f"nutsty_settings{PROFILE_SUFFIX}.json")
    if not os.path.exists(settings_path) and not PROFILE_SUFFIX:
        settings_path = os.path.join(CONFIG_DIR, "nutsty_settings.json")
    if os.path.exists(settings_path):
        try:
            with open(settings_path, "r", encoding="utf-8") as f:
                return json.load(f).get("streamingQuality", "high_opus")
        except Exception:
            pass
    return "high_opus"

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

def ensure_mpv():
    """Ensure background MPV process is running with IPC socket safely without process thrashing"""
    with _MPV_LOCK:
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
        ytdl_bin = pc.get_binary_path("yt-dlp")
        ipc_arg = pc.get_mpv_ipc_arg(IPC_TYPE, IPC_TARGET)

        cmd = [
            mpv_bin,
            "--no-config",
            "--idle=yes",
            "--pause=no",
            "--no-video",
            "--no-terminal",
            "--force-window=no",
            ipc_arg,
            "--audio-buffer=0.4",
            "--demuxer-max-bytes=16M",
            "--demuxer-max-back-bytes=4M",
            f"--title={MPV_TITLE}",
            "--loop-playlist=inf",
            "--gapless-audio=yes",
            f"--ytdl-format={ytdl_fmt}",
            "--ytdl-raw-options=extractor-args=youtube:player_client=android,ios,tv_embedded,android_creator",
            f"--user-agent={DEFAULT_UA}",
            "--referrer=https://www.youtube.com/",
            f"--log-file={LOG_FILE}"
        ]
        if ytdl_bin and os.path.exists(ytdl_bin):
            safe_ytdl = ytdl_bin.replace("\\", "/")
            cmd.append(f"--script-opts=ytdl_hook-ytdl_path={safe_ytdl}")

        try:
            import ytmusic_helper
            cookie_file = ytmusic_helper.get_exported_cookie_file()
            if cookie_file and os.path.exists(cookie_file):
                safe_cookie = cookie_file.replace("\\", "/")
                cmd.append(f"--cookies-file={safe_cookie}")
                cmd.append(f"--ytdl-raw-options=cookies={safe_cookie},extractor-args=youtube:player_client=android,ios,tv_embedded,android_creator")
        except Exception:
            pass

        popen_kwargs = pc.get_daemon_popen_kwargs()
        subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, **popen_kwargs)
        
        # Wait for socket to appear and accept connection
        for _ in range(25):
            time.sleep(0.1)
            try:
                s = pc.connect_mpv_socket(IPC_TYPE, IPC_TARGET, timeout=1.0)
                s.close()
                return True
            except Exception:
                pass
        return False

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
    """Check download_state.json and library.json for an already downloaded local audio file (0ms latency)."""
    if vid and vid.startswith("yt_"):
        vid = vid[3:]
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

def resolve_media_path(file_path, title="", artist=""):
    if not file_path:
        return file_path
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
                return local_file

            streaming_quality = get_current_streaming_quality()

            # Instant cache lookup with quality fallback
            cache = ytmusic_helper.load_json(ytmusic_helper.STREAM_CACHE_FILE, {})
            cached = cache.get(f"{vid}_{streaming_quality}") or cache.get(vid)
            if not cached:
                for k, v in cache.items():
                    if k.startswith(f"{vid}_") and isinstance(v, dict) and v.get("stream_url"):
                        cached = v
                        break
            if cached and (time.time() - cached.get("timestamp", 0)) < 10800:
                ua = cached.get("user_agent")
                if ua:
                    try:
                        send_mpv_cmd(["set_property", "user-agent", ua])
                    except Exception:
                        pass
                return cached.get("stream_url")

            # Resolve direct stream URL using authenticated format picker
            res = ytmusic_helper.resolve_stream_url(vid, streaming_quality)
            if res and res.get("stream_url"):
                ua = res.get("user_agent")
                if ua:
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

    steps = max(10, int(duration * 20))  # 20 steps per second (50ms interval)
    interval = duration / steps

    for i in range(1, steps + 1):
        if os.path.exists(abort_file):
            try:
                os.remove(abort_file)
            except Exception:
                pass
            send_mpv_cmd(["set_property", "volume", current_vol])
            return

        t = i / steps  # 0.0 -> 1.0
        # Cosine S-curve: factor = (1 + cos(pi * t)) / 2 (starts at 1.0, ends at 0.0)
        factor = (1.0 + math.cos(math.pi * t)) / 2.0
        v = round(current_vol * factor, 1)
        send_mpv_cmd(["set_property", "volume", v])
        time.sleep(interval)

    # Pause playback once volume touches 0
    send_mpv_cmd(["set_property", "pause", True])
    # Restore original volume safely so next session starts normal
    send_mpv_cmd(["set_property", "volume", current_vol])

def get_status_dict():
    is_loading = False
    target_vid = ""
    target_path = ""
    if os.path.exists(PLAYBACK_STATE_FILE):
        try:
            with open(PLAYBACK_STATE_FILE, "r", encoding="utf-8") as f:
                st = json.load(f)
                if st.get("state") == "loading" and (time.time() - st.get("timestamp", 0)) < 15.0:
                    is_loading = True
                    target_vid = st.get("target_vid", "")
                    target_path = st.get("path", "")
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

    global _CURRENT_PLAYING_VID, _CURRENT_PLAYING_PATH
    is_target_active = True
    if target_vid:
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

    return {
        "is_playing": (pause is False) and has_file,
        "is_paused": (pause is True) and bool((path or filename) and not idle and is_target_active),
        "time_pos": round(time_pos, 1) if (has_file and is_target_active) else 0.0,
        "duration": round(duration, 1) if (has_file and is_target_active) else 0.0,
        "filename": (filename or path) if (has_file and is_target_active) else "",
        "volume": vol,
        "is_loading": is_loading
    }

def get_status_json():
    return json.dumps(get_status_dict())

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
        global _ACTIVE_PLAY_REQ_ID, _CURRENT_PLAYING_VID, _CURRENT_PLAYING_PATH
        with _PLAY_REQ_LOCK:
            _ACTIVE_PLAY_REQ_ID += 1
            my_req_id = _ACTIVE_PLAY_REQ_ID

        file_path = args[1]
        title_arg = args[2] if len(args) > 2 else ""
        artist_arg = args[3] if len(args) > 3 else ""
        art_arg = args[4] if len(args) > 4 else ""

        is_online = file_path.startswith("ytdl://") or "youtube.com" in file_path or "youtu.be" in file_path
        target_vid = file_path.replace("ytdl://", "") if is_online else ""
        if "watch?v=" in target_vid:
            target_vid = target_vid.split("watch?v=")[1].split("&")[0]

        # Priority #1: Check if online track is ALREADY downloaded locally on disk
        if is_online:
            local_match = find_local_downloaded_file(target_vid, title_arg, artist_arg)
            if local_match and os.path.exists(local_match):
                file_path = local_match
                is_online = False

        req_ts = time.time()
        initial_state = "loading" if is_online else "playing"
        state_file = PLAYBACK_STATE_FILE
        state_payload = {"state": initial_state, "path": file_path, "target_vid": target_vid, "timestamp": req_ts}
        try:
            with open(state_file, "w", encoding="utf-8") as f:
                json.dump(state_payload, f)
        except Exception:
            pass

        # Stop MPV immediately BEFORE resolving online stream URL to clear previous audio
        if is_online:
            send_mpv_cmd(["stop"])

        meta = update_current_track_metadata(file_path, title_arg, artist_arg, art_arg)
        stream_target = resolve_media_path(file_path, title_arg, artist_arg) if is_online else file_path

        # Guard against stale concurrent play requests
        with _PLAY_REQ_LOCK:
            if my_req_id != _ACTIVE_PLAY_REQ_ID:
                sys.stderr.write(f"Aborted superseded play request #{my_req_id} (active is #{_ACTIVE_PLAY_REQ_ID}) for: {file_path}\n")
                return

        send_mpv_cmd(["loadfile", stream_target, "replace"])
        send_mpv_cmd(["set_property", "loop-playlist", "inf"])
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
                    if st.get("state") == "loading" and (time.time() - st.get("timestamp", 0)) < 15.0:
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
                stream_target = resolve_media_path(target_file)
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
                json.dump({"state": "paused", "timestamp": time.time()}, f)
        except Exception:
            pass
        send_mpv_cmd(["set_property", "pause", True])
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
                    json.dump({"state": "playing", "path": target_file or path or "", "timestamp": time.time()}, f)
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

    elif action == "status":
        print(get_status_json())


    elif action == "audio_specs":
        ensure_mpv()
        codec = get_mpv_property("audio-codec-name") or ""
        bitrate = get_mpv_property("audio-bitrate") or 0
        params = get_mpv_property("audio-params") or {}

        sample_rate = params.get("samplerate", 0)
        channels = params.get("channel-count", 2)
        channel_str = "Stereo (2ch)" if channels == 2 else (f"{channels}ch" if channels else "Stereo")

        bitrate_kbps = round(bitrate / 1000) if bitrate > 1000 else int(bitrate)
        if bitrate_kbps == 0:
            bitrate_kbps = 192 if codec in ["opus", "aac"] else (320 if codec == "mp3" else 192)

        samplerate_str = f"{sample_rate / 1000:.1f} kHz" if sample_rate > 0 else "48.0 kHz"

        specs = {
            "codec": (codec or "aac").upper(),
            "bitrate": bitrate_kbps,
            "bitrate_str": f"{bitrate_kbps} kbps" if bitrate_kbps > 0 else "192 kbps",
            "sample_rate": sample_rate or 48000,
            "sample_rate_str": samplerate_str,
            "channels": channel_str
        }
    elif action == "set_streaming_quality" and len(args) > 1:
        ensure_mpv()
        qual = args[1]
        ytdl_fmt = YTDL_FORMAT_MAP.get(qual, "774/141/251/140/bestaudio/best")
        send_mpv_cmd(["set_property", "ytdl-format", ytdl_fmt])
        print(json.dumps({"success": True, "quality": qual, "ytdl_format": ytdl_fmt}))

if __name__ == "__main__":
    main()
