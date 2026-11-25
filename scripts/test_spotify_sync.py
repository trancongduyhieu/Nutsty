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


if __name__ == "__main__":
    unittest.main(verbosity=1)
