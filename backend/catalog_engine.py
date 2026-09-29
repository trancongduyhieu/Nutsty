#!/usr/bin/env python3
"""
Nutsty YouTube Music Catalog & Discovery Engine
Provides personalized home feed, mood categories, dynamic radio queues,
disliked songs preferences, artist avatar caching, and comprehensive categorized search.
"""
import sys
import os
import json
import time
import re
import hashlib
import urllib.request

try:
    from . import platform_compat as pc
    from .ytmusic_auth import (
        PROFILE_NAME, PROFILE_SUFFIX, AUTH_FILE,
        load_json, save_json,
        create_resilient_session,
        get_ytmusic_client, get_auth_status
    )
except (ImportError, ValueError):
    import platform_compat as pc
    from ytmusic_auth import (
        PROFILE_NAME, PROFILE_SUFFIX, AUTH_FILE,
        load_json, save_json,
        create_resilient_session,
        get_ytmusic_client, get_auth_status
    )

HOME_CACHE_FILE = os.path.join(pc.get_cache_dir(), f"home_feed{PROFILE_SUFFIX}.json")
ONLINE_TRACKS_FILE = os.path.join(pc.get_cache_dir(), f"online_tracks{PROFILE_SUFFIX}.json")
MOOD_CACHE_DIR = os.path.join(pc.get_cache_dir(), "moods")
MOOD_CATS_FILE = os.path.join(pc.get_cache_dir(), "mood_categories.json")
DISLIKED_SONGS_FILE = os.path.join(pc.get_config_dir(), f"nutsty_disliked_songs{PROFILE_SUFFIX}.json")
ARTIST_AVATARS_FILE = os.path.join(pc.get_cache_dir(), "artist_avatars.json")

DISLIKED_SONGS_FILE = os.path.join(pc.get_config_dir(), f"nutsty_disliked_songs{PROFILE_SUFFIX}.json")

def load_disliked_songs():
    return load_json(DISLIKED_SONGS_FILE, {})

def save_disliked_songs(data):
    save_json(DISLIKED_SONGS_FILE, data)

def add_disliked_song(video_id, title="", artist=""):
    clean_vid = str(video_id).strip().replace("ytdl://", "").replace("yt_", "")
    if not clean_vid:
        return False
    data = load_disliked_songs()
    data[clean_vid] = {
        "videoId": clean_vid,
        "title": title,
        "artist": artist,
        "timestamp": int(time.time())
    }
    save_disliked_songs(data)
    return True

def remove_disliked_song(video_id):
    clean_vid = str(video_id).strip().replace("ytdl://", "").replace("yt_", "")
    if not clean_vid:
        return False
    data = load_disliked_songs()
    if clean_vid in data:
        del data[clean_vid]
        save_disliked_songs(data)
    return True

def is_song_disliked(video_id):
    if not video_id:
        return False
    clean_vid = str(video_id).strip().replace("ytdl://", "").replace("yt_", "")
    data = load_disliked_songs()
    return clean_vid in data

ARTIST_AVATARS_FILE = os.path.join(pc.get_cache_dir(), "artist_avatars.json")

def load_artist_avatars():
    return load_json(ARTIST_AVATARS_FILE, {})

def save_artist_avatars(data):
    save_json(ARTIST_AVATARS_FILE, data)

def cache_artist_avatar(artist_name, avatar_url):
    if not artist_name or not avatar_url:
        return
    norm = str(artist_name).strip().lower()
    data = load_artist_avatars()
    if data.get(norm) != avatar_url:
        data[norm] = avatar_url
        save_artist_avatars(data)

def get_cached_artist_avatar(artist_name):
    if not artist_name:
        return ""
    norm = str(artist_name).strip().lower()
    return load_artist_avatars().get(norm, "")


def cache_online_tracks(tracks):
    try:
        data = load_json(ONLINE_TRACKS_FILE, {})
        for t in tracks:
            vid = t.get("videoId")
            if vid:
                data[vid] = t
                data[t.get("path")] = t
        save_json(ONLINE_TRACKS_FILE, data)
    except Exception:
        pass


def clean_artist_name(raw_name):
    if not raw_name:
        return "YouTube Music"
    s = str(raw_name).strip()
    # Split by bullet point separator ' • '
    parts = re.split(r'\s*•\s*', s)
    for p in parts:
        p_clean = p.strip()
        if not p_clean:
            continue
        if re.search(r'\d+([.,]\d+)?\s*[KMBkmb]?\s*(views|plays|lượt xem|lượt nghe)', p_clean, re.I):
            continue
        if p_clean.lower() in ("single", "album", "ep", "video", "bài hát", "nghệ sĩ", "artist"):
            continue
        return p_clean
    return parts[0].strip() or "YouTube Music"

def clean_thumbnail_url(url, vid=None, is_16_9=False):
    """
    Returns optimal high-resolution artwork URL:
    1. Google CDN: upscaled to =w1200-h1200-l90-rj (square) or =w1280-h720-l90-rj (16:9).
    2. Apple Music CDN: upscaled to 1200x1200bb.
    3. YouTube video CDN: strips ?sqp= compression query parameters.
    """
    if not url:
        return f"https://i.ytimg.com/vi/{vid}/maxresdefault.jpg" if vid else ""
    url = str(url).strip()
    if "googleusercontent.com" in url or "ggpht.com" in url:
        target_dim = "=w1280-h720-l90-rj" if is_16_9 else "=w1200-h1200-l90-rj"
        upgraded = re.sub(r'=w\d+-h\d+.*', target_dim, url)
        if target_dim not in upgraded:
            if "=" in upgraded:
                upgraded = upgraded.split("=")[0] + target_dim
            else:
                upgraded = upgraded + target_dim
        return upgraded
    if "mzstatic.com" in url:
        return re.sub(r'\d+x\d+bb', '1200x1200bb', url)
    if "i.ytimg.com" in url:
        clean = url.split("?")[0]
        return clean
    return url

def normalize_track(item):
    vid = item.get("videoId")
    if not vid or is_song_disliked(vid):
        return None
    title = item.get("title", "Unknown")
    artists = item.get("artists", [])
    channel_id = ""
    for a in artists:
        if isinstance(a, dict) and a.get("id"):
            channel_id = a.get("id")
            break
    artist_name = ", ".join(a.get("name", "") for a in artists if a.get("name")) or ""
    if not artist_name:
        artist_name = item.get("artist", "")
    artist_name = clean_artist_name(artist_name)
    dur_str = item.get("duration", "--:--")
    dur_sec = item.get("duration_seconds") or 0
    thumbs = item.get("thumbnails", [])
    raw_thumb = thumbs[-1].get("url", "") if thumbs else ""
    thumb_url = clean_thumbnail_url(raw_thumb, vid)

    res = {
        "id": f"yt_{vid}",
        "title": title,
        "name": title,
        "artist": artist_name,
        "source": "YouTube Music",
        "path": f"ytdl://{vid}",
        "videoId": vid,
        "duration": dur_str,
        "durationMs": dur_sec * 1000,
        "image": thumb_url
    }
    alb = item.get("album")
    if isinstance(alb, dict):
        res["album"] = alb.get("name", "")
        res["albumId"] = alb.get("id", "")
    elif isinstance(alb, str):
        res["album"] = alb
    views = item.get("views", "")
    if views:
        res["views"] = views if ("lượt" in str(views).lower() or "play" in str(views).lower()) else f"{views} lượt phát"
    if channel_id:
        res["channelId"] = channel_id
    return res

def get_recent_seed_track():
    sess_file = os.path.expanduser("~/.config/noctalia/nutsty_session.json")
    if os.path.exists(sess_file):
        try:
            data = load_json(sess_file)
            p = data.get("path", "")
            if p.startswith("ytdl://"):
                return p.replace("ytdl://", "")
        except Exception:
            pass
    return "J7p4bzqLvCw"

DEFAULT_MOOD_PILLS = [
    {"title": "All", "params": ""},
    {"title": "Relax", "params": "ggM8SgQIBxADSgQIBRABSgQICRABSgQIChABSgQIDRABSgQIDhABSgQIAxABSgQICBABSgQIBhABSgQIBBAB"},
    {"title": "Sleep", "params": "ggM8SgQIBxABSgQIBRADSgQICRABSgQIChABSgQIDRABSgQIDhABSgQIAxABSgQICBABSgQIBhABSgQIBBAB"},
    {"title": "Energize", "params": "ggM8SgQIBxABSgQIBRABSgQICRADSgQIChABSgQIDRABSgQIDhABSgQIAxABSgQICBABSgQIBhABSgQIBBAB"},
    {"title": "Sad", "params": "ggM8SgQIBxABSgQIBRABSgQICRABSgQIChADSgQIDRABSgQIDhABSgQIAxABSgQICBABSgQIBhABSgQIBBAB"},
    {"title": "Romance", "params": "ggM8SgQIBxABSgQIBRABSgQICRABSgQIChABSgQIDRADSgQIDhABSgQIAxABSgQICBABSgQIBhABSgQIBBAB"},
    {"title": "Party", "params": "ggM8SgQIBxABSgQIBRABSgQICRABSgQIChABSgQIDRABSgQIDhADSgQIAxABSgQICBABSgQIBhABSgQIBBAB"},
    {"title": "Commute", "params": "ggM8SgQIBxABSgQIBRABSgQICRABSgQIChABSgQIDRABSgQIDhABSgQIAxADSgQICBABSgQIBhABSgQIBBAB"},
    {"title": "Feel good", "params": "ggM8SgQIBxABSgQIBRABSgQICRABSgQIChABSgQIDRABSgQIDhABSgQIAxABSgQICBADSgQIBhABSgQIBBAB"},
    {"title": "Focus", "params": "ggM8SgQIBxABSgQIBRABSgQICRABSgQIChABSgQIDRABSgQIDhABSgQIAxABSgQICBABSgQIBhADSgQIBBAB"},
    {"title": "Workout", "params": "ggM8SgQIBxABSgQIBRABSgQICRABSgQIChABSgQIDRABSgQIDhABSgQIAxABSgQICBABSgQIBhABSgQIBBAD"}
]

def get_mood_categories_live():
    cached = load_json(MOOD_CATS_FILE, None)
    if cached and (time.time() - cached.get("timestamp", 0)) < 86400:
        return cached.get("categories", DEFAULT_MOOD_PILLS)
    return DEFAULT_MOOD_PILLS

def _normalize_shelf_item(it, shelf_title=""):
    if not isinstance(it, dict):
        return None

PALETTE_CREATORS = [
    "#00bcd4",  # cyan
    "#ff7043",  # orange
    "#ab47bc",  # purple
    "#26a69a",  # teal
    "#42a5f5",  # blue
    "#ff5722",  # deep orange
    "#ffa726",  # amber
    "#ec407a",  # pink
    "#7e57c2",  # deep purple
    "#66bb6a",  # light green
]

def get_creator_color(name):
    if not name:
        return "#00bcd4"
    h = 0
    for ch in str(name):
        h = (h * 31 + ord(ch)) & 0xFFFFFFFF
    return PALETTE_CREATORS[h % len(PALETTE_CREATORS)]

def classify_section(title, norm_items):
    lower_t = str(title).lower()
    track_count = sum(1 for x in norm_items if x.get("type") in ["track", "video"])
    pl_count = sum(1 for x in norm_items if x.get("type") in ["playlist", "album"])
    has_16_9 = any(x.get("aspectRatio") == "16:9" or x.get("isVideo") for x in norm_items)

    # 1. Multi-row Track Grid (4 rows per column)
    if any(k in lower_t for k in ["quick", "lựa chọn nhanh", "cover", "remix", "trending song", "bài hát thịnh hành", "long", "thư giãn", "shorts"]):
        return "track_grid"

    # 2. Video Carousel (16:9 Widescreen)
    if any(k in lower_t for k in ["video", "listen again", "nghe lại", "forgotten", "giai điệu", "cùng nghe", "together"]):
        return "video_carousel"

    # 3. Large Square Album & Playlist Carousel
    if pl_count >= len(norm_items) * 0.5 or any(k in lower_t for k in ["album", "playlist", "community", "cộng đồng", "release", "mới phát hành", "mix", "kết hợp", "bảng xếp hạng", "chart", "station", "danh sách"]):
        return "album_carousel"

    # 4. Aspect Ratio Heuristic
    if has_16_9:
        return "video_carousel"

    # 5. Default fallback heuristics
    if track_count > len(norm_items) * 0.7:
        return "track_grid"
    return "album_carousel"

def _normalize_shelf_item(it, shelf_title):
    if not isinstance(it, dict):
        return None
    # 1. musicResponsiveListItemRenderer
    if "musicResponsiveListItemRenderer" in it:
        r = it["musicResponsiveListItemRenderer"]
        vid = r.get("playlistItemData", {}).get("videoId")
        if vid and is_song_disliked(vid):
            return None
        cols = r.get("flexColumns", [])
        title = "".join(x.get("text", "") for x in cols[0].get("musicResponsiveListItemFlexColumnRenderer", {}).get("text", {}).get("runs", [])) if cols else ""
        artist = ""
        channel_id = ""
        views = ""
        if len(cols) > 1:
            artist_runs = cols[1].get("musicResponsiveListItemFlexColumnRenderer", {}).get("text", {}).get("runs", [])
            for x in artist_runs:
                txt = x.get("text", "").strip()
                if not txt or txt == "•":
                    continue
                if any(w in txt.lower() for w in ["views", "plays", "lượt xem", "lượt phát"]):
                    views = txt
                    continue
                if not artist:
                    artist = txt
                    ep = x.get("navigationEndpoint", {}).get("browseEndpoint", {})
                    if ep and ep.get("browseId"):
                        channel_id = ep.get("browseId")
            if not artist:
                artist = "".join(x.get("text", "") for x in artist_runs if "views" not in x.get("text", "").lower() and "plays" not in x.get("text", "").lower() and "lượt" not in x.get("text", "").lower()).strip(" • ")
        artist = clean_artist_name(artist)
        thumbs = r.get("thumbnail", {}).get("musicThumbnailRenderer", {}).get("thumbnail", {}).get("thumbnails", [])
        raw_thumb = thumbs[-1].get("url", "") if thumbs else ""
        thumb_url = clean_thumbnail_url(raw_thumb, vid, is_16_9=False)
        if vid and title:
            item_res = {
                "id": f"yt_{vid}",
                "type": "track",
                "title": title,
                "name": title,
                "artist": artist or "YouTube Music",
                "subtitle": f"{artist} • {views}" if (artist and views) else (artist or "YouTube Music"),
                "views": views,
                "source": "YouTube Music",
                "path": f"ytdl://{vid}",
                "videoId": vid,
                "duration": "--:--",
                "durationMs": 0,
                "image": thumb_url,
                "aspectRatio": "1:1",
                "isVideo": False
            }
            if channel_id:
                item_res["channelId"] = channel_id
            return item_res

    # 2. musicTwoRowItemRenderer
    elif "musicTwoRowItemRenderer" in it:
        r = it["musicTwoRowItemRenderer"]
        title = "".join(x.get("text", "") for x in r.get("title", {}).get("runs", []))
        sub = "".join(x.get("text", "") for x in r.get("subtitle", {}).get("runs", []))
        sub_runs = r.get("subtitle", {}).get("runs", [])
        artist_name = ""
        channel_id = ""
        views = ""
        for x in sub_runs:
            txt = x.get("text", "").strip()
            if not txt or txt == "•":
                continue
            if any(w in txt.lower() for w in ["views", "plays", "lượt xem", "lượt phát"]):
                views = txt
            elif not artist_name and not any(w in txt.lower() for w in ["playlist", "danh sách phát", "album", "ep", "single"]):
                artist_name = txt
                ep = x.get("navigationEndpoint", {}).get("browseEndpoint", {})
                if ep and ep.get("browseId"):
                    channel_id = ep.get("browseId")
        if not artist_name:
            artist_name = clean_artist_name(sub)

        r_aspect = str(r.get("aspectRatio", ""))
        is_16_9 = ("16_9" in r_aspect) or ("RECTANGLE" in r_aspect)
        if not is_16_9 and any(k in shelf_title.lower() for k in ["video", "listen again", "nghe lại", "forgotten", "giai điệu", "cùng nghe"]):
            is_16_9 = True

        thumbs = r.get("thumbnailRenderer", {}).get("musicThumbnailRenderer", {}).get("thumbnail", {}).get("thumbnails", [])
        raw_thumb = thumbs[-1].get("url", "") if thumbs else ""
        thumb_url = clean_thumbnail_url(raw_thumb, vid=None, is_16_9=is_16_9)

        nav_ep = r.get("navigationEndpoint", {})
        watch_ep = nav_ep.get("watchEndpoint", {})
        browse_ep = nav_ep.get("browseEndpoint", {})

        vid = watch_ep.get("videoId")
        if vid and is_song_disliked(vid):
            return None
        pl_id = watch_ep.get("playlistId") or browse_ep.get("browseId")

        if vid and (not pl_id or is_16_9 or "listen" in shelf_title.lower() or "favorite" in shelf_title.lower() or "video" in shelf_title.lower()):
            item_res = {
                "id": f"yt_{vid}",
                "type": "video" if is_16_9 else "track",
                "title": title,
                "name": title,
                "artist": artist_name or "YouTube Music",
                "subtitle": f"{artist_name} • {views}" if (artist_name and views) else (artist_name or "YouTube Music"),
                "views": views,
                "source": "YouTube Music",
                "path": f"ytdl://{vid}",
                "videoId": vid,
                "duration": "--:--",
                "durationMs": 0,
                "image": thumb_url,
                "aspectRatio": "16:9" if is_16_9 else "1:1",
                "isVideo": is_16_9
            }
            if channel_id:
                item_res["channelId"] = channel_id
            return item_res
        elif pl_id and title:
            is_album = str(pl_id).startswith("MPREb_") or any(w in sub.lower() for w in ["album", "ep", "single"]) or "album" in shelf_title.lower()
            creator = artist_name or ""
            not_community_shelf = any(w in shelf_title.lower() for w in ["mixed for you", "dành riêng", "nghe lại", "listen again", "quick", "album", "mới phát hành", "release", "radio", "for you", "cho bạn"])
            is_community = not not_community_shelf and (("community" in shelf_title.lower()) or ("cộng đồng" in shelf_title.lower()) or (bool(views) and not is_album))
            if is_community and creator and not any(w in creator.lower() for w in ["youtube music", "supermix"]):
                creator_initial = creator.strip()[:1].upper()
                creator_color = get_creator_color(creator)
            else:
                creator_initial = ""
                creator_color = ""
            return {
                "id": pl_id,
                "type": "album" if is_album else "playlist",
                "playlistId": pl_id,
                "title": title,
                "subtitle": (f"Album • {artist_name}" if artist_name else "Album") if is_album else (f"Playlist • {creator}" + (f" • {views}" if views else "") if creator else "Playlist"),
                "creator": creator,
                "creatorInitial": creator_initial,
                "creatorColor": creator_color,
                "views": views,
                "image": thumb_url,
                "aspectRatio": "1:1",
                "isVideo": False
            }

    # 3. Parsed item (from parse_mixed_content)
    elif isinstance(it, dict):
        vid = it.get("videoId")
        pl_id = it.get("playlistId") or it.get("browseId") or it.get("audioPlaylistId")
        title = it.get("title", "")
        r_aspect = str(it.get("aspectRatio", ""))
        is_16_9 = ("16_9" in r_aspect) or ("RECTANGLE" in r_aspect)
        if not is_16_9 and any(k in shelf_title.lower() for k in ["video", "listen again", "nghe lại", "forgotten", "giai điệu", "cùng nghe", "together"]):
            is_16_9 = True

        thumbs = it.get("thumbnails", [])
        raw_thumb = thumbs[-1].get("url", "") if thumbs else ""
        thumb_url = clean_thumbnail_url(raw_thumb, vid, is_16_9=is_16_9)

        artist = ""
        channel_id = ""
        views = ""
        desc = it.get("description") or ""
        if desc:
            parts = [p.strip() for p in desc.split("•")]
            for p in parts:
                if any(w in p.lower() for w in ["views", "plays", "lượt xem", "lượt phát"]):
                    views = p
                elif not artist and not any(w in p.lower() for w in ["playlist", "album", "ep", "single"]):
                    artist = p

        if it.get("artists"):
            artist = ", ".join(a.get("name", "") for a in it.get("artists", []) if isinstance(a, dict))
            for a in it.get("artists", []):
                if isinstance(a, dict) and a.get("id"):
                    channel_id = a.get("id")
                    break
        elif not artist and desc:
            artist = desc
        artist = clean_artist_name(artist)

        if vid and (not pl_id or is_16_9 or "song" in str(it.get("videoType", "")).lower() or "atv" in str(it.get("videoType", "")).lower() or "listen" in shelf_title.lower() or "quick" in shelf_title.lower() or "cover" in shelf_title.lower() or "video" in shelf_title.lower() or "trending" in shelf_title.lower() or "favorite" in shelf_title.lower() or "long" in shelf_title.lower()):
            item_res = {
                "id": f"yt_{vid}",
                "type": "video" if is_16_9 else "track",
                "title": title,
                "name": title,
                "artist": artist or "YouTube Music",
                "subtitle": f"{artist} • {views}" if (artist and views) else (artist or "YouTube Music"),
                "views": views,
                "source": "YouTube Music",
                "path": f"ytdl://{vid}",
                "videoId": vid,
                "duration": it.get("duration", "--:--"),
                "durationMs": (it.get("duration_seconds") or 0) * 1000,
                "image": thumb_url,
                "aspectRatio": "16:9" if is_16_9 else "1:1",
                "isVideo": is_16_9
            }
            if channel_id:
                item_res["channelId"] = channel_id
            return item_res
        elif pl_id and title:
            is_album = str(it.get("type", "")).lower() == "album" or str(pl_id).startswith("MPREb_") or "album" in desc.lower() or "album" in shelf_title.lower()
            creator = artist or ""
            not_community_shelf = any(w in shelf_title.lower() for w in ["mixed for you", "dành riêng", "nghe lại", "listen again", "quick", "album", "mới phát hành", "release", "radio", "for you", "cho bạn"])
            is_community = not not_community_shelf and (("community" in shelf_title.lower()) or ("cộng đồng" in shelf_title.lower()) or (bool(views) and not is_album))
            if is_community and creator and not any(w in creator.lower() for w in ["youtube music", "supermix"]):
                creator_initial = creator.strip()[:1].upper()
                creator_color = get_creator_color(creator)
            else:
                creator_initial = ""
                creator_color = ""
            return {
                "id": pl_id,
                "type": "album" if is_album else "playlist",
                "playlistId": pl_id,
                "title": title,
                "subtitle": (f"Album • {artist}" if artist else "Album") if is_album else (f"Playlist • {creator}" + (f" • {views}" if views else "") if creator else "Playlist"),
                "creator": creator,
                "creatorInitial": creator_initial,
                "creatorColor": creator_color,
                "views": views,
                "image": thumb_url,
                "aspectRatio": "1:1",
                "isVideo": False
            }
    return None

def get_personalized_home():
    cached = load_json(HOME_CACHE_FILE, None)
    if cached and (time.time() - cached.get("timestamp", 0)) < 1800:
        sections = cached.get("sections", [])
        has_legacy = any(s.get("type") == "card_carousel" for s in sections)
        if not has_legacy and sections and len(sections) > 0 and (cached.get("quick_picks") or cached.get("featured_playlists")):
            return cached

    yt = get_ytmusic_client()
    quick_picks = []
    featured_playlists = []
    dynamic_moods = []
    shelves = []
    final_sections = []
    all_tracks_discovered = []
    home_res = None

    try:
        home_res = yt._send_request("browse", {"browseId": "FEmusic_home"})
    except Exception as e:
        sys.stderr.write(f"[personalized home auth browse error]: {e}\n")
        # Automatic fallback: try guest client if user account/cookies failed
        try:
            from ytmusicapi import YTMusic
            guest_session = create_resilient_session()
            guest_yt = YTMusic(requests_session=guest_session)
            home_res = guest_yt._send_request("browse", {"browseId": "FEmusic_home"})
            yt = guest_yt
            sys.stderr.write("[personalized home] Recovered using guest browse!\n")
        except Exception as e2:
            sys.stderr.write(f"[personalized home guest browse error]: {e2}\n")

    if home_res and isinstance(home_res, dict):
        # 1. Extract dynamic mood chips directly from user's account home
        try:
            from ytmusicapi.navigation import nav, SINGLE_COLUMN_TAB
            chip_cloud = nav(home_res, [*SINGLE_COLUMN_TAB, "sectionListRenderer", "header", "chipCloudRenderer", "chips"], True)
            if chip_cloud:
                for c in chip_cloud:
                    chip = c.get("chipCloudChipRenderer", {})
                    chip_title = "".join(r.get("text", "") for r in chip.get("text", {}).get("runs", []))
                    chip_params = chip.get("navigationEndpoint", {}).get("browseEndpoint", {}).get("params", "")
                    if chip_title and chip_params:
                        dynamic_moods.append({"title": chip_title, "params": chip_params})
        except Exception as e:
            sys.stderr.write(f"[chip extract error]: {e}\n")

        # 2. Extract initial sections
        raw_sections = home_res.get("contents", {}).get("singleColumnBrowseResultsRenderer", {}).get("tabs", [{}])[0].get("tabRenderer", {}).get("content", {}).get("sectionListRenderer", {}).get("contents", [])
        for s in raw_sections:
            shelf = s.get("musicCarouselShelfRenderer") or s.get("musicShelfRenderer")
            if shelf:
                header = shelf.get("header", {}).get("musicCarouselShelfBasicHeaderRenderer", {})
                t = "".join(r.get("text", "") for r in header.get("title", {}).get("runs", []))
                sub = "".join(r.get("text", "") for r in header.get("strapline", {}).get("runs", []))
                shelves.append((t, sub, shelf.get("contents", [])))

        # 3. Extract continuation sections (up to 12 continuation shelves)
        try:
            from ytmusicapi.navigation import nav, SINGLE_COLUMN_TAB
            from ytmusicapi.continuations import get_continuations
            from ytmusicapi.parsers.browsing import parse_mixed_content

            section_list = nav(home_res, [*SINGLE_COLUMN_TAB, "sectionListRenderer"], True)
            if section_list and "continuations" in section_list:
                request_func = lambda additionalParams: yt._send_request("browse", {"browseId": "FEmusic_home"}, additionalParams)
                conts = get_continuations(section_list, "sectionListContinuation", 4, request_func, parse_mixed_content)
                for c in conts:
                    shelves.append((c.get("title", ""), "", c.get("contents", [])))
        except Exception as e:
            sys.stderr.write(f"[home continuations error]: {e}\n")

        for title, subtitle, items in shelves:
            if not title or not items or (len(items) <= 1 and "together" in title.lower()):
                continue
            norm_items = []
            track_count = 0
            for it in items:
                norm = _normalize_shelf_item(it, title)
                if norm:
                    norm_items.append(norm)
                    if norm.get("type") == "track":
                        track_count += 1
                        if not any(q.get("videoId") == norm.get("videoId") for q in quick_picks) and len(quick_picks) < 24:
                            quick_picks.append(norm)
                        if not any(q.get("videoId") == norm.get("videoId") for q in all_tracks_discovered):
                            all_tracks_discovered.append(norm)
                    elif norm.get("type") == "playlist":
                        if not any(p.get("id") == norm.get("id") or p.get("title") == norm.get("title") for p in featured_playlists):
                            featured_playlists.append(norm)

            if not norm_items:
                continue

            final_sections.append({
                "title": title,
                "subtitle": subtitle,
                "type": classify_section(title, norm_items),
                "items": norm_items
            })

    # Robust multi-tier fallback: Ensure sections and quick picks are never empty
    if not final_sections or not quick_picks:
        sys.stderr.write("[personalized home] Running robust trending fallback...\n")
        try:
            trending_tracks = search_ytmusic("Trending Music", limit=20)
            if trending_tracks:
                if not any(s.get("title") == "Trending" for s in final_sections):
                    final_sections.append({
                        "title": "Trending",
                        "subtitle": "POPULAR NOW",
                        "type": "track_grid",
                        "items": trending_tracks
                    })
                if not quick_picks:
                    quick_picks = trending_tracks[:12]
        except Exception as te:
            sys.stderr.write(f"[trending fallback error]: {te}\n")

    if not featured_playlists:
        try:
            top_playlists = search_ytmusic("Top Hits", limit=10)
            if top_playlists:
                if not any(s.get("title") == "Top Hits" for s in final_sections):
                    final_sections.append({
                        "title": "Top Hits",
                        "subtitle": "FEATURED PLAYLISTS",
                        "type": "album_carousel",
                        "items": top_playlists
                    })
                featured_playlists = top_playlists
        except Exception:
            pass

    mood_pills = [{"title": "All", "params": ""}] + (dynamic_moods if dynamic_moods else DEFAULT_MOOD_PILLS[1:])
    save_json(MOOD_CATS_FILE, {"timestamp": time.time(), "categories": mood_pills})

    # Fallback for quick picks if empty
    if not quick_picks:
        seed_vid = get_recent_seed_track()
        try:
            radio = yt.get_watch_playlist(seed_vid, limit=16)
            for t in radio.get("tracks", [])[:12]:
                norm = normalize_track(t)
                if norm:
                    quick_picks.append(norm)
        except Exception:
            pass

    if not quick_picks:
        quick_picks = search_ytmusic("Trending Music", limit=12)

    cache_online_tracks(quick_picks)
    if all_tracks_discovered:
        cache_online_tracks(all_tracks_discovered)

    # Load top cached moods from ~/.cache/nutsty/moods/ into preloaded_moods (capped to 2 to prevent IPC buffer choke)
    preloaded = {}
    if os.path.exists(MOOD_CACHE_DIR):
        p_count = 0
        for f in sorted(os.listdir(MOOD_CACHE_DIR)):
            if f.endswith(".json") and p_count < 2:
                m_data = load_json(os.path.join(MOOD_CACHE_DIR, f))
                if m_data and m_data.get("sections") and (m_data.get("quick_picks") or m_data.get("featured_playlists")):
                    m_title = f.split("_")[0]
                    preloaded[m_title] = m_data
                    p_count += 1

    res = {
        "timestamp": time.time(),
        "moods": mood_pills,
        "sections": final_sections,
        "quick_picks": quick_picks[:20],
        "featured_playlists": featured_playlists[:50],
        "preloaded_moods": preloaded
    }
    if final_sections or quick_picks:
        save_json(HOME_CACHE_FILE, res)

    # Pre-warm top moods in background thread for 0ms disk cache hits
    def _prewarm():
        for pill in mood_pills[1:6]:
            p = pill.get("params")
            t = pill.get("title")
            if p and t != "All":
                try:
                    get_mood_feed(p, t)
                except Exception:
                    pass

    import threading
    threading.Thread(target=_prewarm, daemon=True).start()

    return res

def get_radio(video_id, limit=30):
    if video_id.startswith("ytdl://"):
        video_id = video_id.replace("ytdl://", "")

    yt = get_ytmusic_client()
    try:
        radio = yt.get_watch_playlist(video_id, limit=limit)
        raw_tracks = radio.get("tracks", [])
        tracks = []
        for t in raw_tracks:
            norm = normalize_track(t)
            if norm:
                tracks.append(norm)
        cache_online_tracks(tracks)
        return tracks
    except Exception as e:
        sys.stderr.write(f"[get_radio error for {video_id}]: {e}\n")
        return []

def _parse_duration_seconds(dur_str):
    if not dur_str or dur_str == "--:--":
        return 0
    parts = dur_str.split(":")
    try:
        if len(parts) == 2:
            return int(parts[0]) * 60 + int(parts[1])
        elif len(parts) == 3:
            return int(parts[0]) * 3600 + int(parts[1]) * 60 + int(parts[2])
    except Exception:
        return 0
    return 0

def _safe_parse_watch_playlist(contents):
    """Safely parse watch playlist contents with ytmusicapi or inline fallback."""
    try:
        from ytmusicapi.parsers.watch import parse_watch_playlist
        parsed = parse_watch_playlist(contents)
        if parsed:
            return parsed
    except Exception:
        pass

    tracks = []
    for item in contents:
        data = None
        if "playlistPanelVideoWrapperRenderer" in item:
            data = item["playlistPanelVideoWrapperRenderer"].get("primaryRenderer", {}).get("playlistPanelVideoRenderer")
        elif "playlistPanelVideoRenderer" in item:
            data = item["playlistPanelVideoRenderer"]
        if not data or "unplayableText" in data:
            continue

        vid = data.get("videoId", "")
        title_runs = data.get("title", {}).get("runs", [])
        title = "".join(r.get("text", "") for r in title_runs).strip()
        length = data.get("lengthText", {}).get("runs", [{}])[0].get("text", "")
        thumbs = data.get("thumbnail", {}).get("thumbnails", [])
        thumb = thumbs[-1].get("url", "") if thumbs else ""

        artist = ""
        byline_runs = data.get("longBylineText", {}).get("runs", []) or data.get("shortBylineText", {}).get("runs", [])
        if byline_runs:
            artist = "".join(r.get("text", "") for r in byline_runs).strip()

        if vid and title:
            tracks.append({
                "videoId": vid,
                "title": title,
                "name": title,
                "length": length,
                "duration": length,
                "thumbnail": thumb,
                "thumbnails": thumbs,
                "artist": artist,
                "artists": [{"name": artist}] if artist else []
            })
    return tracks

def get_watch_playlist_chips(video_id):
    if video_id.startswith("ytdl://"):
        video_id = video_id.replace("ytdl://", "")

    clients = [get_ytmusic_client()]
    try:
        from ytmusicapi import YTMusic
        clients.append(YTMusic(requests_session=create_resilient_session()))
    except Exception:
        pass

    for yt in clients:
        try:
            res = yt._send_request('next', {'videoId': video_id, 'playlistId': f'RDAMVM{video_id}'})
            tabs = res.get('contents', {}).get('singleColumnMusicWatchNextResultsRenderer', {}).get('tabbedRenderer', {}).get('watchNextTabbedResultsRenderer', {}).get('tabs', [])
            if not tabs:
                continue
            queue = tabs[0].get('tabRenderer', {}).get('content', {}).get('musicQueueRenderer', {})
            chips_raw = queue.get('subHeaderChipCloud', {}).get('chipCloudRenderer', {}).get('chips', [])

            chips = []
            for c in chips_raw:
                cr = c.get('chipCloudChipRenderer', {})
                title = ''.join(r.get('text', '') for r in cr.get('text', {}).get('runs', [])).strip()
                ep = cr.get('navigationEndpoint', {}).get('queueUpdateCommand', {}).get('fetchContentsCommand', {}).get('watchEndpoint', {})
                playlist_id = ep.get('playlistId', '')
                params = ep.get('params', '')
                is_selected = cr.get('isSelected', False)
                if title:
                    chips.append({
                        "title": title,
                        "playlistId": playlist_id,
                        "params": params,
                        "selected": is_selected
                    })
            if chips:
                return chips
        except Exception as e:
            sys.stderr.write(f"[get_watch_playlist_chips error for {video_id}]: {e}\n")
            continue
    return []

def get_filtered_radio_queue(video_id, playlist_id, params=None):
    if video_id.startswith("ytdl://"):
        video_id = video_id.replace("ytdl://", "")

    clients = [get_ytmusic_client()]
    try:
        from ytmusicapi import YTMusic
        clients.append(YTMusic(requests_session=create_resilient_session()))
    except Exception:
        pass

    for yt in clients:
        try:
            body = {'videoId': video_id, 'playlistId': playlist_id}
            if params:
                body['params'] = params
            res = yt._send_request('next', body)
            tabs = res.get('contents', {}).get('singleColumnMusicWatchNextResultsRenderer', {}).get('tabbedRenderer', {}).get('watchNextTabbedResultsRenderer', {}).get('tabs', [])
            if not tabs:
                continue
            queue = tabs[0].get('tabRenderer', {}).get('content', {}).get('musicQueueRenderer', {})
            contents = queue.get('content', {}).get('playlistPanelRenderer', {}).get('contents', [])
            parsed = _safe_parse_watch_playlist(contents)
            if not parsed:
                continue

            tracks = []
            for p in parsed:
                if "length" in p and "duration" not in p:
                    p["duration"] = p["length"]
                if "thumbnail" in p and "thumbnails" not in p:
                    p["thumbnails"] = p["thumbnail"]
                norm = normalize_track(p)
                if norm:
                    if (not norm.get("durationMs") or norm.get("durationMs") == 0) and norm.get("duration") and norm.get("duration") != "--:--":
                        norm["durationMs"] = _parse_duration_seconds(norm["duration"]) * 1000
                    tracks.append(norm)
            if tracks:
                cache_online_tracks(tracks)
                return tracks
        except Exception as e:
            sys.stderr.write(f"[get_filtered_radio_queue error for {video_id}, {playlist_id}]: {e}\n")
            continue
    return []


def _process_mood_items(items, shelf_title, quick_picks, featured_playlists, max_qp=30, max_fp=60):
    for it in items:
        if not isinstance(it, dict):
            continue
        if "musicResponsiveListItemRenderer" in it:
            r = it["musicResponsiveListItemRenderer"]
            vid = r.get("playlistItemData", {}).get("videoId")
            cols = r.get("flexColumns", [])
            title_text = "".join(x.get("text", "") for x in cols[0].get("musicResponsiveListItemFlexColumnRenderer", {}).get("text", {}).get("runs", [])) if cols else ""
            artist = ""
            channel_id = ""
            if len(cols) > 1:
                artist_runs = cols[1].get("musicResponsiveListItemFlexColumnRenderer", {}).get("text", {}).get("runs", [])
                for x in artist_runs:
                    txt = x.get("text", "").strip()
                    if not txt or txt == "•" or "views" in txt.lower() or "plays" in txt.lower() or "lượt xem" in txt.lower():
                        continue
                    if not artist:
                        artist = txt
                        ep = x.get("navigationEndpoint", {}).get("browseEndpoint", {})
                        if ep and ep.get("browseId"):
                            channel_id = ep.get("browseId")
                if not artist:
                    artist = "".join(x.get("text", "") for x in artist_runs if "views" not in x.get("text", "").lower() and "plays" not in x.get("text", "").lower()).strip(" • ")
            artist = clean_artist_name(artist)
            thumbs = r.get("thumbnail", {}).get("musicThumbnailRenderer", {}).get("thumbnail", {}).get("thumbnails", [])
            thumb_url = thumbs[-1].get("url", "") if thumbs else (f"https://i.ytimg.com/vi/{vid}/hqdefault.jpg" if vid else "")
            if "w60" in thumb_url or "w120" in thumb_url or "w226" in thumb_url:
                thumb_url = re.sub(r'=w\d+-h\d+.*', '=w1200-h1200-l90-rj', thumb_url)
            if vid and title_text and len(quick_picks) < max_qp:
                if not any(q.get("videoId") == vid for q in quick_picks):
                    qp_item = {
                        "id": f"yt_{vid}",
                        "title": title_text,
                        "name": title_text,
                        "artist": artist or "YouTube Music",
                        "source": "YouTube Music",
                        "path": f"ytdl://{vid}",
                        "videoId": vid,
                        "duration": "--:--",
                        "durationMs": 0,
                        "image": thumb_url
                    }
                    if channel_id:
                        qp_item["channelId"] = channel_id
                    quick_picks.append(qp_item)
        elif "musicTwoRowItemRenderer" in it:
            r = it["musicTwoRowItemRenderer"]
            t_text = "".join(x.get("text", "") for x in r.get("title", {}).get("runs", []))
            sub = "".join(x.get("text", "") for x in r.get("subtitle", {}).get("runs", []))
            sub_runs = r.get("subtitle", {}).get("runs", [])
            artist_name = ""
            channel_id = ""
            for x in sub_runs:
                txt = x.get("text", "").strip()
                if not txt or txt == "•" or "views" in txt.lower() or "plays" in txt.lower() or "lượt xem" in txt.lower():
                    continue
                if not artist_name:
                    artist_name = txt
                    ep = x.get("navigationEndpoint", {}).get("browseEndpoint", {})
                    if ep and ep.get("browseId"):
                        channel_id = ep.get("browseId")
            if not artist_name:
                artist_name = clean_artist_name(sub)

            thumbs = r.get("thumbnailRenderer", {}).get("musicThumbnailRenderer", {}).get("thumbnail", {}).get("thumbnails", [])
            thumb_url = thumbs[-1].get("url", "") if thumbs else ""
            if "w120" in thumb_url or "w226" in thumb_url:
                thumb_url = re.sub(r'=w\d+-h\d+.*', '=w1200-h1200-l90-rj', thumb_url)

            nav_ep = r.get("navigationEndpoint", {})
            watch_ep = nav_ep.get("watchEndpoint", {})
            browse_ep = nav_ep.get("browseEndpoint", {})

            vid = watch_ep.get("videoId")
            pl_id = watch_ep.get("playlistId") or browse_ep.get("browseId")

            if vid and (not pl_id or "listen again" in shelf_title.lower()):
                if len(quick_picks) < max_qp and not any(q.get("videoId") == vid for q in quick_picks):
                    qp_item = {
                        "id": f"yt_{vid}",
                        "title": t_text,
                        "name": t_text,
                        "artist": artist_name or "YouTube Music",
                        "source": "YouTube Music",
                        "path": f"ytdl://{vid}",
                        "videoId": vid,
                        "duration": "--:--",
                        "durationMs": 0,
                        "image": thumb_url
                    }
                    if channel_id:
                        qp_item["channelId"] = channel_id
                    quick_picks.append(qp_item)
            elif pl_id and t_text and thumb_url:
                if len(featured_playlists) < max_fp and not any(p.get("title") == t_text for p in featured_playlists):
                    featured_playlists.append({
                        "id": pl_id,
                        "playlistId": pl_id,
                        "title": t_text,
                        "subtitle": sub or shelf_title or "Playlist",
                        "image": thumb_url
                    })
        elif isinstance(it, dict) and (it.get("playlistId") or it.get("browseId")):
            pl_id = it.get("playlistId") or it.get("browseId")
            t_text = it.get("title", "")
            thumbs = it.get("thumbnails", [])
            thumb_url = thumbs[-1].get("url", "") if thumbs else ""
            if "w120" in thumb_url or "w226" in thumb_url:
                thumb_url = re.sub(r'=w\d+-h\d+.*', '=w1200-h1200-l90-rj', thumb_url)
            if pl_id and t_text and thumb_url:
                if len(featured_playlists) < max_fp and not any(p.get("title") == t_text for p in featured_playlists):
                    featured_playlists.append({
                        "id": pl_id,
                        "playlistId": pl_id,
                        "title": t_text,
                        "subtitle": it.get("description") or shelf_title or "Playlist",
                        "image": thumb_url
                    })
        elif isinstance(it, dict) and it.get("videoId"):
            vid = it.get("videoId")
            t_text = it.get("title", "")
            artist = ", ".join(a.get("name", "") for a in it.get("artists", [])) if it.get("artists") else ""
            thumbs = it.get("thumbnails", [])
            thumb_url = thumbs[-1].get("url", "") if thumbs else (f"https://i.ytimg.com/vi/{vid}/hqdefault.jpg" if vid else "")
            if "w60" in thumb_url or "w120" in thumb_url or "w226" in thumb_url:
                thumb_url = re.sub(r'=w\d+-h\d+.*', '=w1200-h1200-l90-rj', thumb_url)
            if vid and t_text and len(quick_picks) < max_qp:
                if not any(q.get("videoId") == vid for q in quick_picks):
                    quick_picks.append({
                        "id": f"yt_{vid}",
                        "title": t_text,
                        "name": t_text,
                        "artist": artist or shelf_title or "YouTube Music",
                        "source": "YouTube Music",
                        "path": f"ytdl://{vid}",
                        "videoId": vid,
                        "duration": "--:--",
                        "durationMs": 0,
                        "image": thumb_url
                    })

def get_mood_feed(params, title=""):
    if (not params or params == "") and title and title != "All":
        cats = get_mood_categories_live()
        for c in cats:
            if c.get("title", "").lower() == title.lower():
                params = c.get("params", "")
                break

    if not params or title == "All":
        return get_personalized_home()

    os.makedirs(MOOD_CACHE_DIR, exist_ok=True)
    slug = re.sub(r'[^a-zA-Z0-9_-]', '_', f"{title}_{params[:16]}" if params else title)
    cache_path = os.path.join(MOOD_CACHE_DIR, f"{slug}.json")

    # Instant cache return (valid for 3 hours)
    cached = load_json(cache_path, None)
    if cached and (time.time() - cached.get("timestamp", 0)) < 10800:
        if cached.get("sections") and (cached.get("quick_picks") or cached.get("featured_playlists")):
            return cached

    yt = get_ytmusic_client()
    quick_picks = []
    featured_playlists = []
    final_sections = []

    try:
        # Native personalized mood browse via FEmusic_home with params
        endpoint = "browse"
        body = {"browseId": "FEmusic_home", "params": params}
        res = yt._send_request(endpoint, body)

        shelves = []
        raw_sections = res.get("contents", {}).get("singleColumnBrowseResultsRenderer", {}).get("tabs", [{}])[0].get("tabRenderer", {}).get("content", {}).get("sectionListRenderer", {}).get("contents", [])
        for s in raw_sections:
            shelf = s.get("musicCarouselShelfRenderer") or s.get("musicShelfRenderer")
            if not shelf:
                continue
            header = shelf.get("header", {}).get("musicCarouselShelfBasicHeaderRenderer", {})
            t = "".join(r.get("text", "") for r in header.get("title", {}).get("runs", []))
            sub = "".join(r.get("text", "") for r in header.get("strapline", {}).get("runs", []))
            shelves.append((t, sub, shelf.get("contents", [])))

        # 2. Process continuation sections (Continuation scraper for 50+ playlists)
        from ytmusicapi.navigation import nav, SINGLE_COLUMN_TAB
        from ytmusicapi.parsers.browsing import parse_mixed_content
        from ytmusicapi.continuations import get_continuations

        section_list = nav(res, [*SINGLE_COLUMN_TAB, "sectionListRenderer"], True)
        if section_list and "continuations" in section_list:
            try:
                request_func = lambda additionalParams: yt._send_request(endpoint, body, additionalParams)
                conts = get_continuations(section_list, "sectionListContinuation", 10, request_func, parse_mixed_content)
                for c_sec in conts:
                    shelves.append((c_sec.get("title", ""), "", c_sec.get("contents", [])))
            except Exception as e:
                sys.stderr.write(f"[continuations error for {title}]: {e}\n")

        all_tracks_discovered = []
        for s_title, s_sub, s_items in shelves:
            if not s_title or not s_items or (len(s_items) <= 1 and "together" in s_title.lower()):
                continue
            norm_items = []
            track_count = 0
            for it in s_items:
                norm = _normalize_shelf_item(it, s_title)
                if norm:
                    norm_items.append(norm)
                    if norm.get("type") == "track":
                        track_count += 1
                        if not any(q.get("videoId") == norm.get("videoId") for q in quick_picks) and len(quick_picks) < 30:
                            quick_picks.append(norm)
                        if not any(q.get("videoId") == norm.get("videoId") for q in all_tracks_discovered):
                            all_tracks_discovered.append(norm)
                    elif norm.get("type") == "playlist":
                        if not any(p.get("id") == norm.get("id") or p.get("title") == norm.get("title") for p in featured_playlists):
                            featured_playlists.append(norm)

            if not norm_items:
                continue

            final_sections.append({
                "title": s_title,
                "subtitle": s_sub,
                "type": classify_section(s_title, norm_items),
                "items": norm_items
            })

    except Exception as e:
        sys.stderr.write(f"[personalized mood browse error for {title}]: {e}\n")

    # If featured_playlists has fewer than 6, supplement from official mood playlists
    if len(featured_playlists) < 6 and params:
        try:
            raw_playlists = yt.get_mood_playlists(params)
            for item in raw_playlists[:12]:
                pl_id = item.get("playlistId")
                pl_title = item.get("title", "")
                thumbs = item.get("thumbnails", [])
                thumb_url = thumbs[-1].get("url", "") if thumbs else ""
                if "w120" in thumb_url or "w226" in thumb_url:
                    thumb_url = re.sub(r'=w\d+-h\d+.*', '=w1200-h1200-l90-rj', thumb_url)
                if pl_id and pl_title and not any(p.get("title") == pl_title for p in featured_playlists):
                    featured_playlists.append({
                        "id": pl_id,
                        "playlistId": pl_id,
                        "title": pl_title,
                        "subtitle": item.get("description") or "Playlist",
                        "image": thumb_url
                    })
        except Exception as e:
            sys.stderr.write(f"[mood playlist fallback error for {title}]: {e}\n")

    # If quick_picks is empty, extract from top playlist
    if not quick_picks and featured_playlists:
        for pl in featured_playlists[:2]:
            try:
                top_tracks = get_playlist_tracks(pl["playlistId"], limit=12)
                if top_tracks:
                    quick_picks = top_tracks
                    break
            except Exception:
                pass

    cache_online_tracks(quick_picks)
    if 'all_tracks_discovered' in locals() and all_tracks_discovered:
        cache_online_tracks(all_tracks_discovered)

    result = {
        "timestamp": time.time(),
        "title": title,
        "sections": final_sections,
        "quick_picks": quick_picks[:30],
        "featured_playlists": featured_playlists[:60]
    }
    save_json(cache_path, result)
    return result

def get_album_details(browse_id):
    if not browse_id:
        return {"metadata": {}, "tracks": []}
    clean_id = browse_id
    if clean_id.startswith("VL"):
        clean_id = clean_id[2:]

    yt = get_ytmusic_client()
    try:
        alb = yt.get_album(clean_id)
        if not alb:
            return {"metadata": {}, "tracks": []}

        thumbs = alb.get("thumbnails", [])
        alb_thumb = thumbs[-1].get("url", "") if thumbs else ""
        if "w60" in alb_thumb or "w120" in alb_thumb or "w226" in alb_thumb:
            alb_thumb = re.sub(r'=w\d+-h\d+.*', '=w1200-h1200-l90-rj', alb_thumb)

        artists = alb.get("artists", [])
        artist_name = ", ".join(a.get("name", "") for a in artists if isinstance(a, dict)) if artists else "Unknown Artist"
        if not artist_name:
            artist_name = "Unknown Artist"

        tracks = []
        raw_tracks = alb.get("tracks", [])
        for t in raw_tracks:
            if not t.get("thumbnails") and alb_thumb:
                t["thumbnails"] = [{"url": alb_thumb}]
            norm = normalize_track(t)
            if norm:
                if not norm.get("album"):
                    norm["album"] = alb.get("title", "")
                tracks.append(norm)

        if tracks:
            cache_online_tracks(tracks)

        meta = {
            "id": clean_id,
            "browseId": clean_id,
            "title": alb.get("title", "Album"),
            "name": alb.get("title", "Album"),
            "artist": artist_name,
            "year": str(alb.get("year", "") or ""),
            "type": alb.get("type", "Album"),
            "trackCount": alb.get("trackCount", len(tracks)),
            "duration": alb.get("duration", ""),
            "image": alb_thumb,
            "description": alb.get("description", "")
        }
        return {
            "metadata": meta,
            "tracks": tracks
        }
    except Exception as e:
        sys.stderr.write(f"[get_album_details error for {clean_id}]: {e}\n")
        return {"metadata": {}, "tracks": []}

def get_artist(channel_id_or_name):
    if not channel_id_or_name:
        return {"metadata": {}, "popular": [], "singles": [], "albums": [], "videos": [], "related": []}
    
    clean_id = str(channel_id_or_name).strip()
    yt = get_ytmusic_client()
    
    browse_id = clean_id
    if not (clean_id.startswith("UC") or clean_id.startswith("FEmusic_library_privately_owned_artist_detail")):
        search_query = clean_artist_name(clean_id)
        try:
            search_res = yt.search(search_query, filter="artists")
            if search_res and len(search_res) > 0:
                browse_id = search_res[0].get("browseId", "")
            else:
                # Fallback: search without filter and locate first artist browseId
                gen_res = yt.search(search_query)
                for it in gen_res:
                    if it.get("resultType") == "artist" and it.get("browseId"):
                        browse_id = it.get("browseId")
                        break
                    for a in it.get("artists", []):
                        if isinstance(a, dict) and a.get("id"):
                            browse_id = a.get("id")
                            break
                    if browse_id:
                        break
        except Exception as e:
            sys.stderr.write(f"[get_artist search error for {clean_id}]: {e}\n")
            
    if not browse_id:
        return {"metadata": {"name": clean_artist_name(clean_id), "title": clean_artist_name(clean_id)}, "popular": [], "singles": [], "albums": [], "videos": [], "related": []}

    try:
        art = yt.get_artist(browse_id)
        if not art:
            return {"metadata": {"name": clean_id, "title": clean_id}, "popular": [], "singles": [], "albums": [], "videos": [], "related": []}
            
        thumbs = art.get("thumbnails", [])
        art_thumb = thumbs[-1].get("url", "") if thumbs else ""
        if "w60" in art_thumb or "w120" in art_thumb or "w226" in art_thumb:
            art_thumb = re.sub(r'=w\d+-h\d+.*', '=w1200-h1200-l90-rj', art_thumb)
        elif "s60" in art_thumb or "s120" in art_thumb or "s226" in art_thumb:
            art_thumb = re.sub(r'=s\d+.*', '=s960-c-k-c0x00ffffff-no-rj', art_thumb)
            
        artist_name = art.get("name", clean_id)
        if artist_name and art_thumb:
            cache_artist_avatar(artist_name, art_thumb)
            
        popular_tracks = []
        raw_songs = art.get("songs", {}).get("results", [])
        for t in raw_songs:
            if not t.get("thumbnails") and art_thumb:
                t["thumbnails"] = [{"url": art_thumb}]
            norm = normalize_track(t)
            if norm:
                if not norm.get("artist"):
                    norm["artist"] = artist_name
                popular_tracks.append(norm)
                
        if popular_tracks:
            cache_online_tracks(popular_tracks)
            
        singles_list = []
        raw_singles = art.get("singles", {}).get("results", [])
        for s in raw_singles:
            s_thumbs = s.get("thumbnails", [])
            s_thumb = s_thumbs[-1].get("url", "") if s_thumbs else ""
            if "w60" in s_thumb or "w120" in s_thumb or "w226" in s_thumb:
                s_thumb = re.sub(r'=w\d+-h\d+.*', '=w1200-h1200-l90-rj', s_thumb)
            singles_list.append({
                "title": s.get("title", ""),
                "browseId": s.get("browseId", ""),
                "year": str(s.get("year", "") or ""),
                "image": s_thumb,
                "type": "Single"
            })
            
        albums_list = []
        raw_albums = art.get("albums", {}).get("results", [])
        for a in raw_albums:
            a_thumbs = a.get("thumbnails", [])
            a_thumb = a_thumbs[-1].get("url", "") if a_thumbs else ""
            if "w60" in a_thumb or "w120" in a_thumb or "w226" in a_thumb:
                a_thumb = re.sub(r'=w\d+-h\d+.*', '=w1200-h1200-l90-rj', a_thumb)
            albums_list.append({
                "title": a.get("title", ""),
                "browseId": a.get("browseId", ""),
                "year": str(a.get("year", "") or ""),
                "image": a_thumb,
                "type": "Album"
            })
            
        videos_list = []
        raw_videos = art.get("videos", {}).get("results", [])
        for v in raw_videos:
            v_thumbs = v.get("thumbnails", [])
            v_thumb = v_thumbs[-1].get("url", "") if v_thumbs else ""
            views_str = v.get("views", "") or ""
            videos_list.append({
                "title": v.get("title", ""),
                "videoId": v.get("videoId", ""),
                "views": views_str,
                "image": v_thumb
            })
            
        related_list = []
        raw_related = art.get("related", {}).get("results", [])
        for r in raw_related:
            r_thumbs = r.get("thumbnails", [])
            r_thumb = r_thumbs[-1].get("url", "") if r_thumbs else ""
            if "w60" in r_thumb or "w120" in r_thumb or "w226" in r_thumb:
                r_thumb = re.sub(r'=w\d+-h\d+.*', '=w1200-h1200-l90-rj', r_thumb)
            r_name = r.get("title", "")
            if r_name and r_thumb:
                cache_artist_avatar(r_name, r_thumb)
            related_list.append({
                "name": r_name,
                "title": r_name,
                "browseId": r.get("browseId", ""),
                "subscribers": r.get("subscribers", "") or "",
                "image": r_thumb
            })
            
        meta = {
            "channelId": browse_id,
            "browseId": browse_id,
            "name": artist_name,
            "title": artist_name,
            "subscribers": art.get("subscribers", "") or "",
            "views": art.get("views", "") or "",
            "radioId": art.get("radioId", "") or "",
            "shuffleId": art.get("shuffleId", "") or "",
            "subscribed": bool(art.get("subscribed", False)),
            "image": art_thumb,
            "description": art.get("description", "") or ""
        }
        
        return {
            "metadata": meta,
            "popular": popular_tracks,
            "singles": singles_list,
            "albums": albums_list,
            "videos": videos_list,
            "related": related_list
        }
    except Exception as e:
        sys.stderr.write(f"[get_artist error for {clean_id}]: {e}\n")
        return {"metadata": {"name": clean_id, "title": clean_id}, "popular": [], "singles": [], "albums": [], "videos": [], "related": []}

def subscribe_artist_action(channel_id, subscribe=True):
    clean_id = str(channel_id).strip()
    yt = get_ytmusic_client()
    res = {"channelId": clean_id, "subscribed": subscribe, "status": "ok"}
    try:
        if subscribe:
            if hasattr(yt, "subscribe_artist"):
                yt.subscribe_artist(clean_id)
            else:
                yt.subscribe_artists([clean_id])
        else:
            if hasattr(yt, "unsubscribe_artist"):
                yt.unsubscribe_artist(clean_id)
            else:
                yt.unsubscribe_artists([clean_id])
    except Exception as e:
        sys.stderr.write(f"[subscribe_artist error for {clean_id}]: {e}\n")
        res["error"] = str(e)
        res["status"] = "error"
    return res


def get_playlist_tracks(playlist_id, limit=50):
    if not playlist_id:
        return []
    yt = get_ytmusic_client()
    raw_tracks = []
    tracks = []

    clean_id = playlist_id
    if clean_id.startswith("VL"):
        clean_id = clean_id[2:]

    # Case 1: Album browseId (starts with MPREb_)
    if clean_id.startswith("MPREb_") or playlist_id.startswith("MPREb_"):
        res = get_album_details(clean_id)
        if res and res.get("tracks"):
            return res["tracks"]

    # Case 2: Radio and automix playlists (RD or VLRD)
    if playlist_id.startswith("RD") or playlist_id.startswith("VLRD") or clean_id.startswith("RD"):
        try:
            res = yt.get_watch_playlist(playlistId=playlist_id, limit=limit)
            raw_tracks = res.get("tracks", [])
        except Exception as e:
            try:
                res = yt.get_watch_playlist(playlistId=clean_id, limit=limit)
                raw_tracks = res.get("tracks", [])
            except Exception as e2:
                sys.stderr.write(f"[get_watch_playlist error for {playlist_id}]: {e} | {e2}\n")

    # Case 3: Standard playlist
    if not raw_tracks:
        try:
            pl = yt.get_playlist(playlist_id, limit=limit)
            raw_tracks = pl.get("tracks", [])
        except Exception as e:
            if playlist_id.startswith("VL"):
                try:
                    pl = yt.get_playlist(clean_id, limit=limit)
                    raw_tracks = pl.get("tracks", [])
                except Exception:
                    pass

            if not raw_tracks:
                try:
                    res = yt.get_watch_playlist(playlistId=playlist_id, limit=limit)
                    raw_tracks = res.get("tracks", [])
                except Exception:
                    try:
                        alb = yt.get_album(clean_id)
                        thumbs = alb.get("thumbnails", [])
                        alb_thumb = thumbs[-1].get("url", "") if thumbs else ""
                        for t in alb.get("tracks", []):
                            if not t.get("thumbnails") and alb_thumb:
                                t["thumbnails"] = [{"url": alb_thumb}]
                            norm = normalize_track(t)
                            if norm:
                                tracks.append(norm)
                        if tracks:
                            cache_online_tracks(tracks)
                            return tracks
                    except Exception as e_alb:
                        sys.stderr.write(f"[get_playlist_tracks all fallback error for {playlist_id}]: {e} | {e_alb}\n")

    for t in raw_tracks:
        norm = normalize_track(t)
        if norm:
            tracks.append(norm)
    cache_online_tracks(tracks)
    return tracks

def search_ytmusic(query, limit=20):
    if not query or not query.strip():
        query = "Trending Music"

    try:
        ytm = get_ytmusic_client()
        try:
            raw = ytm.search(query.strip(), filter="songs")
        except Exception as se:
            sys.stderr.write(f"[ytmusic search error, guest fallback]: {se}\n")
            from ytmusicapi import YTMusic
            guest_yt = YTMusic(requests_session=create_resilient_session())
            raw = guest_yt.search(query.strip(), filter="songs")

        tracks = []
        for item in raw[:limit]:
            norm = normalize_track(item)
            if norm:
                tracks.append(norm)
        cache_online_tracks(tracks)
        return tracks
    except Exception as e:
        sys.stderr.write(f"[ytmusic search fatal error]: {e}\n")
        return []

def search_categorized(query):
    if not query or not query.strip():
        query = "Trending"

    q = query.strip()
    try:
        ytm = get_ytmusic_client()
        try:
            raw = ytm.search(q)
        except Exception as se:
            sys.stderr.write(f"[search_categorized auth error, guest fallback]: {se}\n")
            from ytmusicapi import YTMusic
            guest_yt = YTMusic(requests_session=create_resilient_session())
            raw = guest_yt.search(q)
        top_result = None
        songs = []
        albums = []
        artists = []
        playlists = []

        for i, r in enumerate(raw):
            rtype = r.get("resultType")
            cat = r.get("category")
            is_top = (cat == "Top result" or (i == 0 and rtype in ("artist", "album", "song")))

            if is_top and not top_result:
                if rtype == "artist":
                    arts = r.get("artists", [])
                    a_name = r.get("artist") or (arts[0].get("name") if arts else q)
                    a_id = (arts[0].get("id") if arts else "") or r.get("browseId", "")
                    thumbs = r.get("thumbnails", [])
                    turl = thumbs[-1].get("url", "") if thumbs else ""
                    turl = re.sub(r'=w\d+-h\d+.*', '=w1200-h1200-l90-rj', turl)
                    top_result = {
                        "type": "artist",
                        "browseId": a_id,
                        "name": a_name,
                        "artist": a_name,
                        "subscribers": r.get("subscribers", ""),
                        "image": turl
                    }
                elif rtype in ("song", "video"):
                    norm = normalize_track(r)
                    if norm:
                        norm["type"] = "song"
                        top_result = norm
                elif rtype == "album":
                    thumbs = r.get("thumbnails", [])
                    turl = thumbs[-1].get("url", "") if thumbs else ""
                    turl = re.sub(r'=w\d+-h\d+.*', '=w1200-h1200-l90-rj', turl)
                    arts = r.get("artists", [])
                    aname = ", ".join(a.get("name", "") for a in arts if isinstance(a, dict)) if arts else ""
                    bid = r.get("browseId", "")
                    top_result = {
                        "type": "album",
                        "browseId": bid,
                        "playlistId": r.get("playlistId", "") or bid,
                        "title": r.get("title", ""),
                        "name": r.get("title", ""),
                        "artist": aname,
                        "year": str(r.get("year", "") or ""),
                        "image": turl
                    }

            if rtype in ("song", "video"):
                norm = normalize_track(r)
                if norm and not is_song_disliked(norm.get("videoId")):
                    songs.append(norm)
            elif rtype == "album":
                thumbs = r.get("thumbnails", [])
                turl = thumbs[-1].get("url", "") if thumbs else ""
                turl = re.sub(r'=w\d+-h\d+.*', '=w1200-h1200-l90-rj', turl)
                arts = r.get("artists", [])
                aname = ", ".join(a.get("name", "") for a in arts if isinstance(a, dict)) if arts else ""
                bid = r.get("browseId", "")
                albums.append({
                    "type": "album",
                    "browseId": bid,
                    "playlistId": r.get("playlistId", "") or bid,
                    "title": r.get("title", ""),
                    "name": r.get("title", ""),
                    "artist": aname,
                    "year": str(r.get("year", "") or ""),
                    "image": turl
                })
            elif rtype == "artist":
                arts = r.get("artists", [])
                a_name = r.get("artist") or (arts[0].get("name") if arts else "")
                a_id = (arts[0].get("id") if arts else "") or r.get("browseId", "")
                thumbs = r.get("thumbnails", [])
                turl = thumbs[-1].get("url", "") if thumbs else ""
                turl = re.sub(r'=w\d+-h\d+.*', '=w1200-h1200-l90-rj', turl)
                artists.append({
                    "type": "artist",
                    "browseId": a_id,
                    "name": a_name,
                    "artist": a_name,
                    "subscribers": r.get("subscribers", ""),
                    "image": turl
                })
            elif rtype == "playlist":
                thumbs = r.get("thumbnails", [])
                turl = thumbs[-1].get("url", "") if thumbs else ""
                turl = re.sub(r'=w\d+-h\d+.*', '=w1200-h1200-l90-rj', turl)
                bid = r.get("browseId", "")
                author = r.get("author", "") or (r.get("artists", [{}])[0].get("name") if r.get("artists") else "")
                playlists.append({
                    "type": "playlist",
                    "id": bid,
                    "browseId": bid,
                    "title": r.get("title", ""),
                    "name": r.get("title", ""),
                    "author": author,
                    "artist": author,
                    "itemCount": r.get("itemCount", ""),
                    "image": turl
                })

        cache_online_tracks(songs)

        # Distinguish community playlists vs featured playlists
        community_playlists = []
        featured_playlists = []
        for pl in playlists:
            author_low = (pl.get("author") or "").lower()
            if "youtube music" in author_low or "youtube" in author_low or "tuyển tập" in author_low:
                featured_playlists.append(pl)
            else:
                community_playlists.append(pl)

        # If top_result is not artist but artists list has an exact or strong match for query, promote artist to top_result (YouTube Music Desktop pattern)
        clean_q_low = q.lower().strip()
        if artists and (not top_result or top_result.get("type") != "artist"):
            for a in artists:
                a_name_low = (a.get("name") or "").lower().strip()
                if a_name_low == clean_q_low or clean_q_low in a_name_low or a_name_low in clean_q_low:
                    top_result = a
                    break

        # Attach top 3 tracks to top_result for 2-column desktop hero card
        if top_result:
            if top_result.get("type") == "artist":
                a_name = top_result.get("name", "")
                for s in songs:
                    if not s.get("artist") or s.get("artist") == "YouTube Music":
                        s["artist"] = a_name
            top_result["top_tracks"] = songs[:3]

        return {
            "query": q,
            "top_result": top_result,
            "songs": songs,
            "albums": albums,
            "artists": artists,
            "community_playlists": community_playlists,
            "featured_playlists": featured_playlists,
            "playlists": playlists
        }
    except Exception as e:
        sys.stderr.write(f"[search_categorized error]: {e}\n")
        return {"query": q, "top_result": None, "songs": [], "albums": [], "artists": [], "community_playlists": [], "featured_playlists": [], "playlists": []}

_FILTER_SEARCH_CACHE = {}
_FILTER_SEARCH_CACHE_TTL = 180.0

def filter_search(query, category="songs", limit=30):
    q = str(query or "").strip()
    if not q:
        return []

    cat_map = {
        "songs": "songs",
        "albums": "albums",
        "artists": "artists",
        "community_playlists": "community_playlists",
        "playlists": "community_playlists",
        "featured_playlists": "featured_playlists"
    }
    flt = cat_map.get(category, "songs")

    safe_limit = 30
    try:
        safe_limit = min(max(10, int(limit)), 60)
    except (TypeError, ValueError):
        safe_limit = 30

    cache_key = (q.lower(), flt, safe_limit)
    now = time.time()
    if cache_key in _FILTER_SEARCH_CACHE:
        cached_ts, cached_data = _FILTER_SEARCH_CACHE[cache_key]
        if now - cached_ts < _FILTER_SEARCH_CACHE_TTL:
            return cached_data

    try:
        ytm = get_ytmusic_client()
        try:
            raw = ytm.search(q, filter=flt, limit=safe_limit)
        except Exception as se:
            sys.stderr.write(f"[filter_search auth error, guest fallback]: {se}\n")
            from ytmusicapi import YTMusic
            guest_yt = YTMusic(requests_session=create_resilient_session())
            raw = guest_yt.search(q, filter=flt, limit=safe_limit)

        # Pre-load disliked songs once before the loop (avoids up to 60 disk reads!)
        try:
            disliked_set = set(load_disliked_songs().keys())
        except Exception:
            disliked_set = set()

        items = []
        for r in raw:
            rtype = r.get("resultType")
            thumbs = r.get("thumbnails", [])
            turl = thumbs[-1].get("url", "") if thumbs else ""
            turl = re.sub(r'=w\d+-h\d+.*', '=w1200-h1200-l90-rj', turl)

            if flt == "songs" or rtype in ("song", "video"):
                norm = normalize_track(r)
                if norm and (norm.get("videoId") not in disliked_set):
                    norm["type"] = "song"
                    items.append(norm)
            elif flt == "albums" or rtype == "album":
                arts = r.get("artists", [])
                aname = ", ".join(a.get("name", "") for a in arts if isinstance(a, dict)) if arts else (r.get("artist") or "")
                bid = r.get("browseId", "")
                year_str = str(r.get("year", "") or "")
                album_type = "EP" if "ep" in (r.get("title", "")).lower() else ("Single" if "single" in (r.get("title", "")).lower() else "Album")
                items.append({
                    "type": "album",
                    "browseId": bid,
                    "playlistId": r.get("playlistId", "") or bid,
                    "title": r.get("title", ""),
                    "name": r.get("title", ""),
                    "artist": aname,
                    "albumType": album_type,
                    "year": year_str,
                    "image": turl
                })
            elif flt == "artists" or rtype == "artist":
                arts = r.get("artists", [])
                a_name = r.get("artist") or (arts[0].get("name") if arts else "")
                a_id = (arts[0].get("id") if arts else "") or r.get("browseId", "")
                items.append({
                    "type": "artist",
                    "browseId": a_id,
                    "name": a_name,
                    "artist": a_name,
                    "subscribers": r.get("subscribers", ""),
                    "image": turl
                })
            elif flt in ("community_playlists", "featured_playlists") or rtype == "playlist":
                bid = r.get("browseId", "")
                author = r.get("author", "") or (r.get("artists", [{}])[0].get("name") if r.get("artists") else "")
                items.append({
                    "type": "playlist",
                    "id": bid,
                    "browseId": bid,
                    "title": r.get("title", ""),
                    "name": r.get("title", ""),
                    "author": author,
                    "artist": author,
                    "itemCount": r.get("itemCount", ""),
                    "image": turl
                })

        if len(_FILTER_SEARCH_CACHE) > 128:
            _FILTER_SEARCH_CACHE.clear()
        _FILTER_SEARCH_CACHE[cache_key] = (now, items)

        return items
    except Exception as e:
        sys.stderr.write(f"[filter_search error]: {e}\n")
        return []


def get_artist_shuffle(name, browse_id=None):
    """
    Fetches the full official YouTube Music artist shuffle queue (up to 50 tracks)
    using the artist's shuffleId (e.g. 'RDAO...'), with fallback to filter_search songs.
    """
    yt = get_ytmusic_client()
    tracks = []
    artist_name = (name or "").strip()
    clean_id = (browse_id or "").strip()

    # Strategy 1: Use official shuffleId from artist details
    if clean_id:
        try:
            art = get_artist(clean_id)
            if art and isinstance(art, dict):
                meta = art.get("metadata", {})
                if not artist_name:
                    artist_name = meta.get("name", "")
                shuf_id = meta.get("shuffleId")
                if shuf_id:
                    wp = yt.get_watch_playlist(playlistId=shuf_id)
                    raw_tracks = wp.get("tracks", [])
                    for t in raw_tracks:
                        norm = normalize_track(t)
                        if norm and not is_song_disliked(norm.get("videoId")):
                            tracks.append(norm)
                    if tracks:
                        cache_online_tracks(tracks)
                        return {"artist": artist_name, "playlistId": shuf_id, "tracks": tracks}
        except Exception as e:
            sys.stderr.write(f"[get_artist_shuffle strategy 1 error]: {e}\n")

    # Strategy 2: If no browse_id, search artist first to get browseId & shuffleId
    if not tracks and artist_name:
        try:
            sr = yt.search(artist_name, filter="artists")
            if sr and len(sr) > 0:
                first_aid = sr[0].get("browseId")
                if first_aid:
                    art = get_artist(first_aid)
                    if art and isinstance(art, dict):
                        shuf_id = art.get("metadata", {}).get("shuffleId")
                        if shuf_id:
                            wp = yt.get_watch_playlist(playlistId=shuf_id)
                            raw_tracks = wp.get("tracks", [])
                            for t in raw_tracks:
                                norm = normalize_track(t)
                                if norm and not is_song_disliked(norm.get("videoId")):
                                    tracks.append(norm)
                            if tracks:
                                cache_online_tracks(tracks)
                                return {"artist": artist_name, "playlistId": shuf_id, "tracks": tracks}
        except Exception as e:
            sys.stderr.write(f"[get_artist_shuffle strategy 2 error]: {e}\n")

    # Strategy 3: Fallback search songs by artist
    if not tracks and artist_name:
        try:
            songs = filter_search(artist_name, "songs")
            if songs:
                tracks = songs
        except Exception as e:
            sys.stderr.write(f"[get_artist_shuffle strategy 3 error]: {e}\n")

    return {"artist": artist_name, "playlistId": "songs", "tracks": tracks}




def search_albums(query, limit=10):
    if not query or not query.strip():
        return []
    try:
        ytm = get_ytmusic_client()
        raw = ytm.search(query.strip(), filter="albums")
        albums = []
        for item in raw[:limit]:
            thumbs = item.get("thumbnails", [])
            thumb_url = thumbs[-1].get("url", "") if thumbs else ""
            if "w60" in thumb_url or "w120" in thumb_url or "w226" in thumb_url:
                thumb_url = re.sub(r'=w\d+-h\d+.*', '=w1200-h1200-l90-rj', thumb_url)
            artists = item.get("artists", [])
            art_name = ", ".join(a.get("name", "") for a in artists if isinstance(a, dict)) if artists else "Unknown Artist"
            bid = item.get("browseId", "")
            albums.append({
                "id": bid,
                "browseId": bid,
                "type": "album",
                "title": item.get("title", ""),
                "name": item.get("title", ""),
                "artist": art_name,
                "year": str(item.get("year", "") or ""),
                "image": thumb_url
            })
        return albums
    except Exception as e:
        sys.stderr.write(f"[search_albums error]: {e}\n")
        return []

def get_search_suggestions(query):
    if not query or not str(query).strip():
        return {"queries": [], "recommended": []}
    q = str(query).strip()

    # Method 1: Direct YouTube Music Innertube API (< 0.2s, music-specific + rich recommended songs with avatar)
    try:
        import urllib.request
        req_data = json.dumps({
            "context": {
                "client": {
                    "clientName": "WEB_REMIX",
                    "clientVersion": "1.20240101.01.00",
                    "hl": "vi",
                    "gl": "VN"
                }
            },
            "input": q
        }).encode("utf-8")
        req = urllib.request.Request(
            "https://music.youtube.com/youtubei/v1/music/get_search_suggestions",
            data=req_data,
            headers={
                "Content-Type": "application/json",
                "User-Agent": "Mozilla/5.0 (X11; Linux x86_64; rv:130.0) Gecko/20100101 Firefox/130.0",
                "Origin": "https://music.youtube.com"
            }
        )
        with urllib.request.urlopen(req, timeout=2.0) as resp:
            data = json.loads(resp.read().decode("utf-8"))
            queries = []
            recommended = []
            for content in data.get("contents", []):
                sec = content.get("searchSuggestionsSectionRenderer", {})
                for it in sec.get("contents", []):
                    # Query suggestion
                    if "searchSuggestionRenderer" in it:
                        runs = it["searchSuggestionRenderer"].get("suggestion", {}).get("runs", [])
                        text = "".join(r.get("text", "") for r in runs).strip()
                        if text and text not in queries:
                            queries.append(text)
                    # Recommended song item with thumbnail/avatar
                    elif "musicResponsiveListItemRenderer" in it:
                        r = it["musicResponsiveListItemRenderer"]
                        flex = r.get("flexColumns", [])
                        title = ""
                        subtitle = ""
                        if flex:
                            title_runs = flex[0].get("musicResponsiveListItemFlexColumnRenderer", {}).get("text", {}).get("runs", [])
                            title = "".join(x.get("text", "") for x in title_runs).strip()
                        if len(flex) > 1:
                            sub_runs = flex[1].get("musicResponsiveListItemFlexColumnRenderer", {}).get("text", {}).get("runs", [])
                            subtitle = "".join(x.get("text", "") for x in sub_runs).strip()
                        thumbs = r.get("thumbnail", {}).get("musicThumbnailRenderer", {}).get("thumbnail", {}).get("thumbnails", [])
                        thumb = thumbs[-1].get("url", "") if thumbs else ""
                        thumb = re.sub(r'=w\d+-h\d+.*', '=w120-h120-l90-rj', thumb)
                        nav = r.get("navigationEndpoint", {})

                        # 1. Check Watch Endpoint (Song)
                        vid = nav.get("watchEndpoint", {}).get("videoId", "")
                        if not vid:
                            overlay = r.get("overlay", {}).get("musicItemThumbnailOverlayRenderer", {})
                            vid = overlay.get("content", {}).get("musicPlayButtonRenderer", {}).get("playNavigationEndpoint", {}).get("watchEndpoint", {}).get("videoId", "")

                        # 2. Check Browse Endpoint (Artist / Album)
                        browse_ep = nav.get("browseEndpoint", {})
                        browse_id = browse_ep.get("browseId", "")
                        page_type = browse_ep.get("browseEndpointContextSupportedConfigs", {}).get("browseEndpointContextMusicConfig", {}).get("pageType", "")
                        crop_circle = r.get("thumbnail", {}).get("musicThumbnailRenderer", {}).get("thumbnailCrop", "") == "MUSIC_THUMBNAIL_CROP_CIRCLE"

                        if title and (crop_circle or page_type == "MUSIC_PAGE_TYPE_ARTIST" or (browse_id and (browse_id.startswith("UC") or browse_id.startswith("FEmusic_library")))):
                            recommended.append({
                                "type": "artist",
                                "id": browse_id,
                                "browseId": browse_id,
                                "name": title,
                                "title": title,
                                "artist": title,
                                "subtitle": subtitle or "Nghệ sĩ",
                                "image": thumb
                            })
                        elif title and (page_type == "MUSIC_PAGE_TYPE_ALBUM" or (browse_id and browse_id.startswith("MPREb_"))):
                            recommended.append({
                                "type": "album",
                                "id": browse_id,
                                "browseId": browse_id,
                                "playlistId": browse_id,
                                "name": title,
                                "title": title,
                                "artist": subtitle,
                                "subtitle": subtitle or "Album",
                                "image": thumb
                            })
                        elif title and vid:
                            # Clean artist name (SimpMusic pattern)
                            parts = subtitle.split(" • ")
                            artist_name = parts[1].strip() if len(parts) > 1 else subtitle
                            recommended.append({
                                "type": "song",
                                "id": vid,
                                "videoId": vid,
                                "title": title,
                                "name": title,
                                "artist": artist_name,
                                "subtitle": subtitle,
                                "image": thumb,
                                "path": "ytdl://" + vid
                            })
            if queries or recommended:
                return {"queries": queries, "recommended": recommended}
    except Exception as e:
        sys.stderr.write(f"[innertube suggestions fallback]: {e}\n")

    # Method 2: Google Suggest Queries API (Instant < 0.1s fallback)
    try:
        import urllib.request
        import urllib.parse
        encoded_q = urllib.parse.quote(q)
        url = f"https://suggestqueries.google.com/complete/search?client=firefox&ds=yt&q={encoded_q}"
        req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
        with urllib.request.urlopen(req, timeout=1.2) as resp:
            data = json.loads(resp.read().decode("utf-8"))
            if isinstance(data, list) and len(data) > 1 and isinstance(data[1], list):
                return {"queries": data[1], "recommended": []}
    except Exception as e:
        sys.stderr.write(f"[google suggest fallback]: {e}\n")

    # Method 3: ytmusicapi fallback
    try:
        yt = get_ytmusic_client()
        raw_sug = yt.get_search_suggestions(q)
        return {"queries": raw_sug if isinstance(raw_sug, list) else [], "recommended": []}
    except Exception as e:
        sys.stderr.write(f"[get_search_suggestions error]: {e}\n")
        return {"queries": [], "recommended": []}


