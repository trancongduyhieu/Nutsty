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
import base64
import glob
from pathlib import Path

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
    if new_cover is not None:
        prune_generated_covers()
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
    prune_generated_covers()
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
    prune_generated_covers()
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
# Backup: export / import custom + favorite playlists, liked songs and the
# downloaded-song list as one JSON file
# ---------------------------------------------------------------------------
BACKUP_FORMAT = "nutsty-playlists"
BACKUP_VERSION = 2  # v2 adds likedSongs + downloads; v1 files still import
MAX_BACKUP_BYTES = 50 * 1024 * 1024
# The custom_pl_ prefix is what makes the UI treat a playlist as local (PlaylistStore.isCustom);
# without it the playlist is opened as a YouTube one and shows up empty.
CUSTOM_ID_PREFIX = "custom_pl_"
DOWNLOADS_PLAYLIST_ID = CUSTOM_ID_PREFIX + "backup_downloads"
_LEGACY_DOWNLOADS_IDS = ("nutsty_backup_downloads",)
LIBRARY_JSON = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "library.json")
_DOWNLOAD_FIELDS = ("title", "artist", "album", "duration", "duration_ms", "image", "videoId", "path", "filename")


def _liked_file():
    return os.path.join(CONFIG_DIR, f"nutsty_liked_songs{_ACTIVE_SUFFIX.get()}.json")


def _read_json(path, default):
    try:
        with open(path, "r", encoding="utf-8") as f:
            data = json.load(f)
        return data if isinstance(data, type(default)) else default
    except Exception:
        return default


def _write_json(path, data):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    tmp = path + ".tmp"
    try:
        with open(tmp, "w", encoding="utf-8") as f:
            json.dump(data, f, ensure_ascii=False, indent=2)
        os.replace(tmp, path)
        return True
    except Exception as e:
        sys.stderr.write(f"Error writing {path}: {e}\n")
        return False


def _ui_is_vietnamese():
    settings = _read_json(os.path.join(CONFIG_DIR, f"nutsty_settings{_ACTIVE_SUFFIX.get()}.json"), {})
    return str(settings.get("language") or "vi").lower().startswith("vi")


def _lookup_video_id(title, artist):
    """YouTube Music match for a downloaded file that has no videoId (cached by stream_resolver)."""
    try:
        try:
            from .stream_resolver import resolve_video_id_for_track
        except (ImportError, ValueError):
            from stream_resolver import resolve_video_id_for_track
        return resolve_video_id_for_track("", title, artist) or ""
    except Exception as e:
        sys.stderr.write(f"videoId lookup failed for {title!r}: {e}\n")
        return ""


def _downloaded_tracks():
    """Every song in library.json. Each keeps its local path (plays the file when it is still there,
    e.g. after a reinstall) and a videoId (streams it on another computer). Files saved without a
    videoId get one looked up by title + artist, flagged videoIdMatched."""
    out = []
    for t in _read_json(LIBRARY_JSON, []):
        if not isinstance(t, dict) or not (t.get("title") or t.get("path")):
            continue
        item = {k: t[k] for k in _DOWNLOAD_FIELDS if t.get(k) not in (None, "")}
        item["name"] = item.get("title", "")
        if not str(item.get("videoId") or "").strip():
            vid = _lookup_video_id(item.get("title", ""), item.get("artist", ""))
            if vid:
                item["videoId"] = vid
                item["videoIdMatched"] = True
        out.append(item)
    return out


def _restore_download(t):
    """Backup entry -> playable track on this computer, or None."""
    local = str(t.get("path") or "")
    vid = str(t.get("videoId") or "").strip()
    track = dict(t)
    if local and not local.startswith("ytdl://") and os.path.isfile(local):
        return track
    if vid:
        track["path"] = "ytdl://" + vid
        return track
    return None

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


# ---------------------------------------------------------------------------
# Cover files: generated covers live in <config>/nutsty_covers. Files no playlist of any profile
# points to are removed; backups carry local cover images inline so they survive a move.
# ---------------------------------------------------------------------------
COVERS_DIRNAME = "nutsty_covers"
COVER_GRACE_SEC = 3600            # a cover just made in an open dialog is not referenced yet
MAX_EMBED_COVER_BYTES = 8 * 1024 * 1024
_COVER_EXTS = (".png", ".jpg", ".jpeg", ".webp")
_COVER_MAGIC = (b"\x89PNG", b"\xff\xd8\xff", b"RIFF")


def _covers_dir():
    return os.path.join(CONFIG_DIR, COVERS_DIRNAME)


def _is_local_ref(ref):
    r = str(ref or "").strip()
    return r.lower().startswith("file:") or (r != "" and os.path.isabs(os.path.expanduser(r)))


def _norm(path):
    return os.path.normcase(os.path.abspath(path))


def prune_generated_covers():
    """Delete files in nutsty_covers that no profile's playlist uses. Never raises."""
    try:
        folder = _covers_dir()
        if not os.path.isdir(folder):
            return 0
        used = set()
        for f in glob.glob(os.path.join(CONFIG_DIR, "custom_playlists*.json")):
            for pl in _read_json(f, []):
                if isinstance(pl, dict):
                    for key in ("customCover", "image"):
                        if _is_local_ref(pl.get(key)):
                            used.add(_norm(_to_local_path(pl.get(key))))
        removed, now = 0, time.time()
        for name in os.listdir(folder):
            path = os.path.join(folder, name)
            if not name.lower().endswith(_COVER_EXTS) or not os.path.isfile(path):
                continue
            if _norm(path) in used or now - os.path.getmtime(path) < COVER_GRACE_SEC:
                continue
            os.remove(path)
            removed += 1
        return removed
    except Exception as e:
        sys.stderr.write(f"Error pruning generated covers: {e}\n")
        return 0


def _embed_cover(pl):
    """Copy of a playlist with its local cover image inlined as base64 (others are returned as is)."""
    ref = pl.get("customCover") if isinstance(pl, dict) else None
    if not _is_local_ref(ref):
        return pl
    path = _to_local_path(ref)
    try:
        if not path.lower().endswith(_COVER_EXTS) or os.path.getsize(path) > MAX_EMBED_COVER_BYTES:
            return pl
        with open(path, "rb") as f:
            data = f.read()
    except OSError:
        return pl
    out = dict(pl)
    out["coverFile"] = {"name": os.path.basename(path), "data": base64.b64encode(data).decode("ascii")}
    return out


def _restore_cover(cover_file, seq=0):
    """Write a backup's inline cover into nutsty_covers; returns its file URL or ""."""
    if not isinstance(cover_file, dict):
        return ""
    ext = os.path.splitext(str(cover_file.get("name") or ""))[1].lower()
    if ext not in _COVER_EXTS:
        return ""
    try:
        data = base64.b64decode(str(cover_file.get("data") or ""), validate=True)
    except Exception:
        return ""
    if not data or len(data) > MAX_EMBED_COVER_BYTES or not data.startswith(_COVER_MAGIC):
        return ""
    folder = _covers_dir()
    try:
        os.makedirs(folder, exist_ok=True)
        path = os.path.join(folder, f"cover_{int(time.time() * 1000)}_{seq}{ext}")
        with open(path, "wb") as f:
            f.write(data)
    except OSError as e:
        sys.stderr.write(f"Error restoring cover: {e}\n")
        return ""
    return Path(path).resolve().as_uri()


def _local_cover_missing(pl):
    ref = pl.get("customCover")
    return _is_local_ref(ref) and not os.path.isfile(_to_local_path(ref))


def export_playlists(dest):
    dest = _to_local_path(dest)
    if not dest:
        return {"success": False, "error": "no_path"}
    if not dest.lower().endswith(".json"):
        dest += ".json"
    playlists = load_playlists()
    favorites = load_favorite_playlists()
    liked = _read_json(_liked_file(), {})
    downloads = _downloaded_tracks()
    payload = {
        "format": BACKUP_FORMAT,
        "version": BACKUP_VERSION,
        "app": "Nutsty",
        "appVersion": getattr(pc, "APP_VERSION", ""),
        "exportedAt": int(time.time()),
        "playlists": [_embed_cover(p) for p in playlists],
        "favorites": favorites,
        "likedSongs": liked,
        "downloads": downloads,
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
    return {"success": True, "path": dest, "playlists": len(playlists), "favorites": len(favorites),
            "likedSongs": len(liked), "downloads": len(downloads)}

def _playlist_id(pl):
    return str(pl.get("id") or pl.get("playlistId") or pl.get("browseId") or "")

@_with_lock
def import_playlists(src):
    """Merge a backup into the current playlists. Never deletes anything:
    unknown playlists are added, known ones (same id) gain the tracks they lack.
    Liked songs are merged into the liked list; the downloaded-song list becomes one
    playlist (fixed id, so importing twice only tops it up)."""
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
    in_liked, in_downloads = {}, []
    updated_legacy = False
    if isinstance(data, dict) and data.get("format") == BACKUP_FORMAT:
        in_pls = data.get("playlists") or []
        in_favs = data.get("favorites") or []
        in_liked = data.get("likedSongs") or {}
        in_downloads = data.get("downloads") or []
    elif isinstance(data, list):
        in_pls, in_favs = data, []
    else:
        return {"success": False, "error": "unsupported"}
    if not isinstance(in_pls, list) or not isinstance(in_favs, list):
        return {"success": False, "error": "unsupported"}
    if not isinstance(in_liked, dict):
        in_liked = {}
    if not isinstance(in_downloads, list):
        in_downloads = []

    in_pls = list(in_pls)
    dl_tracks = [r for r in (_restore_download(t) for t in in_downloads if isinstance(t, dict)) if r]
    downloads_skipped = len(in_downloads) - len(dl_tracks)
    if dl_tracks:
        title = "Bài hát đã tải (bản sao lưu)" if _ui_is_vietnamese() else "Downloaded songs (backup)"
        in_pls.append({"id": DOWNLOADS_PLAYLIST_ID, "title": title, "tracks": dl_tracks})

    playlists = load_playlists()
    # Undo the first version of this import, which saved the downloads playlist under an id
    # the UI did not treat as local
    for p in playlists:
        if isinstance(p, dict) and _playlist_id(p) in _LEGACY_DOWNLOADS_IDS:
            p["id"] = p["playlistId"] = DOWNLOADS_PLAYLIST_ID
            updated_legacy = True
    by_id = {_playlist_id(p): p for p in playlists if isinstance(p, dict) and _playlist_id(p)}
    added = updated = tracks_added = covers_restored = 0
    now_ms = int(time.time() * 1000)

    for pl in in_pls:
        if not isinstance(pl, dict):
            continue
        tracks = [t for t in (pl.get("tracks") or []) if isinstance(t, (dict, str))]
        cover_file = pl.get("coverFile")
        pid = _playlist_id(pl)
        if pid in _LEGACY_DOWNLOADS_IDS:
            pid = DOWNLOADS_PLAYLIST_ID
        elif pid and not pid.startswith(CUSTOM_ID_PREFIX):
            pid = CUSTOM_ID_PREFIX + pid
        existing = by_id.get(pid) if pid else None
        if existing is not None:
            # Same playlist already here: only bring the cover back if its file is gone
            if cover_file and _local_cover_missing(existing):
                url = _restore_cover(cover_file, covers_restored)
                if url:
                    _apply_cover(existing, url)
                    covers_restored += 1
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
        entry.pop("coverFile", None)
        url = _restore_cover(cover_file, covers_restored) if cover_file else ""
        if url:
            entry["customCover"] = url
            entry["image"] = url
            covers_restored += 1
        elif _local_cover_missing(entry):
            # Cover chosen on the other machine and not in the backup: fall back to the first track
            entry["customCover"] = ""
            entry["image"] = ""
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

    liked_added = 0
    if in_liked:
        liked = _read_json(_liked_file(), {})
        have_vids = {str(v.get("videoId")) for v in liked.values() if isinstance(v, dict) and v.get("videoId")}
        for key, song in in_liked.items():
            if not isinstance(song, dict) or key in liked:
                continue
            vid = str(song.get("videoId") or "")
            if vid and vid in have_vids:
                continue
            liked[key] = song
            if vid:
                have_vids.add(vid)
            liked_added += 1

    if (added or updated or updated_legacy or covers_restored) and not save_playlists(playlists):
        return {"success": False, "error": "write_failed"}
    if favs_added and not save_favorite_playlists(favs):
        return {"success": False, "error": "write_failed"}
    if liked_added and not _write_json(_liked_file(), liked):
        return {"success": False, "error": "write_failed"}
    return {"success": True, "added": added, "updated": updated,
            "tracksAdded": tracks_added, "favoritesAdded": favs_added, "likedAdded": liked_added,
            "coversRestored": covers_restored,
            "downloadsSkipped": downloads_skipped}

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

