#!/usr/bin/env python3
"""
Two-way Spotify sync (docs/superpowers/specs/2026-11-25-spotify-two-way-sync-design.md).

Pull: the user's chosen Spotify playlists and liked songs flow into Nutsty, three-way merged
so a song removed in Nutsty is never re-added and an incomplete read never deletes anything.
Linked playlists keep a fixed id `custom_pl_spotify_{pid}` and a `spotifyLink` record that
account_sync carries to the user's other devices. The switch and liked-songs base are per device.
"""
import time

try:
    from . import playlist_manager as pm
except (ImportError, ValueError):
    import playlist_manager as pm

LINK_PREFIX = "custom_pl_spotify_"


def linked_id(pid):
    return f"{LINK_PREFIX}{pid}"


def match_item(item, match, cache, now=None):
    """Spotify item -> Nutsty track (with spotifyId) via the cache, calling `match` at most
    once per retry window. Returns None while the track stays unmatched."""
    now = time.time() if now is None else now
    sid = item.get("spotifyId")
    if not sid:
        return None
    hit = cache.get(sid)
    if hit and not hit.get("unmatched"):
        return dict(hit, spotifyId=sid)
    if not cache.should_retry(sid, now):
        return None
    try:
        found = match(item)
    except Exception:
        found = None
    if found and found.get("videoId"):
        found = dict(found, spotifyId=sid)
        cache.put(sid, found, now=now)
        return dict(found)
    cache.put(sid, None, now=now)
    return None


def migrate_legacy_imports(playlists, remote_by_pid, match, cache, now=None):
    """Turn the newest one-shot import of each Spotify playlist into a linked playlist (spec 5.1).
    Older duplicates stay as they are. Already linked pids and pids without a remote are skipped."""
    now = time.time() if now is None else now
    linked = {p.get("id") for p in playlists if isinstance(p, dict)}
    newest = {}
    for idx, pl in enumerate(playlists):
        if not isinstance(pl, dict) or pl.get("source") != "spotify_import" or pl.get("spotifyLink"):
            continue
        pid = pl.get("spotifyId")
        if not pid or pid not in remote_by_pid or linked_id(pid) in linked:
            continue
        if pid not in newest or (pl.get("createdAt") or 0) > (playlists[newest[pid]].get("createdAt") or 0):
            newest[pid] = idx

    for pid, idx in newest.items():
        pl = playlists[idx]
        remote = remote_by_pid[pid]
        tracks = list(pl.get("tracks") or [])
        by_video = {t.get("videoId"): t for t in tracks if isinstance(t, dict) and t.get("videoId")}
        base = []
        for item in remote.items:
            m = match_item(item, match, cache, now)
            if not m:
                continue
            base.append(item["spotifyId"])
            existing = by_video.get(m["videoId"])
            if existing is not None:
                existing["spotifyId"] = item["spotifyId"]
            else:
                tracks.append(m)
                by_video[m["videoId"]] = m
        new_id = linked_id(pid)
        pl.update({
            "id": new_id, "playlistId": new_id, "tracks": tracks, "trackCount": len(tracks),
            "spotifyLink": {"id": pid, "owned": False, "spotifyMade": False, "base": base,
                            "revision": remote.revision or "", "syncedAt": now, "unmatched": 0},
        })
    return playlists
