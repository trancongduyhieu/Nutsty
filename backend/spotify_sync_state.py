#!/usr/bin/env python3
"""
Per-device, per-profile state for Spotify sync (spec 5.2, 5.7).

Lives next to the playlists in the config dir and follows playlist_manager.profile_scope,
so each Nutsty profile on this machine keeps its own sync switch, baselines and cache.
None of this goes through account sync: a second device starts with a baseline-only run.
"""
import contextlib
import copy
import os
import threading
import time

try:
    from . import playlist_manager as pm
except (ImportError, ValueError):
    import playlist_manager as pm

UNMATCHED_RETRY_SEC = 3 * 86400

DEFAULT_STATE = {
    "enabled": False,
    "selectionConfirmed": False,
    "selected": [],          # Spotify playlist ids the user chose
    "likedSelected": True,
    "likedBase": None,       # Spotify ids agreed after the last liked-songs sync; None = never synced here
    "seen": [],              # Spotify playlist ids already offered; a new owned one gets auto-selected
    "writeBack": False,
    "writeBackSince": 0.0,
    "localBaseline": {},     # "liked" or playlist id -> Nutsty track keys at write-back switch-on
    "writeBackAbsent": {},   # "liked" or playlist id -> base ids already gone locally at switch-on (never pushed)
    "forceApply": [],
    "linked": [],            # Spotify playlist ids whose Nutsty copy existed here; deleting it unlinks
    "lastSync": 0.0,
    "lastError": "",
    "blocked": [],
    "unmatchedCount": 0,
    "backlog": {},
}


def _path(name):
    return os.path.join(pm.CONFIG_DIR, f"{name}{pm._ACTIVE_SUFFIX.get()}.json")


def load_state():
    data = pm._read_json(_path("spotify_sync_state"), {})
    state = copy.deepcopy(DEFAULT_STATE)
    for k, v in data.items():
        if k in state:
            state[k] = v
    return state


def save_state(state):
    return pm._write_json(_path("spotify_sync_state"), state)


# Every read-modify-write of the state file holds this, so a route and a running sync never
# overwrite each other's change. Never hold it across a network call.
STATE_LOCK = threading.RLock()


@contextlib.contextmanager
def edit_state():
    with STATE_LOCK:
        state = load_state()
        yield state
        save_state(state)


class MatchCache:
    """Spotify track id -> matched Nutsty track, or {"unmatched": True, "triedAt": t}."""

    def __init__(self):
        self.path = _path("spotify_match_cache")
        self.data = pm._read_json(self.path, {})
        self._by_video = None
        self.dirty = False

    def get(self, spotify_id):
        return self.data.get(spotify_id)

    def put(self, spotify_id, track, now=None):
        if track:
            self.data[spotify_id] = dict(track)
        else:
            self.data[spotify_id] = {"unmatched": True, "triedAt": time.time() if now is None else now}
        self._by_video = None
        self.dirty = True

    def should_retry(self, spotify_id, now):
        hit = self.data.get(spotify_id)
        if hit is None:
            return True
        if hit.get("unmatched"):
            return now - float(hit.get("triedAt") or 0) > UNMATCHED_RETRY_SEC
        return False

    def find_by_video(self, video_id):
        if self._by_video is None:
            self._by_video = {v.get("videoId"): k for k, v in self.data.items()
                              if isinstance(v, dict) and v.get("videoId")}
        return self._by_video.get(video_id)

    def save(self):
        if pm._write_json(self.path, self.data):
            self.dirty = False
