#!/usr/bin/env python3
"""Nutsty disk cache manager: usage report, size limit (LRU eviction) and one-click cleanup.

CLI (Linux subprocess and Windows in-process via handle_cli):
    cache_manager.py usage            -> {"total": bytes, "audio": .., "images": .., "lyrics": .., "other": .., "limitMb": n}
    cache_manager.py enforce [mb]     -> trims the oldest audio until the cache fits the limit
    cache_manager.py clear            -> removes audio and temporary data, then reports usage

Never touched: sign-in sessions (browser_auth*), listening history and library files
(including the library's cover thumbnails)
(online_tracks*, pending_history*, local_yt_mappings), tokens, and lyrics (they hold the
user's manually picked lyric sources).
"""
import fnmatch
import json
import os
import shutil
import sys
import time

try:
    from . import platform_compat as pc
except ImportError:
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    import platform_compat as pc

LIMIT_CHOICES_MB = (1024, 1536, 2048)
DEFAULT_LIMIT_MB = 1536
# Large, re-downloadable media: evicted oldest-first by the size limit.
# "thumbnails" holds the library's own cover art (paths saved in library.json), so it is never evicted.
EVICTABLE_DIRS = ("audio_cache", "mpv_stream_cache")
# Extra regenerable data removed by "clear" (not by the limit)
CLEAR_DIRS = ("related", "moods", "beatgrid")
CLEAR_FILES = ("stream_cache.json",)
CLEAR_GLOBS = ("*.tmp",)
RECENT_GUARD_SEC = 600  # never evict files touched in the last 10 minutes (current / next track)
CATEGORY_DIRS = {"audio": ("audio_cache", "mpv_stream_cache"), "images": ("thumbnails",), "lyrics": ("lyrics",)}


def _root():
    return pc.get_cache_dir()


def _dir_size(path):
    total = 0
    for base, _dirs, files in os.walk(path):
        for name in files:
            try:
                total += os.path.getsize(os.path.join(base, name))
            except OSError:
                pass
    return total


def _settings():
    suffix = pc.get_profile_suffix() if hasattr(pc, "get_profile_suffix") else ""
    for name in (f"nutsty_settings{suffix}.json", "nutsty_settings.json"):
        try:
            with open(os.path.join(pc.get_config_dir(), name), "r", encoding="utf-8") as f:
                return json.load(f)
        except Exception:
            continue
    return {}


def normalize_limit_mb(value):
    try:
        mb = int(float(value))
    except (TypeError, ValueError):
        return DEFAULT_LIMIT_MB
    return min(LIMIT_CHOICES_MB, key=lambda c: abs(c - mb))


def get_limit_mb():
    return normalize_limit_mb(_settings().get("cacheLimitMb", DEFAULT_LIMIT_MB))


def get_usage():
    root = _root()
    total = _dir_size(root)
    out = {"total": total, "limitMb": get_limit_mb()}
    known = 0
    for cat, dirs in CATEGORY_DIRS.items():
        size = sum(_dir_size(os.path.join(root, d)) for d in dirs)
        out[cat] = size
        known += size
    out["other"] = max(0, total - known)
    return out


def enforce_limit(limit_mb=None):
    """Delete the least recently used media until the whole cache fits in 90% of the limit."""
    limit = normalize_limit_mb(limit_mb) if limit_mb is not None else get_limit_mb()
    root = _root()
    total = _dir_size(root)
    budget = limit * 1024 * 1024
    if total <= budget:
        return {"removed": 0, "freed": 0}
    target = int(budget * 0.9)
    now = time.time()
    files = []
    for d in EVICTABLE_DIRS:
        base = os.path.join(root, d)
        if not os.path.isdir(base):
            continue
        for entry in os.scandir(base):
            try:
                if not entry.is_file() or entry.name.endswith(".tmp"):
                    continue
                st = entry.stat()
                used = max(st.st_atime, st.st_mtime)
                if now - used < RECENT_GUARD_SEC:
                    continue
                files.append((used, entry.path, st.st_size))
            except OSError:
                pass
    files.sort()
    removed = freed = 0
    for _used, path, size in files:
        if total <= target:
            break
        try:
            os.remove(path)  # a file still open on Windows raises and is simply skipped
            total -= size
            freed += size
            removed += 1
        except OSError:
            pass
    return {"removed": removed, "freed": freed}


def _remove_tree_contents(path):
    if not os.path.isdir(path):
        return
    for entry in os.scandir(path):
        try:
            if entry.is_dir(follow_symlinks=False):
                shutil.rmtree(entry.path, ignore_errors=True)
            else:
                os.remove(entry.path)
        except OSError:
            pass


def clear_cache():
    root = _root()
    for d in EVICTABLE_DIRS + CLEAR_DIRS:
        _remove_tree_contents(os.path.join(root, d))
    for name in CLEAR_FILES:
        try:
            os.remove(os.path.join(root, name))
        except OSError:
            pass
    now = time.time()
    for name in os.listdir(root):
        p = os.path.join(root, name)
        if any(fnmatch.fnmatch(name, g) for g in CLEAR_GLOBS) and os.path.isfile(p):
            try:
                if now - os.path.getmtime(p) > 60:  # leave writes still in flight
                    os.remove(p)
            except OSError:
                pass
    return get_usage()


def handle_cli(args):
    cmd = args[0] if args else "usage"
    if cmd == "enforce":
        enforce_limit(args[1] if len(args) > 1 else None)
        print(json.dumps(get_usage()))
    elif cmd == "clear":
        print(json.dumps(clear_cache()))
    else:
        print(json.dumps(get_usage()))
    sys.stdout.flush()


if __name__ == "__main__":
    handle_cli(sys.argv[1:])
