#!/usr/bin/env python3
"""
Nutsty YouTube Music Helper (Facade & CLI Dispatcher)
Provides full backward compatibility for all Python callers and QML CLI processes
by delegating to specialized deep modules:
- ytmusic_auth: Google Account authentication & session client
- stream_resolver: Direct audio stream URL resolution & TTL caching
- catalog_engine: Personalized home feeds, mood categories, radio & search
- song_enrichment: Track details, related content & Apple Music animated art
"""
import sys
import os
import json
import time

try:
    from . import platform_compat as pc
    from .ytmusic_auth import (
        PROFILE_NAME, PROFILE_SUFFIX, AUTH_FILE, AUTH_CHANGED_FILE,
        load_json, save_json,
        create_resilient_session, sanitize_cookie_for_ytmusic, safe_sapisid_from_cookie,
        fetch_google_profile_from_cookies, get_ytmusic_client,
        extract_account_details_from_client, get_auth_status, save_auth, logout,
        get_exported_cookie_file, extract_ytmusic_cookies_from_browsers
    )
    from .catalog_engine import (
        HOME_CACHE_FILE, ONLINE_TRACKS_FILE, MOOD_CACHE_DIR, MOOD_CATS_FILE,
        DISLIKED_SONGS_FILE, ARTIST_AVATARS_FILE,
        load_disliked_songs, save_disliked_songs, add_disliked_song, remove_disliked_song, is_song_disliked,
        load_artist_avatars, save_artist_avatars, cache_artist_avatar, get_cached_artist_avatar,
        cache_online_tracks, clean_artist_name, clean_thumbnail_url, normalize_track,
        get_recent_seed_track, get_mood_categories_live, get_creator_color, classify_section,
        get_personalized_home, get_radio, get_watch_playlist_chips, get_filtered_radio_queue,
        get_mood_feed, get_album_details, get_artist, subscribe_artist_action,
        get_playlist_tracks, search_ytmusic, search_categorized, filter_search,
        get_artist_shuffle, search_albums, get_search_suggestions
    )
    from .stream_resolver import (
        STREAM_CACHE_FILE, LOCAL_YT_MAPPINGS_FILE, PENDING_HISTORY_FILE,
        QUALITY_ITAG_PRIORITIES,
        resolve_stream_url, resolve_video_id_for_track, send_playback_tracking,
        get_cached_stream_url, put_cached_stream_url, invalidate_cached_stream_url
    )
    from .song_enrichment import (
        SQUARE_COVERS_CACHE_FILE,
        get_song_details, rate_song_action, get_song_related_content, get_youtube_lyrics,
        get_am_token, select_am_rendition, clean_for_search, normalize_for_match,
        match_key, matches_loosely, artist_agrees, match_score,
        get_apple_music_animated_artwork, resolve_square_cover, get_animated_background
    )
except (ImportError, ValueError):
    import platform_compat as pc
    from ytmusic_auth import (
        PROFILE_NAME, PROFILE_SUFFIX, AUTH_FILE, AUTH_CHANGED_FILE,
        load_json, save_json,
        create_resilient_session, sanitize_cookie_for_ytmusic, safe_sapisid_from_cookie,
        fetch_google_profile_from_cookies, get_ytmusic_client,
        extract_account_details_from_client, get_auth_status, save_auth, logout,
        get_exported_cookie_file, extract_ytmusic_cookies_from_browsers
    )
    from catalog_engine import (
        HOME_CACHE_FILE, ONLINE_TRACKS_FILE, MOOD_CACHE_DIR, MOOD_CATS_FILE,
        DISLIKED_SONGS_FILE, ARTIST_AVATARS_FILE,
        load_disliked_songs, save_disliked_songs, add_disliked_song, remove_disliked_song, is_song_disliked,
        load_artist_avatars, save_artist_avatars, cache_artist_avatar, get_cached_artist_avatar,
        cache_online_tracks, clean_artist_name, clean_thumbnail_url, normalize_track,
        get_recent_seed_track, get_mood_categories_live, get_creator_color, classify_section,
        get_personalized_home, get_radio, get_watch_playlist_chips, get_filtered_radio_queue,
        get_mood_feed, get_album_details, get_artist, subscribe_artist_action,
        get_playlist_tracks, search_ytmusic, search_categorized, filter_search,
        get_artist_shuffle, search_albums, get_search_suggestions
    )
    from stream_resolver import (
        STREAM_CACHE_FILE, LOCAL_YT_MAPPINGS_FILE, PENDING_HISTORY_FILE,
        QUALITY_ITAG_PRIORITIES,
        resolve_stream_url, resolve_video_id_for_track, send_playback_tracking,
        get_cached_stream_url, put_cached_stream_url, invalidate_cached_stream_url
    )
    from song_enrichment import (
        SQUARE_COVERS_CACHE_FILE,
        get_song_details, rate_song_action, get_song_related_content, get_youtube_lyrics,
        get_am_token, select_am_rendition, clean_for_search, normalize_for_match,
        match_key, matches_loosely, artist_agrees, match_score,
        get_apple_music_animated_artwork, resolve_square_cover, get_animated_background
    )

def handle_cli(args):
    """Entry point for thread-safe in-process execution without modifying sys.argv."""
    execute_command(list(args))

def main():
    execute_command(sys.argv[1:])

def _load_settings():
    settings_path = os.path.join(pc.get_config_dir(), "nutsty_settings.json")
    if os.path.exists(settings_path):
        try:
            with open(settings_path, "r", encoding="utf-8") as f:
                return json.load(f)
        except Exception:
            return {}
    return {}

def execute_command(args):
    if len(args) < 1:
        print("Usage: ytmusic_helper.py [home | radio <id> | mood <params> | playlist <id> | search <q> | get_url <id> | auth_status | save_auth <text> | logout | track_playback <id> | song_details <id> | rate_song <id> <rating> | song_related <id>]")
        return

    cmd = args[0].lower()
    if cmd == "song_related" and len(args) > 1:
        vid = args[1]
        title = args[2] if len(args) > 2 else ""
        artist = args[3] if len(args) > 3 else ""
        res = get_song_related_content(vid, title, artist)
        print(json.dumps(res, ensure_ascii=False))

    elif cmd == "song_details" and len(args) > 1:
        vid = args[1]
        res = get_song_details(vid)
        print(json.dumps(res, ensure_ascii=False))

    elif cmd == "rate_song" and len(args) > 2:
        vid = args[1]
        rating = args[2]
        res = rate_song_action(vid, rating)
        print(json.dumps(res, ensure_ascii=False))

    elif cmd == "disliked_list":
        print(json.dumps(load_disliked_songs(), ensure_ascii=False))

    elif cmd == "home":
        res = get_personalized_home()
        print(json.dumps(res, ensure_ascii=False))

    elif cmd == "radio" and len(args) > 1:
        vid = args[1]
        res = get_radio(vid)
        print(json.dumps(res, ensure_ascii=False))

    elif cmd == "next_chips" and len(args) > 1:
        vid = args[1]
        res = get_watch_playlist_chips(vid)
        print(json.dumps(res, ensure_ascii=False))

    elif cmd == "filter_queue" and len(args) > 2:
        vid = args[1]
        pl_id = args[2]
        params = args[3] if len(args) > 3 else None
        res = get_filtered_radio_queue(vid, pl_id, params)
        print(json.dumps(res, ensure_ascii=False))

    elif cmd == "mood" and len(args) > 1:
        params = args[1]
        title = args[2] if len(args) > 2 else ""
        res = get_mood_feed(params, title)
        print(json.dumps(res, ensure_ascii=False))

    elif cmd == "playlist" and len(args) > 1:
        pl_id = args[1]
        res = get_playlist_tracks(pl_id)
        print(json.dumps(res, ensure_ascii=False))

    elif cmd == "album" and len(args) > 1:
        alb_id = args[1]
        res = get_album_details(alb_id)
        print(json.dumps(res, ensure_ascii=False))

    elif cmd == "search_albums" and len(args) > 1:
        q = args[1]
        res = search_albums(q)
        print(json.dumps(res, ensure_ascii=False))

    elif cmd == "categorized_search":
        q = args[1] if len(args) > 1 else "Trending"
        res = search_categorized(q)
        print(json.dumps(res, ensure_ascii=False))

    elif cmd == "search":
        q = args[1] if len(args) > 1 else "Trending"
        res = search_ytmusic(q)
        print(json.dumps(res, ensure_ascii=False))

    elif cmd == "suggestions" and len(args) > 1:
        q = args[1]
        res = get_search_suggestions(q)
        print(json.dumps(res, ensure_ascii=False))

    elif cmd == "get_url":
        vid = args[1] if len(args) > 1 else ""
        res = resolve_stream_url(vid)
        print(json.dumps(res or {}, ensure_ascii=False))

    elif cmd == "auth_status":
        res = get_auth_status()
        print(json.dumps(res, ensure_ascii=False))

    elif cmd == "save_auth" and len(args) > 1:
        text = args[1]
        res = save_auth(text)
        print(json.dumps(res, ensure_ascii=False))

    elif cmd in ("auto_sync", "auto_sync_browser"):
        res = extract_ytmusic_cookies_from_browsers()
        print(json.dumps(res, ensure_ascii=False))

    elif cmd == "logout":
        res = logout()
        print(json.dumps(res, ensure_ascii=False))

    elif cmd == "track_playback" and len(args) > 1:
        vid = args[1]
        title = args[2] if len(args) > 2 else ""
        artist = args[3] if len(args) > 3 else ""
        pl_id = args[4] if len(args) > 4 else None
        res = send_playback_tracking(vid, title, artist, pl_id)
        print(json.dumps(res, ensure_ascii=False))

    elif cmd == "artist" and len(args) > 1:
        art_id = args[1]
        res = get_artist(art_id)
        print(json.dumps(res, ensure_ascii=False))

    elif cmd == "subscribe" and len(args) > 1:
        channel_id = args[1]
        sub = True
        if len(args) > 2:
            sub = str(args[2]).lower() in ("true", "1", "yes")
        res = subscribe_artist_action(channel_id, sub)
        print(json.dumps(res, ensure_ascii=False))

    elif cmd == "cached_avatar" and len(args) > 1:
        name = args[1]
        url = get_cached_artist_avatar(name)
        print(json.dumps({"artist": name, "avatar": url}, ensure_ascii=False))

    elif cmd == "filter_search" and len(args) > 1:
        q = args[1]
        flt = args[2] if len(args) > 2 else "songs"
        res = filter_search(q, flt)
        print(json.dumps(res, ensure_ascii=False))

    elif cmd == "artist_shuffle" and len(args) > 1:
        name = args[1]
        browse_id = args[2] if len(args) > 2 else None
        res = get_artist_shuffle(name, browse_id)
        print(json.dumps(res, ensure_ascii=False))

    elif cmd == "animated_artwork" and len(args) > 1:
        title = args[1]
        artist = args[2] if len(args) > 2 else ""
        dur = float(args[3]) if len(args) > 3 and args[3] else 0.0
        album_hint = args[4] if len(args) > 4 else ""
        pref = args[5] if len(args) > 5 else _load_settings().get("canvasPreference", "apple_first")
        res = get_animated_background(title, artist, dur, album_hint, pref)
        print(json.dumps(res, ensure_ascii=False))

    elif cmd == "resolve_stream" and len(args) > 1:
        vid = args[1]
        qual = args[2] if len(args) > 2 else None
        res = resolve_stream_url(vid, qual)
        print(json.dumps(res, ensure_ascii=False) if res else "{}")

    elif cmd == "resolve_cover" and len(args) > 1:
        title = args[1]
        artist = args[2] if len(args) > 2 else ""
        vid = args[3] if len(args) > 3 else None
        curr = args[4] if len(args) > 4 else None
        res = resolve_square_cover(title, artist, vid, curr)
        print(json.dumps(res, ensure_ascii=False))

if __name__ == "__main__":
    main()
