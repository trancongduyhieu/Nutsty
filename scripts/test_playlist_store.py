#!/usr/bin/env python3
"""
Behaviour test for components/PlaylistStore.qml (ADR-0007), loaded through the compat layer and talking
HTTP to a real auth_server on a random port with a temporary XDG_CONFIG_HOME.

Checks: optimistic patch applies at once, writes run in order and the last playlist write result replaces
the patches, selected follows the store, profile picks the file, a failed write is reverted and reported,
and an unreachable backend reports "offline".
Usage: python scripts/test_playlist_store.py
"""
import json
import os
import sys
import tempfile
import threading
import time
from pathlib import Path

ROOT_DIR = Path(__file__).resolve().parent.parent
TMP_CONFIG = tempfile.mkdtemp(prefix="nutsty-store-test-")
os.environ["XDG_CONFIG_HOME"] = TMP_CONFIG
os.environ["NUTSTY_PROFILE"] = "storetest"
os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
os.environ.setdefault("QT_QUICK_BACKEND", "software")
sys.path.insert(0, str(ROOT_DIR))
sys.path.insert(0, str(ROOT_DIR / "backend"))

from PySide6.QtCore import QCoreApplication, QObject, QUrl, Slot  # noqa: E402
from PySide6.QtQml import QQmlComponent, QQmlEngine  # noqa: E402
from PySide6.QtWidgets import QApplication  # noqa: E402

FAILURES = []


def check(cond, msg):
    print(("ok   " if cond else "FAIL ") + msg)
    if not cond:
        FAILURES.append(msg)


def wait_for(pred, timeout=10.0):
    end = time.monotonic() + timeout
    while time.monotonic() < end:
        QCoreApplication.processEvents()
        if pred():
            return True
        time.sleep(0.005)
    return False


class FakeBridge(QObject):
    """Only the part of NutstyBridge the store uses: Quickshell.env() on compat reads it."""
    @Slot(str, result=str)
    def getEnv(self, key):
        return os.environ.get(key, "")


def main():
    app = QApplication([])
    import launcher_win
    launcher_win.register_qml_types()

    import auth_server
    from http.server import ThreadingHTTPServer
    httpd = ThreadingHTTPServer(("127.0.0.1", 0), auth_server.AuthWebhookHandler)
    threading.Thread(target=httpd.serve_forever, daemon=True).start()
    api = f"http://127.0.0.1:{httpd.server_address[1]}"

    engine = QQmlEngine()
    bridge = FakeBridge()
    engine.rootContext().setContextProperty("__NutstyBridge", bridge)
    for sub in ("compat", "", "components"):
        engine.addImportPath(str(ROOT_DIR / sub))
    comp = QQmlComponent(engine)
    comp.setData(f'''
        import QtQuick
        import "{(ROOT_DIR / "components").as_uri()}"
        PlaylistStore {{
            apiUrl: "{api}"
            property var failures: []
            property var done: []
            onWriteFailed: (op, error) => failures = failures.concat([op + ":" + error])
            function js(code) {{ return JSON.stringify(eval(code)); }}
        }}'''.encode(), QUrl.fromLocalFile(str(ROOT_DIR / "components" / "_store_test.qml")))
    store = comp.create()
    if store is None:
        print("\n".join(e.toString() for e in comp.errors()))
        return 1

    def js(code):
        return json.loads(store.js(code) or "null")

    idle = lambda: not store.property("busy")  # noqa: E731

    check(js("profile") == "storetest", "profile comes from NUTSTY_PROFILE")
    store.reload()
    check(wait_for(lambda: store.property("loaded")), "reload reaches the backend")

    js('create("Mix", "d", "", [{videoId:"a", title:"a", image:"ia"}], r => done = done.concat(["create"]))')
    check(wait_for(idle) and js("customPlaylists.length") == 1, "create lands in customPlaylists")
    check(js("done") == ["create"], "onDone runs after a confirmed write")
    pid = js("customPlaylists[0].id")
    check(js(f'isCustom("{pid}")') and not js('isCustom({id:"local_alb_x", isLocal:true})'),
          "isCustom: custom_pl_ only, not local albums")

    js(f'select("{pid}", null)')
    check(js("selected.title") == "Mix", "selected follows selectedId")

    # Three writes back to back: patches show at once, final state comes from the last result
    js(f'addTracks("{pid}", [{{videoId:"b"}}, {{videoId:"a"}}])')
    js(f'update("{pid}", "Renamed", "desc2", "/cover.png")')
    js(f'reorder("{pid}", 1, 0)')
    check(js("selected.title") == "Renamed" and js("selected.trackCount") == 2,
          "optimistic patch applies before the backend answers (dedup kept 2 tracks)")
    check(wait_for(idle), "queued writes drain")
    on_disk = json.loads((Path(TMP_CONFIG) / "noctalia" / "custom_playlists_storetest.json").read_text())
    check([t["videoId"] for t in on_disk[0]["tracks"]] == ["b", "a"] and on_disk[0]["title"] == "Renamed"
          and on_disk[0]["customCover"] == "/cover.png", "all three writes reached disk in order")
    check([t["videoId"] for t in js("selected.tracks")] == ["b", "a"], "store shows the state on disk")

    js(f'removeTrack("{pid}", {{videoId:"b"}})')
    check(wait_for(idle) and js("selected.trackCount") == 1, "removeTrack")

    js(f'toggleFavorite({{id:"{pid}", title:"Renamed"}})')
    check(wait_for(idle) and js(f'isFavorite("{pid}")'), "toggleFavorite adds")

    # Backend rejects the write: patch is reverted to the state on disk and the failure is reported
    js(f'reorder("{pid}", 0, 5)')
    js('update("custom_pl_missing", "x", "", undefined)')
    check(wait_for(idle) and js("failures") == ["reorder:Invalid indices", "rename:Playlist not found"],
          "each rejected write is reported (got %s)" % js("failures"))
    check(js("selected.trackCount") == 1, "store still matches disk after a rejected write")

    js(f'remove("{pid}")')
    check(js("selected") is None and js("customPlaylists.length") == 0, "remove clears selection at once")
    check(wait_for(idle) and js("favoritePlaylists.length") == 0, "remove also drops the favorite")

    # Backend gone: the write is reported as offline
    httpd.shutdown()
    httpd.server_close()
    js('create("Offline", "", "", [])')
    check(wait_for(lambda: "create:offline" in js("failures")), "unreachable backend reports offline")

    print(f"\n{'FAILED' if FAILURES else 'OK'}: {len(FAILURES)} failure(s)")
    return 1 if FAILURES else 0


if __name__ == "__main__":
    sys.exit(main())
