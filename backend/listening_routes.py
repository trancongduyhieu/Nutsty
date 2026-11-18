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


def handle_get_listening_stats(handler, query):
    """The Stats page: ?year=2026&month=11 for a month, month=0 (or none) for the whole year."""
    try:
        _ensure_db()
        from datetime import datetime
        now = datetime.now()
        year = int(query.get("year", [now.year])[0] or now.year)
        month = int(query.get("month", [0])[0] or 0)
        if not 0 <= month <= 12:
            raise ValueError("month out of range")
        stats = database.get_period_stats(year, month)
        _attach_artist_photos((stats.get("top_artists") or [])[:10])
        handler._send_json({"success": True, "stats": stats}, 200)
    except Exception as e:
        handler._send_json({"success": False, "error": str(e)}, 500)


# --- genres -------------------------------------------------------------------------------
# Nothing in the library knows a song's genre. As Mochy does, each *artist* is looked up by name
# alone on the iTunes Search API (nothing about what or how much was played is sent), answers are
# kept on disk so an artist is asked about once, and shares are weighted here by listening time.
_GENRE_MAX_LOOKUPS = 12          # per request; the API allows about 20 a minute
_genre_lock = None


def _genre_cache_path():
    try:
        from . import platform_compat as pc
    except (ImportError, ValueError):
        import platform_compat as pc
    return os.path.join(pc.get_config_dir(), "nutsty_artist_genres.json")


def _lookup_genre(name):
    import json
    import urllib.parse
    import urllib.request
    url = "https://itunes.apple.com/search?" + urllib.parse.urlencode(
        {"term": name, "entity": "musicArtist", "limit": 1})
    req = urllib.request.Request(url, headers={"User-Agent": "Nutsty"})
    with urllib.request.urlopen(req, timeout=4) as r:
        res = json.loads(r.read().decode("utf-8", "replace"))
    for item in res.get("results") or []:
        g = (item.get("primaryGenreName") or "").strip()
        if g:
            return g
    return ""


def handle_get_listening_genres(handler, query):
    """Genre shares for a month or year, biggest first; artists not yet known are asked a few at a time."""
    import json
    import threading
    global _genre_lock
    try:
        _ensure_db()
        from datetime import datetime
        now = datetime.now()
        year = int(query.get("year", [now.year])[0] or now.year)
        month = int(query.get("month", [0])[0] or 0)
        if _genre_lock is None:
            _genre_lock = threading.Lock()
        artists = database.get_artist_minutes(year, month)
        with _genre_lock:
            path = _genre_cache_path()
            try:
                with open(path, "r", encoding="utf-8") as f:
                    known = json.load(f)
            except Exception:
                known = {}
            asked = 0
            for a in artists:
                key = a["artist"].strip().lower()
                if key in known or asked >= _GENRE_MAX_LOOKUPS:
                    continue
                asked += 1
                try:
                    g = _lookup_genre(a["artist"])
                except Exception:
                    g = ""
                if g:
                    known[key] = g
            if asked:
                try:
                    with open(path, "w", encoding="utf-8") as f:
                        json.dump(known, f, ensure_ascii=False)
                except Exception:
                    pass
        totals = {}
        for a in artists:
            g = known.get(a["artist"].strip().lower())
            if g:
                totals[g] = totals.get(g, 0) + a["minutes"]
        whole = sum(totals.values())
        shares = [{"name": g, "minutes": m, "fraction": (m / whole) if whole else 0}
                  for g, m in sorted(totals.items(), key=lambda kv: -kv[1])]
        handler._send_json({"success": True, "genres": shares,
                            "pending": any(a["artist"].strip().lower() not in known for a in artists)}, 200)
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
