"""HTTP handlers for listening history: count plays (>= 30s) and report totals."""

import os
import pathlib
import re

try:
    from . import database
except (ImportError, ValueError):
    import database

_db_ready = False


def _ensure_db():
    global _db_ready
    if not _db_ready:
        database.init_db()
        _db_ready = True


def handle_post_play_record(handler, req_data):
    try:
        _ensure_db()
        counted = database.upsert_play(
            str(req_data.get("play_id") or ""),
            req_data.get("track") or {},
            float(req_data.get("listened_seconds") or 0),
            float(req_data.get("total_seconds") or 0),
        )
        handler._send_json({"success": True, "counted": counted}, 200)
    except Exception as e:
        handler._send_json({"success": False, "error": str(e)}, 500)


def handle_get_listening_totals(handler, query):
    try:
        _ensure_db()
        handler._send_json({"success": True, "totals": database.get_lifetime_totals()}, 200)
    except Exception as e:
        handler._send_json({"success": False, "error": str(e)}, 500)


def handle_get_listening_profile(handler, query):
    try:
        _ensure_db()
        handler._send_json({"success": True, "profile": database.get_profile_overview()}, 200)
    except Exception as e:
        handler._send_json({"success": False, "error": str(e)}, 500)


def handle_get_listening_recap(handler, query):
    """The monthly recap. ?force=1 or NUTSTY_FORCE_RECAP=1 opens it with whatever has been played."""
    try:
        _ensure_db()
        force = (query.get("force", [""])[0] in ("1", "true")) or os.environ.get("NUTSTY_FORCE_RECAP") == "1"
        recap = database.get_monthly_recap(force=force)
        stats = recap.get("stats") if isinstance(recap, dict) else None
        if stats:
            _attach_artist_photos(stats.get("top_artists") or [])
        handler._send_json({"success": True, "recap": recap}, 200)
    except Exception as e:
        handler._send_json({"success": False, "error": str(e)}, 500)


def _artist_photo(name):
    """The artist's own photo: the shared avatar cache first, then a YouTube Music artist search."""
    try:
        from . import catalog_engine as ce
    except (ImportError, ValueError):
        import catalog_engine as ce
    url = ce.get_cached_artist_avatar(name)
    if url:
        return url
    try:
        found = ce.get_ytmusic_client().search(ce.clean_artist_name(name), filter="artists", limit=1)
    except Exception:
        return ""
    for item in found or []:
        thumbs = item.get("thumbnails") or []
        if thumbs and thumbs[-1].get("url"):
            url = re.sub(r"=w\d+-h\d+", "=w544-h544", thumbs[-1]["url"])
            ce.cache_artist_avatar(name, url)
            return url
    return ""


def _attach_artist_photos(artists):
    """photo_url on each top artist, looked up in parallel; a slow lookup leaves the song cover in place."""
    from concurrent.futures import ThreadPoolExecutor, wait
    names = [a.get("artist", "") for a in artists]
    pool = ThreadPoolExecutor(max_workers=6)
    futures = [pool.submit(_artist_photo, n) for n in names]
    wait(futures, timeout=8)
    for a, f in zip(artists, futures):
        photo = f.result() if f.done() and not f.exception() else ""
        a["photo_url"] = photo or a.get("cover_url") or ""
    pool.shutdown(wait=False)


def handle_get_recap_snippet(handler, query):
    """A playable URL for one recap song: the file itself when it is on disk, otherwise its audio stream."""
    track = (query.get("track", [""])[0] or "").strip()
    try:
        if not track:
            raise ValueError("no track")
        if os.path.isfile(track):
            handler._send_json({"success": True, "url": pathlib.Path(track).as_uri()}, 200)
            return
        try:
            from . import stream_resolver
        except (ImportError, ValueError):
            import stream_resolver
        vid = track.replace("ytdl://", "")
        if vid.startswith("yt_"):
            vid = vid[3:]
        res = stream_resolver.resolve_stream_url(vid) or {}
        url = res.get("stream_url", "")
        if url and res.get("is_local_file"):
            url = pathlib.Path(url).as_uri()
        handler._send_json({"success": bool(url), "url": url}, 200)
    except Exception as e:
        handler._send_json({"success": False, "error": str(e)}, 500)
