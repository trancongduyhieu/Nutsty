"""Account sync: keeps playlists, favorite playlists, liked songs, plays and listening progress the
same on every device signed in to one Nutsty cloud account (Cloudflare Worker, /api/sync/*).

How it works (no hook in the write paths, so playlist_manager, spotify_importer and the liked-song
writer stay as they are):
  1. Snapshot the local files and compare each item's hash with the last synced one. A changed or
     missing item is marked dirty with the time it was seen (that mark is the offline outbox).
  2. Pull what other devices changed since our cursor. A remote item wins unless our dirty copy is
     newer (last write wins on updated_at). Deletes arrive as tombstones.
  3. Push the dirty items, unsynced plays and the latest progress.

Local covers are sent as bytes and keyed by their sha1, because each device stores them at its own
path. Footgun: updated_at comes from device clocks; the Worker clamps times far in the future.
"""

import base64
import contextlib
import hashlib
import json
import os
import sys
import threading
import time
import uuid

try:
    from . import platform_compat as pc
    from . import playlist_manager as pm
    from . import database
    from . import cloud_relay_client as crc
except (ImportError, ValueError):
    import platform_compat as pc
    import playlist_manager as pm
    import database
    import cloud_relay_client as crc

STATE_VERSION = 1
PUSH_BATCH = 50
PUSH_BATCH_BYTES = 1_500_000
MAX_SYNC_COVER_BYTES = 700_000  # base64 grows it by a third; a D1 value holds 2 MB
MAX_PULL_PAGES = 20
PROGRESS_MAX_AGE_MS = 7 * 24 * 3600 * 1000
COVER_TOKEN = "nutsty-cover:"

_THREAD_LOCKS = {}
_THREAD_LOCKS_GUARD = threading.Lock()


def _now_ms():
    return int(time.time() * 1000)


def _suffix(profile):
    return pc.get_profile_suffix(profile, None)


def _state_path(suffix):
    return os.path.join(pc.get_config_dir(), f"nutsty_sync_state{suffix}.json")


def _load_state(suffix):
    try:
        with open(_state_path(suffix), "r", encoding="utf-8") as f:
            st = json.load(f)
        if isinstance(st, dict) and st.get("version") == STATE_VERSION:
            return st
    except Exception:
        pass
    return {"version": STATE_VERSION, "device_id": "dev_" + uuid.uuid4().hex[:16], "user_id": "",
            "cursor": 0, "known": {}, "covers": {}, "cover_hashes": {},
            "remote_progress": None, "last_sync": 0, "last_error": ""}


def _write_atomic(p, obj):
    tmp = p + ".tmp"
    try:
        with open(tmp, "w", encoding="utf-8") as f:
            json.dump(obj, f, ensure_ascii=False)
        os.replace(tmp, p)
    except Exception as e:
        sys.stderr.write(f"[AccountSync] save {os.path.basename(p)} failed: {e}\n")


def _save_state(suffix, st):
    _write_atomic(_state_path(suffix), st)


# On/off lives in its own file: a sync running while the switch flips saves the state file at its end
def _settings_path(suffix):
    return os.path.join(pc.get_config_dir(), f"nutsty_sync_settings{suffix}.json")


def is_enabled(profile=""):
    try:
        with open(_settings_path(_suffix(profile)), "r", encoding="utf-8") as f:
            return json.load(f).get("enabled", True) is not False
    except Exception:
        return True


def set_enabled(profile, enabled):
    """Off: this device keeps everything and stops sending and receiving. On again: the next sync merges
    what changed on both sides meanwhile (the outbox compares against what was last synced)."""
    on = bool(enabled)
    _write_atomic(_settings_path(_suffix(profile)), {"enabled": on})
    return {"success": True, "enabled": on}


# Progress has its own small file: it is written every few minutes while a sync may be running
def _progress_path(suffix):
    return os.path.join(pc.get_config_dir(), f"nutsty_sync_progress{suffix}.json")


def _load_progress(suffix):
    try:
        with open(_progress_path(suffix), "r", encoding="utf-8") as f:
            data = json.load(f)
        return data if isinstance(data, dict) else {}
    except Exception:
        return {}


@contextlib.contextmanager
def _sync_lock(suffix):
    """One sync per profile at a time, across threads and processes. Yields False when busy."""
    with _THREAD_LOCKS_GUARD:
        tlock = _THREAD_LOCKS.setdefault(suffix, threading.Lock())
    if not tlock.acquire(blocking=False):
        yield False
        return
    fh = None
    try:
        fh = open(os.path.join(pc.get_config_dir(), f"sync{suffix}.lock"), "a+b")
        try:
            if os.name == "nt":
                import msvcrt
                fh.seek(0)
                msvcrt.locking(fh.fileno(), msvcrt.LK_NBLCK, 1)
            else:
                import fcntl
                fcntl.flock(fh.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
        except OSError:
            yield False
            return
        try:
            yield True
        finally:
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
    finally:
        if fh:
            fh.close()
        tlock.release()


def _hash(obj):
    return hashlib.sha1(json.dumps(obj, sort_keys=True, ensure_ascii=False).encode("utf-8")).hexdigest()


def _identity(suffix):
    ident = crc.load_cloud_identity(suffix)
    if not ident:
        ident = crc.ensure_cloud_identity(suffix)
    if ident and ident.get("user_id") and ident.get("secret_key"):
        return ident
    return None


_server_outdated = False


def _call(endpoint, data):
    global _server_outdated
    if not crc.GLOBAL_RELAY_CLIENT.is_external():
        return None
    res = crc.GLOBAL_RELAY_CLIENT._http_request("POST", endpoint, data=data)
    # The relay answers but has no sync routes yet (Worker not deployed): not the same as no network
    _server_outdated = isinstance(res, dict) and res.get("error") == "Endpoint not found"
    return res


def _fail_code():
    return "server_outdated" if _server_outdated else "offline"


# ---------------------------------------------------------------------------
# Local items <-> sync items
# ---------------------------------------------------------------------------

def _cover_sha(st, path):
    try:
        stt = os.stat(path)
    except OSError:
        return ""
    key = f"{path}|{int(stt.st_mtime)}|{stt.st_size}"
    cached = st["cover_hashes"].get(path)
    if cached and cached.get("k") == key:
        return cached["sha"]
    try:
        with open(path, "rb") as f:
            sha = hashlib.sha1(f.read()).hexdigest()
    except OSError:
        return ""
    st["cover_hashes"][path] = {"k": key, "sha": sha}
    st["covers"][sha] = path
    return sha


def _canonical_playlist(st, pl):
    """Playlist as other devices see it: local cover paths become a content token."""
    out = {k: v for k, v in pl.items() if k not in ("coverFile",)}
    for key in ("customCover", "image"):
        ref = out.get(key)
        if pm._is_local_ref(ref):
            sha = _cover_sha(st, pm._to_local_path(ref))
            out[key] = (COVER_TOKEN + sha) if sha else ""
    return out


def _wire_playlist(st, canon):
    """Sync data for a playlist: the canonical form plus the cover bytes when they are small."""
    data = dict(canon)
    tok = str(canon.get("customCover") or "")
    if tok.startswith(COVER_TOKEN):
        path = st["covers"].get(tok[len(COVER_TOKEN):])
        try:
            if path and os.path.getsize(path) <= MAX_SYNC_COVER_BYTES:
                with open(path, "rb") as f:
                    data["coverFile"] = {"name": os.path.basename(path),
                                         "data": base64.b64encode(f.read()).decode("ascii")}
        except OSError:
            pass
    return data


def _localize_playlist(st, data):
    """Turn a pulled playlist back into this device's form (restore its cover file)."""
    pl = {k: v for k, v in data.items() if k != "coverFile"}
    for key in ("customCover", "image"):
        tok = str(pl.get(key) or "")
        if not tok.startswith(COVER_TOKEN):
            continue
        sha = tok[len(COVER_TOKEN):]
        path = st["covers"].get(sha)
        if not (path and os.path.isfile(path)):
            uri = pm._restore_cover(data.get("coverFile"), seq=len(st["covers"]))
            path = pm._to_local_path(uri) if uri else ""
            if path:
                st["covers"][sha] = path
                _cover_sha(st, path)
        if path:
            from pathlib import Path
            pl[key] = Path(path).resolve().as_uri()
        else:
            tracks = pl.get("tracks") or []
            pl[key] = (tracks[0].get("image", "") if tracks and isinstance(tracks[0], dict) else "")
    return pl


def _local_items(st):
    """{key: (kind, item_id, canonical_obj)} for everything kept as one sync item each."""
    items = {}
    with pm.locked():
        playlists = pm.load_playlists()
        favorites = pm.load_favorite_playlists()
        liked = pm._read_json(pm._liked_file(), {})
    for pl in playlists:
        pid = pm._playlist_id(pl) if isinstance(pl, dict) else ""
        if pid:
            items[f"playlist:{pid}"] = ("playlist", pid, _canonical_playlist(st, pl))
    for fav in favorites:
        fid = pm._playlist_id(fav) if isinstance(fav, dict) else ""
        if fid:
            items[f"favorite:{fid}"] = ("favorite", fid, fav)
    if isinstance(liked, dict):
        for vid, song in liked.items():
            if vid:
                items[f"liked:{vid}"] = ("liked", str(vid), song)
    return items


def _detect_changes(st, items):
    """Mark changed, new and removed items dirty in st["known"]. Returns the number marked."""
    now, marked = _now_ms(), 0
    known = st["known"]
    for key, (_kind, _iid, obj) in items.items():
        h = _hash(obj)
        k = known.get(key)
        if not k or k.get("del") or k.get("h") != h:
            known[key] = {"h": h, "t": now, "dirty": True}
            marked += 1
    for key, k in list(known.items()):
        if key.split(":", 1)[0] in ("playlist", "favorite", "liked") and key not in items and not k.get("del"):
            known[key] = {"h": "", "t": now, "dirty": True, "del": True}
            marked += 1
    return marked


def _apply_remote(st, remote):
    """Write pulled items into the local files in one locked load-modify-save per file."""
    changed = {"playlists": False, "favorites": False, "liked": False}
    by_kind = {"playlist": [], "favorite": [], "liked": []}
    for r in remote:
        by_kind[r["kind"]].append(r)
    if not any(by_kind.values()):
        return changed

    def parse(r):
        try:
            return json.loads(r.get("data") or "null")
        except Exception:
            return None

    with pm.locked():
        if by_kind["playlist"]:
            playlists = pm.load_playlists()
            index = {pm._playlist_id(p): i for i, p in enumerate(playlists) if isinstance(p, dict)}
            for r in by_kind["playlist"]:
                iid = r["item_id"]
                if r.get("deleted"):
                    if iid in index:
                        playlists[index[iid]] = None
                    continue
                data = parse(r)
                if not isinstance(data, dict):
                    continue
                pl = _localize_playlist(st, data)
                if iid in index and playlists[index[iid]] is not None:
                    playlists[index[iid]] = pl
                else:
                    index[iid] = len(playlists)
                    playlists.append(pl)
            pm.save_playlists([p for p in playlists if p is not None])
            changed["playlists"] = True
        if by_kind["favorite"]:
            favs = pm.load_favorite_playlists()
            index = {pm._playlist_id(f): i for i, f in enumerate(favs) if isinstance(f, dict)}
            for r in by_kind["favorite"]:
                iid = r["item_id"]
                data = None if r.get("deleted") else parse(r)
                if iid in index:
                    favs[index[iid]] = data if isinstance(data, dict) else None
                elif isinstance(data, dict):
                    index[iid] = len(favs)
                    favs.append(data)
            pm.save_favorite_playlists([f for f in favs if f is not None])
            changed["favorites"] = True
        if by_kind["liked"]:
            liked = pm._read_json(pm._liked_file(), {})
            if not isinstance(liked, dict):
                liked = {}
            for r in by_kind["liked"]:
                data = None if r.get("deleted") else parse(r)
                if data is None:
                    liked.pop(r["item_id"], None)
                else:
                    liked[r["item_id"]] = data
            pm._write_json(pm._liked_file(), liked)
            changed["liked"] = True
    return changed


# ---------------------------------------------------------------------------
# One sync round
# ---------------------------------------------------------------------------

def _pull(st, ident):
    """Pull pages after the cursor. Returns (file items to apply, remote plays) or None offline."""
    to_apply, plays = [], []
    for _ in range(MAX_PULL_PAGES):
        res = _call("/api/sync/pull", {"user_id": ident["user_id"], "secret_key": ident["secret_key"],
                                       "since": st["cursor"]})
        if not res or not res.get("success"):
            return None
        for r in res.get("items") or []:
            kind, iid = r.get("kind"), str(r.get("item_id") or "")
            if kind == "play":
                try:
                    p = json.loads(r.get("data") or "{}")
                    p["play_id"] = iid
                    plays.append(p)
                except Exception:
                    pass
                continue
            if kind == "progress":
                if r.get("device_id") != st["device_id"]:
                    try:
                        prog = json.loads(r.get("data") or "{}")
                        prog["updated_at"] = int(r.get("updated_at") or 0)
                        st["remote_progress"] = prog
                    except Exception:
                        pass
                continue
            if kind not in ("playlist", "favorite", "liked"):
                continue
            key = f"{kind}:{iid}"
            k = st["known"].get(key)
            t = int(r.get("updated_at") or 0)
            if k and k.get("dirty") and k.get("t", 0) >= t:
                continue  # our unsent change is newer: it will be pushed
            if k and not k.get("dirty") and k.get("t", 0) >= t:
                continue  # already have this version (our own echo)
            st["known"][key] = {"h": "", "t": t, "dirty": False, "del": bool(r.get("deleted"))}
            to_apply.append({"kind": kind, "item_id": iid, "data": r.get("data"), "deleted": r.get("deleted")})
        st["cursor"] = int(res.get("cursor") or st["cursor"])
        if not res.get("has_more"):
            break
    return to_apply, plays


def _push_items(ident, st, batch):
    res = _call("/api/sync/push", {"user_id": ident["user_id"], "secret_key": ident["secret_key"],
                                   "device_id": st["device_id"], "items": batch})
    if not res or not res.get("success"):
        return None
    return res.get("results") or []


def _push(st, ident, items):
    """Send dirty file items, unsynced plays and progress. Returns False when the cloud is unreachable."""
    pending = []
    for key, k in st["known"].items():
        if not k.get("dirty"):
            continue
        kind, iid = key.split(":", 1)
        if k.get("del"):
            pending.append((key, {"kind": kind, "item_id": iid, "deleted": True, "updated_at": k["t"]}))
            continue
        entry = items.get(key)
        if not entry:
            continue
        obj = _wire_playlist(st, entry[2]) if kind == "playlist" else entry[2]
        pending.append((key, {"kind": kind, "item_id": iid, "updated_at": k["t"],
                              "data": json.dumps(obj, ensure_ascii=False)}))

    batch, size = [], 0
    for idx, (key, it) in enumerate(pending):
        batch.append((key, it))
        size += len(it.get("data") or "")
        if len(batch) >= PUSH_BATCH or size >= PUSH_BATCH_BYTES or idx == len(pending) - 1:
            results = _push_items(ident, st, [b[1] for b in batch])
            if results is None:
                return False
            for (bkey, bit), r in zip(batch, results):
                k = st["known"].get(bkey)
                # Accepted, or the cloud already holds a newer copy that the next pull brings
                if k and k.get("t") == bit["updated_at"] and r.get("error") != "too_large":
                    k["dirty"] = False
            batch, size = [], 0

    while True:
        plays = database.unsynced_plays(100)
        if not plays:
            break
        wire = []
        for p in plays:
            pid = p.pop("play_id")
            stamp = _play_time_ms(p.get("timestamp")) + int(p.get("listened_ms") or 0)
            wire.append({"kind": "play", "item_id": pid, "updated_at": max(1, stamp),
                         "data": json.dumps(p, ensure_ascii=False)})
        if _push_items(ident, st, wire) is None:
            return False
        database.mark_plays_synced([w["item_id"] for w in wire],
                                   {w["item_id"]: int(json.loads(w["data"]).get("listened_ms") or 0) for w in wire})
        if len(plays) < 100:
            break

    return _push_progress(st["device_id"], ident, st["_suffix"])


def _push_progress(device_id, ident, suffix):
    prog = _load_progress(suffix).get("local")
    if not isinstance(prog, dict) or not prog.get("dirty"):
        return True
    stamp = prog.get("updated_at")
    data = {k: v for k, v in prog.items() if k not in ("dirty", "updated_at")}
    res = _call("/api/sync/push", {"user_id": ident["user_id"], "secret_key": ident["secret_key"],
                                   "device_id": device_id,
                                   "items": [{"kind": "progress", "item_id": "current", "updated_at": stamp,
                                              "data": json.dumps(data, ensure_ascii=False)}]})
    if not res or not res.get("success"):
        return False
    cur = _load_progress(suffix)  # re-read: a newer position may have landed meanwhile
    if isinstance(cur.get("local"), dict) and cur["local"].get("updated_at") == stamp:
        cur["local"]["dirty"] = False
        _write_atomic(_progress_path(suffix), cur)
    return True


def _play_time_ms(ts):
    try:
        from datetime import datetime, timezone
        return int(datetime.strptime(str(ts), "%Y-%m-%d %H:%M:%S").replace(tzinfo=timezone.utc).timestamp() * 1000)
    except Exception:
        return _now_ms()


def _offer(st):
    """Progress from another device worth offering ("continue listening"), or None."""
    rp = st.get("remote_progress")
    if not isinstance(rp, dict) or not rp.get("track"):
        return None
    t = int(rp.get("updated_at") or 0)
    pf = _load_progress(st["_suffix"])
    lp = pf.get("local") or {}
    if t <= int(lp.get("updated_at") or 0) or t <= int(pf.get("offered_at") or 0):
        return None
    if _now_ms() - t > PROGRESS_MAX_AGE_MS:
        return None
    trk = rp["track"]
    path = str(trk.get("path") or "")
    if not trk.get("videoId") and path and not path.startswith(("ytdl://", "http://", "https://")) \
            and not os.path.isfile(pm._to_local_path(path)):
        return None  # a file that lives only on the other device
    return rp


def sync_once(profile=""):
    suffix = _suffix(profile)
    if not is_enabled(profile):
        return {"success": False, "error": "disabled", "last_sync": _load_state(suffix).get("last_sync", 0)}
    with _sync_lock(suffix) as ok:
        if not ok:
            return {"success": False, "error": "busy"}
        with pm.profile_scope(profile):
            return _sync_locked(suffix)


def _sync_locked(suffix):
    st = _load_state(suffix)
    st["_suffix"] = suffix
    database.init_db()
    items = _local_items(st)
    _detect_changes(st, items)
    ident = _identity(suffix)
    if not ident:
        st.pop("_suffix", None)
        _save_state(suffix, st)
        return {"success": False, "error": "offline", "last_sync": st.get("last_sync", 0)}
    if st.get("user_id") != ident["user_id"]:
        # New account on this device (first sync, or just linked): start over and merge everything
        st.update({"user_id": ident["user_id"], "cursor": 0, "remote_progress": None})
        for k in st["known"].values():
            k["dirty"] = not k.get("del")
        st["known"] = {key: k for key, k in st["known"].items() if not k.get("del")}

    pulled = _pull(st, ident)
    if pulled is None:
        st["last_error"] = _fail_code()
        st.pop("_suffix", None)
        _save_state(suffix, st)
        return {"success": False, "error": st["last_error"], "last_sync": st.get("last_sync", 0)}
    to_apply, remote_plays = pulled
    changed = _apply_remote(st, to_apply)
    plays_added = database.merge_remote_plays(remote_plays)
    if any(changed.values()):
        # Remember what the applied items look like here, so the next round does not send them back
        items = _local_items(st)
        for r in to_apply:
            key = f"{r['kind']}:{r['item_id']}"
            k = st["known"].get(key)
            if k is not None:
                k["h"] = _hash(items[key][2]) if key in items else ""
                k["del"] = key not in items
    pushed = _push(st, ident, items)
    if pushed:
        st["last_sync"] = _now_ms()
        st["last_error"] = ""
    else:
        st["last_error"] = _fail_code()
    resume = _offer(st)
    st.pop("_suffix", None)
    _save_state(suffix, st)
    return {"success": bool(pushed), "error": st["last_error"], "changed": changed,
            "plays_added": plays_added, "last_sync": st["last_sync"], "resume": resume}


def record_progress(profile, track, position, duration, playing):
    """Remember where listening is and send it at once (one small row, last write wins)."""
    if not isinstance(track, dict) or not (track.get("videoId") or track.get("path") or track.get("id")):
        return {"success": False, "error": "no_track"}
    suffix = _suffix(profile)
    keep = ("videoId", "path", "id", "title", "name", "artist", "author", "album", "image", "cover",
            "artUrl", "thumbnail", "duration", "isLocal")
    st = _load_state(suffix)
    if not os.path.exists(_state_path(suffix)):
        _save_state(suffix, st)  # keep the new device_id
    pf = _load_progress(suffix)
    pf["local"] = {"track": {k: track.get(k) for k in keep if track.get(k) not in (None, "")},
                   "position": round(float(position or 0), 1), "duration": round(float(duration or 0), 1),
                   "playing": bool(playing), "updated_at": _now_ms(), "dirty": True}
    _write_atomic(_progress_path(suffix), pf)
    ident = crc.load_cloud_identity(suffix) if is_enabled(profile) else None
    sent = bool(ident) and _push_progress(st["device_id"], ident, suffix)
    return {"success": True, "sent": sent}


def dismiss_resume(profile, updated_at):
    suffix = _suffix(profile)
    pf = _load_progress(suffix)
    pf["offered_at"] = max(int(pf.get("offered_at") or 0), int(updated_at or 0))
    _write_atomic(_progress_path(suffix), pf)
    return {"success": True}


def status(profile=""):
    suffix = _suffix(profile)
    st = _load_state(suffix)
    ident = crc.load_cloud_identity(suffix) or {}
    dirty = sum(1 for k in st["known"].values() if k.get("dirty"))
    return {"success": True, "last_sync": st.get("last_sync", 0), "pending": dirty,
            "last_error": st.get("last_error", ""), "tag": ident.get("tag", ""),
            "device_id": st.get("device_id", ""), "enabled": is_enabled(profile)}


# ---------------------------------------------------------------------------
# Linking a second device to this account
# ---------------------------------------------------------------------------

def create_link_code(profile=""):
    ident = _identity(_suffix(profile))
    if not ident:
        return {"success": False, "error": "offline"}
    res = _call("/api/devices/link_code", {"user_id": ident["user_id"], "secret_key": ident["secret_key"]})
    if not res:
        return {"success": False, "error": "offline"}
    return res


def claim_link_code(profile, code):
    """Make this device use the account that showed `code`. Local data is merged on the next sync."""
    suffix = _suffix(profile)
    old = crc.load_cloud_identity(suffix) or {}
    res = _call("/api/devices/link_claim", {"code": str(code or ""), "old_user_id": old.get("user_id", ""),
                                            "old_secret_key": old.get("secret_key", "")})
    if not res:
        return {"success": False, "error": "offline"}
    if not res.get("success"):
        return {"success": False, "error": res.get("error") or "invalid_code"}
    u = res.get("user") or {}
    if old.get("user_id") == u.get("id"):
        return {"success": True, "tag": u.get("tag", ""), "already": True}
    ident = {"user_id": u.get("id"), "secret_key": res.get("secret_key"), "username": u.get("username", ""),
             "discriminator": u.get("discriminator", ""), "tag": u.get("tag", ""),
             "avatar_url": u.get("avatar_url", ""), "created_at": int(u.get("created_at") or _now_ms()),
             "custom_username": True}
    crc.save_cloud_identity(ident, suffix)
    set_enabled(profile, True)  # typing a code means this device should sync
    return {"success": True, "tag": ident["tag"]}


def detach_device(profile=""):
    """Give this device an account of its own (same name), keeping its data, which goes up to the new
    account on the next sync. The old account stays as it is for the other devices, friends and notes
    included. Needs the server: on failure this device stays on the old account."""
    suffix = _suffix(profile)
    with _sync_lock(suffix) as ok:
        if not ok:
            return {"success": False, "error": "busy"}
        old = crc.load_cloud_identity(suffix) or {}
        res = crc.GLOBAL_RELAY_CLIENT.register(username=old.get("username") or "Nutsty User",
                                               avatar_url=old.get("avatar_url") or "")
        u = (res or {}).get("user") or {}
        if not (res or {}).get("success") or not u.get("id") or not res.get("secret_key"):
            return {"success": False, "error": "offline"}
        ident = {"user_id": u["id"], "secret_key": res["secret_key"], "username": u.get("username", ""),
                 "discriminator": u.get("discriminator", ""), "tag": u.get("tag", ""),
                 "avatar_url": u.get("avatar_url", ""), "created_at": int(u.get("created_at") or _now_ms()),
                 "custom_username": bool(old.get("custom_username"))}
        crc.save_cloud_identity(ident, suffix)
        # The new account is empty: the next sync sends everything here (see _sync_locked)
        st = _load_state(suffix)
        st.update({"user_id": "", "cursor": 0, "remote_progress": None, "last_error": ""})
        _save_state(suffix, st)
        return {"success": True, "tag": ident["tag"]}


# ---------------------------------------------------------------------------
# HTTP: POST /api/sync/{run,status,progress,dismiss_resume,link_code,link_claim,set_enabled,detach}
# ---------------------------------------------------------------------------

def handle_http_path(handler, path, body):
    op = path.rstrip("/").rsplit("/", 1)[-1]
    body = body if isinstance(body, dict) else {}
    profile = str(body.get("profile") or "")
    try:
        if op == "run":
            res = sync_once(profile)
        elif op == "status":
            res = status(profile)
        elif op == "progress":
            res = record_progress(profile, body.get("track"), body.get("position"), body.get("duration"),
                                  body.get("playing"))
        elif op == "dismiss_resume":
            res = dismiss_resume(profile, body.get("updated_at"))
        elif op == "link_code":
            res = create_link_code(profile)
        elif op == "link_claim":
            res = claim_link_code(profile, body.get("code"))
        elif op == "set_enabled":
            res = set_enabled(profile, body.get("enabled"))
        elif op == "detach":
            res = detach_device(profile)
        else:
            handler._send_json({"success": False, "error": f"unknown_op: {op}"}, 404)
            return
    except Exception as e:
        sys.stderr.write(f"[AccountSync] {op} failed: {e}\n")
        res = {"success": False, "error": "internal", "detail": str(e)}
    if isinstance(res, dict) and res.get("error") == "Endpoint not found":
        res["error"] = "server_outdated"
    handler._send_json(res, 200)
