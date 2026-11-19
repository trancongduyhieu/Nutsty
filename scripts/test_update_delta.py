#!/usr/bin/env python3
"""Delta update: only changed files are fetched from a Range-capable server, and the result is verified."""
import http.server
import io
import os
import re
import shutil
import sys
import tempfile
import threading
import zipfile

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "backend"))
import update_delta as ud  # noqa: E402


def make_zip(files):
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w", zipfile.ZIP_DEFLATED) as z:
        for name, data in files.items():
            z.writestr(name, data)
    return buf.getvalue()


class RangeHandler(http.server.BaseHTTPRequestHandler):
    payload = b""
    ranges = []
    honour_range = True

    def log_message(self, *a):
        pass

    def do_GET(self):
        rng = re.match(r"bytes=(\d+)-(\d+)", self.headers.get("Range", ""))
        data = self.payload
        if rng and self.honour_range:
            a, b = int(rng.group(1)), min(int(rng.group(2)), len(data) - 1)
            RangeHandler.ranges.append((a, b))
            self.send_response(206)
            self.send_header("Content-Range", f"bytes {a}-{b}/{len(data)}")
            body = data[a:b + 1]
        else:
            self.send_response(200)
            body = data
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


def serve(payload, honour=True):
    RangeHandler.payload = payload
    RangeHandler.ranges = []
    RangeHandler.honour_range = honour
    srv = http.server.ThreadingHTTPServer(("127.0.0.1", 0), RangeHandler)
    threading.Thread(target=srv.serve_forever, daemon=True).start()
    return srv, f"http://127.0.0.1:{srv.server_address[1]}/u.zip"


def main():
    big = os.urandom(300_000)
    old = {"Nutsty.exe": b"exe-v1", "_internal/big.bin": big, "shell.qml": b"qml v1", "components/A.qml": b"A" * 5000}
    new = dict(old, **{"shell.qml": b"qml v2 changed", "components/B.qml": b"brand new " * 400})
    tmp = tempfile.mkdtemp()
    try:
        app, stage = os.path.join(tmp, "app"), os.path.join(tmp, "stage")
        for name, data in old.items():
            path = os.path.join(app, *name.split("/"))
            os.makedirs(os.path.dirname(path), exist_ok=True)
            open(path, "wb").write(data)

        srv, url = serve(make_zip(new))
        entries, size = ud.read_directory(url)
        todo, _ = ud.plan(entries, app, stage)
        assert sorted(e.name for e in todo) == ["components/B.qml", "shell.qml"], [e.name for e in todo]

        done = []
        ud.download(url, todo, stage, done.append)
        assert sum(done) == sum(e.csize for e in todo)
        for name in ("shell.qml", "components/B.qml"):
            assert open(os.path.join(stage, *name.split("/")), "rb").read() == new[name]
        assert not os.path.exists(os.path.join(stage, "_internal"))
        fetched = sum(b - a + 1 for a, b in RangeHandler.ranges)
        assert fetched < size, "must not pull the whole zip"
        # the 300 KB random file is never requested
        assert all(not (a <= 200 and b >= 300_000) for a, b in RangeHandler.ranges[2:])

        # resume: staged files are already right, nothing left to fetch
        todo2, _ = ud.plan(entries, app, stage)
        assert todo2 == [], [e.name for e in todo2]

        # corrupt staged file is fetched again
        open(os.path.join(stage, "shell.qml"), "wb").write(b"broken")
        todo3, _ = ud.plan(entries, app, stage)
        assert [e.name for e in todo3] == ["shell.qml"]

        # a server without Range support must fall back, not mis-parse
        srv.shutdown()
        srv2, url2 = serve(make_zip(new), honour=False)
        try:
            ud.read_directory(url2)
            raise AssertionError("expected DeltaUnavailable")
        except ud.DeltaUnavailable:
            pass
        srv2.shutdown()
        print("test_update_delta: OK")
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


if __name__ == "__main__":
    main()
