#!/usr/bin/env python3
"""
Nutsty Audio Stream Resolver
Handles direct audio stream URL extraction, multi-client Innertube fallback,
yt-dlp integration, playback history tracking, and resilient TTL stream caching.
"""
import sys
import os
import json
import time
import re
import urllib.request
import subprocess
import threading

try:
    from . import platform_compat as pc
    from .ytmusic_auth import (
        PROFILE_NAME, PROFILE_SUFFIX, AUTH_FILE,
        load_json, save_json,
        create_resilient_session,
        get_ytmusic_client, get_exported_cookie_file
    )
    from .catalog_engine import search_ytmusic
except (ImportError, ValueError):
    import platform_compat as pc
    from ytmusic_auth import (
        PROFILE_NAME, PROFILE_SUFFIX, AUTH_FILE,
        load_json, save_json,
        create_resilient_session,
        get_ytmusic_client, get_exported_cookie_file
    )
    from catalog_engine import search_ytmusic

STREAM_CACHE_FILE = os.path.join(pc.get_cache_dir(), "stream_cache.json")
ONLINE_TRACKS_FILE = os.path.join(pc.get_cache_dir(), f"online_tracks{PROFILE_SUFFIX}.json")
LOCAL_YT_MAPPINGS_FILE = os.path.join(pc.get_cache_dir(), "local_yt_mappings.json")
PENDING_HISTORY_FILE = os.path.join(pc.get_cache_dir(), f"pending_history{PROFILE_SUFFIX}.json")
VISITOR_DATA_FILE = os.path.join(pc.get_cache_dir(), "visitor_data.json")
AUDIO_CACHE_DIR = os.path.join(pc.get_cache_dir(), "audio_cache")
os.makedirs(AUDIO_CACHE_DIR, exist_ok=True)

QUALITY_ITAG_PRIORITIES = {
    "high_opus": [774, 251, 250, 249, 141, 140, 18],
    "high_aac": [141, 140, 774, 251, 250, 18],
    "medium": [251, 140, 250, 141, 774, 18],
    "low": [250, 249, 139, 251, 140, 141, 774, 18]
}

# In-memory stream cache with LRU eviction and TTL (20 minutes) to prevent memory leaks and expired CDN links
from collections import OrderedDict
_MEMORY_STREAM_CACHE = OrderedDict()
_STREAM_CACHE_LOCK = threading.Lock()
STREAM_CACHE_TTL_SECONDS = 1200
STREAM_CACHE_MAX_ENTRIES = 128

_VISITOR_DATA_LOCK = threading.Lock()
_CACHED_VISITOR_DATA = None
_VISITOR_DATA_TS = 0.0

def get_visitor_data(force_refresh=False):
    """Retrieve or refresh YouTube visitorData needed for client VISIONOS (cached for 24h)."""
    global _CACHED_VISITOR_DATA, _VISITOR_DATA_TS
    now = time.time()
    with _VISITOR_DATA_LOCK:
        if not force_refresh and _CACHED_VISITOR_DATA and (now - _VISITOR_DATA_TS < 86400):
            return _CACHED_VISITOR_DATA

        if not force_refresh and os.path.exists(VISITOR_DATA_FILE):
            data = load_json(VISITOR_DATA_FILE, {})
            v = data.get("visitorData")
            ts = data.get("timestamp", 0)
            if v and (now - ts < 86400):
                _CACHED_VISITOR_DATA = v
                _VISITOR_DATA_TS = ts
                return v

    # Fetch fresh visitorData from sw.js_data
    visitor = None
    urls = ["https://music.youtube.com/sw.js_data", "https://www.youtube.com/sw.js_data"]
    for u in urls:
        try:
            req = urllib.request.Request(u, headers={
                "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15",
                "Accept-Language": "en-US,en;q=0.9"
            })
            with urllib.request.urlopen(req, timeout=4) as resp:
                text = resp.read().decode("utf-8", errors="ignore")
                matches = re.findall(r"Cg[ts][a-zA-Z0-9_\-]+", text)
                if matches:
                    visitor = matches[0]
                    break
        except Exception:
            continue

    if visitor:
        with _VISITOR_DATA_LOCK:
            _CACHED_VISITOR_DATA = visitor
            _VISITOR_DATA_TS = now
        save_json(VISITOR_DATA_FILE, {"visitorData": visitor, "timestamp": now})
    return visitor

def resolve_visionos_stream(video_id, quality="high_opus"):
    """
    Direct Innertube player resolution using Apple Vision Pro (VISIONOS) client.
    Serves non-ciphered, unthrottled direct googlevideo.com URLs (Opus 251 / AAC 140)
    in ~200-300ms without requiring PoToken or BotGuard overhead.
    """
    if not video_id:
        return None

    visitor = get_visitor_data()
    url = "https://music.youtube.com/youtubei/v1/player"
    headers = {
        "Content-Type": "application/json",
        "Accept": "application/json",
        "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15",
        "X-YouTube-Client-Name": "101",
        "X-YouTube-Client-Version": "0.1",
        "X-Origin": "https://music.youtube.com",
        "Referer": "https://music.youtube.com/",
    }
    if visitor:
        headers["X-Goog-Visitor-Id"] = visitor

    client_context = {
        "clientName": "VISIONOS",
        "clientVersion": "0.1",
        "osName": "visionOS",
        "osVersion": "1.3.21O771",
        "deviceMake": "Apple",
        "deviceModel": "RealityDevice14,1",
        "gl": "US",
        "hl": "en",
    }
    if visitor:
        client_context["visitorData"] = visitor

    payload = {
        "context": {
            "client": client_context
        },
        "videoId": video_id
    }

    data_bytes = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(url, data=data_bytes, headers=headers, method="POST")

    try:
        with urllib.request.urlopen(req, timeout=5) as resp:
            data = json.loads(resp.read().decode("utf-8"))

        status = data.get("playabilityStatus", {}).get("status")
        if status != "OK":
            return None

        streaming_data = data.get("streamingData", {})
        formats = streaming_data.get("adaptiveFormats", []) + streaming_data.get("formats", [])

        # Only accept formats with direct un-ciphered URL
        direct_formats = [f for f in formats if f.get("url") and f.get("url").startswith("https://") and "audio" in f.get("mimeType", "")]
        if not direct_formats:
            direct_formats = [f for f in formats if f.get("url") and f.get("url").startswith("https://")]
        if not direct_formats:
            return None

        priority = QUALITY_ITAG_PRIORITIES.get(quality, QUALITY_ITAG_PRIORITIES["high_opus"])
        selected = None
        for itag in priority:
            for f in direct_formats:
                if str(f.get("itag")) == str(itag):
                    selected = f
                    break
            if selected:
                break

        if not selected:
            selected = direct_formats[0]

        vdetails = data.get("videoDetails", {})
        dur = int(vdetails.get("lengthSeconds") or 0)
        return {
            "stream_url": selected["url"],
            "duration": dur,
            "quality": quality,
            "itag": str(selected.get("itag", "")),
            "bitrate": selected.get("bitrate") or selected.get("averageBitrate"),
            "codec": selected.get("mimeType", ""),
            "user_agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15",
            "referer": "https://www.youtube.com/",
            "client": "VISIONOS",
            "timestamp": time.time(),
            "title": vdetails.get("title", ""),
            "artist": vdetails.get("author", "")
        }
    except Exception as e:
        sys.stderr.write(f"[VISIONOS Innertube error for {video_id}]: {e}\n")
        return None

_ACTIVE_DOWNLOADS = set()
_ACTIVE_DOWNLOADS_LOCK = threading.Lock()

def find_audio_disk_cache(video_id):
    """
    Check if track is already cached locally on SSD in AUDIO_CACHE_DIR.
    Returns absolute path if found (> 64KB), touching mtime for LRU eviction.
    """
    if not video_id:
        return None
    clean_vid = video_id.replace("ytdl://", "")
    if "watch?v=" in clean_vid:
        clean_vid = clean_vid.split("watch?v=")[1].split("&")[0]

    candidates = [
        os.path.join(AUDIO_CACHE_DIR, f"{clean_vid}.opus"),
        os.path.join(AUDIO_CACHE_DIR, f"{clean_vid}.m4a"),
        os.path.join(AUDIO_CACHE_DIR, f"{clean_vid}.webm"),
        os.path.join(AUDIO_CACHE_DIR, f"{clean_vid}.mp3")
    ]
    for p in candidates:
        if os.path.exists(p) and os.path.getsize(p) > 65536:
            try:
                os.utime(p, None)
            except Exception:
                pass
            return p
    return None

def trim_audio_cache(max_size_mb=1200, target_size_mb=900):
    """Evict oldest accessed audio files when disk cache exceeds max_size_mb."""
    try:
        if not os.path.exists(AUDIO_CACHE_DIR):
            return
        files = []
        total_size = 0
        for entry in os.scandir(AUDIO_CACHE_DIR):
            if entry.is_file() and not entry.name.endswith(".tmp"):
                st = entry.stat()
                files.append((entry.path, st.st_size, st.st_mtime))
                total_size += st.st_size

        max_bytes = max_size_mb * 1024 * 1024
        target_bytes = target_size_mb * 1024 * 1024
        if total_size > max_bytes:
            files.sort(key=lambda x: x[2])
            for path, sz, _ in files:
                try:
                    os.remove(path)
                    total_size -= sz
                    if total_size <= target_bytes:
                        break
                except Exception:
                    pass
    except Exception:
        pass

def _download_stream_worker(clean_vid, stream_url, user_agent=None, referer=None):
    final_path = os.path.join(AUDIO_CACHE_DIR, f"{clean_vid}.opus")
    if os.path.exists(final_path) and os.path.getsize(final_path) > 65536:
        return

    tmp_path = os.path.join(AUDIO_CACHE_DIR, f"{clean_vid}_{os.getpid()}_{int(time.time())}.tmp")
    try:
        # Extract total bytes from clen parameter if available
        clen_match = re.search(r"clen=(\d+)", stream_url)
        total_bytes = int(clen_match.group(1)) if clen_match else None

        base_headers = {
            "User-Agent": user_agent or "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15",
            "Referer": referer or "https://www.youtube.com/",
            "Origin": "https://www.youtube.com"
        }

        chunk_size = 1024 * 1024  # 1MB range chunks bypass YouTube bandwidth throttling
        start_pos = 0
        with open(tmp_path, "wb") as f:
            while True:
                end_pos = start_pos + chunk_size - 1
                if total_bytes and end_pos >= total_bytes:
                    end_pos = total_bytes - 1

                h = dict(base_headers)
                h["Range"] = f"bytes={start_pos}-{end_pos}"
                req = urllib.request.Request(stream_url, headers=h)

                with urllib.request.urlopen(req, timeout=10) as resp:
                    chunk = resp.read()
                    if not chunk:
                        break
                    f.write(chunk)
                    start_pos += len(chunk)
                    if total_bytes and start_pos >= total_bytes:
                        break
                    if len(chunk) < chunk_size:
                        break

        if os.path.exists(tmp_path) and os.path.getsize(tmp_path) > 65536:
            os.replace(tmp_path, final_path)
            trim_audio_cache()
        else:
            if os.path.exists(tmp_path):
                os.remove(tmp_path)
    except Exception:
        if os.path.exists(tmp_path):
            try:
                os.remove(tmp_path)
            except Exception:
                pass
    finally:
        with _ACTIVE_DOWNLOADS_LOCK:
            _ACTIVE_DOWNLOADS.discard(clean_vid)

def cache_audio_stream_async(video_id, stream_url, user_agent=None, referer=None):
    """
    Download audio stream in background to SSD disk cache so subsequent
    plays have 0s latency (instant local playback).
    """
    if not video_id or not stream_url or stream_url.startswith("/") or stream_url.startswith("file://"):
        return
    clean_vid = video_id.replace("ytdl://", "")
    if "watch?v=" in clean_vid:
        clean_vid = clean_vid.split("watch?v=")[1].split("&")[0]

    final_path = os.path.join(AUDIO_CACHE_DIR, f"{clean_vid}.opus")
    if os.path.exists(final_path) and os.path.getsize(final_path) > 65536:
        return

    with _ACTIVE_DOWNLOADS_LOCK:
        if clean_vid in _ACTIVE_DOWNLOADS:
            return
        _ACTIVE_DOWNLOADS.add(clean_vid)

    try:
        script_path = os.path.abspath(__file__)
        popen_args = [
            sys.executable, script_path, "cache_worker",
            clean_vid, stream_url,
            user_agent or "", referer or ""
        ]
        popen_kwargs = pc.get_daemon_popen_kwargs() if hasattr(pc, "get_daemon_popen_kwargs") else {}
        if not pc.IS_WINDOWS and "start_new_session" not in popen_kwargs:
            popen_kwargs["start_new_session"] = True
        subprocess.Popen(
            popen_args,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            **popen_kwargs
        )
    except Exception:
        t = threading.Thread(target=_download_stream_worker, args=(clean_vid, stream_url, user_agent, referer), daemon=True)
        t.start()

def get_cached_stream_url(video_id, quality="high_opus"):
    """Thread-safe TTL cache lookup in memory with disk fallback"""
    now = time.time()
    cache_key = f"{video_id}_{quality}"
    with _STREAM_CACHE_LOCK:
        if cache_key in _MEMORY_STREAM_CACHE:
            entry = _MEMORY_STREAM_CACHE[cache_key]
            if now - entry.get("timestamp", 0) < STREAM_CACHE_TTL_SECONDS:
                _MEMORY_STREAM_CACHE.move_to_end(cache_key)
                return entry.get("url")
            else:
                del _MEMORY_STREAM_CACHE[cache_key]

    # Disk cache lookup
    disk_cache = load_json(STREAM_CACHE_FILE, {})
    if cache_key in disk_cache:
        entry = disk_cache[cache_key]
        if isinstance(entry, dict):
            if now - entry.get("timestamp", 0) < STREAM_CACHE_TTL_SECONDS:
                with _STREAM_CACHE_LOCK:
                    _MEMORY_STREAM_CACHE[cache_key] = entry
                    _MEMORY_STREAM_CACHE.move_to_end(cache_key)
                return entry.get("url")
        elif isinstance(entry, str):
            with _STREAM_CACHE_LOCK:
                _MEMORY_STREAM_CACHE[cache_key] = {"url": entry, "timestamp": now}
                _MEMORY_STREAM_CACHE.move_to_end(cache_key)
            return entry
    return None

def put_cached_stream_url(video_id, url, quality="high_opus"):
    """Store fresh stream URL in memory (LRU bounded) and persistent disk cache"""
    if not video_id or not url:
        return
    now = time.time()
    cache_key = f"{video_id}_{quality}"
    entry = {"url": url, "timestamp": now}
    with _STREAM_CACHE_LOCK:
        if cache_key in _MEMORY_STREAM_CACHE:
            _MEMORY_STREAM_CACHE.move_to_end(cache_key)
        _MEMORY_STREAM_CACHE[cache_key] = entry
        while len(_MEMORY_STREAM_CACHE) > STREAM_CACHE_MAX_ENTRIES:
            _MEMORY_STREAM_CACHE.popitem(last=False)
    try:
        disk_cache = load_json(STREAM_CACHE_FILE, {})
        disk_cache[cache_key] = entry
        if len(disk_cache) > 256:
            # Prune oldest disk cache entries
            sorted_keys = sorted(disk_cache.keys(), key=lambda k: disk_cache[k].get("timestamp", 0) if isinstance(disk_cache[k], dict) else 0)
            for old_k in sorted_keys[:-256]:
                disk_cache.pop(old_k, None)
        save_json(STREAM_CACHE_FILE, disk_cache)
    except Exception:
        pass

def invalidate_cached_stream_url(video_id, quality=None):
    """Evict stream URL on HTTP 403 or network failure"""
    with _STREAM_CACHE_LOCK:
        keys_to_del = [k for k in _MEMORY_STREAM_CACHE if k.startswith(video_id)]
        for k in keys_to_del:
            del _MEMORY_STREAM_CACHE[k]
    try:
        disk_cache = load_json(STREAM_CACHE_FILE, {})
        keys_to_del = [k for k in disk_cache if k.startswith(video_id)]
        if keys_to_del:
            for k in keys_to_del:
                del disk_cache[k]
            save_json(STREAM_CACHE_FILE, disk_cache)
    except Exception:
        pass

def resolve_stream_url(video_id, quality=None, force_fresh=False):
    if not video_id:
        return None

    if video_id.startswith("ytdl://"):
        video_id = video_id.replace("ytdl://", "")
    elif "watch?v=" in video_id:
        vid_match = re.search(r"[?&]v=([^&#]+)", video_id)
        if vid_match:
            video_id = vid_match.group(1)
        else:
            video_id = video_id.split("watch?v=")[1].split("&")[0]

    if force_fresh:
        invalidate_cached_stream_url(video_id)

    if not quality:
        settings_path = os.path.join(pc.get_config_dir(), "nutsty_settings.json")
        if os.path.exists(settings_path):
            try:
                with open(settings_path, "r", encoding="utf-8") as f:
                    s_obj = json.load(f)
                    quality = s_obj.get("streamingQuality", "high_opus")
            except Exception:
                quality = "high_opus"
        else:
            quality = "high_opus"

    quality = quality if quality in QUALITY_ITAG_PRIORITIES else "high_opus"
    cache_key = f"{video_id}_{quality}"

    now = time.time()

    # ── PRIORITY 0: Check SSD Disk Audio Cache (0s Instant Local Latency) ──
    if not force_fresh:
        cached_disk = find_audio_disk_cache(video_id)
        if cached_disk and os.path.exists(cached_disk):
            res = {
                "stream_url": cached_disk,
                "duration": 0,
                "quality": quality,
                "itag": "disk",
                "codec": "opus",
                "client": "DISK_CACHE",
                "is_local_file": True,
                "timestamp": now
            }
            return res

    if not force_fresh:
        with _STREAM_CACHE_LOCK:
            if cache_key in _MEMORY_STREAM_CACHE:
                entry = _MEMORY_STREAM_CACHE[cache_key]
                if (now - entry.get("timestamp", 0)) < STREAM_CACHE_TTL_SECONDS:
                    return entry

        cache = load_json(STREAM_CACHE_FILE, {})
        cached = cache.get(cache_key)
        if not cached:
            legacy = cache.get(video_id)
            if legacy and legacy.get("quality") == quality:
                cached = legacy

        if cached and (now - cached.get("timestamp", 0)) < STREAM_CACHE_TTL_SECONDS:
            # If user wanted high_opus but cached entry is legacy fallback itag 18 / mp4a, ignore stale cache
            if quality == "high_opus" and (str(cached.get("itag")) == "18" or "mp4a" in str(cached.get("codec", ""))):
                cached = None
            else:
                with _STREAM_CACHE_LOCK:
                    _MEMORY_STREAM_CACHE[cache_key] = cached
                return cached
    else:
        cache = load_json(STREAM_CACHE_FILE, {})

    # ── PRIORITY 1: Super-Fast Direct Innertube via VISIONOS Client (~0.2s - 0.4s) ──
    try:
        vision_res = resolve_visionos_stream(video_id, quality=quality)
        if vision_res and vision_res.get("stream_url"):
            cache[cache_key] = vision_res
            save_json(STREAM_CACHE_FILE, cache)
            with _STREAM_CACHE_LOCK:
                _MEMORY_STREAM_CACHE[cache_key] = vision_res
            # Background async caching to SSD so repeated plays are 0s
            cache_audio_stream_async(
                video_id,
                vision_res["stream_url"],
                user_agent=vision_res.get("user_agent"),
                referer=vision_res.get("referer")
            )
            return vision_res
    except Exception as e:
        sys.stderr.write(f"[VISIONOS stream fallback for {video_id}]: {e}\n")

    try:
        import yt_dlp

        cookie_file = get_exported_cookie_file()
        url = f"https://www.youtube.com/watch?v={video_id}"
        attempts = []

        # Attempt 1: Android client (Highest resilience against bot detection on YouTube Music)
        attempts.append({
            "quiet": True,
            "no_warnings": True,
            "skip_download": True,
            "check_formats": False,
            "noplaylist": True,
            "socket_timeout": 8,
            "extractor_args": {"youtube": {"player_client": ["android", "web"]}}
        })

        # Attempt 2: Modern TV / Web Embedded client with optional cookies (extracts clean 251 Opus / 140 AAC)
        opt2 = {
            "quiet": True,
            "no_warnings": True,
            "skip_download": True,
            "check_formats": False,
            "noplaylist": True,
            "socket_timeout": 8,
            "extractor_args": {"youtube": {"player_client": ["tv", "web_embedded"]}}
        }
        if cookie_file and os.path.exists(cookie_file):
            opt2["cookiefile"] = cookie_file
        attempts.append(opt2)

        # Attempt 3: User cookie file with mweb / web_embedded client
        if cookie_file and os.path.exists(cookie_file):
            attempts.append({
                "quiet": True,
                "no_warnings": True,
                "skip_download": True,
                "check_formats": False,
                "noplaylist": True,
                "socket_timeout": 8,
                "cookiefile": cookie_file,
                "extractor_args": {"youtube": {"player_client": ["mweb", "web_embedded"]}}
            })

        # Attempt 4: Standard resilient web client extraction
        attempts.append({
            "quiet": True,
            "no_warnings": True,
            "skip_download": True,
            "check_formats": False,
            "noplaylist": True,
            "socket_timeout": 8,
        })

        # Attempt 5: Resilient iOS / mobile web client fallback
        attempts.append({
            "quiet": True,
            "no_warnings": True,
            "skip_download": True,
            "check_formats": False,
            "noplaylist": True,
            "socket_timeout": 8,
            "extractor_args": {"youtube": {"player_client": ["ios", "mweb"]}}
        })

        for ydl_opts in attempts:
            try:
                with yt_dlp.YoutubeDL(ydl_opts) as ydl:
                    info = ydl.extract_info(url, download=False)
                    formats = [f for f in info.get("formats", []) if f.get("acodec") != "none"]
                    if not formats and info.get("url"):
                        formats = [info]

                    # Select format matching priority list (SimpMusic Twin Fallback)
                    priority = QUALITY_ITAG_PRIORITIES.get(quality, QUALITY_ITAG_PRIORITIES["high_opus"])
                    selected_format = None
                    for itag in priority:
                        for f in formats:
                            fid = str(f.get("format_id") or "")
                            if fid == str(itag) and f.get("url"):
                                selected_format = f
                                break
                        if selected_format:
                            break

                    if not selected_format and formats:
                        selected_format = formats[-1]

                    stream_url = selected_format.get("url") if selected_format else info.get("url")
                    duration = info.get("duration") or 0
                    ua = selected_format.get("http_headers", {}).get("User-Agent") if selected_format else None
                    if stream_url:
                        res = {
                            "stream_url": stream_url,
                            "duration": duration,
                            "quality": quality,
                            "itag": selected_format.get("format_id") if selected_format else None,
                            "bitrate": selected_format.get("abr") if selected_format else None,
                            "codec": selected_format.get("acodec") if selected_format else None,
                            "user_agent": ua,
                            "timestamp": now
                        }
                        cache[cache_key] = res
                        save_json(STREAM_CACHE_FILE, cache)
                        with _STREAM_CACHE_LOCK:
                            _MEMORY_STREAM_CACHE[cache_key] = res
                        cache_audio_stream_async(video_id, stream_url, user_agent=ua)
                        return res
            except Exception:
                continue
    except Exception as e:
        sys.stderr.write(f"[resolve_stream_url error for {video_id} ({quality})]: {e}\n")

    return None

PENDING_HISTORY_FILE = os.path.join(pc.get_cache_dir(), "pending_history.json")
LOCAL_YT_MAPPINGS_FILE = os.path.join(pc.get_cache_dir(), "local_yt_mappings.json")

def resolve_video_id_for_track(video_id, title="", artist=""):
    """If video_id is valid, return it. If local song, lookup via Title + Artist on YTMusic"""
    if video_id and not video_id.startswith("/") and not os.path.isabs(video_id) and not video_id.startswith("file://"):
        vid = video_id.replace("ytdl://", "")
        if "watch?v=" in vid:
            vid = vid.split("watch?v=")[1].split("&")[0]
        if len(vid) == 11:
            return vid

    clean_title = (title or "").strip()
    clean_artist = (artist or "").strip()
    if not clean_title:
        return None

    cache_key = f"{clean_title}|||{clean_artist}".lower()
    mappings = load_json(LOCAL_YT_MAPPINGS_FILE, {})
    if cache_key in mappings:
        return mappings[cache_key]

    try:
        yt = get_ytmusic_client()
        query = f"{clean_title} {clean_artist}".strip()
        results = yt.search(query, filter="songs", limit=1)
        if results and "videoId" in results[0]:
            found_id = results[0]["videoId"]
            mappings[cache_key] = found_id
            save_json(LOCAL_YT_MAPPINGS_FILE, mappings)
            return found_id
    except Exception as e:
        sys.stderr.write(f"[resolve_video_id_for_track error]: {e}\n")
    return None

def send_playback_tracking(video_id, title="", artist="", playlist_id=None):
    """
    Sends playback tracking and watchtime to Google account
    so that account records it in Watch History and updates personalized shelves.
    """
    vid = resolve_video_id_for_track(video_id, title, artist)
    if not vid:
        return {"success": False, "error": "Could not resolve videoId for tracking"}

    if not os.path.exists(AUTH_FILE):
        return {"success": False, "error": "Not logged in to Google Account"}

    def _execute_tracking(target_vid, p_id=None):
        import string
        import random
        try:
            yt = get_ytmusic_client()
            song = yt.get_song(target_vid)
            pt = song.get("playbackTracking")
            if not pt:
                return False

            # 1. Official playback ping to s.youtube.com via ytmusicapi
            yt.add_history_item(song)

            cpn = "".join(random.choices(string.ascii_letters + string.digits + "-_", k=16))

            # 2. Watchtime ping 1 (Initial start registration)
            watchtime_url = pt.get("videostatsWatchtimeUrl", {}).get("baseUrl")
            if watchtime_url:
                p_wt1 = {
                    "ver": 2,
                    "c": "WEB_REMIX",
                    "cpn": cpn,
                    "st": "0",
                    "et": "5.5",
                    "state": "playing"
                }
                if p_id:
                    p_wt1["list"] = p_id
                    p_wt1["referrer"] = f"https://music.youtube.com/playlist?list={p_id}"
                yt._send_get_request(watchtime_url, params=p_wt1)

                # 3. Watchtime ping 2 (Sustained listen >= 35s - triggers "Listen again" shelf promotion)
                p_wt2 = {
                    "ver": 2,
                    "c": "WEB_REMIX",
                    "cpn": cpn,
                    "st": "5.5",
                    "et": "35.0",
                    "state": "playing"
                }
                if p_id:
                    p_wt2["list"] = p_id
                    p_wt2["referrer"] = f"https://music.youtube.com/playlist?list={p_id}"
                yt._send_get_request(watchtime_url, params=p_wt2)

            # 4. Synchronous ATR (Attribution) ping
            atr_url = pt.get("atrUrl", {}).get("baseUrl")
            if atr_url:
                p_atr = {"cpn": cpn}
                if p_id:
                    p_atr["list"] = p_id
                    p_atr["referrer"] = f"https://music.youtube.com/playlist?list={p_id}"
                yt._send_get_request(atr_url, params=p_atr)

            return True
        except Exception as e:
            sys.stderr.write(f"[execute_tracking error]: {e}\n")
            return False

    def _flush_pending():
        pending = load_json(PENDING_HISTORY_FILE, [])
        if pending and isinstance(pending, list):
            remaining = []
            for item in pending:
                t_vid = item.get("videoId")
                if t_vid:
                    ok = _execute_tracking(t_vid, item.get("playlistId"))
                    if not ok:
                        remaining.append(item)
            save_json(PENDING_HISTORY_FILE, remaining)

    import threading
    threading.Thread(target=_flush_pending, daemon=True).start()

    success = _execute_tracking(vid, playlist_id)
    if not success:
        pending = load_json(PENDING_HISTORY_FILE, [])
        if not isinstance(pending, list):
            pending = []
        pending.append({
            "videoId": vid,
            "title": title,
            "artist": artist,
            "playlistId": playlist_id,
            "timestamp": int(time.time())
        })
        save_json(PENDING_HISTORY_FILE, pending)
        return {"success": False, "queued": True, "videoId": vid}

    return {"success": True, "videoId": vid, "title": title, "artist": artist}

if __name__ == "__main__":
    if len(sys.argv) > 1:
        cmd = sys.argv[1].lower()
        if cmd == "cache_worker" and len(sys.argv) > 3:
            _vid = sys.argv[2]
            _url = sys.argv[3]
            _ua = sys.argv[4] if len(sys.argv) > 4 else None
            _ref = sys.argv[5] if len(sys.argv) > 5 else None
            _download_stream_worker(_vid, _url, _ua, _ref)
        elif cmd == "resolve" and len(sys.argv) > 2:
            _vid = sys.argv[2]
            _q = sys.argv[3] if len(sys.argv) > 3 else "high_opus"
            res = resolve_stream_url(_vid, quality=_q)
            print(json.dumps(res or {}, ensure_ascii=False))


