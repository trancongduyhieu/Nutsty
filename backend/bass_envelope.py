"""How hard a track's bass hits over time, for the artwork backdrop's pulse.

Port of SimpMusic's BassEnvelope (core/domain/.../player/BassEnvelope.kt): mono samples go through two
one-pole low-passes at 150 Hz, each 25 ms slot keeps the RMS of what passed, and a slot's pulse is judged
against the hardest hit within 2 s either side (never less than 0.15 of the track's loud hits), so a quiet
verse pulses as plainly as a loud drop. The whole track is measured, then every slot's pulse is stored as
one byte (0..255).
"""
import array
import math
import os
import subprocess
import sys
from collections import deque

SLOTS_PER_SECOND = 40
CUTOFF_HZ = 150.0
FLOOR = 0.5
REFERENCE_PERCENTILE = 0.95
WINDOW_SLOTS = 2 * SLOTS_PER_SECOND
QUIET_SHARE = 0.15
HISTOGRAM_BINS = 200
MIN_DECADE = -5.0
MAX_SLOTS = 6 * 3600 * SLOTS_PER_SECOND


class BassEnvelope:
    """Feed a continuous mono stream with add(); pulses() closes it and returns one byte per slot."""

    def __init__(self, rate):
        self.rate = rate
        self.alpha = 1.0 - math.exp(-2.0 * math.pi * CUTOFF_HZ / rate)
        self.low1 = 0.0
        self.low2 = 0.0
        self.n = 0
        self.per_slot = rate / SLOTS_PER_SECOND
        self.levels = []
        self._sum = 0.0
        self._count = 0
        self._slot = 0

    def add(self, samples):
        """Samples are floats in -1..1, in order, with no gaps."""
        a, l1, l2 = self.alpha, self.low1, self.low2
        s, c, slot, n = self._sum, self._count, self._slot, self.n
        per = self.per_slot
        boundary = int((slot + 1) * per)
        for x in samples:
            if n >= boundary:
                self._store(slot, s, c)
                s, c = 0.0, 0
                slot = int(n / per)
                boundary = int((slot + 1) * per)
            l1 += a * (x - l1)
            l2 += a * (l1 - l2)
            s += l2 * l2
            c += 1
            n += 1
        self.low1, self.low2 = l1, l2
        self._sum, self._count, self._slot, self.n = s, c, slot, n

    def _store(self, slot, s, c):
        if c == 0 or slot >= MAX_SLOTS:
            return
        while len(self.levels) < slot:
            self.levels.append(0.0)
        self.levels.append(math.sqrt(s / c))

    def pulses(self):
        self._store(self._slot, self._sum, self._count)
        self._sum, self._count = 0.0, 0
        return pulses_from_levels(self.levels)


def _bin(level):
    b = int((math.log10(level) - MIN_DECADE) / -MIN_DECADE * HISTOGRAM_BINS)
    return min(max(b, 0), HISTOGRAM_BINS - 1)


def _level_of(edge):
    return 10.0 ** (MIN_DECADE + edge / HISTOGRAM_BINS * -MIN_DECADE)


def _reference(levels):
    hist = [0] * HISTOGRAM_BINS
    total = 0
    for v in levels:
        if v > 0 and math.isfinite(v):
            hist[_bin(v)] += 1
            total += 1
    if total == 0:
        return 0.0
    target = int(total * REFERENCE_PERCENTILE)
    seen = 0
    for i, h in enumerate(hist):
        seen += h
        if seen > target:
            return _level_of(i + 1)
    return _level_of(HISTOGRAM_BINS)


def pulses_from_levels(levels):
    """One byte per slot: round(pulse * 255), pulse as SimpMusic's pulseAt."""
    reference = _reference(levels)
    if reference <= 0 or not levels:
        return bytes(len(levels))
    quiet = reference * QUIET_SHARE
    n = len(levels)
    out = bytearray(n)
    window = deque()  # indices with decreasing levels: front is the max of [i-W, i+W]
    nxt = 0
    for i in range(n):
        hi = min(n - 1, i + WINDOW_SLOTS)
        while nxt <= hi:
            while window and levels[window[-1]] <= levels[nxt]:
                window.pop()
            window.append(nxt)
            nxt += 1
        while window[0] < i - WINDOW_SLOTS:
            window.popleft()
        local = max(quiet, levels[window[0]])
        p = (levels[i] / local - FLOOR) / (1.0 - FLOOR)
        out[i] = int(round(min(max(p, 0.0), 1.0) * 255))
    return bytes(out)


def pulses_from_samples(samples, rate):
    env = BassEnvelope(rate)
    env.add(samples)
    return env.pulses()


# ---- measuring a whole track and caching it ----

ANALYSIS_RATE = 8000
MAX_SECONDS = 15 * 60
DECODE_TIMEOUT = 120
CACHE_KEEP = 500
_CHUNK = 1 << 20


def _cache_path(cache_dir, key):
    import hashlib
    return os.path.join(cache_dir, hashlib.sha1(key.encode("utf-8", "replace")).hexdigest() + ".bass")


def _default_cache_dir():
    import platform_compat as pc
    return os.path.join(pc.get_cache_dir(), "bass")


def _prune(cache_dir):
    try:
        names = [os.path.join(cache_dir, n) for n in os.listdir(cache_dir) if n.endswith(".bass")]
        if len(names) <= CACHE_KEEP:
            return
        names.sort(key=lambda f: os.path.getmtime(f))
        for f in names[: len(names) - CACHE_KEEP]:
            os.remove(f)
    except OSError:
        pass


def cached(key, cache_dir=None):
    """The stored pulse for key (b"" = measured, nothing usable), or None when not measured yet."""
    path = _cache_path(cache_dir or _default_cache_dir(), key)
    try:
        with open(path, "rb") as f:
            return f.read()
    except OSError:
        return None


def measure(url, stream_args, key, cache_dir=None):
    """Pulse bytes for the track at url (decoding it once through mpv), or None when decoding failed."""
    cache_dir = cache_dir or _default_cache_dir()
    hit = cached(key, cache_dir)
    if hit is not None:
        return hit
    if not url:
        return None
    import platform_compat as pc
    os.makedirs(cache_dir, exist_ok=True)
    raw_path = os.path.join(cache_dir, f"decode_{os.getpid()}.raw")
    cmd = [
        pc.get_binary_path("mpv"),
        "--no-config", "--no-video", "--really-quiet", "--untimed",
        "--ao=pcm", f"--ao-pcm-file={raw_path}", "--ao-pcm-waveheader=no",
        "--audio-format=s16", f"--audio-samplerate={ANALYSIS_RATE}", "--audio-channels=mono",
        f"--length={MAX_SECONDS}", "--network-timeout=10",
    ] + list(stream_args) + [url]
    try:
        kwargs = pc.get_daemon_popen_kwargs()
        kwargs.pop("start_new_session", None)
        done = subprocess.run(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                              timeout=DECODE_TIMEOUT, **kwargs)
        if done.returncode != 0 or not os.path.exists(raw_path):
            return None
        env = BassEnvelope(ANALYSIS_RATE)
        with open(raw_path, "rb") as f:
            rest = b""
            while True:
                chunk = f.read(_CHUNK)
                if not chunk:
                    break
                chunk = rest + chunk
                even = len(chunk) - (len(chunk) % 2)
                rest = chunk[even:]
                samples = array.array("h")
                samples.frombytes(chunk[:even])
                if sys.byteorder == "big":
                    samples.byteswap()
                env.add([x / 32768.0 for x in samples])
        pulse = env.pulses()
    except Exception as e:
        sys.stderr.write(f"[bass] measure failed: {e}\n")
        return None
    finally:
        try:
            os.remove(raw_path)
        except OSError:
            pass
    if not any(pulse):
        pulse = b""
    path = _cache_path(cache_dir, key)
    tmp = path + ".tmp"
    try:
        with open(tmp, "wb") as f:
            f.write(pulse)
        os.replace(tmp, path)
        _prune(cache_dir)
    except OSError:
        pass
    return pulse
