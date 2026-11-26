#!/usr/bin/env python3
"""
Behaviour test for components/SpotifySync.qml, loaded through the compat layer against a stub backend.

Checks: after confirmSelection the playlist list and the Liked Songs choice show the new picks at once,
so the "x of y" count in Settings is right without opening the picker a second time (both directions).
Usage: python scripts/test_spotify_sync_qml.py
"""
import json
import os
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

ROOT_DIR = Path(__file__).resolve().parent.parent
os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
os.environ.setdefault("QT_QUICK_BACKEND", "software")
sys.path.insert(0, str(ROOT_DIR))

from PySide6.QtCore import QCoreApplication, QMetaObject, QObject, Slot  # noqa: E402
from PySide6.QtQml import QQmlComponent, QQmlEngine  # noqa: E402
from PySide6.QtWidgets import QApplication  # noqa: E402

FAILURES = []
STATUS = {"success": True, "enabled": True, "selectionConfirmed": True, "running": False, "lastSync": 0}
CALLS = []   # ops the component posted, in order


def check(cond, msg):
    print(("ok   " if cond else "FAIL ") + msg)
    if not cond:
        FAILURES.append(msg)


def wait_for(pred, timeout=5.0):
    end = time.monotonic() + timeout
    while time.monotonic() < end:
        QCoreApplication.processEvents()
        if pred():
            return True
        time.sleep(0.005)
    return False


class Stub(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def do_POST(self):
        self.rfile.read(int(self.headers.get("Content-Length") or 0))
        CALLS.append(self.path.rsplit("/", 1)[-1])
        body = json.dumps(STATUS).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


class FakeBridge(QObject):
    @Slot(str, result=str)
    def getEnv(self, key):
        return os.environ.get(key, "")


def selected(sp):
    return sorted(c["id"] for c in sp.property("choices").toVariant() if c.get("selected"))


def main():
    app = QApplication([])
    import launcher_win
    launcher_win.register_qml_types()

    httpd = ThreadingHTTPServer(("127.0.0.1", 0), Stub)
    threading.Thread(target=httpd.serve_forever, daemon=True).start()

    engine = QQmlEngine()
    bridge = FakeBridge()
    engine.rootContext().setContextProperty("__NutstyBridge", bridge)
    for sub in ("compat", "", "components"):
        engine.addImportPath(str(ROOT_DIR / sub))
    comp = QQmlComponent(engine)
    comp.setData(f'''
        import QtQuick
        import "{(ROOT_DIR / "components").as_uri()}"
        SpotifySync {{
            apiUrl: "http://127.0.0.1:{httpd.server_address[1]}"
            hasCookie: false
            choices: [{{ id: "a", title: "A", selected: true }}, {{ id: "b", title: "B", selected: false }}]
            likedChoice: false
        }}
    '''.encode(), "file:///test.qml")
    sp = comp.create()
    if sp is None:
        print("\n".join(e.toString() for e in comp.errors()))
        return 1
    wait_for(lambda: False, 0.3)  # let the startup status call land

    sp.confirmSelection(["a", "b"], True)
    wait_for(lambda: selected(sp) == ["a", "b"])
    check(selected(sp) == ["a", "b"], "picking more shows every pick at once")
    check(sp.property("likedChoice") is True, "Liked Songs picked shows at once")

    sp.confirmSelection(["b"], False)
    wait_for(lambda: selected(sp) == ["b"])
    check(selected(sp) == ["b"], "picking fewer shows only the picks at once")
    check(sp.property("likedChoice") is False, "Liked Songs dropped shows at once")

    # Auto sync: a local change runs a sync shortly after, only with two-way on
    keep = []

    def make(extra=""):
        c = QQmlComponent(engine)
        c.setData(f'''
            import QtQuick
            import "{(ROOT_DIR / "components").as_uri()}"
            SpotifySync {{
                apiUrl: "http://127.0.0.1:{httpd.server_address[1]}"
                hasCookie: true
                soonDelay: 60
                {extra}
            }}
        '''.encode(), "file:///auto.qml")
        o = c.create()
        keep.extend([c, o])   # the object dies with its component otherwise
        if o is None:
            print("\n".join(e.toString() for e in c.errors()))
        wait_for(lambda: False, 0.3)
        return o

    STATUS.update(writeBack=True, likedSelected=False, backlogRan=True, lastSync=time.time())
    sp2 = make()
    CALLS.clear()
    QMetaObject.invokeMethod(sp2, "schedule")
    QMetaObject.invokeMethod(sp2, "schedule")
    wait_for(lambda: "run" in CALLS, 1.0)
    wait_for(lambda: False, 0.2)
    check(CALLS.count("run") == 1, "two quick local changes make one sync")

    STATUS.update(writeBack=False)
    QMetaObject.invokeMethod(sp2, "refreshStatus")
    wait_for(lambda: sp2.property("writeBack") is False)
    CALLS.clear()
    QMetaObject.invokeMethod(sp2, "schedule")
    wait_for(lambda: False, 0.3)
    check("run" not in CALLS, "one way: a local change does not sync")

    STATUS.update(writeBack=True)
    QMetaObject.invokeMethod(sp2, "refreshStatus")
    wait_for(lambda: sp2.property("writeBack") is True)
    sp2.setProperty("quietUntil", time.time() * 1000 + 10000)
    CALLS.clear()
    QMetaObject.invokeMethod(sp2, "schedule")
    wait_for(lambda: False, 0.3)
    check("run" not in CALLS, "the reload after a sync does not start another")

    CALLS.clear()
    QMetaObject.invokeMethod(sp2, "windowActivated")
    wait_for(lambda: False, 0.2)
    check("run" not in CALLS, "window back soon after a sync: no new sync")
    STATUS.update(lastSync=time.time() - 600)
    QMetaObject.invokeMethod(sp2, "refreshStatus")
    wait_for(lambda: False, 0.2)
    CALLS.clear()
    QMetaObject.invokeMethod(sp2, "windowActivated")
    wait_for(lambda: "run" in CALLS, 1.0)
    check("run" in CALLS, "window back after a while: sync")

    check(sp2.property("periodMinutes") == 15, "checks Spotify every 15 minutes")

    # Earlier likes go up on their own, once, when two-way and Liked Songs are on
    STATUS.update(likedSelected=True, backlogRan=False, lastSync=time.time())
    CALLS.clear()
    QMetaObject.invokeMethod(sp2, "refreshStatus")
    wait_for(lambda: "backlog_start" in CALLS, 1.0)
    check("backlog_start" in CALLS, "earlier likes pushed without a button")
    STATUS.update(backlogRan=True)
    QMetaObject.invokeMethod(sp2, "refreshStatus")
    wait_for(lambda: False, 0.2)
    CALLS.clear()
    QMetaObject.invokeMethod(sp2, "refreshStatus")
    wait_for(lambda: False, 0.3)
    check("backlog_start" not in CALLS, "pushed once, not again")
    STATUS.update(likedSelected=False, backlogRan=False)
    CALLS.clear()
    QMetaObject.invokeMethod(sp2, "refreshStatus")
    wait_for(lambda: False, 0.3)
    check("backlog_start" not in CALLS, "Liked Songs not picked: no push")

    httpd.shutdown()
    print(f"\n{len(FAILURES)} failure(s)")
    return 1 if FAILURES else 0


if __name__ == "__main__":
    sys.exit(main())
