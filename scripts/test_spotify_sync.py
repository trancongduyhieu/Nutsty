#!/usr/bin/env python3
"""
Tests for two-way Spotify sync (docs/superpowers/specs/2026-11-25-spotify-two-way-sync-design.md):
the web-player client, the three-way merge, per-device state, pull/push orchestration and the routes.

No network: every Spotify call goes through a fake transport or a fake client.
Runs against a temporary XDG_CONFIG_HOME, never the real ~/.config/noctalia.
Usage: python scripts/test_spotify_sync.py
"""
import json
import os
import sys
import tempfile
import unittest
from pathlib import Path

ROOT_DIR = Path(__file__).resolve().parent.parent
BACKEND_DIR = ROOT_DIR / "backend"
TMP_CONFIG = tempfile.mkdtemp(prefix="nutsty-spsync-test-")
os.environ["XDG_CONFIG_HOME"] = TMP_CONFIG
os.environ.pop("NUTSTY_PROFILE", None)
sys.path.insert(0, str(BACKEND_DIR))

CONFIG_DIR = Path(TMP_CONFIG) / "noctalia"


# ---------------------------------------------------------------------------
# Fake GraphQL payloads in the web-player shapes the client parses
# ---------------------------------------------------------------------------

def gql_track(sid, name=None, artist="Artist", dur=200000):
    return {
        "uri": f"spotify:track:{sid}",
        "name": name or f"Song {sid}",
        "artists": {"items": [{"profile": {"name": artist}}]},
        "albumOfTrack": {"name": "Album", "coverArt": {"sources": [{"url": f"https://i/{sid}.jpg"}]}},
        "trackDuration": {"totalMilliseconds": dur},
    }


def playlist_page(ids, total, offset, owner="spotify:user:me", revision="rev1"):
    return {"data": {"playlistV2": {
        "__typename": "Playlist",
        "name": "PL",
        "revisionId": revision,
        "ownerV2": {"data": {"uri": owner, "name": "Owner"}},
        "content": {
            "totalCount": total,
            "items": [{"uid": f"uid-{s}", "itemV2": {"data": gql_track(s)}} for s in ids],
        },
    }}}


class FakeTransport:
    """Answers by operationName. `script[op]` is a list of responses consumed in order
    (last one repeats); a response is (status, headers, body) or an Exception to raise."""

    def __init__(self, script):
        self.script = {k: list(v) for k, v in script.items()}
        self.calls = []

    def __call__(self, url, payload, headers):
        op = payload.get("operationName")
        self.calls.append((op, payload.get("variables")))
        queue = self.script[op]
        resp = queue.pop(0) if len(queue) > 1 else queue[0]
        if isinstance(resp, Exception):
            raise resp
        return resp


def ok(body):
    return (200, {}, body)


ME = ok({"data": {"me": {"profile": {"uri": "spotify:user:me", "username": "me", "name": "Me"}}}})


class WebClientTests(unittest.TestCase):
    def client(self, script):
        import spotify_web as sw
        t = FakeTransport(dict({"profileAttributes": [ME]}, **script))
        c = sw.SpotifyWebClient("cookie", transport=t, min_interval=0, token_provider=lambda: "tok",
                                client_token_provider=lambda: "ct")
        return c, t

    def test_paginates_until_total(self):
        ids = [f"t{i}" for i in range(220)]
        c, _ = self.client({"fetchPlaylist": [
            ok(playlist_page(ids[0:100], 220, 0)),
            ok(playlist_page(ids[100:200], 220, 100)),
            ok(playlist_page(ids[200:220], 220, 200)),
        ]})
        r = c.playlist_items("pl1")
        self.assertTrue(r.complete)
        self.assertEqual(len(r.items), 220)
        self.assertEqual(r.total, 220)
        self.assertEqual(r.revision, "rev1")
        self.assertEqual(r.items[0]["spotifyId"], "t0")
        self.assertEqual(r.items[0]["uid"], "uid-t0")
        self.assertEqual(r.items[0]["artist"], "Artist")
        self.assertEqual(r.items[0]["duration_ms"], 200000)

    def test_short_page_marks_incomplete(self):
        import spotify_web as sw
        ids = [f"t{i}" for i in range(200)]
        c, _ = self.client({"fetchPlaylist": [
            ok(playlist_page(ids[0:100], 200, 0)),
            sw.SpotifyNetworkError("boom"),
        ]})
        with self.assertRaises(sw.SpotifyNetworkError):
            c.playlist_items("pl1")

    def test_page_shorter_than_total_is_incomplete(self):
        ids = [f"t{i}" for i in range(50)]
        c, _ = self.client({"fetchPlaylist": [ok(playlist_page(ids, 120, 0)), ok(playlist_page([], 120, 50))]})
        r = c.playlist_items("pl1")
        self.assertFalse(r.complete)

    def test_429_raises_rate_limited_with_retry_after(self):
        import spotify_web as sw
        c, _ = self.client({"fetchPlaylist": [(429, {"Retry-After": "7"}, {})]})
        with self.assertRaises(sw.SpotifyRateLimited) as cm:
            c.playlist_items("pl1")
        self.assertEqual(cm.exception.retry_after, 7)
        self.assertEqual(cm.exception.code, "rate_limited")

    def test_persisted_query_not_found_maps_to_query_changed(self):
        import spotify_web as sw
        c, _ = self.client({"fetchPlaylist": [ok({"errors": [{"message": "PersistedQueryNotFound"}]})]})
        with self.assertRaises(sw.SpotifyQueryChanged) as cm:
            c.playlist_items("pl1")
        self.assertEqual(cm.exception.code, "query_changed")

    def test_401_maps_to_auth_expired(self):
        import spotify_web as sw
        c, _ = self.client({"fetchPlaylist": [(401, {}, {})]})
        with self.assertRaises(sw.SpotifyAuthError) as cm:
            c.playlist_items("pl1")
        self.assertEqual(cm.exception.code, "auth_expired")

    def test_empty_token_is_auth_expired(self):
        import spotify_web as sw
        c = sw.SpotifyWebClient("cookie", transport=FakeTransport({}), min_interval=0, token_provider=lambda: "")
        with self.assertRaises(sw.SpotifyAuthError):
            c.me()

    def test_spotify_made_flag(self):
        def lib_item(pid, owner):
            return {"item": {"__typename": "PlaylistResponseWrapper", "_uri": f"spotify:playlist:{pid}", "data": {
                "__typename": "Playlist", "name": pid, "revisionId": f"r-{pid}",
                "ownerV2": {"data": {"uri": owner, "name": owner.rsplit(':', 1)[-1]}},
                "images": {"items": [{"sources": [{"url": f"https://i/{pid}.jpg"}]}]},
            }}}
        body = {"data": {"me": {"libraryV3": {"totalCount": 3, "items": [
            lib_item("mine", "spotify:user:me"),
            lib_item("dw", "spotify:user:spotify"),
            lib_item("friend", "spotify:user:bob"),
            {"item": {"data": {"__typename": "Album", "uri": "spotify:album:x", "name": "x"}}},
        ]}}}}
        c, _ = self.client({"libraryV3": [ok(body)]})
        pls = {p["id"]: p for p in c.library_playlists()}
        self.assertEqual(set(pls), {"mine", "dw", "friend"})
        self.assertTrue(pls["mine"]["owned"])
        self.assertFalse(pls["mine"]["spotifyMade"])
        self.assertTrue(pls["dw"]["spotifyMade"])
        self.assertFalse(pls["dw"]["owned"])
        self.assertFalse(pls["friend"]["owned"])
        self.assertEqual(pls["mine"]["revision"], "r-mine")
        self.assertEqual(pls["mine"]["image"], "https://i/mine.jpg")

    def test_liked_items_parsed(self):
        body = {"data": {"me": {"library": {"tracks": {"totalCount": 2, "items": [
            {"track": {"_uri": "spotify:track:a", "data": dict(gql_track("a"), duration={"totalMilliseconds": 1000})}},
            {"track": {"_uri": "spotify:track:b", "data": gql_track("b")}},
        ]}}}}}
        c, _ = self.client({"fetchLibraryTracks": [ok(body)]})
        r = c.liked_items()
        self.assertTrue(r.complete)
        self.assertEqual([i["spotifyId"] for i in r.items], ["a", "b"])

    def test_search_tracks_parsed(self):
        body = {"data": {"searchV2": {"tracksV2": {"items": [
            {"item": {"data": dict(gql_track("s1", name="Hello"), duration={"totalMilliseconds": 180000})}},
        ]}}}}
        c, _ = self.client({"searchTracks": [ok(body)]})
        res = c.search_tracks("Hello", "Adele")
        self.assertEqual(res[0]["spotifyId"], "s1")
        self.assertEqual(res[0]["name"], "Hello")
        self.assertEqual(res[0]["duration_ms"], 180000)


class MergeTests(unittest.TestCase):
    def m(self, base, remote, local, write_back=False, unmatched=frozenset()):
        import spotify_sync_merge as sm
        return sm.three_way(list(base), list(remote), list(local), write_back, set(unmatched))

    def test_remote_add_pulled_in_remote_order(self):
        r = self.m("a", "acb", "a")
        self.assertEqual(r.pull_add, ["c", "b"])
        self.assertEqual(r.pull_remove, [])

    def test_remote_add_already_local_not_duplicated(self):
        r = self.m("a", "ab", "ab")
        self.assertEqual(r.pull_add, [])
        self.assertEqual(r.new_base, ["a", "b"])

    def test_remote_remove_pulled(self):
        r = self.m("ab", "a", "ab")
        self.assertEqual(r.pull_remove, ["b"])
        self.assertEqual(r.new_base, ["a"])

    def test_local_removal_not_readded(self):
        r = self.m("ab", "ab", "a", write_back=False)
        self.assertEqual(r.pull_add, [])
        self.assertEqual(r.push_remove, [])
        self.assertEqual(r.new_base, ["a", "b"])

    def test_local_removal_pushed_when_write_back(self):
        r = self.m("ab", "ab", "a", write_back=True)
        self.assertEqual(r.push_remove, ["b"])
        self.assertEqual(r.new_base, ["a"])

    def test_local_add_pushed_only_when_write_back(self):
        off = self.m("a", "a", "az", write_back=False)
        self.assertEqual(off.push_add, [])
        self.assertEqual(off.new_base, ["a"])
        on = self.m("a", "a", "az", write_back=True)
        self.assertEqual(on.push_add, ["z"])
        self.assertEqual(on.new_base, ["a", "z"])

    def test_both_removed_is_quiet(self):
        r = self.m("ab", "a", "a", write_back=True)
        self.assertEqual((r.pull_remove, r.push_remove), ([], []))
        self.assertEqual(r.new_base, ["a"])

    def test_unmatched_excluded_from_new_base(self):
        r = self.m("", "ax", "", unmatched={"x"})
        self.assertNotIn("x", r.new_base)
        self.assertEqual(r.pull_add, ["a", "x"])

    def test_incomplete_remote_rejected(self):
        import spotify_web as sw
        import spotify_sync_merge as sm
        self.assertTrue(sm.remote_is_valid(sw.RemoteList(items=[{}] * 3, total=3, complete=True)))
        self.assertFalse(sm.remote_is_valid(sw.RemoteList(items=[{}] * 3, total=3, complete=False)))
        self.assertFalse(sm.remote_is_valid(sw.RemoteList(items=[{}] * 2, total=3, complete=True)))
        self.assertFalse(sm.remote_is_valid(None))

    def test_mass_delete_guard(self):
        import spotify_sync_merge as sm
        self.assertTrue(sm.mass_delete_blocked(10, 6))
        self.assertFalse(sm.mass_delete_blocked(10, 5))
        self.assertFalse(sm.mass_delete_blocked(4, 3))
        self.assertTrue(sm.mass_delete_blocked(6, 4))


class StateTests(unittest.TestCase):
    def setUp(self):
        for f in CONFIG_DIR.glob("spotify_*"):
            f.unlink()

    def test_defaults_when_missing(self):
        import spotify_sync_state as st
        s = st.load_state()
        self.assertFalse(s["enabled"])
        self.assertFalse(s["selectionConfirmed"])
        self.assertIsNone(s["likedBase"])
        self.assertFalse(s["writeBack"])
        self.assertEqual(s["selected"], [])
        self.assertEqual(s["localBaseline"], {})

    def test_round_trip(self):
        import spotify_sync_state as st
        s = st.load_state()
        s.update(enabled=True, selected=["p1"], likedBase=["a"])
        st.save_state(s)
        again = st.load_state()
        self.assertTrue(again["enabled"])
        self.assertEqual(again["selected"], ["p1"])
        self.assertEqual(again["likedBase"], ["a"])

    def test_profile_isolation(self):
        import playlist_manager as pm
        import spotify_sync_state as st
        with pm.profile_scope("user2"):
            s = st.load_state()
            s["enabled"] = True
            st.save_state(s)
        self.assertFalse(st.load_state()["enabled"])
        self.assertTrue((CONFIG_DIR / "spotify_sync_state_user2.json").exists())
        self.assertFalse((CONFIG_DIR / "spotify_sync_state.json").exists())

    def test_match_cache_retry_window(self):
        import spotify_sync_state as st
        c = st.MatchCache()
        c.put("sx", None, now=1000.0)
        self.assertTrue(c.get("sx")["unmatched"])
        self.assertFalse(c.should_retry("sx", 1000.0 + 86400))
        self.assertTrue(c.should_retry("sx", 1000.0 + 3 * 86400 + 1))
        self.assertTrue(c.should_retry("never-seen", 1000.0))

    def test_match_cache_reverse_lookup_and_persist(self):
        import spotify_sync_state as st
        c = st.MatchCache()
        c.put("s1", {"videoId": "v1", "title": "T"})
        c.save()
        c2 = st.MatchCache()
        self.assertEqual(c2.get("s1")["videoId"], "v1")
        self.assertEqual(c2.find_by_video("v1"), "s1")
        self.assertIsNone(c2.find_by_video("nope"))
        self.assertFalse(c2.should_retry("s1", 0))


def sp_item(sid, name=None):
    return {"spotifyId": sid, "uid": f"u-{sid}", "name": name or f"Song {sid}", "artist": "Artist",
            "album": "Album", "duration_ms": 200000, "image": ""}


def remote_list(ids, revision="r1"):
    import spotify_web as sw
    items = [sp_item(s) for s in ids]
    return sw.RemoteList(items=items, total=len(items), revision=revision, complete=True)


class FakeMatcher:
    """Spotify id -> videoId 'v<sid>'; ids in `unmatched` return None."""

    def __init__(self, unmatched=()):
        self.unmatched = set(unmatched)
        self.calls = []

    def __call__(self, item):
        sid = item.get("spotifyId") or item.get("id")
        self.calls.append(sid)
        if sid in self.unmatched:
            return None
        vid = f"v{sid}"
        return {"title": item.get("name"), "artist": item.get("artist"), "album": "", "duration": 200,
                "videoId": vid, "path": f"ytdl://{vid}", "image": "", "source": "spotify_import",
                "spotifyId": sid}


def yt(vid, **kw):
    return dict({"title": vid, "artist": "A", "videoId": vid, "path": f"ytdl://{vid}"}, **kw)


def legacy(pid, ts, vids):
    pl_id = f"custom_pl_spotify_{pid}_{ts}"
    return {"id": pl_id, "playlistId": pl_id, "title": "Old", "name": "Old", "source": "spotify_import",
            "spotifyId": pid, "createdAt": ts, "tracks": [yt(v) for v in vids], "trackCount": len(vids)}


class MigrationTests(unittest.TestCase):
    def setUp(self):
        for f in CONFIG_DIR.glob("spotify_*"):
            f.unlink()

    def migrate(self, playlists, remote):
        import spotify_sync as ss
        import spotify_sync_state as st
        return ss.migrate_legacy_imports(playlists, {"P": remote}, FakeMatcher(), st.MatchCache())

    def test_newest_duplicate_becomes_linked(self):
        out = self.migrate([legacy("P", 100, ["va"]), legacy("P", 200, ["va"])], remote_list(["a"]))
        ids = [p["id"] for p in out]
        self.assertIn("custom_pl_spotify_P", ids)
        self.assertIn("custom_pl_spotify_P_100", ids)
        linked = next(p for p in out if p["id"] == "custom_pl_spotify_P")
        self.assertEqual(linked["createdAt"], 200)
        self.assertEqual(linked["playlistId"], "custom_pl_spotify_P")
        self.assertEqual(linked["spotifyLink"]["id"], "P")
        self.assertEqual(linked["spotifyLink"]["revision"], "r1")
        self.assertNotIn("spotifyLink", next(p for p in out if p["id"] == "custom_pl_spotify_P_100"))

    def test_tracks_get_spotify_id_by_video_match(self):
        out = self.migrate([legacy("P", 100, ["va", "vmanual"])], remote_list(["a"]))
        tracks = out[0]["tracks"]
        self.assertEqual(tracks[0]["spotifyId"], "a")
        self.assertNotIn("spotifyId", tracks[1])
        self.assertEqual(out[0]["spotifyLink"]["base"], ["a"])

    def test_missing_remote_tracks_appended(self):
        out = self.migrate([legacy("P", 100, ["va"])], remote_list(["a", "b", "c"]))
        self.assertEqual([t["videoId"] for t in out[0]["tracks"]], ["va", "vb", "vc"])
        self.assertEqual(out[0]["spotifyLink"]["base"], ["a", "b", "c"])
        self.assertEqual(out[0]["trackCount"], 3)

    def test_migration_idempotent(self):
        once = self.migrate([legacy("P", 100, ["va"])], remote_list(["a", "b"]))
        twice = self.migrate(json.loads(json.dumps(once)), remote_list(["a", "b"]))
        self.assertEqual(once, twice)

    def test_legacy_without_remote_left_alone(self):
        import spotify_sync as ss
        import spotify_sync_state as st
        pls = [legacy("Q", 100, ["va"])]
        out = ss.migrate_legacy_imports(json.loads(json.dumps(pls)), {}, FakeMatcher(), st.MatchCache())
        self.assertEqual(out, pls)


def lib(pid, owned=True, made=False, rev="r1"):
    return {"id": pid, "title": f"PL {pid}", "image": "", "ownerId": "me" if owned else ("spotify" if made else "bob"),
            "ownerName": "", "owned": owned, "spotifyMade": made, "revision": rev, "trackCount": 0}


class FakeClient:
    """Spotify stand-in. A playlist/liked value may be a RemoteList, an Exception, or a list of them
    consumed in order (last repeats). Writes are recorded in `writes` and applied to a RemoteList value;
    `write_error` raises on every write while set. `search` maps a title to candidate items."""

    def __init__(self, library=(), playlists=None, liked=None, error=None, search=None):
        self.library = list(library)
        self.playlists = dict(playlists or {})
        self.liked = liked if liked is not None else remote_list([])
        self.error = error
        self.search = dict(search or {})
        self.fetched = []
        self.searched = []
        self.writes = []
        self.write_error = None

    def me(self):
        return {"id": "me", "name": "Me"}

    def library_playlists(self):
        if self.error:
            raise self.error
        return [dict(p) for p in self.library]

    @staticmethod
    def _next(value):
        if isinstance(value, list):
            value = value.pop(0) if len(value) > 1 else value[0]
        if isinstance(value, Exception):
            raise value
        return value

    def playlist_items(self, pid):
        self.fetched.append(pid)
        return self._next(self.playlists[pid])

    def liked_items(self):
        return self._next(self.liked)

    def search_tracks(self, title, artist, limit=10):
        self.searched.append(title)
        return [dict(c) for c in self.search.get(title, [])]

    def _write(self, op, target, items, remote, mutate):
        if self.write_error:
            raise self.write_error
        self.writes.append((op, target, list(items)))
        if not isinstance(remote, list) and remote is not None and not isinstance(remote, Exception):
            mutate(remote)

    def add_to_playlist(self, pid, uris):
        ids = [u.rsplit(":", 1)[-1] for u in uris]
        self._write("add_to_playlist", pid, uris, self.playlists.get(pid),
                    lambda r: _grow(r, ids))

    def remove_from_playlist(self, pid, uids):
        self._write("remove_from_playlist", pid, uids, self.playlists.get(pid),
                    lambda r: _shrink(r, lambda i: i["uid"] in set(uids)))

    def add_to_library(self, uris):
        ids = [u.rsplit(":", 1)[-1] for u in uris]
        self._write("add_to_library", None, uris, self.liked, lambda r: _grow(r, ids))

    def remove_from_library(self, uris):
        ids = {u.rsplit(":", 1)[-1] for u in uris}
        self._write("remove_from_library", None, uris, self.liked,
                    lambda r: _shrink(r, lambda i: i["spotifyId"] in ids))


def _grow(remote, ids):
    remote.items.extend(sp_item(s) for s in ids)
    remote.total = len(remote.items)


def _shrink(remote, gone):
    remote.items[:] = [i for i in remote.items if not gone(i)]
    remote.total = len(remote.items)


class SyncCase(unittest.TestCase):
    NOW = 1_800_000_000.0

    def setUp(self):
        for f in CONFIG_DIR.glob("*"):
            if f.is_file():
                f.unlink()
        self.sleeps = []

    def enable(self, selected, liked=False, seen=None):
        import spotify_sync_state as st
        s = st.load_state()
        s.update(enabled=True, selectionConfirmed=True, selected=list(selected), likedSelected=liked,
                 seen=list(seen if seen is not None else selected))
        st.save_state(s)

    def sync(self, client, matcher=None, now=None):
        import spotify_sync as ss
        return ss.sync_once("", client=client, matcher=matcher or FakeMatcher(), now=now or self.NOW,
                            sleep=self.sleeps.append)

    def playlist(self, pid="P"):
        import playlist_manager as pm
        return next((p for p in pm.load_playlists() if p["id"] == f"custom_pl_spotify_{pid}"), None)

    def vids(self, pid="P"):
        return [t["videoId"] for t in self.playlist(pid)["tracks"]]

    def liked(self):
        import playlist_manager as pm
        return pm._read_json(pm._liked_file(), {})


class PullTests(SyncCase):
    def test_disabled_or_unconfirmed_does_nothing(self):
        import spotify_sync_state as st
        c = FakeClient([lib("P")], {"P": remote_list(["a"])})
        self.assertEqual(self.sync(c)["error"], "disabled")
        s = st.load_state()
        s["enabled"] = True
        st.save_state(s)
        self.assertEqual(self.sync(c)["error"], "disabled")
        self.assertEqual(c.fetched, [])
        self.assertIsNone(self.playlist())

    def test_creates_linked_playlist_with_fixed_id(self):
        self.enable(["P"])
        r = self.sync(FakeClient([lib("P")], {"P": remote_list(["a", "b"])}))
        self.assertTrue(r["success"])
        self.assertTrue(r["changed"]["playlists"])
        pl = self.playlist()
        self.assertEqual(self.vids(), ["va", "vb"])
        self.assertEqual(pl["spotifyLink"]["base"], ["a", "b"])
        self.assertTrue(pl["spotifyLink"]["owned"])
        self.assertEqual(pl["tracks"][0]["spotifyId"], "a")
        self.assertEqual(pl["trackCount"], 2)

    def test_unchanged_revision_skips_fetch(self):
        self.enable(["P"])
        c = FakeClient([lib("P")], {"P": remote_list(["a"])})
        self.sync(c)
        self.sync(c)
        self.assertEqual(c.fetched, ["P"])

    def test_truncated_fetch_removes_nothing(self):
        import spotify_web as sw
        self.enable(["P"])
        self.sync(FakeClient([lib("P")], {"P": remote_list(["a", "b"])}))
        cut = sw.RemoteList(items=[sp_item("a")], total=2, revision="r2", complete=False)
        self.sync(FakeClient([lib("P", rev="r2")], {"P": cut}))
        self.assertEqual(self.vids(), ["va", "vb"])

    def test_local_delete_survives_two_syncs(self):
        import playlist_manager as pm
        self.enable(["P"])
        self.sync(FakeClient([lib("P")], {"P": remote_list(["a", "b"])}))
        pls = pm.load_playlists()
        pl = next(p for p in pls if p["id"] == "custom_pl_spotify_P")
        pl["tracks"] = [t for t in pl["tracks"] if t["videoId"] != "vb"]
        pm.save_playlists(pls)
        for rev in ("r2", "r3"):
            self.sync(FakeClient([lib("P", rev=rev)], {"P": remote_list(["a", "b"], revision=rev)}))
            self.assertEqual(self.vids(), ["va"])

    def test_remote_remove_and_add_pulled(self):
        self.enable(["P"])
        self.sync(FakeClient([lib("P")], {"P": remote_list(["a", "b", "c", "d"])}))
        self.sync(FakeClient([lib("P", rev="r2")], {"P": remote_list(["a", "b", "c", "e"], revision="r2")}))
        self.assertEqual(self.vids(), ["va", "vb", "vc", "ve"])

    def test_unmatched_remote_add_retried_later(self):
        self.enable(["P"])
        c = FakeClient([lib("P")], {"P": remote_list(["a", "b"])})
        r = self.sync(c, FakeMatcher(unmatched={"b"}))
        self.assertEqual(r["unmatched"], 1)
        self.assertEqual(self.vids(), ["va"])
        fixed = FakeMatcher()
        self.sync(c, fixed, now=self.NOW + 86400)
        self.assertEqual(self.vids(), ["va"])
        self.assertNotIn("b", fixed.calls)
        self.sync(c, fixed, now=self.NOW + 3 * 86400 + 1)
        self.assertEqual(self.vids(), ["va", "vb"])

    def test_mass_delete_blocked_then_force_apply(self):
        import spotify_sync as ss
        import spotify_sync_state as st
        self.enable(["P"])
        self.sync(FakeClient([lib("P")], {"P": remote_list(list("abcdef"))}))
        c = FakeClient([lib("P", rev="r2")], {"P": remote_list(["a"], revision="r2")})
        r = self.sync(c)
        self.assertEqual(r["blocked"], ["P"])
        self.assertEqual(len(self.vids()), 6)
        self.assertEqual(st.load_state()["blocked"], ["P"])
        ss.force_apply("", "P")
        r = self.sync(c)
        self.assertEqual(r["blocked"], [])
        self.assertEqual(self.vids(), ["va"])
        self.assertEqual(st.load_state()["forceApply"], [])

    def test_spotify_made_replaced_wholesale_without_guard(self):
        self.enable(["D"])
        self.sync(FakeClient([lib("D", owned=False, made=True)], {"D": remote_list(list("abcdef"))}))
        r = self.sync(FakeClient([lib("D", owned=False, made=True, rev="r2")], {"D": remote_list(["x"], revision="r2")}))
        self.assertEqual(r["blocked"], [])
        self.assertEqual(self.vids("D"), ["vx"])

    def test_liked_first_run_is_baseline_only(self):
        import playlist_manager as pm
        import spotify_sync_state as st
        pm._write_json(pm._liked_file(), {"vz": yt("vz"), "va": yt("va")})
        self.enable([], liked=True)
        r = self.sync(FakeClient([], liked=remote_list(["a", "b"])))
        self.assertTrue(r["changed"]["liked"])
        liked = self.liked()
        self.assertEqual(set(liked), {"vz", "va", "vb"})
        self.assertEqual(liked["vb"]["spotifyId"], "b")
        self.assertEqual(liked["vb"]["path"], "ytdl://vb")
        self.assertIn("timestamp", liked["vb"])
        self.assertEqual(sorted(st.load_state()["likedBase"]), ["a", "b"])

    def test_liked_removal_after_baseline(self):
        self.enable([], liked=True)
        self.sync(FakeClient([], liked=remote_list(["a", "b"])))
        self.sync(FakeClient([], liked=remote_list(["a"])))
        self.assertEqual(set(self.liked()), {"va"})

    def test_auth_error_leaves_files_untouched(self):
        import spotify_web as sw
        import spotify_sync_state as st
        import playlist_manager as pm
        self.enable(["P"], liked=True)
        self.sync(FakeClient([lib("P")], {"P": remote_list(["a"])}, liked=remote_list(["a"])))
        before = {f.name: f.read_bytes() for f in CONFIG_DIR.glob("*.json") if "spotify_sync_state" not in f.name}
        r = self.sync(FakeClient(error=sw.SpotifyAuthError("x")))
        self.assertFalse(r["success"])
        self.assertEqual(r["error"], "auth_expired")
        after = {f.name: f.read_bytes() for f in CONFIG_DIR.glob("*.json") if "spotify_sync_state" not in f.name}
        self.assertEqual(before, after)
        self.assertEqual(st.load_state()["lastError"], "auth_expired")

    def test_error_mid_cycle_keeps_that_playlist_untouched(self):
        import spotify_web as sw
        self.enable(["P", "Q"])
        self.sync(FakeClient([lib("P"), lib("Q")], {"P": remote_list(["a"]), "Q": remote_list(["q"])}))
        r = self.sync(FakeClient([lib("P", rev="r2"), lib("Q", rev="r2")],
                                 {"P": remote_list(["a", "b"], revision="r2"), "Q": sw.SpotifyRateLimited("x", 5)}))
        self.assertEqual(r["error"], "rate_limited")
        self.assertEqual(self.vids("P"), ["va", "vb"])
        self.assertEqual(self.vids("Q"), ["vq"])

    def test_new_owned_playlist_auto_selected_spotify_made_not(self):
        import spotify_sync_state as st
        self.enable(["P"], seen=["P"])
        self.sync(FakeClient([lib("P"), lib("N"), lib("D", owned=False, made=True)],
                             {"P": remote_list(["a"]), "N": remote_list(["n"]), "D": remote_list(["d"])}))
        sel = st.load_state()["selected"]
        self.assertIn("N", sel)
        self.assertNotIn("D", sel)
        self.assertEqual(self.vids("N"), ["vn"])
        self.assertIsNone(self.playlist("D"))

    def test_list_choices_defaults_then_confirmed(self):
        import spotify_sync as ss
        c = FakeClient([lib("P"), lib("D", owned=False, made=True), lib("F", owned=False)])
        ch = ss.list_choices("", client=c)
        sel = {p["id"]: p["selected"] for p in ch["playlists"]}
        self.assertEqual(sel, {"P": True, "D": False, "F": False})
        self.assertTrue(ch["liked"])
        ss.set_selection("", ["D"], False)
        ch = ss.list_choices("", client=c)
        self.assertEqual({p["id"]: p["selected"] for p in ch["playlists"]}, {"P": False, "D": True, "F": False})
        self.assertFalse(ch["liked"])

    def test_playlist_list_cache_expires_after_6h(self):
        import time as _t
        import spotify_importer as si
        cached = CONFIG_DIR / "spotify_cached_playlists.json"
        CONFIG_DIR.mkdir(parents=True, exist_ok=True)
        orig = si.lyrics_helper.get_spotify_access_token
        si.lyrics_helper.get_spotify_access_token = lambda *a, **k: ""
        try:
            cached.write_text(json.dumps({"fetchedAt": _t.time() - 3600, "playlists": [{"id": "x"}]}))
            self.assertTrue(si.fetch_user_spotify_playlists(spdc="c")["success"])
            cached.write_text(json.dumps({"fetchedAt": _t.time() - 7 * 3600, "playlists": [{"id": "x"}]}))
            self.assertFalse(si.fetch_user_spotify_playlists(spdc="c")["success"])
            cached.write_text(json.dumps([{"id": "x"}]))
            self.assertFalse(si.fetch_user_spotify_playlists(spdc="c")["success"])
        finally:
            si.lyrics_helper.get_spotify_access_token = orig


def cand(sid, name, artist="A", dur=0):
    return {"spotifyId": sid, "name": name, "artist": artist, "album": "", "duration_ms": dur, "image": ""}


class PushTests(SyncCase):
    """Write-back (spec 5.6): only changes made after the switch goes on reach Spotify."""

    def write_back(self, on=True):
        import spotify_sync as ss
        return ss.set_write_back("", on, now=self.NOW)

    def edit_playlist(self, pid="P", drop=(), add=()):
        import playlist_manager as pm
        pls = pm.load_playlists()
        pl = next(p for p in pls if p["id"] == f"custom_pl_spotify_{pid}")
        pl["tracks"] = [t for t in pl["tracks"] if t["videoId"] not in set(drop)] + list(add)
        pm.save_playlists(pls)

    def set_liked(self, data):
        import playlist_manager as pm
        pm._write_json(pm._liked_file(), data)

    def owned_p(self, ids, search=None):
        self.enable(["P"])
        c = FakeClient([lib("P")], {"P": remote_list(ids)}, search=search)
        self.sync(c)
        return c

    def test_write_back_off_pushes_nothing(self):
        c = self.owned_p(["a", "b"], search={"New": [cand("n1", "New")]})
        self.edit_playlist(drop=["vb"], add=[yt("vn", title="New")])
        self.sync(c)
        self.assertEqual(c.writes, [])
        self.assertEqual(c.searched, [])

    def test_only_changes_after_switch_on_are_pushed(self):
        import spotify_sync_state as st
        self.set_liked({"vold": yt("vold", title="Old")})
        self.enable([], liked=True)
        c = FakeClient([], liked=remote_list([]),
                       search={"Old": [cand("o1", "Old")], "New": [cand("n1", "New")]})
        self.sync(c)
        self.write_back(True)
        self.set_liked(dict(self.liked(), vnew=yt("vnew", title="New")))
        self.sync(c)
        self.assertEqual(c.writes, [("add_to_library", None, ["spotify:track:n1"])])
        self.assertEqual(c.searched, ["New"])
        self.assertEqual(self.liked()["vnew"]["spotifyId"], "n1")
        self.assertEqual(st.load_state()["likedBase"], ["n1"])

    def test_removal_before_switch_on_not_pushed(self):
        c = self.owned_p(["a", "b"])
        self.edit_playlist(drop=["vb"])
        self.write_back(True)
        self.sync(c)
        self.assertEqual(c.writes, [])
        self.assertEqual(self.vids(), ["va"])

    def test_push_add_skips_track_already_remote(self):
        c = self.owned_p(["a"], search={"New": [cand("n1", "New")]})
        self.write_back(True)
        self.edit_playlist(add=[yt("vn", title="New")])
        c.playlists["P"] = [remote_list(["a"]), remote_list(["a", "n1"])]
        self.sync(c)
        self.assertEqual(c.writes, [])
        self.assertEqual(self.vids(), ["va", "vn"])
        self.assertEqual(self.playlist()["spotifyLink"]["base"], ["a", "n1"])

    def test_push_add_to_owned_playlist(self):
        c = self.owned_p(["a"], search={"New": [cand("n1", "New")]})
        self.write_back(True)
        self.edit_playlist(add=[yt("vn", title="New")])
        self.sync(c)
        self.assertEqual(c.writes, [("add_to_playlist", "P", ["spotify:track:n1"])])
        self.assertEqual(self.playlist()["spotifyLink"]["base"], ["a", "n1"])
        self.assertEqual(self.playlist()["tracks"][1]["spotifyId"], "n1")

    def test_unlike_pushes_remove_from_library(self):
        import spotify_sync_state as st
        self.enable([], liked=True)
        c = FakeClient([], liked=remote_list(["a", "b"]))
        self.sync(c)
        self.write_back(True)
        liked = self.liked()
        del liked["vb"]
        self.set_liked(liked)
        self.sync(c)
        self.assertEqual(c.writes, [("remove_from_library", None, ["spotify:track:b"])])
        self.assertEqual(st.load_state()["likedBase"], ["a"])
        self.assertEqual(set(self.liked()), {"va"})

    def test_remove_in_owned_playlist_uses_uid(self):
        c = self.owned_p(["a", "b"])
        self.write_back(True)
        self.edit_playlist(drop=["vb"])
        self.sync(c)
        self.assertEqual(c.writes, [("remove_from_playlist", "P", ["u-b"])])
        self.assertEqual(self.playlist()["spotifyLink"]["base"], ["a"])
        self.assertEqual(self.vids(), ["va"])

    def test_followed_playlist_never_written(self):
        self.enable(["F"])
        c = FakeClient([lib("F", owned=False)], {"F": remote_list(["a", "b"])},
                       search={"New": [cand("n1", "New")]})
        self.sync(c)
        self.write_back(True)
        self.edit_playlist("F", drop=["vb"], add=[yt("vn", title="New")])
        c.library = [lib("F", owned=False, rev="r2")]
        self.sync(c)
        self.assertEqual(c.writes, [])
        self.assertEqual(c.searched, [])

    def test_mass_local_delete_not_pushed(self):
        import spotify_sync_state as st
        c = self.owned_p(list("abcdef"))
        self.write_back(True)
        self.edit_playlist(drop=["va", "vb", "vc", "vd", "ve"])
        r = self.sync(c)
        self.assertEqual(c.writes, [])
        self.assertEqual(r["blocked"], ["P"])
        self.assertEqual(st.load_state()["blocked"], ["P"])

    def test_write_cap_30_per_cycle_rest_next_cycle(self):
        import spotify_sync_state as st
        self.enable([], liked=True)
        c = FakeClient([], liked=remote_list([]))
        self.sync(c)
        self.write_back(True)
        self.set_liked({f"v{i}": yt(f"v{i}", spotifyId=f"s{i}") for i in range(35)})
        self.sync(c)
        pushed = [u for op, _t, uris in c.writes for u in uris]
        self.assertEqual(len(pushed), 30)
        self.assertEqual(len(self.sleeps), len(c.writes) - 1)
        self.assertTrue(all(s >= 3 for s in self.sleeps))
        self.assertEqual(len(st.load_state()["likedBase"]), 30)
        self.sync(c)
        pushed = [u for op, _t, uris in c.writes for u in uris]
        self.assertEqual(len(pushed), 35)
        self.assertEqual(len(set(pushed)), 35)
        self.assertEqual(len(st.load_state()["likedBase"]), 35)

    def test_failed_write_not_in_base(self):
        import spotify_web as sw
        import spotify_sync_state as st
        self.enable([], liked=True)
        c = FakeClient([], liked=remote_list(["a"]))
        self.sync(c)
        self.write_back(True)
        self.set_liked(dict(self.liked(), vn=yt("vn", spotifyId="n")))
        c.write_error = sw.SpotifyRateLimited("slow down", 5)
        r = self.sync(c)
        self.assertEqual(r["error"], "rate_limited")
        self.assertEqual(st.load_state()["likedBase"], ["a"])
        c.write_error = None
        self.sync(c)
        self.assertEqual(c.writes, [("add_to_library", None, ["spotify:track:n"])])
        self.assertEqual(st.load_state()["likedBase"], ["a", "n"])

    def test_switch_off_mid_run_stops_pushing(self):
        import spotify_sync as ss
        import spotify_sync_state as st
        self.enable([], liked=True)
        c = FakeClient([], liked=remote_list([]))
        self.sync(c)
        self.write_back(True)
        self.set_liked({f"v{i}": yt(f"v{i}", spotifyId=f"s{i}") for i in range(25)})

        def sleep(sec):
            ss.set_write_back("", False, now=self.NOW)

        ss.sync_once("", client=c, matcher=FakeMatcher(), now=self.NOW, sleep=sleep)
        self.assertEqual(len(c.writes), 1)
        self.assertFalse(st.load_state()["writeBack"])

    def test_reverse_match_threshold(self):
        import spotify_sync as ss
        import spotify_sync_state as st
        cache = st.MatchCache()
        c = FakeClient(search={"My Song": [cand("x", "Totally Other", "Someone")]})
        self.assertIsNone(ss.reverse_match(yt("v1", title="My Song", artist="Me"), c, cache, now=self.NOW))
        self.assertTrue(cache.get("rev:yt_v1")["unmatched"])
        self.assertIsNone(ss.reverse_match(yt("v1", title="My Song", artist="Me"), c, cache, now=self.NOW + 60))
        self.assertEqual(c.searched, ["My Song"])
        c.search["Good"] = [cand("w", "Other"), cand("g", "Good", "Me", dur=200000)]
        self.assertEqual(ss.reverse_match(yt("v2", title="Good", artist="Me", duration=200), c, cache,
                                          now=self.NOW), "g")
        self.assertEqual(cache.find_by_video("v2"), "g")


class RouteTests(unittest.TestCase):
    def setUp(self):
        for f in CONFIG_DIR.glob("spotify_*"):
            f.unlink()

    def test_status_route_on_both_routers(self):
        import subprocess
        import threading
        import urllib.request
        import auth_server
        from http.server import ThreadingHTTPServer
        proc = subprocess.Popen([sys.executable, str(BACKEND_DIR / "route_dispatcher.py"), "--serve"],
                                stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True, env=os.environ.copy())
        try:
            proc.stdin.write(json.dumps({"method": "POST", "url": "/api/spotify/sync/status",
                                         "body": json.dumps({"profile": ""})}) + "\n")
            proc.stdin.flush()
            out = json.loads(proc.stdout.readline())
            self.assertEqual(out["status"], 200)
            self.assertFalse(json.loads(out["body"])["enabled"])
        finally:
            proc.stdin.close()
            proc.wait(timeout=10)
        httpd = ThreadingHTTPServer(("127.0.0.1", 0), auth_server.AuthWebhookHandler)
        threading.Thread(target=httpd.serve_forever, daemon=True).start()
        try:
            url = f"http://127.0.0.1:{httpd.server_address[1]}/api/spotify/sync/status"
            req = urllib.request.Request(url, data=b'{"profile": ""}',
                                         headers={"Content-Type": "application/json"}, method="POST")
            with urllib.request.urlopen(req, timeout=10) as resp:
                self.assertEqual(resp.status, 200)
                self.assertFalse(json.loads(resp.read())["enabled"])
        finally:
            httpd.shutdown()
            httpd.server_close()

    def test_status_names_blocked_lists(self):
        import spotify_sync as ss
        import spotify_sync_state as sstate
        import playlist_manager as pm
        pm.save_playlists([{"id": ss.linked_id("P1"), "title": "Road trip", "tracks": []}])
        st = sstate.load_state()
        st["blocked"] = ["P1", "liked", "GONE"]
        sstate.save_state(st)
        names = ss.status("")["blockedNames"]
        self.assertEqual(names, {"P1": "Road trip", "liked": "", "GONE": ""})

    def test_unknown_op_404(self):
        import spotify_sync as ss
        h = FakeHandler()
        ss.handle_http_path(h, "/api/spotify/sync/nope", {})
        self.assertEqual(h.sent[1], 404)

    def test_set_enabled_and_selection_ops(self):
        import spotify_sync as ss
        h = FakeHandler()
        ss.handle_http_path(h, "/api/spotify/sync/set_enabled", {"enabled": True})
        self.assertTrue(h.sent[0]["enabled"])
        ss.handle_http_path(h, "/api/spotify/sync/set_selection", {"ids": ["P"], "liked": False})
        self.assertTrue(h.sent[0]["selectionConfirmed"])
        self.assertEqual(h.sent[0]["selectedCount"], 1)
        ss.handle_http_path(h, "/api/spotify/sync/force_apply", {"id": "P"})
        self.assertEqual(h.sent[1], 200)
        ss.handle_http_path(h, "/api/spotify/sync/set_write_back", {"on": True})
        self.assertTrue(h.sent[0]["writeBack"])
        ss.handle_http_path(h, "/api/spotify/sync/set_write_back", {"on": False})
        self.assertFalse(h.sent[0]["writeBack"])


class FakeHandler:
    def __init__(self):
        self.sent = None

    def _send_json(self, data, status=200):
        self.sent = (data, status)


if __name__ == "__main__":
    unittest.main(verbosity=1)
