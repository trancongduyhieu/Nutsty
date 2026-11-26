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
        op = payload.get("operationName") or url
        self.calls.append((op, payload.get("variables")))
        self.bodies = getattr(self, "bodies", []) + [payload]
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

    def test_library_albums_parsed(self):
        node = {"__typename": "Album", "name": "SUMMERTIDE", "uri": "spotify:album:al1",
                "artists": {"items": [{"profile": {"name": "Alohaii"}}]},
                "coverArt": {"sources": [{"url": "https://i/al1.jpg"}]}}
        c, t = self.client({"libraryV3": [ok({"data": {"me": {"libraryV3": {
            "totalCount": 1, "items": [{"item": {"_uri": "spotify:album:al1", "data": node}}]}}}})]})
        out = c.library_albums()
        self.assertEqual(len(out), 1)
        a = out[0]
        self.assertEqual((a["id"], a["title"], a["kind"], a["ownerName"], a["image"]),
                         ("al1", "SUMMERTIDE", "album", "Alohaii", "https://i/al1.jpg"))
        self.assertFalse(a["owned"] or a["editable"] or a["spotifyMade"])
        self.assertEqual(t.calls[-1][1]["filters"], ["Albums"])

    def test_album_items_paginated_with_album_art(self):
        def page(ids, total):
            return ok({"data": {"albumUnion": {"__typename": "Album", "name": "AL",
                "coverArt": {"sources": [{"url": "https://i/al.jpg"}]},
                "tracksV2": {"totalCount": total, "items": [
                    {"uid": f"u-{s}", "track": {"uri": f"spotify:track:{s}", "name": f"Song {s}",
                     "artists": {"items": [{"profile": {"name": "Artist"}}]},
                     "duration": {"totalMilliseconds": 200000}}} for s in ids]}}}})
        c, _ = self.client({"getAlbum": [page(["a", "b"], 3), page(["c"], 3)]})
        r = c.album_items("al")
        self.assertEqual([i["spotifyId"] for i in r.items], ["a", "b", "c"])
        self.assertTrue(r.complete)
        self.assertEqual(r.total, 3)
        self.assertEqual((r.items[0]["album"], r.items[0]["image"], r.items[0]["duration_ms"]),
                         ("AL", "https://i/al.jpg", 200000))

    def test_album_gone_is_not_found(self):
        import spotify_web as sw
        c, _ = self.client({"getAlbum": [ok({"data": {"albumUnion": {"__typename": "NotFound"}}})]})
        with self.assertRaises(sw.SpotifyError) as cm:
            c.album_items("gone")
        self.assertEqual(cm.exception.code, "not_found")

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

    def test_add_to_playlist_sends_playlist_item_uris(self):
        c, t = self.client({"addToPlaylist": [ok({"data": {}})]})
        c.add_to_playlist("pl1", ["spotify:track:x"])
        op, variables = t.calls[-1]
        self.assertEqual(op, "addToPlaylist")
        self.assertEqual(variables["playlistItemUris"], ["spotify:track:x"])
        self.assertEqual(variables["playlistUri"], "spotify:playlist:pl1")

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

    def __init__(self, library=(), playlists=None, liked=None, error=None, search=None, albums=()):
        self.library = list(library)
        self.albums = list(albums)
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

    def library_albums(self):
        return [dict(a) for a in self.albums]

    def album_items(self, aid):
        self.fetched.append(aid)
        return self._next(self.playlists[aid])

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

    def rename_playlist(self, pid, name):
        if self.write_error:
            raise self.write_error
        self.writes.append(("rename_playlist", pid, name))
        for p in self.library:
            if p["id"] == pid:
                p["title"] = name

    def remove_from_playlist(self, pid, uids):
        self._write("remove_from_playlist", pid, uids, self.playlists.get(pid),
                    lambda r: _shrink(r, lambda i: i["uid"] in set(uids)))

    def add_to_library(self, uris):
        ids = [u.rsplit(":", 1)[-1] for u in uris]
        self._write("add_to_library", None, uris, self.liked, lambda r: _grow(r, ids))

    def remove_playlist(self, pid):
        if self.write_error:
            raise self.write_error
        self.writes.append(("remove_playlist", pid))
        self.library = [p for p in self.library if p["id"] != pid]

    def remove_from_library(self, uris):
        if any(u.startswith("spotify:album:") for u in uris):
            if self.write_error:
                raise self.write_error
            self.writes.append(("remove_album", None, list(uris)))
            gone = {u.rsplit(":", 1)[-1] for u in uris}
            self.albums = [a for a in self.albums if a["id"] not in gone]
            return
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


def album(aid):
    return {"id": aid, "title": f"AL {aid}", "image": "", "ownerId": "", "ownerName": "Band",
            "owned": False, "editable": False, "spotifyMade": False, "revision": "", "trackCount": 0,
            "kind": "album"}


class AlbumTests(SyncCase):
    """Saved albums are choices like playlists: pulled into a Nutsty playlist, never written back."""

    def test_album_offered_unpicked(self):
        import spotify_sync as ss
        c = FakeClient([lib("P")], albums=[album("AL")])
        ch = ss.list_choices("", client=c)
        by = {p["id"]: p for p in ch["playlists"]}
        self.assertTrue(by["P"]["selected"])
        self.assertFalse(by["AL"]["selected"])
        self.assertEqual(by["AL"]["kind"], "album")

    def test_picked_album_is_pulled(self):
        c = FakeClient([lib("P")], {"P": remote_list(["a"]), "AL": remote_list(["x", "y"])}, albums=[album("AL")])
        self.enable(["AL"], seen=["P", "AL"])
        self.sync(c)
        self.assertEqual(self.vids("AL"), ["vx", "vy"])
        self.assertEqual(self.playlist("AL")["title"], "AL AL")
        self.assertNotIn("P", c.fetched)

    def test_album_never_written_back(self):
        import spotify_sync as ss
        import playlist_manager as pm
        c = FakeClient([], {"AL": remote_list(["x"])}, albums=[album("AL")], search={"New": [cand("n1", "New")]})
        self.enable(["AL"])
        self.sync(c)
        ss.set_write_back("", True, now=self.NOW)
        pls = pm.load_playlists()
        rec = next(p for p in pls if p["id"] == "custom_pl_spotify_AL")
        rec["tracks"].append(yt("vnew", title="New"))
        pm.save_playlists(pls)
        self.sync(c, now=self.NOW + 10)
        self.assertEqual(c.writes, [])


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

    def test_list_made_on_spotify_after_switch_on_pushes_first_edit(self):
        # Two-way already on; a new Spotify playlist is pulled, then songs are added in Nutsty
        self.write_back(True)
        self.enable(["P"])
        c = FakeClient([lib("P")], {"P": remote_list(["a"])}, search={"New": [cand("n1", "New")]})
        self.sync(c)
        self.edit_playlist(add=[yt("vn", title="New")])
        c.library = [lib("P", rev="r2")]
        self.sync(c, now=self.NOW + 10)
        self.assertEqual(c.writes, [("add_to_playlist", "P", ["spotify:track:n1"])])

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
        self.sync(c, now=self.NOW + 6)  # after Spotify's Retry-After of 5 s
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

    def test_reverse_match_needs_the_artist(self):
        """A long YouTube title holding a short Spotify title ("PHONG" in "... Phong Max ...") is not
        a match unless an artist agrees: write-back would add the wrong song to the user's Spotify."""
        import spotify_sync as ss
        import spotify_sync_state as st
        cache = st.MatchCache()
        title = "05 (Không Phai) | @tangduytan  x T.R.I x Phong Max ( phiên bản Phong Max )"
        c = FakeClient(search={title: [cand("p", "PHONG", "VSTRA, TGSN, Tyronee")]})
        self.assertIsNone(ss.reverse_match(yt("v3", title=title, artist="Phong Max"), c, cache, now=self.NOW))
        # The artist named in the YouTube title counts as the artist
        c.search[title] = [cand("p", "PHONG", "VSTRA, TGSN, Tyronee"), cand("k", "05 (Không Phai)", "tangduytan, T.R.I")]
        self.assertEqual(ss.reverse_match(yt("v4", title=title, artist="Phong Max"), c, cache, now=self.NOW), "k")


class BacklogTests(SyncCase):
    """'Push earlier likes' (spec 5.6): likes that were in Nutsty before write-back went on."""

    def setup_liked(self, n, remote=()):
        import spotify_sync as ss
        self.enable([], liked=True)
        self.set_liked({f"v{i}": yt(f"v{i}", spotifyId=f"s{i}") for i in range(n)})
        c = FakeClient([], liked=remote_list(list(remote)))
        self.sync(c)
        ss.set_write_back("", True, now=self.NOW)
        return c

    def set_liked(self, data):
        import playlist_manager as pm
        pm._write_json(pm._liked_file(), data)

    def run_backlog(self, c, sleep=None):
        import spotify_sync as ss
        return ss.start_backlog("", client=c, sleep=sleep or self.sleeps.append, background=False)

    def test_backlog_pushes_pre_switch_likes(self):
        import spotify_sync as ss
        import spotify_sync_state as st
        c = self.setup_liked(12, remote=["s0"])
        self.run_backlog(c)
        pushed = [u for _op, _t, uris in c.writes for u in uris]
        self.assertEqual(sorted(pushed), sorted(f"spotify:track:s{i}" for i in range(1, 12)))
        self.assertTrue(all(op == "add_to_library" for op, _t, _u in c.writes))
        self.assertTrue(all(x >= 3 for x in self.sleeps))
        self.assertEqual(len(self.sleeps), len(c.writes) - 1)
        b = ss.status("")["backlog"]
        self.assertEqual((b["running"], b["done"], b["total"], b["unmatched"]), (False, 11, 11, 0))
        s = st.load_state()
        self.assertEqual(s["localBaseline"]["liked"], [])
        self.assertEqual(sorted(s["likedBase"]), sorted(f"s{i}" for i in range(12)))
        # nothing left to push on the next cycle
        before = len(c.writes)
        self.sync(c)
        self.assertEqual(len(c.writes), before)

    def test_backlog_cancel_stops_between_writes(self):
        import spotify_sync as ss
        import spotify_sync_state as st
        c = self.setup_liked(25)

        def sleep(sec):
            ss.cancel_backlog("")

        self.run_backlog(c, sleep=sleep)
        self.assertEqual(len(c.writes), 1)
        b = ss.status("")["backlog"]
        self.assertEqual((b["running"], b["done"], b["total"]), (False, 10, 25))
        self.assertEqual(len(st.load_state()["localBaseline"]["liked"]), 15)

    def test_backlog_requires_write_back_on(self):
        import spotify_sync as ss
        c = self.setup_liked(3)
        ss.set_write_back("", False, now=self.NOW)
        r = self.run_backlog(c)
        self.assertFalse(r["success"])
        self.assertEqual(r["error"], "write_back_off")
        self.assertEqual(c.writes, [])

    def test_backlog_counts_unmatched(self):
        import spotify_sync as ss
        self.enable([], liked=True)
        self.set_liked({"vx": yt("vx", title="Nowhere")})
        c = FakeClient([], liked=remote_list([]))
        self.sync(c)
        ss.set_write_back("", True, now=self.NOW)
        self.run_backlog(c)
        self.assertEqual(c.writes, [])
        b = ss.status("")["backlog"]
        self.assertEqual((b["done"], b["total"], b["unmatched"]), (0, 0, 1))

    def test_backlog_routes(self):
        import spotify_sync as ss
        h = FakeHandler()
        ss.handle_http_path(h, "/api/spotify/sync/backlog_start", {})
        self.assertEqual(h.sent[0]["error"], "write_back_off")
        ss.handle_http_path(h, "/api/spotify/sync/backlog_cancel", {})
        self.assertEqual(h.sent[1], 200)
        self.assertFalse(h.sent[0]["backlog"]["running"])


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


class AliasMatcher(FakeMatcher):
    """Like FakeMatcher, but ids in `alias` match the same YouTube video as another id."""

    def __init__(self, alias, unmatched=()):
        super().__init__(unmatched)
        self.alias = dict(alias)

    def __call__(self, item):
        out = super().__call__(item)
        sid = item.get("spotifyId")
        if out and sid in self.alias:
            vid = f"v{self.alias[sid]}"
            out.update(videoId=vid, path=f"ytdl://{vid}")
        return out


class FinalReviewTests(SyncCase):
    """Findings from the whole-branch review: each test reproduces one."""

    def write_back(self, on=True):
        import spotify_sync as ss
        return ss.set_write_back("", on, now=self.NOW)

    def sync(self, client, matcher=None, now=None):
        return super().sync(client, matcher or self.matcher, now)

    def setUp(self):
        super().setUp()
        self.matcher = FakeMatcher()

    # C1: two Spotify ids, one YouTube video
    def test_two_ids_same_video_playlist_never_removes_original(self):
        self.matcher = AliasMatcher({"s2": "s1"})
        self.enable(["P"])
        c = FakeClient([lib("P")], {"P": remote_list(["s1"])})
        self.sync(c)
        self.write_back(True)
        c.library, c.playlists["P"] = [lib("P", rev="r2")], remote_list(["s1", "s2"])
        self.sync(c)
        c.library = [lib("P", rev="r3")]
        self.sync(c)
        self.assertEqual(c.writes, [])
        self.assertEqual(self.vids(), ["vs1"])
        c.library, c.playlists["P"] = [lib("P", rev="r4")], remote_list(["s2"])
        self.sync(c)
        self.assertEqual(self.vids(), ["vs1"])
        self.assertEqual(c.writes, [])

    def test_two_ids_same_video_liked_never_unliked(self):
        self.matcher = AliasMatcher({"s2": "s1"})
        self.enable([], liked=True)
        c = FakeClient([], liked=remote_list(["s1"]))
        self.sync(c)
        self.write_back(True)
        c.liked = remote_list(["s1", "s2"])
        self.sync(c)
        self.sync(c)
        self.assertEqual(c.writes, [])
        c.liked = remote_list(["s2"])
        self.sync(c)
        self.assertIn("vs1", self.liked())
        self.assertEqual(c.writes, [])

    def test_two_ids_same_video_migration_keeps_both(self):
        import spotify_sync as ss
        import spotify_sync_state as st
        out = ss.migrate_legacy_imports([legacy("P", 100, ["va"])], {"P": remote_list(["a", "a2"])},
                                        AliasMatcher({"a2": "a"}), st.MatchCache())
        self.assertEqual([t["videoId"] for t in out[0]["tracks"]], ["va"])
        self.assertEqual(ss.track_ids(out[0]["tracks"][0]), ["a", "a2"])

    # I1: a list linked after write-back went on gets its own baseline
    def test_list_linked_after_switch_on_pushes_only_later_changes(self):
        import playlist_manager as pm
        pm.save_playlists([legacy("P", 100, ["va", "vgone"])])
        self.enable([])
        self.write_back(True)
        self.enable(["P"])
        c = FakeClient([lib("P")], {"P": remote_list(["a"])},
                       search={"vgone": [cand("g1", "vgone")], "New": [cand("n1", "New")]})
        self.sync(c)
        self.sync(c)
        self.assertEqual(c.writes, [])
        pls = pm.load_playlists()
        next(p for p in pls if p["id"] == "custom_pl_spotify_P")["tracks"].append(yt("vn", title="New"))
        pm.save_playlists(pls)
        self.sync(c)
        self.assertEqual(c.writes, [("add_to_playlist", "P", ["spotify:track:n1"])])
        self.assertEqual(self.playlist()["title"], "PL P")   # Spotify's later name, not pushed back

    # I2: the worker must not recycle itself while a sync or backlog holds the lock
    def test_worker_busy_while_sync_lock_held(self):
        import route_dispatcher as rd
        import spotify_sync as ss
        self.assertFalse(rd._background_busy())
        with ss._RUN_LOCK:
            self.assertTrue(rd._background_busy())

    # I3: one unreadable playlist does not stop the rest
    def test_unavailable_playlist_skipped_rest_synced(self):
        import spotify_web as sw
        self.enable(["P1", "P2"], liked=True)
        c = FakeClient([lib("P1"), lib("P2")],
                       {"P1": sw.SpotifyError("gone", code="not_found"), "P2": remote_list(["b"])},
                       liked=remote_list(["c"]))
        self.sync(c)
        self.assertEqual(self.vids("P2"), ["vb"])
        self.assertIn("vc", self.liked())

    # I6: a switch flipped while a run is in flight is not overwritten
    def test_list_choices_keeps_switch_flipped_meanwhile(self):
        import spotify_sync as ss
        import spotify_sync_state as st
        self.enable(["P"])
        self.write_back(True)

        class Racing(FakeClient):
            def library_playlists(inner):
                ss.set_write_back("", False)
                return super().library_playlists()
        ss.list_choices("", client=Racing([lib("P")]))
        self.assertFalse(st.load_state()["writeBack"])

    def test_selection_changed_during_sync_kept(self):
        import spotify_sync as ss
        import spotify_sync_state as st

        class Racing(FakeClient):
            def playlist_items(inner, pid):
                ss.set_selection("", ["Q"], False)
                ss.force_apply("", "Q")
                return super().playlist_items(pid)
        self.enable(["P"], liked=True)
        self.sync(Racing([lib("P")], {"P": remote_list(["a"])}))
        s = st.load_state()
        self.assertEqual(s["selected"], ["Q"])
        self.assertFalse(s["likedSelected"])
        self.assertIn("Q", s["forceApply"])

    # I7: a linked playlist deleted in Nutsty stays deleted
    def test_deleted_linked_playlist_not_recreated(self):
        import playlist_manager as pm
        import spotify_sync as ss
        import spotify_sync_state as st
        self.enable(["P"])
        c = FakeClient([lib("P")], {"P": remote_list(["a"])})
        self.sync(c)
        pm.save_playlists([p for p in pm.load_playlists() if p["id"] != "custom_pl_spotify_P"])
        c.library = [lib("P", rev="r2")]
        self.sync(c)
        self.assertIsNone(self.playlist())
        self.assertNotIn("P", st.load_state()["selected"])
        ss.set_selection("", ["P"], False)
        self.sync(c)
        self.assertEqual(self.vids(), ["va"])

    # I8: a cycle that changes nothing leaves the record as it was
    def test_unchanged_reread_keeps_record(self):
        self.matcher = FakeMatcher(unmatched={"b"})
        self.enable(["P"])
        c = FakeClient([lib("P")], {"P": remote_list(["a", "b"])})
        self.sync(c)
        before = self.playlist()
        self.sync(c, now=self.NOW + 100)
        self.assertEqual(c.fetched, ["P", "P"])
        self.assertEqual(self.playlist(), before)

    # I5: each profile uses its own Spotify cookie
    def test_profile_reads_its_own_cookie(self):
        import playlist_manager as pm
        import spotify_sync as ss
        (CONFIG_DIR / "nutsty_settings.json").write_text(json.dumps({"spotifySpdc": "A"}))
        (CONFIG_DIR / "nutsty_settings_user2.json").write_text(json.dumps({"spotifySpdc": "B"}))
        with pm.profile_scope("user2"):
            self.assertEqual(ss._default_client().spdc, "B")
        with pm.profile_scope(""):
            self.assertEqual(ss._default_client().spdc, "A")


class RemainingFixTests(SyncCase):
    """The deferred minors and I9, each reproduced."""

    def write_back(self, on=True):
        import spotify_sync as ss
        return ss.set_write_back("", on, now=self.NOW)

    def set_liked(self, data):
        import playlist_manager as pm
        pm._write_json(pm._liked_file(), data)

    # I9: a like that has been on Spotify is never re-added from a device that missed the unlike
    def test_like_seen_on_spotify_not_readded_by_other_device(self):
        import spotify_sync_state as st
        self.enable([], liked=True)
        c = FakeClient([], liked=remote_list(["z"]))
        self.sync(c)
        entry = self.liked()["vz"]
        self.assertTrue(entry.get("spotifySynced"))
        # device B: its own base never had z; the entry came over account sync; Spotify unliked z
        s = st.load_state()
        s["likedBase"] = []
        st.save_state(s)
        self.write_back(True)
        s = st.load_state()
        s["localBaseline"] = {"liked": []}
        st.save_state(s)
        c.liked = remote_list([])
        self.sync(c)
        self.assertEqual(c.writes, [])

    def test_pushed_like_marked_synced(self):
        self.enable([], liked=True)
        c = FakeClient([], liked=remote_list([]), search={"New": [cand("n1", "New")]})
        self.sync(c)
        self.write_back(True)
        self.set_liked({"vnew": yt("vnew", title="New")})
        self.sync(c)
        self.assertEqual(c.writes, [("add_to_library", None, ["spotify:track:n1"])])
        self.assertTrue(self.liked()["vnew"].get("spotifySynced"))

    # matcher network error: retried next cycle, not marked unmatched for 3 days
    def test_matcher_error_retried_next_cycle(self):
        class Flaky(FakeMatcher):
            def __call__(inner, item):
                if not inner.calls:
                    inner.calls.append(item["spotifyId"])
                    raise ConnectionError("offline")
                return super().__call__(item)
        self.matcher = Flaky()
        self.enable(["P"])
        c = FakeClient([lib("P")], {"P": remote_list(["a"])})
        self.sync(c)
        self.sync(c)
        self.assertEqual(self.vids(), ["va"])

    def sync(self, client, matcher=None, now=None):
        return super().sync(client, matcher or getattr(self, "matcher", None), now)

    def test_strict_matcher_raises_on_search_failure(self):
        import catalog_engine as ce
        import spotify_importer as si
        orig = ce.get_ytmusic_client

        def boom():
            raise ConnectionError("offline")
        ce.get_ytmusic_client = boom
        try:
            self.assertEqual(ce.filter_search("zz strict probe", "songs", limit=5), [])
            with self.assertRaises(Exception):
                ce.filter_search("zz strict probe 2", "songs", limit=5, strict=True)
        finally:
            ce.get_ytmusic_client = orig
        orig_fs = si.ytmusic_helper.filter_search

        def raising(*a, **kw):
            raise ConnectionError("offline")
        si.ytmusic_helper.filter_search = raising
        try:
            self.assertIsNone(si.match_spotify_track_to_ytmusic({"name": "X", "artist": "Y"}))
            with self.assertRaises(ConnectionError):
                si.match_spotify_track_to_ytmusic({"name": "X", "artist": "Y"}, strict=True)
        finally:
            si.ytmusic_helper.filter_search = orig_fs

    # _learn: an id cached as unmatched but carried by a track is that track's match
    def test_learn_overrides_unmatched_entry(self):
        import spotify_sync as ss
        import spotify_sync_state as st
        cache = st.MatchCache()
        cache.put("a", None, now=self.NOW)
        ss._learn(cache, [yt("va", spotifyId="a")], self.NOW)
        self.assertEqual(cache.get("a").get("videoId"), "va")

    # set_write_back(on) twice keeps the first baseline
    def test_write_back_on_twice_keeps_baseline(self):
        import spotify_sync_state as st
        self.set_liked({"vold": yt("vold", title="Old")})
        self.write_back(True)
        self.set_liked(dict(self.liked(), vnew=yt("vnew", title="New")))
        self.write_back(True)
        self.assertEqual(len(st.load_state()["localBaseline"]["liked"]), 1)

    # Retry-After: no Spotify call before the wait is over
    def test_rate_limit_waits_retry_after(self):
        import spotify_web as sw

        class Counting(FakeClient):
            calls = 0

            def library_playlists(inner):
                inner.calls += 1
                return super().library_playlists()
        self.enable(["P"])
        c = Counting([lib("P")], {"P": [sw.SpotifyRateLimited("slow", retry_after=600), remote_list(["a"])]})
        self.assertEqual(self.sync(c)["error"], "rate_limited")
        self.assertEqual(self.sync(c, now=self.NOW + 10)["error"], "rate_limited")
        self.assertEqual(c.calls, 1)
        self.assertTrue(self.sync(c, now=self.NOW + 601)["success"])
        self.assertEqual(self.vids(), ["va"])

    # two devices adding at once: re-read before each later add batch
    def test_add_batch_rechecks_spotify_first(self):
        import playlist_manager as pm
        self.enable(["P"])
        names = [f"N{i}" for i in range(11)]

        class Other(FakeClient):
            reads = 0

            def playlist_items(inner, pid):
                inner.reads += 1
                r = super().playlist_items(pid)
                if inner.reads == 4:  # before the second add batch: another device added N10
                    _grow(r, ["n10"])
                return r
        c = Other([lib("P")], {"P": remote_list(["a"])},
                  search={n: [cand(n.lower(), n)] for n in names})
        self.sync(c)
        self.write_back(True)
        pls = pm.load_playlists()
        next(p for p in pls if p["id"] == "custom_pl_spotify_P")["tracks"].extend(yt(f"v{n}", title=n) for n in names)
        pm.save_playlists(pls)
        c.reads = 1
        r = self.sync(c)
        added = [u for op, _t, uris in c.writes if op == "add_to_playlist" for u in uris]
        self.assertEqual(added.count("spotify:track:n10"), 0)
        self.assertEqual(len(added), 10)
        self.assertEqual(r["pushed"], 10)

    # pushed counts only what was written
    def test_pushed_counts_only_writes(self):
        self.enable(["P"])
        c = FakeClient([lib("P")], {"P": remote_list(["a"])}, search={"New": [cand("n1", "New")]})
        self.sync(c)
        self.write_back(True)
        import playlist_manager as pm
        pls = pm.load_playlists()
        next(p for p in pls if p["id"] == "custom_pl_spotify_P")["tracks"].append(yt("vn", title="New"))
        pm.save_playlists(pls)
        c.playlists["P"] = [remote_list(["a"]), remote_list(["a", "n1"])]
        self.assertEqual(self.sync(c)["pushed"], 0)

    # migration is saved even when that playlist is held back this cycle
    def test_migration_saved_when_blocked(self):
        import playlist_manager as pm
        import spotify_sync as ss
        pm.save_playlists([legacy("P", 100, ["va"])])
        self.enable(["P"])
        orig = ss._apply_playlist
        ss._apply_playlist = lambda *a, **kw: False
        try:
            self.sync(FakeClient([lib("P")], {"P": remote_list(["a"])}))
        finally:
            ss._apply_playlist = orig
        self.assertIsNotNone(self.playlist())

    # collaborative: a list the user may edit is written even when someone else owns it
    def test_collaborative_playlist_written(self):
        info = dict(lib("C", owned=False), editable=True)
        self.enable(["C"])
        c = FakeClient([info], {"C": remote_list(["a"])}, search={"New": [cand("n1", "New")]})
        self.sync(c)
        self.write_back(True)
        import playlist_manager as pm
        pls = pm.load_playlists()
        next(p for p in pls if p["id"] == "custom_pl_spotify_C")["tracks"].append(yt("vn", title="New"))
        pm.save_playlists(pls)
        self.sync(c)
        self.assertEqual(c.writes, [("add_to_playlist", "C", ["spotify:track:n1"])])

    # catalog_engine liked writes hold the playlist lock
    def test_liked_writes_hold_lock(self):
        import contextlib
        import catalog_engine as ce
        import playlist_manager as pm
        used = []
        orig = pm.locked

        @contextlib.contextmanager
        def rec():
            used.append(1)
            with orig():
                yield
        pm.locked = rec
        try:
            ce.add_liked_song("vx", "X", "Y")
            ce.remove_liked_song("vx", "X", "Y")
        finally:
            pm.locked = orig
        self.assertEqual(len(used), 2)


class TokenTests(unittest.TestCase):
    """I5 / C2: the access token belongs to one cookie, and an anonymous one is not a login."""

    def setUp(self):
        import lyrics_helper as lh
        self.lh = lh
        self.orig = lh._http_get
        lh._SPOTIFY_TOKEN_CACHE = {"token": "", "expires_at": 0}
        self.anon = False

        def fake(url, headers=None, timeout=8):
            if "/api/token" in url:
                cookie = (headers or {}).get("Cookie", "").split("=", 1)[-1]
                return json.dumps({"accessToken": f"tok-{cookie}", "isAnonymous": self.anon,
                                   "accessTokenExpirationTimestampMs": 4_000_000_000_000})
            return None
        lh._http_get = fake

    def tearDown(self):
        self.lh._http_get = self.orig
        self.lh._SPOTIFY_TOKEN_CACHE = {"token": "", "expires_at": 0}

    def test_token_cache_is_per_cookie(self):
        self.assertEqual(self.lh.get_spotify_access_token("A"), "tok-A")
        self.assertEqual(self.lh.get_spotify_access_token("B"), "tok-B")

    def test_anonymous_token_refused_for_sync(self):
        import spotify_web as sw
        self.anon = True
        self.assertEqual(sw._default_token("A"), "")


class EmptyResponseTests(unittest.TestCase):
    """C2 / I4: a 200 answer without the expected data is an error, never an empty list."""

    client = WebClientTests.client

    def test_null_playlist_is_error(self):
        import spotify_web as sw
        c, _ = self.client({"fetchPlaylist": [ok({"data": {"playlistV2": None}})]})
        with self.assertRaises(sw.SpotifyError):
            c.playlist_items("pl1")

    def test_null_me_on_liked_is_auth_error(self):
        import spotify_web as sw
        c, _ = self.client({"fetchLibraryTracks": [ok({"data": {"me": None}})]})
        with self.assertRaises(sw.SpotifyAuthError):
            c.liked_items()

    def test_null_library_is_error(self):
        import spotify_web as sw
        c, _ = self.client({"libraryV3": [ok({"data": {"me": {"libraryV3": None}}})]})
        with self.assertRaises(sw.SpotifyError):
            c.library_playlists()

    def test_me_without_id_is_auth_error(self):
        import spotify_web as sw
        c, _ = self.client({"profileAttributes": [ok({"data": {"me": None}})]})
        with self.assertRaises(sw.SpotifyAuthError):
            c.me()

    def test_editable_from_capabilities(self):
        node = {"__typename": "Playlist", "name": "c", "revisionId": "r", "uri": "spotify:playlist:c",
                "ownerV2": {"data": {"uri": "spotify:user:bob", "name": "bob"}},
                "currentUserCapabilities": {"canEditItems": True}}
        body = {"data": {"me": {"libraryV3": {"totalCount": 1, "items": [
            {"item": {"_uri": "spotify:playlist:c", "data": node}}]}}}}
        c, _ = self.client({"libraryV3": [ok(body)]})
        p = c.library_playlists()[0]
        self.assertFalse(p["owned"])
        self.assertTrue(p["editable"])

    def test_episode_rows_do_not_make_list_incomplete(self):
        import spotify_sync_merge as merge
        page = playlist_page(["a", "b"], 3, 0)
        page["data"]["playlistV2"]["content"]["items"].append(
            {"uid": "uid-e", "itemV2": {"data": {"uri": "spotify:episode:e"}}})
        c, _ = self.client({"fetchPlaylist": [ok(page)]})
        r = c.playlist_items("pl1")
        self.assertEqual([i["spotifyId"] for i in r.items], ["a", "b"])
        self.assertTrue(merge.remote_is_valid(r))


class FakeHandler:
    def __init__(self):
        self.sent = None

    def _send_json(self, data, status=200):
        self.sent = (data, status)


class RenameTests(SyncCase):
    """A playlist's name follows the side that changed it; Nutsty's goes to Spotify only with write-back on."""

    def setup_p(self, owned=True):
        self.enable(["P"])
        c = FakeClient([lib("P", owned=owned)], {"P": remote_list(["a"])})
        self.sync(c)
        return c

    def rename_local(self, name, drop_base=False):
        import playlist_manager as pm
        pls = pm.load_playlists()
        rec = next(p for p in pls if p["id"] == "custom_pl_spotify_P")
        rec["title"] = rec["name"] = name
        if drop_base:
            rec["spotifyLink"].pop("title", None)
        pm.save_playlists(pls)

    def test_spotify_rename_is_pulled_even_without_new_revision(self):
        c = self.setup_p()
        c.library[0]["title"] = "Renamed on Spotify"
        self.sync(c, now=self.NOW + 10)
        pl = self.playlist()
        self.assertEqual((pl["title"], pl["name"]), ("Renamed on Spotify", "Renamed on Spotify"))
        self.assertEqual(c.writes, [])

    def test_nutsty_rename_stays_local_without_write_back(self):
        c = self.setup_p()
        self.rename_local("ahihi")
        self.sync(c, now=self.NOW + 10)
        self.assertEqual(self.playlist()["title"], "ahihi")
        self.assertEqual(c.writes, [])

    def test_nutsty_rename_is_pushed_with_write_back(self):
        import spotify_sync as ss
        c = self.setup_p()
        ss.set_write_back("", True, now=self.NOW)
        self.rename_local("ahihi")
        self.sync(c, now=self.NOW + 10)
        self.assertEqual(c.writes, [("rename_playlist", "P", "ahihi")])
        self.sync(c, now=self.NOW + 20)
        self.assertEqual(c.writes, [("rename_playlist", "P", "ahihi")])
        self.assertEqual(self.playlist()["title"], "ahihi")

    def test_not_editable_playlist_is_never_renamed_on_spotify(self):
        import spotify_sync as ss
        c = self.setup_p(owned=False)
        ss.set_write_back("", True, now=self.NOW)
        self.rename_local("mine")
        self.sync(c, now=self.NOW + 10)
        self.assertEqual(c.writes, [])
        self.assertEqual(self.playlist()["title"], "mine")

    def test_link_from_before_names_were_tracked_keeps_nutsty_name(self):
        import spotify_sync as ss
        c = self.setup_p()
        ss.set_write_back("", True, now=self.NOW)
        self.rename_local("ahihi", drop_base=True)
        self.sync(c, now=self.NOW + 10)
        self.assertEqual(c.writes, [("rename_playlist", "P", "ahihi")])

    def test_both_renamed_spotify_wins(self):
        import spotify_sync as ss
        c = self.setup_p()
        ss.set_write_back("", True, now=self.NOW)
        self.rename_local("nutsty name")
        c.library[0]["title"] = "spotify name"
        self.sync(c, now=self.NOW + 10)
        self.assertEqual(self.playlist()["title"], "spotify name")
        self.assertEqual(c.writes, [])

    def test_failed_rename_is_retried_next_cycle(self):
        import spotify_sync as ss
        import spotify_web as sw
        c = self.setup_p()
        ss.set_write_back("", True, now=self.NOW)
        self.rename_local("ahihi")
        c.write_error = sw.SpotifyNetworkError("down")
        r = self.sync(c, now=self.NOW + 10)
        self.assertEqual(r["error"], "network")
        c.write_error = None
        self.sync(c, now=self.NOW + 20)
        self.assertEqual(c.writes, [("rename_playlist", "P", "ahihi")])


class AutoBacklogTests(SyncCase):
    """The earlier-likes push runs on its own once per switch-on: status says whether it has run."""

    def test_never_run_then_run(self):
        import spotify_sync as ss
        import spotify_sync_state as st
        self.enable([], liked=True)
        ss.set_write_back("", True, now=self.NOW)
        self.assertFalse(ss.status("")["backlogRan"])
        ss._backlog_progress(running=False, done=0, total=0)
        self.assertTrue(ss.status("")["backlogRan"])

    def test_switching_on_again_runs_it_again(self):
        import spotify_sync as ss
        self.enable([], liked=True)
        ss.set_write_back("", True, now=self.NOW)
        ss._backlog_progress(running=False, done=3, total=3)
        ss.set_write_back("", False, now=self.NOW)
        ss.set_write_back("", True, now=self.NOW + 5)
        self.assertFalse(ss.status("")["backlogRan"])


class RenameClientTests(WebClientTests):
    URL = "https://spclient.wg.spotify.com/playlist/v2/playlist/P/changes"

    def test_rename_sends_list_attribute_change(self):
        c, t = self.client({self.URL: [(200, {}, {})]})
        c.rename_playlist("P", "ahihi")
        self.assertEqual(t.calls[-1][0], self.URL)
        op = t.bodies[-1]["deltas"][0]["ops"][0]
        self.assertEqual(op["kind"], 6)
        self.assertEqual(op["updateListAttributes"]["newAttributes"]["values"], {"name": "ahihi"})

    def test_protobuf_reply_is_not_a_network_error(self):
        import spotify_web as sw
        self.assertEqual(sw._json_or_empty("\n\x08rev"), {})

    def test_rename_on_playlist_not_ours_raises(self):
        import spotify_web as sw
        c, _ = self.client({self.URL: [(403, {}, {})]})
        with self.assertRaises(sw.SpotifyError):
            c.rename_playlist("P", "x")


class DeleteTests(SyncCase):
    """Deleting a linked playlist on one side deletes it on the other: Spotify to Nutsty always,
    Nutsty to Spotify only with write-back on. Guards keep a bad read or a lost file from wiping lists."""

    def setup_lists(self, ids=("P",), write_back=False, albums=()):
        import spotify_sync as ss
        self.enable(list(ids) + [a["id"] for a in albums])
        c = FakeClient([lib(i) for i in ids], {i: remote_list(["a"]) for i in ids}, albums=albums)
        c.playlists.update({a["id"]: remote_list(["x"]) for a in albums})
        self.sync(c)
        if write_back:
            ss.set_write_back("", True, now=self.NOW)
        return c

    def delete_local(self, pid, confirmed=True):
        """The user deletes it in Nutsty; the delete dialog tells the sync (forget_playlist)."""
        import playlist_manager as pm
        import spotify_sync as ss
        pm.save_playlists([p for p in pm.load_playlists() if p["id"] != f"custom_pl_spotify_{pid}"])
        if confirmed:
            ss.forget_playlist("", pid)

    def test_spotify_delete_removes_nutsty_copy_after_second_check(self):
        import spotify_sync_state as st
        c = self.setup_lists(("P", "Q"))
        c.library = [lib("Q")]
        self.sync(c, now=self.NOW + 10)
        self.assertIsNotNone(self.playlist("P"))   # one missing read is not enough
        self.sync(c, now=self.NOW + 20)
        self.assertIsNone(self.playlist("P"))
        self.assertIsNotNone(self.playlist("Q"))
        s = st.load_state()
        self.assertNotIn("P", s["selected"])
        self.assertNotIn("P", s["linked"])
        self.assertEqual(c.writes, [])

    def test_playlist_back_in_library_resets_the_count(self):
        c = self.setup_lists(("P", "Q"))
        c.library = [lib("Q")]
        self.sync(c, now=self.NOW + 10)
        c.library = [lib("P"), lib("Q")]
        self.sync(c, now=self.NOW + 20)
        c.library = [lib("Q")]
        self.sync(c, now=self.NOW + 30)
        self.assertIsNotNone(self.playlist("P"))

    def test_spotify_delete_of_all_lists_is_followed(self):
        c = self.setup_lists(("P", "Q", "R"))
        c.library = []
        self.sync(c, now=self.NOW + 10)
        self.sync(c, now=self.NOW + 20)
        self.assertEqual([self.playlist(i) for i in "PQR"], [None, None, None])

    def test_other_account_never_deletes(self):
        c = self.setup_lists(("P",))
        c.me = lambda: {"id": "someone-else", "name": "X"}
        c.library = []
        self.sync(c, now=self.NOW + 10)
        self.sync(c, now=self.NOW + 20)
        self.assertIsNotNone(self.playlist("P"))

    def test_album_kept_while_albums_cannot_be_read(self):
        import spotify_web as sw
        c = self.setup_lists(("P",), albums=[album("AL")])
        def broken():
            raise sw.SpotifyError("changed", code="query_changed")
        c.library_albums = broken
        self.sync(c, now=self.NOW + 10)
        self.sync(c, now=self.NOW + 20)
        self.assertIsNotNone(self.playlist("AL"))

    def test_nutsty_delete_stays_local_without_write_back(self):
        c = self.setup_lists(("P",))
        self.delete_local("P")
        self.sync(c, now=self.NOW + 10)
        self.assertEqual(c.writes, [])
        self.assertIn("P", [p["id"] for p in c.library])

    def test_nutsty_delete_removes_spotify_playlist_with_write_back(self):
        import spotify_sync_state as st
        c = self.setup_lists(("P", "Q"), write_back=True)
        self.delete_local("P")
        self.sync(c, now=self.NOW + 10)
        self.assertEqual(c.writes, [("remove_playlist", "P")])
        self.sync(c, now=self.NOW + 20)
        self.assertEqual(c.writes, [("remove_playlist", "P")])
        self.assertIsNone(self.playlist("P"))
        self.assertNotIn("P", st.load_state()["selected"])

    def test_nutsty_delete_of_album_unsaves_it(self):
        c = self.setup_lists(("P",), write_back=True, albums=[album("AL")])
        self.delete_local("AL")
        self.sync(c, now=self.NOW + 10)
        self.assertEqual(c.writes, [("remove_album", None, ["spotify:album:AL"])])

    def test_failed_remote_delete_is_retried(self):
        import spotify_web as sw
        c = self.setup_lists(("P", "Q"), write_back=True)
        self.delete_local("P")
        c.write_error = sw.SpotifyError("down", code="network")
        self.sync(c, now=self.NOW + 10)
        self.assertIn("P", [p["id"] for p in c.library])
        c.write_error = None
        self.sync(c, now=self.NOW + 20)
        self.assertEqual(c.writes, [("remove_playlist", "P")])
        self.assertIsNone(self.playlist("P"))

    def test_lost_playlist_file_deletes_nothing_on_spotify(self):
        import playlist_manager as pm
        import spotify_sync_state as st
        c = self.setup_lists(("P", "Q"), write_back=True)
        pm.save_playlists([])
        self.sync(c, now=self.NOW + 10)
        self.assertEqual(c.writes, [])
        self.assertEqual(sorted(p["id"] for p in c.library), ["P", "Q"])

    def test_forget_unlinks_at_once(self):
        import spotify_sync as ss
        import spotify_sync_state as st
        self.setup_lists(("P", "Q"))
        self.delete_local("P")
        s = st.load_state()
        self.assertNotIn("P", s["selected"])
        self.assertNotIn("P", s["linked"])
        self.assertEqual(s.get("deleteRemote") or [], [])
        self.assertFalse(ss.forget_playlist("", "nope")["queued"])


class RemovePlaylistClientTests(WebClientTests):
    URL = "https://spclient.wg.spotify.com/playlist/v2/user/me/rootlist/changes"

    def test_remove_sends_rootlist_rem(self):
        c, t = self.client({self.URL: [(200, {}, {})]})
        c.remove_playlist("P")
        self.assertEqual(t.calls[-1][0], self.URL)
        op = t.bodies[-1]["deltas"][0]["ops"][0]
        self.assertEqual(op["kind"], 3)
        self.assertEqual(op["rem"]["items"], [{"uri": "spotify:playlist:P"}])
        self.assertTrue(op["rem"]["itemsAsKey"])


if __name__ == "__main__":
    unittest.main(verbosity=1)
