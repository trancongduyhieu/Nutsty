#!/usr/bin/env python3
"""
Nutsty delta update: download only the files that changed inside the release zip.

How it works (no extra release assets, no per-version patches):
  1. HTTP Range reads the zip's central directory (a few hundred KB). It lists every file with
     its CRC32 and size, so it doubles as a manifest.
  2. Each file in the install folder is compared by size, then CRC32.
  3. Only the changed or missing entries are fetched, as compressed ranges (neighbours merged),
     inflated and verified against the CRC32, into a staging folder.
Works from any older version, resumes after a cut connection, and raises DeltaUnavailable when the
server cannot do Range so the caller can fall back to the full zip.
"""
import os
import struct
import threading
import time
import urllib.request
import zlib
from concurrent.futures import ThreadPoolExecutor

USER_AGENT = "Nutsty-Desktop-App/1.0"
TAIL_BYTES = 256 * 1024
MERGE_GAP = 256 * 1024
MAX_GROUP = 8 * 1024 * 1024
LOCAL_SLACK = 1024
WORKERS = 4
_EOCD = b"PK\x05\x06"
_CEN = 0x02014B50
_LOC = 0x04034B50


class DeltaUnavailable(Exception):
    """The server or the zip layout cannot be updated piecewise; use the full download."""


class Entry:
    __slots__ = ("name", "method", "crc", "csize", "usize", "offset", "nlen")

    def __init__(self, name, method, crc, csize, usize, offset, nlen):
        self.name = name
        self.method = method
        self.crc = crc
        self.csize = csize
        self.usize = usize
        self.offset = offset
        self.nlen = nlen


def _get(url, start, end, timeout=30.0):
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT, "Range": f"bytes={start}-{end}"})
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        if resp.status != 206:
            raise DeltaUnavailable("server ignored Range")
        data = resp.read()
    if len(data) != end - start + 1:
        raise DeltaUnavailable("short range read")
    return data


def remote_size(url):
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT, "Range": "bytes=0-0"})
    with urllib.request.urlopen(req, timeout=20.0) as resp:
        if resp.status != 206:
            raise DeltaUnavailable("server ignored Range")
        total = (resp.headers.get("Content-Range") or "").rsplit("/", 1)[-1]
        resp.read()
    if not total.isdigit():
        raise DeltaUnavailable("no total size")
    return int(total)


def parse_central_directory(blob):
    entries, pos = [], 0
    while pos + 46 <= len(blob):
        (sig, _vm, _vn, flags, method, _t, _d, crc, csize, usize,
         nlen, elen, clen, _disk, _ia, _ea, offset) = struct.unpack("<I6H3L5H2L", blob[pos:pos + 46])
        if sig != _CEN:
            break
        raw = blob[pos + 46:pos + 46 + nlen]
        name = raw.decode("utf-8" if flags & 0x800 else "cp437", "replace").replace("\\", "/")
        if 0xFFFFFFFF in (csize, usize, offset):
            raise DeltaUnavailable("zip64 entry")
        entries.append(Entry(name, method, crc, csize, usize, offset, nlen))
        pos += 46 + nlen + elen + clen
    return entries


def read_directory(url):
    """Return (entries, total_zip_bytes)."""
    size = remote_size(url)
    start = max(0, size - TAIL_BYTES)
    tail = _get(url, start, size - 1)
    at = tail.rfind(_EOCD)
    if at < 0:
        raise DeltaUnavailable("no end record")
    _s, _d, _dc, _n, total, cd_size, cd_off, _cl = struct.unpack("<4s4H2LH", tail[at:at + 22])
    if 0xFFFF in (total,) or 0xFFFFFFFF in (cd_size, cd_off):
        raise DeltaUnavailable("zip64 archive")
    if cd_off >= start:
        blob = tail[cd_off - start:cd_off - start + cd_size]
    else:
        blob = _get(url, cd_off, cd_off + cd_size - 1)
    entries = parse_central_directory(blob)
    if not entries or len(entries) != total:
        raise DeltaUnavailable("directory mismatch")
    return entries, size


def file_crc(path):
    crc = 0
    with open(path, "rb") as f:
        while True:
            chunk = f.read(1 << 20)
            if not chunk:
                break
            crc = zlib.crc32(chunk, crc)
    return crc & 0xFFFFFFFF


def is_current(path, entry):
    try:
        if os.path.getsize(path) != entry.usize:
            return False
        return file_crc(path) == entry.crc
    except OSError:
        return False


def plan(entries, app_dir, stage_dir, skip=(), cancelled=lambda: False):
    """Entries that differ from the install folder. Files already staged correctly are skipped (resume)."""
    skip_set = {s.replace("\\", "/") for s in skip}
    todo, same_bytes = [], 0
    for e in entries:
        if cancelled():
            raise RuntimeError("cancelled")
        if e.name.endswith("/") or e.name in skip_set:
            continue
        if is_current(os.path.join(app_dir, *e.name.split("/")), e):
            same_bytes += e.csize
            continue
        if is_current(os.path.join(stage_dir, *e.name.split("/")), e):
            continue
        todo.append(e)
    return todo, same_bytes


def _group(todo):
    groups, cur = [], []
    for e in sorted(todo, key=lambda x: x.offset):
        if cur:
            last = cur[-1]
            gap = e.offset - (last.offset + 30 + last.nlen + last.csize)
            span = e.offset + 30 + e.nlen + e.csize - cur[0].offset
            if gap <= MERGE_GAP and span <= MAX_GROUP:
                cur.append(e)
                continue
            groups.append(cur)
        cur = [e]
    if cur:
        groups.append(cur)
    return groups


def _unpack(e, blob, base):
    at = e.offset - base
    sig, = struct.unpack("<I", blob[at:at + 4])
    if sig != _LOC:
        raise DeltaUnavailable("bad local header")
    nlen, elen = struct.unpack("<HH", blob[at + 26:at + 30])
    data = blob[at + 30 + nlen + elen:at + 30 + nlen + elen + e.csize]
    if len(data) != e.csize:
        raise DeltaUnavailable("local header larger than expected")
    if e.method == 0:
        out = data
    elif e.method == 8:
        out = zlib.decompress(data, -15)
    else:
        raise DeltaUnavailable(f"unsupported method {e.method}")
    if len(out) != e.usize or (zlib.crc32(out) & 0xFFFFFFFF) != e.crc:
        raise IOError(f"checksum mismatch: {e.name}")
    return out


def _fetch_group(url, group, stage_dir, on_bytes, cancelled):
    base = group[0].offset
    last = group[-1]
    end = last.offset + 30 + last.nlen + last.csize + LOCAL_SLACK
    last_err = None
    for attempt in range(3):
        if cancelled():
            raise RuntimeError("cancelled")
        try:
            blob = _get(url, base, end - 1 if end > base else base)
            break
        except DeltaUnavailable:
            # slack ran past the end of the zip: retry exactly
            try:
                blob = _get(url, base, last.offset + 30 + last.nlen + last.csize - 1)
                break
            except Exception as ex:
                last_err = ex
        except Exception as ex:
            last_err = ex
            time.sleep(0.8 * (attempt + 1))
    else:
        raise last_err
    for e in group:
        out = _unpack(e, blob, base)
        dest = os.path.join(stage_dir, *e.name.split("/"))
        os.makedirs(os.path.dirname(dest), exist_ok=True)
        tmp = dest + ".part"
        with open(tmp, "wb") as f:
            f.write(out)
        os.replace(tmp, dest)
        on_bytes(e.csize)


def download(url, todo, stage_dir, on_bytes, cancelled=lambda: False):
    groups = _group(todo)
    with ThreadPoolExecutor(max_workers=WORKERS) as pool:
        futures = [pool.submit(_fetch_group, url, g, stage_dir, on_bytes, cancelled) for g in groups]
        for f in futures:
            f.result()


class SpeedMeter:
    """Bytes per second over the last few seconds, for a steady speed and ETA readout."""

    def __init__(self, window=4.0):
        self.window = window
        self._lock = threading.Lock()
        self._samples = []
        self.done = 0

    def add(self, n):
        now = time.monotonic()
        with self._lock:
            self.done += n
            self._samples.append((now, self.done))
            cut = now - self.window
            while len(self._samples) > 2 and self._samples[0][0] < cut:
                self._samples.pop(0)

    def rate(self):
        with self._lock:
            if len(self._samples) < 2:
                return 0.0
            (t0, b0), (t1, b1) = self._samples[0], self._samples[-1]
            return (b1 - b0) / (t1 - t0) if t1 > t0 else 0.0
