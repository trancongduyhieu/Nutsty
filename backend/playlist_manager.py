#!/usr/bin/env python3
"""
Nutsty Custom Playlist Manager
Manages user custom playlists saved in ~/.config/noctalia/custom_playlists.json
"""
import os
import sys
import json
import time
import threading
import contextlib
import contextvars
import functools

try:
    from . import platform_compat as pc
except (ImportError, ValueError):
    import platform_compat as pc


def _suffix_for(profile):
    name = str(profile or "").strip().lower()
    return f"_{name}" if name else ""


# Suffix of the process's own profile. One nutsty-daemon serves every profile window, so HTTP requests
# override it per request with profile_scope(); contextvars keeps that per thread on auth_server.
PROFILE_NAME = os.getenv("NUTSTY_PROFILE", "").strip().lower()
PROFILE_SUFFIX = _suffix_for(PROFILE_NAME)
_ACTIVE_SUFFIX = contextvars.ContextVar("nutsty_playlist_suffix", default=PROFILE_SUFFIX)

CONFIG_DIR = pc.get_config_dir()
PLAYLISTS_FILE = os.path.join(CONFIG_DIR, f"custom_playlists{PROFILE_SUFFIX}.json")
FAVORITE_PLAYLISTS_FILE = os.path.join(CONFIG_DIR, f"favorite_playlists{PROFILE_SUFFIX}.json")
LOCK_TIMEOUT_SEC = 10.0


def _playlists_file():
    return os.path.join(CONFIG_DIR, f"custom_playlists{_ACTIVE_SUFFIX.get()}.json")


def _favorites_file():
    return os.path.join(CONFIG_DIR, f"favorite_playlists{_ACTIVE_SUFFIX.get()}.json")


@contextlib.contextmanager
def profile_scope(profile):
    """Read and write the files of `profile` (NUTSTY_PROFILE value, "" = default) inside this block."""
    token = _ACTIVE_SUFFIX.set(_suffix_for(profile))
    try:
        yield
    finally:
        _ACTIVE_SUFFIX.reset(token)


# ---------------------------------------------------------------------------
# Cross-process lock around load-modify-save. Writers: the QML store (via HTTP), the CLI, spotify_importer.
# Without it two writers each load the file and the later save drops the other's change.
# ---------------------------------------------------------------------------
_THREAD_LOCK = threading.RLock()
_LOCK_STATE = threading.local()


def _acquire_file_lock(fh):
    deadline = time.monotonic() + LOCK_TIMEOUT_SEC
    if os.name == "nt":
        import msvcrt
        while True:
            try:
                fh.seek(0)
                msvcrt.locking(fh.fileno(), msvcrt.LK_NBLCK, 1)
                return
            except OSError:
                if time.monotonic() > deadline:
                    raise TimeoutError("playlist lock busy")
                time.sleep(0.02)
    else:
        import fcntl
        while True:
            try:
                fcntl.flock(fh.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
                return
            except BlockingIOError:
                if time.monotonic() > deadline:
                    raise TimeoutError("playlist lock busy")
                time.sleep(0.02)


def _release_file_lock(fh):
    try:
        if os.name == "nt":
            import msvcrt
            fh.seek(0)
            msvcrt.locking(fh.fileno(), msvcrt.LK_UNLCK, 1)
        else:
            import fcntl
            fcntl.flock(fh.fileno(), fcntl.LOCK_UN)
    except OSError:
        pass


@contextlib.contextmanager
def locked():
    """Hold the playlist lock of the active profile. Reentrant within a thread."""
    with _THREAD_LOCK:
        held = getattr(_LOCK_STATE, "held", None)
        if held is None:
            _LOCK_STATE.held = held = {}
        suffix = _ACTIVE_SUFFIX.get()
        if held.get(suffix):
            held[suffix] += 1
            try:
                yield
            finally:
                held[suffix] -= 1
            return
        os.makedirs(CONFIG_DIR, exist_ok=True)
        fh = open(os.path.join(CONFIG_DIR, f"playlists{suffix}.lock"), "a+b")
        try:
            _acquire_file_lock(fh)
            held[suffix] = 1
            try:
                yield
            finally:
                held[suffix] = 0
                _release_file_lock(fh)
        finally:
            fh.close()


def _with_lock(fn):
    @functools.wraps(fn)
    def wrapper(*args, **kwargs):
        with locked():
            return fn(*args, **kwargs)
    return wrapper


def load_playlists():
    p = _playlists_file()
    if not os.path.exists(p) and not _ACTIVE_SUFFIX.get():
        p = os.path.join(CONFIG_DIR, "custom_playlists.json")
    if not os.path.exists(p):
        return []
    try:
        with open(p, "r", encoding="utf-8") as f:
            data = json.load(f)
            if not isinstance(data, list):
                return []
            needs_save = False
            for item in data:
                if isinstance(item, dict):
                    if not item.get("isCustom"):
                        item["isCustom"] = True
                        needs_save = True
                    if not item.get("isLocal"):
                        item["isLocal"] = True
                        needs_save = True
                    if not item.get("type"):
                        item["type"] = "custom"
                        needs_save = True
                    if not item.get("id") and item.get("playlistId"):
                        item["id"] = item["playlistId"]
                        needs_save = True
                    if not item.get("playlistId") and item.get("id"):
                        item["playlistId"] = item["id"]
                        needs_save = True
                    if not item.get("name") and item.get("title"):
                        item["name"] = item["title"]
                    if not item.get("title") and item.get("name"):
                        item["title"] = item["name"]
                    if not item.get("customCover") and item.get("image"):
                        item["customCover"] = item["image"]
            if needs_save:
                with locked():
                    save_playlists(data)
            return data
    except Exception:
        return []

def save_playlists(playlists):
    os.makedirs(CONFIG_DIR, exist_ok=True)
    dest = _playlists_file()
    tmp = dest + ".tmp"
    try:
        with open(tmp, "w", encoding="utf-8") as f:
            json.dump(playlists, f, ensure_ascii=False, indent=2)
        os.replace(tmp, dest)
        return True
    except Exception as e:
        sys.stderr.write(f"Error saving custom playlists: {e}\n")
        return False

def get_track_unique_key(track):
    if not track:
        return ""
    if isinstance(track, str):
        if track.startswith("ytdl://"):
            return f"yt_{track.replace('ytdl://', '')}"
        return f"local_{track}"
    if isinstance(track, dict):
        if track.get("videoId"):
            return f"yt_{track['videoId']}"
        if track.get("path"):
            p = track["path"]
            if p.startswith("ytdl://"):
                return f"yt_{p.replace('ytdl://', '')}"
            return f"local_{p}"
        if track.get("id"):
            return f"id_{track['id']}"
        return track.get("title", "")
    return str(track)

@_with_lock
def create_playlist(title, initial_tracks=None, description="", custom_cover=""):
    if not title or not title.strip():
        title = "New Playlist"
    playlists = load_playlists()
    pl_id = f"custom_pl_{int(time.time() * 1000)}"
    tracks = []
    if initial_tracks:
        if isinstance(initial_tracks, str):
            try:
                tracks = json.loads(initial_tracks)
            except Exception:
                tracks = []
        elif isinstance(initial_tracks, list):
            tracks = initial_tracks

    new_pl = {
        "id": pl_id,
        "playlistId": pl_id,
        "title": title.strip(),
        "name": title.strip(),
        "description": description.strip() if description else "",
        "customCover": custom_cover.strip() if custom_cover else "",
        "isLocal": True,
        "isCustom": True,
        "createdAt": int(time.time()),
        "tracks": tracks,
        "trackCount": len(tracks),
        "image": custom_cover if custom_cover else (tracks[0].get("image", "") if tracks else "")
    }
    playlists.append(new_pl)
    save_playlists(playlists)
    return new_pl

@_with_lock
def rename_playlist(pl_id, new_title, new_description=None, new_cover=None):
    """Rename a playlist and, when new_cover is given ("" clears it), set its cover in the same write.

    Doing both in one load/save matters: two separate commands run concurrently and the second
    save overwrites the first with a stale copy of the file.
    """
    playlists = load_playlists()
    target = None
    for p in playlists:
        if p.get("id") == pl_id:
            target = p
            break
    if not target:
        return {"success": False, "error": "Playlist not found"}

    if new_title and new_title.strip():
        target["title"] = new_title.strip()
        target["name"] = new_title.strip()
    if new_description is not None:
        target["description"] = new_description.strip()
    if new_cover is not None:
        _apply_cover(target, new_cover)
    save_playlists(playlists)
    return {"success": True, "playlist": target}

def _apply_cover(target, image_path):
    target["customCover"] = image_path.strip() if image_path else ""
    target["image"] = target["customCover"] or (target["tracks"][0].get("image", "") if target.get("tracks") else "")

@_with_lock
def set_playlist_cover(pl_id, image_path):
    playlists = load_playlists()
    target = None
    for p in playlists:
        if p.get("id") == pl_id:
            target = p
            break
    if not target:
        return {"success": False, "error": "Playlist not found"}

    _apply_cover(target, image_path)
    save_playlists(playlists)
    return {"success": True, "playlist": target}

@_with_lock
def reorder_tracks(pl_id, from_index, to_index):
    playlists = load_playlists()
    target = None
    for p in playlists:
        if p.get("id") == pl_id:
            target = p
            break
    if not target:
        return {"success": False, "error": "Playlist not found"}

    tracks = target.get("tracks", [])
    if 0 <= from_index < len(tracks) and 0 <= to_index < len(tracks):
        item = tracks.pop(from_index)
        tracks.insert(to_index, item)
        target["tracks"] = tracks
        if not target.get("customCover") and tracks:
            target["image"] = tracks[0].get("image", "")
        save_playlists(playlists)
        return {"success": True, "playlist": target}
    return {"success": False, "error": "Invalid indices"}

@_with_lock
def delete_playlist(pl_id):
    playlists = load_playlists()
    filtered = [p for p in playlists if p.get("id") != pl_id]
    save_playlists(filtered)
    # Also clean up from favorite playlists if present
    try:
        favs = load_favorite_playlists()
        filtered_favs = [p for p in favs if str(p.get("id") or p.get("playlistId") or p.get("browseId") or "") != str(pl_id)]
        if len(filtered_favs) != len(favs):
            save_favorite_playlists(filtered_favs)
    except Exception as e:
        sys.stderr.write(f"Error updating favorite playlists on delete: {e}\n")
    return {"success": True, "remaining": len(filtered)}

@_with_lock
def add_tracks_to_playlist(pl_id, new_tracks):
    playlists = load_playlists()
    target = None
    for p in playlists:
        if p.get("id") == pl_id:
            target = p
            break
    if not target:
        return {"success": False, "error": "Playlist not found"}

    if isinstance(new_tracks, str):
        try:
            new_tracks = json.loads(new_tracks)
        except Exception:
            new_tracks = []

    existing_keys = set(get_track_unique_key(t) for t in target.get("tracks", []) if get_track_unique_key(t))
    added = 0
    for t in new_tracks:
        k = get_track_unique_key(t)
        if k and k not in existing_keys:
            target["tracks"].append(t)
            existing_keys.add(k)
            added += 1

    target["trackCount"] = len(target["tracks"])
    if not target.get("customCover") and not target.get("image") and target["tracks"]:
        target["image"] = target["tracks"][0].get("image", "")

    save_playlists(playlists)
    return {"success": True, "added": added, "total": len(target["tracks"])}

@_with_lock
def remove_track_from_playlist(pl_id, track_identifier):
    playlists = load_playlists()
    target = None
    for p in playlists:
        if p.get("id") == pl_id:
            target = p
            break
    if not target:
        return {"success": False, "error": "Playlist not found"}

    target_key = get_track_unique_key(track_identifier)
    target_str = str(track_identifier) if not isinstance(track_identifier, dict) else ""

    target["tracks"] = [
        t for t in target.get("tracks", [])
        if get_track_unique_key(t) != target_key
        and (not target_str or (t.get("path") != target_str and t.get("videoId") != target_str))
    ]
    target["trackCount"] = len(target["tracks"])
    if not target.get("customCover"):
        target["image"] = target["tracks"][0].get("image", "") if target["tracks"] else ""
    save_playlists(playlists)
    return {"success": True, "total": len(target["tracks"])}

def load_favorite_playlists():
    p = _favorites_file()
    if not os.path.exists(p) and not _ACTIVE_SUFFIX.get():
        p = os.path.join(CONFIG_DIR, "favorite_playlists.json")
    if not os.path.exists(p):
        return []
    try:
        with open(p, "r", encoding="utf-8") as f:
            data = json.load(f)
            return data if isinstance(data, list) else []
    except Exception:
        return []

def save_favorite_playlists(favs):
    os.makedirs(CONFIG_DIR, exist_ok=True)
    dest = _favorites_file()
    tmp = dest + ".tmp"
    try:
        with open(tmp, "w", encoding="utf-8") as f:
            json.dump(favs, f, ensure_ascii=False, indent=2)
        os.replace(tmp, dest)
        return True
    except Exception as e:
        sys.stderr.write(f"Error saving favorite playlists: {e}\n")
        return False

@_with_lock
def toggle_favorite_playlist(pl_data):
    if not pl_data:
        return {"success": False, "error": "No playlist data"}
    if isinstance(pl_data, str):
        try:
            pl_data = json.loads(pl_data)
        except Exception:
            return {"success": False, "error": "Invalid JSON"}
    if not isinstance(pl_data, dict):
        return {"success": False, "error": "Invalid playlist format"}

    pl_id = str(pl_data.get("id") or pl_data.get("playlistId") or pl_data.get("browseId") or "")
    if not pl_id:
        return {"success": False, "error": "No playlist ID"}

    favs = load_favorite_playlists()
    existing_idx = -1
    for idx, item in enumerate(favs):
        curr_id = str(item.get("id") or item.get("playlistId") or item.get("browseId") or "")
        if curr_id == pl_id:
            existing_idx = idx
            break

    if existing_idx >= 0:
        favs.pop(existing_idx)
        save_favorite_playlists(favs)
        return {"success": True, "isFavorite": False, "playlistId": pl_id, "favorites": favs}
    else:
        title = pl_data.get("title") or pl_data.get("name") or "Playlist"
        subtitle = pl_data.get("subtitle") or pl_data.get("artist") or pl_data.get("author") or ""
        img = pl_data.get("image") or pl_data.get("thumbnail") or ""
        if not img and isinstance(pl_data.get("thumbnails"), list) and pl_data["thumbnails"]:
            img = pl_data["thumbnails"][-1].get("url", "")

        normalized = {
            "id": pl_id,
            "playlistId": pl_id,
            "browseId": pl_id,
            "title": title,
            "name": title,
            "subtitle": subtitle,
            "artist": pl_data.get("artist") or subtitle,
            "image": img,
            "thumbnail": img,
            "type": pl_data.get("type", "playlist"),
            "trackCount": pl_data.get("trackCount") or pl_data.get("itemCount") or len(pl_data.get("tracks", [])),
            "addedAt": int(time.time()),
            "tracks": pl_data.get("tracks", [])
        }
        favs.insert(0, normalized)
        save_favorite_playlists(favs)
        return {"success": True, "isFavorite": True, "playlistId": pl_id, "favorites": favs}

@_with_lock
def remove_favorite_playlist(pl_id):
    if not pl_id:
        return {"success": False}
    favs = load_favorite_playlists()
    filtered = [
        p for p in favs
        if str(p.get("id") or p.get("playlistId") or p.get("browseId") or "") != str(pl_id)
    ]
    save_favorite_playlists(filtered)
    return {"success": True, "favorites": filtered}

# ---------------------------------------------------------------------------
# Backup: export / import custom + favorite playlists as one JSON file
# ---------------------------------------------------------------------------
BACKUP_FORMAT = "nutsty-playlists"
BACKUP_VERSION = 1
MAX_BACKUP_BYTES = 50 * 1024 * 1024

def _to_local_path(path_or_url):
    """Accept a plain path or a file:// URL (what QML FileDialog returns)."""
    p = str(path_or_url or "").strip()
    if p.lower().startswith("file:"):
        from urllib.parse import urlparse, unquote
        from urllib.request import url2pathname
        parsed = urlparse(p)
        p = url2pathname(unquote(parsed.path))
        if parsed.netloc and parsed.netloc != "localhost":
            p = "//" + parsed.netloc + p  # UNC share on Windows
    return os.path.expanduser(p)

def export_playlists(dest):
    dest = _to_local_path(dest)
    if not dest:
        return {"success": False, "error": "no_path"}
    if not dest.lower().endswith(".json"):
        dest += ".json"
    playlists = load_playlists()
    favorites = load_favorite_playlists()
    payload = {
        "format": BACKUP_FORMAT,
        "version": BACKUP_VERSION,
        "app": "Nutsty",
        "appVersion": getattr(pc, "APP_VERSION", ""),
        "exportedAt": int(time.time()),
        "playlists": playlists,
        "favorites": favorites,
    }
    try:
        parent = os.path.dirname(dest)
        if parent:
            os.makedirs(parent, exist_ok=True)
        tmp = dest + ".tmp"
        with open(tmp, "w", encoding="utf-8") as f:
            json.dump(payload, f, ensure_ascii=False, indent=2)
        os.replace(tmp, dest)
    except Exception as e:
        sys.stderr.write(f"Error exporting playlists: {e}\n")
        return {"success": False, "error": "write_failed", "detail": str(e)}
    return {"success": True, "path": dest, "playlists": len(playlists), "favorites": len(favorites)}

def _playlist_id(pl):
    return str(pl.get("id") or pl.get("playlistId") or pl.get("browseId") or "")

@_with_lock
def import_playlists(src):
    """Merge a backup into the current playlists. Never deletes anything:
    unknown playlists are added, known ones (same id) gain the tracks they lack."""
    src = _to_local_path(src)
    if not src or not os.path.isfile(src):
        return {"success": False, "error": "not_found"}
    try:
        if os.path.getsize(src) > MAX_BACKUP_BYTES:
            return {"success": False, "error": "too_large"}
        with open(src, "r", encoding="utf-8-sig") as f:
            data = json.load(f)
    except Exception:
        return {"success": False, "error": "invalid_json"}

    # Our own backup format, or a raw copy of custom_playlists.json (a plain list)
    if isinstance(data, dict) and data.get("format") == BACKUP_FORMAT:
        in_pls = data.get("playlists") or []
        in_favs = data.get("favorites") or []
    elif isinstance(data, list):
        in_pls, in_favs = data, []
    else:
        return {"success": False, "error": "unsupported"}
    if not isinstance(in_pls, list) or not isinstance(in_favs, list):
        return {"success": False, "error": "unsupported"}

    playlists = load_playlists()
    by_id = {_playlist_id(p): p for p in playlists if isinstance(p, dict) and _playlist_id(p)}
    added = updated = tracks_added = 0
    now_ms = int(time.time() * 1000)

    for pl in in_pls:
        if not isinstance(pl, dict):
            continue
        tracks = [t for t in (pl.get("tracks") or []) if isinstance(t, (dict, str))]
        pid = _playlist_id(pl)
        existing = by_id.get(pid) if pid else None
        if existing is not None:
            have = {get_track_unique_key(t) for t in existing.get("tracks", [])}
            new_tracks = [t for t in tracks if get_track_unique_key(t) not in have]
            if new_tracks:
                existing.setdefault("tracks", []).extend(new_tracks)
                existing["trackCount"] = len(existing["tracks"])
                if not existing.get("customCover") and not existing.get("image"):
                    first = existing["tracks"][0]
                    existing["image"] = first.get("image", "") if isinstance(first, dict) else ""
                tracks_added += len(new_tracks)
                updated += 1
            continue
        if not pid:
            now_ms += 1
            pid = f"custom_pl_{now_ms}"
        title = str(pl.get("title") or pl.get("name") or "Playlist").strip() or "Playlist"
        entry = dict(pl)
        entry.update({
            "id": pid,
            "playlistId": pid,
            "title": title,
            "name": title,
            "isLocal": True,
            "isCustom": True,
            "type": pl.get("type") or "custom",
            "tracks": tracks,
            "trackCount": len(tracks),
        })
        entry.setdefault("createdAt", int(time.time()))
        if not entry.get("image"):
            first = tracks[0] if tracks else None
            entry["image"] = entry.get("customCover") or (first.get("image", "") if isinstance(first, dict) else "")
        playlists.append(entry)
        by_id[pid] = entry
        added += 1

    favs = load_favorite_playlists()
    fav_ids = {_playlist_id(f) for f in favs if isinstance(f, dict)}
    favs_added = 0
    for fav in in_favs:
        if not isinstance(fav, dict):
            continue
        fid = _playlist_id(fav)
        if fid and fid not in fav_ids:
            favs.append(fav)
            fav_ids.add(fid)
            favs_added += 1

    if (added or updated) and not save_playlists(playlists):
        return {"success": False, "error": "write_failed"}
    if favs_added and not save_favorite_playlists(favs):
        return {"success": False, "error": "write_failed"}
    return {"success": True, "added": added, "updated": updated,
            "tracksAdded": tracks_added, "favoritesAdded": favs_added}

# ---------------------------------------------------------------------------
# HTTP: POST /api/playlists/<op> (route_dispatcher on Linux, auth_server on Windows).
# Every answer is a playlist write result: the op's own fields plus the playlists and favorites as they are
# on disk after the op, read under the same lock, so the QML store can replace its optimistic patch.
# ---------------------------------------------------------------------------
def _op_list(body):
    return {"success": True}


def _op_create(body):
    tracks = body.get("tracks") or []
    if not isinstance(tracks, list):
        return {"success": False, "error": "invalid_tracks"}
    pl = create_playlist(str(body.get("title") or ""), tracks,
                         str(body.get("description") or ""), str(body.get("cover") or ""))
    return {"success": True, "playlist": pl}


def _op_rename(body):
    cover = body.get("cover") if "cover" in body else None
    desc = body.get("description") if "description" in body else None
    return rename_playlist(str(body.get("id") or ""), str(body.get("title") or ""),
                           None if desc is None else str(desc), None if cover is None else str(cover))


def _op_add(body):
    tracks = body.get("tracks")
    if isinstance(tracks, dict):
        tracks = [tracks]
    if not isinstance(tracks, list):
        return {"success": False, "error": "invalid_tracks"}
    return add_tracks_to_playlist(str(body.get("id") or ""), tracks)


def _op_remove(body):
    track = body.get("track")
    if track in (None, ""):
        return {"success": False, "error": "no_track"}
    return remove_track_from_playlist(str(body.get("id") or ""), track)


def _op_reorder(body):
    try:
        return reorder_tracks(str(body.get("id") or ""), int(body.get("from")), int(body.get("to")))
    except (TypeError, ValueError):
        return {"success": False, "error": "Invalid indices"}


def _op_delete(body):
    pl_id = str(body.get("id") or "")
    if not pl_id:
        return {"success": False, "error": "Playlist not found"}
    return delete_playlist(pl_id)


def _op_toggle_favorite(body):
    res = toggle_favorite_playlist(body.get("playlist"))
    res.pop("favorites", None)
    return res


HTTP_OPS = {
    "list": _op_list,
    "list_favorites": _op_list,
    "create": _op_create,
    "rename": _op_rename,
    "add": _op_add,
    "remove": _op_remove,
    "reorder": _op_reorder,
    "delete": _op_delete,
    "toggle_favorite": _op_toggle_favorite,
}


def handle_http(op, body):
    """Run one playlist op for an HTTP request. Returns (status_code, response_dict)."""
    handler = HTTP_OPS.get(op)
    if handler is None:
        return 404, {"success": False, "error": f"unknown_op: {op}"}
    if not isinstance(body, dict):
        body = {}
    try:
        with profile_scope(body.get("profile", "")), locked():
            res = handler(body)
            res["playlists"] = load_playlists()
            res["favorites"] = load_favorite_playlists()
    except TimeoutError:
        return 503, {"success": False, "error": "busy"}
    except Exception as e:
        sys.stderr.write(f"Playlist op {op} failed: {e}\n")
        return 500, {"success": False, "error": "internal", "detail": str(e)}
    return (200 if res.get("success") else 400), res


def handle_http_path(handler, path, body):
    """Shared by both routers: path is /api/playlists/<op>."""
    status, res = handle_http(path.rstrip("/").rsplit("/", 1)[-1], body)
    handler._send_json(res, status)


def handle_cli(args=None):
    if args is None:
        args = sys.argv[1:] if len(sys.argv) > 1 else []
    cmd = args[0] if len(args) > 0 else "list"

    if cmd == "list":
        print(json.dumps(load_playlists(), ensure_ascii=False))
    elif cmd == "list_favorites":
        print(json.dumps(load_favorite_playlists(), ensure_ascii=False))
    elif cmd == "toggle_favorite" and len(args) > 1:
        print(json.dumps(toggle_favorite_playlist(args[1]), ensure_ascii=False))
    elif cmd == "remove_favorite" and len(args) > 1:
        print(json.dumps(remove_favorite_playlist(args[1]), ensure_ascii=False))
    elif cmd == "create" and len(args) > 1:
        title = args[1]
        trks = args[2] if len(args) > 2 else None
        desc = args[3] if len(args) > 3 else ""
        cover = args[4] if len(args) > 4 else ""
        print(json.dumps(create_playlist(title, trks, desc, cover), ensure_ascii=False))
    elif cmd == "rename" and len(args) > 2:
        pl_id = args[1]
        new_title = args[2]
        desc = args[3] if len(args) > 3 else None
        cover = args[4] if len(args) > 4 else None
        print(json.dumps(rename_playlist(pl_id, new_title, desc, cover), ensure_ascii=False))
    elif cmd == "set_cover" and len(args) > 2:
        pl_id = args[1]
        cover_path = args[2]
        print(json.dumps(set_playlist_cover(pl_id, cover_path), ensure_ascii=False))
    elif cmd == "reorder" and len(args) > 3:
        pl_id = args[1]
        f_idx = int(args[2])
        t_idx = int(args[3])
        print(json.dumps(reorder_tracks(pl_id, f_idx, t_idx), ensure_ascii=False))
    elif cmd == "delete" and len(args) > 1:
        print(json.dumps(delete_playlist(args[1]), ensure_ascii=False))
    elif cmd == "add" and len(args) > 2:
        print(json.dumps(add_tracks_to_playlist(args[1], args[2]), ensure_ascii=False))
    elif cmd == "export" and len(args) > 1:
        print(json.dumps(export_playlists(args[1]), ensure_ascii=False))
    elif cmd == "import" and len(args) > 1:
        print(json.dumps(import_playlists(args[1]), ensure_ascii=False))
    elif cmd == "remove" and len(args) > 2:
        print(json.dumps(remove_track_from_playlist(args[1], args[2]), ensure_ascii=False))
    else:
        print(json.dumps(load_playlists(), ensure_ascii=False))

def main():
    handle_cli(sys.argv[1:] if len(sys.argv) > 1 else [])

if __name__ == "__main__":
    main()

