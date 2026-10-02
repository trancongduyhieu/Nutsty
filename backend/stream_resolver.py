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

QUALITY_ITAG_PRIORITIES = {
    "high_opus": [774, 141, 251, 140, 250, 18],
    "high_aac": [141, 774, 140, 251, 250, 18],
    "medium": [251, 140, 250, 141, 774, 18],
    "low": [250, 249, 139, 251, 140, 141, 774, 18]
}

# In-memory stream cache with TTL eviction (5 hours) to prevent expired Google CDN links
_MEMORY_STREAM_CACHE = {}
_STREAM_CACHE_LOCK = threading.Lock()
STREAM_CACHE_TTL_SECONDS = 5 * 3600

def get_cached_stream_url(video_id, quality="high_opus"):
    """Thread-safe TTL cache lookup in memory with disk fallback"""
    now = time.time()
    cache_key = f"{video_id}_{quality}"
    with _STREAM_CACHE_LOCK:
        if cache_key in _MEMORY_STREAM_CACHE:
            entry = _MEMORY_STREAM_CACHE[cache_key]
            if now - entry.get("timestamp", 0) < STREAM_CACHE_TTL_SECONDS:
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
                return entry.get("url")
        elif isinstance(entry, str):
            with _STREAM_CACHE_LOCK:
                _MEMORY_STREAM_CACHE[cache_key] = {"url": entry, "timestamp": now}
            return entry
    return None

def put_cached_stream_url(video_id, url, quality="high_opus"):
    """Store fresh stream URL in memory and persistent disk cache"""
    if not video_id or not url:
        return
    now = time.time()
    cache_key = f"{video_id}_{quality}"
    entry = {"url": url, "timestamp": now}
    with _STREAM_CACHE_LOCK:
        _MEMORY_STREAM_CACHE[cache_key] = entry
    try:
        disk_cache = load_json(STREAM_CACHE_FILE, {})
        disk_cache[cache_key] = entry
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

def resolve_stream_url(video_id, quality=None):
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

    cache = load_json(STREAM_CACHE_FILE, {})
    cached = cache.get(cache_key)
    if not cached:
        legacy = cache.get(video_id)
        if legacy and legacy.get("quality") == quality:
            cached = legacy
    now = time.time()

    if cached and (now - cached.get("timestamp", 0)) < 10800:
        return cached

    try:
        import yt_dlp

        cookie_file = get_exported_cookie_file()
        url = f"https://www.youtube.com/watch?v={video_id}"

        attempts = []

        # Attempt 1: Fast mobile + TV solver (android, ios, tv_embedded)
        attempts.append({
            "quiet": True,
            "no_warnings": True,
            "skip_download": True,
            "check_formats": False,
            "noplaylist": True,
            "extractor_args": {"youtube": {"player_client": ["android", "ios", "tv_embedded"]}}
        })

        # Attempt 2: User cookie file with mweb/web_embedded/android if Google Account session exists
        if cookie_file and os.path.exists(cookie_file):
            attempts.append({
                "quiet": True,
                "no_warnings": True,
                "skip_download": True,
                "check_formats": False,
                "noplaylist": True,
                "cookiefile": cookie_file,
                "extractor_args": {"youtube": {"player_client": ["mweb", "web_embedded", "android", "tv_embedded"]}}
            })

        # Attempt 3: Creator + TV embedded fallback (bypasses bot detection and SABR restrictions)
        attempts.append({
            "quiet": True,
            "no_warnings": True,
            "skip_download": True,
            "check_formats": False,
            "noplaylist": True,
            "extractor_args": {"youtube": {"player_client": ["android_creator", "tv_embedded"]}}
        })

        # Attempt 4: Resilient broad fallback
        attempts.append({
            "quiet": True,
            "no_warnings": True,
            "skip_download": True,
            "check_formats": False,
            "noplaylist": True
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


