#!/usr/bin/env python3
"""
Tests for playlist writes (ADR-0007): the POST /api/playlists/<op> interface of playlist_manager,
profile scoping, the cross-process lock, and both routers (route_dispatcher on Linux, auth_server on Windows).

Runs against a temporary XDG_CONFIG_HOME, never the real ~/.config/noctalia.
Usage: python scripts/test_playlist_backend.py
"""
import json
import os
import subprocess
import sys
import tempfile
import threading
import unittest
import urllib.request
from pathlib import Path

ROOT_DIR = Path(__file__).resolve().parent.parent
BACKEND_DIR = ROOT_DIR / "backend"
TMP_CONFIG = tempfile.mkdtemp(prefix="nutsty-pl-test-")
os.environ["XDG_CONFIG_HOME"] = TMP_CONFIG
os.environ.pop("NUTSTY_PROFILE", None)
sys.path.insert(0, str(BACKEND_DIR))

import playlist_manager as pm  # noqa: E402

CONFIG_DIR = Path(TMP_CONFIG) / "noctalia"


def track(vid, title=None):
    return {"videoId": vid, "title": title or vid, "image": f"https://img/{vid}.jpg"}


class PlaylistHttpOps(unittest.TestCase):
    def setUp(self):
        for f in CONFIG_DIR.glob("*playlists*"):
            f.unlink()

    def op(self, name, **body):
        return pm.handle_http(name, body)

    def test_create_returns_playlist_and_full_list(self):
        status, res = self.op("create", title="  Chill  ", description="d", tracks=[track("a"), track("b")])
        self.assertEqual(status, 200)
        self.assertTrue(res["playlist"]["id"].startswith("custom_pl_"))
        self.assertEqual(res["playlist"]["title"], "Chill")
        self.assertEqual(res["playlist"]["trackCount"], 2)
        self.assertEqual([p["id"] for p in res["playlists"]], [res["playlist"]["id"]])
        self.assertEqual(res["favorites"], [])

    def test_add_dedups_and_remove_by_track_or_video_id(self):
        _, res = self.op("create", title="P", tracks=[track("a")])
        pid = res["playlist"]["id"]
        status, res = self.op("add", id=pid, tracks=[track("a"), track("b"), track("c")])
        self.assertEqual(status, 200)
        self.assertEqual(res["added"], 2)
        _, res = self.op("add", id=pid, tracks=track("d"))  # a single track object is accepted too
        self.assertEqual(res["playlists"][0]["trackCount"], 4)
        _, res = self.op("remove", id=pid, track=track("b"))
        _, res = self.op("remove", id=pid, track="c")
        self.assertEqual([t["videoId"] for t in res["playlists"][0]["tracks"]], ["a", "d"])

    def test_rename_keeps_or_clears_cover(self):
        _, res = self.op("create", title="P", tracks=[track("a")], cover="/c.png")
        pid = res["playlist"]["id"]
        _, res = self.op("rename", id=pid, title="Q", description="new")
        pl = res["playlist"]
        self.assertEqual((pl["title"], pl["description"], pl["customCover"]), ("Q", "new", "/c.png"))
        _, res = self.op("rename", id=pid, title="Q", cover="")
        self.assertEqual(res["playlist"]["customCover"], "")
        self.assertEqual(res["playlist"]["image"], "https://img/a.jpg")

    def test_reorder_and_errors(self):
        _, res = self.op("create", title="P", tracks=[track("a"), track("b"), track("c")])
        pid = res["playlist"]["id"]
        _, res = self.op("reorder", id=pid, **{"from": 2, "to": 0})
        self.assertEqual([t["videoId"] for t in res["playlist"]["tracks"]], ["c", "a", "b"])
        status, res = self.op("reorder", id=pid, **{"from": 9, "to": 0})
        self.assertEqual(status, 400)
        self.assertEqual(len(res["playlists"]), 1)  # failed writes still return the state on disk
        self.assertEqual(self.op("rename", id="custom_pl_missing", title="x")[0], 400)
        self.assertEqual(self.op("add", id=pid, tracks="not-a-list")[0], 400)
        self.assertEqual(self.op("nope")[0], 404)

    def test_delete_also_drops_favorite(self):
        _, res = self.op("create", title="P")
        pl = res["playlist"]
        _, res = self.op("toggle_favorite", playlist=pl)
        self.assertTrue(res["isFavorite"])
        self.assertEqual([f["id"] for f in res["favorites"]], [pl["id"]])
        _, res = self.op("delete", id=pl["id"])
        self.assertEqual((res["playlists"], res["favorites"]), ([], []))

    def test_toggle_favorite_twice_removes_it(self):
        online = {"browseId": "VLPL123", "title": "Online", "thumbnails": [{"url": "s"}, {"url": "big"}]}
        _, res = self.op("toggle_favorite", playlist=online)
        self.assertEqual(res["favorites"][0]["image"], "big")
        _, res = self.op("toggle_favorite", playlist=online)
        self.assertFalse(res["isFavorite"])
        self.assertEqual(res["favorites"], [])

    def test_profile_scopes_files(self):
        self.op("create", title="Main")
        _, res = self.op("create", title="Other", profile="User2")
        self.assertEqual([p["title"] for p in res["playlists"]], ["Other"])
        self.assertTrue((CONFIG_DIR / "custom_playlists_user2.json").exists())
        _, res = self.op("list")
        self.assertEqual([p["title"] for p in res["playlists"]], ["Main"])
        self.assertEqual(pm._ACTIVE_SUFFIX.get(), "")  # scope does not leak out of the request

    def test_lock_is_reentrant(self):
        with pm.locked():
            with pm.locked():
                pm.create_playlist("nested")
        self.assertEqual(len(pm.load_playlists()), 1)


class PlaylistLockAcrossProcesses(unittest.TestCase):
    def setUp(self):
        for f in CONFIG_DIR.glob("*playlists*"):
            f.unlink()

    def test_concurrent_cli_adds_are_all_kept(self):
        pid = pm.create_playlist("Race")["id"]
        n = 12
        procs = [subprocess.Popen([sys.executable, str(BACKEND_DIR / "playlist_manager.py"), "add", pid,
                                   json.dumps([track(f"v{i}")])],
                                  stdout=subprocess.DEVNULL, env=os.environ.copy()) for i in range(n)]
        for p in procs:
            self.assertEqual(p.wait(timeout=30), 0)
        self.assertEqual(pm.load_playlists()[0]["trackCount"], n)

    def test_concurrent_threads_are_all_kept(self):
        pid = pm.create_playlist("Threads")["id"]
        threads = [threading.Thread(target=pm.handle_http, args=("add", {"id": pid, "tracks": [track(f"t{i}")]}))
                   for i in range(20)]
        for t in threads:
            t.start()
        for t in threads:
            t.join()
        self.assertEqual(pm.load_playlists()[0]["trackCount"], 20)


class Routers(unittest.TestCase):
    def setUp(self):
        for f in CONFIG_DIR.glob("*playlists*"):
            f.unlink()

    def test_route_dispatcher_serve_worker(self):
        proc = subprocess.Popen([sys.executable, str(BACKEND_DIR / "route_dispatcher.py"), "--serve"],
                                stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True, env=os.environ.copy())
        try:
            def call(path, body):
                proc.stdin.write(json.dumps({"method": "POST", "url": path, "body": json.dumps(body)}) + "\n")
                proc.stdin.flush()
                return json.loads(proc.stdout.readline())
            out = call("/api/playlists/create", {"title": "Linux", "profile": "user1"})
            self.assertEqual(out["status"], 200)
            self.assertEqual(json.loads(out["body"])["playlist"]["title"], "Linux")
            out = call("/api/playlists/rename", {"id": "custom_pl_missing", "title": "x", "profile": "user1"})
            self.assertEqual(out["status"], 400)
        finally:
            proc.stdin.close()
            proc.wait(timeout=10)
        self.assertTrue((CONFIG_DIR / "custom_playlists_user1.json").exists())

    def test_auth_server_http(self):
        import auth_server
        from http.server import ThreadingHTTPServer
        httpd = ThreadingHTTPServer(("127.0.0.1", 0), auth_server.AuthWebhookHandler)
        threading.Thread(target=httpd.serve_forever, daemon=True).start()
        try:
            url = f"http://127.0.0.1:{httpd.server_address[1]}/api/playlists/create"
            req = urllib.request.Request(url, data=json.dumps({"title": "Windows"}).encode(),
                                         headers={"Content-Type": "application/json"}, method="POST")
            with urllib.request.urlopen(req, timeout=10) as resp:
                self.assertEqual(resp.status, 200)
                self.assertEqual(json.loads(resp.read())["playlists"][0]["title"], "Windows")
        finally:
            httpd.shutdown()
            httpd.server_close()


if __name__ == "__main__":
    unittest.main(verbosity=1)
