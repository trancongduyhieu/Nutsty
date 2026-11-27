"""How hard a track's bass hits over time, for the artwork backdrop's pulse.

The level comes from SimpMusic's BassEnvelope (core/domain/.../player/BassEnvelope.kt): mono samples go
through two one-pole low-passes at 150 Hz and each 25 ms slot keeps the RMS of what passed. From those
levels two channels are stored, one byte (0..255) per slot each:

- hit: how sharply the bass just rose (from its dip in the last 100 ms), judged against the sharpest rise
  within 2 s either side (a rise of 60% of the track's loud level always counts in full), then weighted by how loud that stretch is against the whole track. A kick hits;
  a held 808 hits once when it starts, not for as long as it rings; a drop hits harder than a verse, and a
  quiet verse still hits (SimpMusic judged the level itself, so a held bass kept the pulse at full and a
  verse hit as hard as the drop).
- body: the bass that stays, the quietest slot within 150 ms either side against the track's loud hits.
  Spaced kicks leave gaps and score near 0; a held bass or a thick bass line fills it.
"""
import array
import math
import os
import subprocess
import sys
import time
from collections import deque

SLOTS_PER_SECOND = 40
CUTOFF_HZ = 150.0
RISE_BASE_SLOTS = 4      # a rise is measured from the quietest of the last 100 ms (the dip before a kick)
HIT_FLOOR = 0.25         # rises under a quarter of the sharpest nearby one do not hit
RISE_FULL = 0.6          # a rise of 60% of the track's loud level is a full hit, whatever rose more nearby
SECTION_MIN = 0.45       # a stretch at a quarter of the track's loud level still hits at ~0.59 of a drop
BODY_HALF_SLOTS = 6      # body: the quietest slot within 150 ms either side
REFERENCE_PERCENTILE = 0.95
WINDOW_SLOTS = 2 * SLOTS_PER_SECOND
QUIET_SHARE = 0.15
HISTOGRAM_BINS = 200
MIN_DECADE = -5.0
MAX_SLOTS = 6 * 3600 * SLOTS_PER_SECOND


class BassEnvelope:
    """Feed a continuous mono stream with add(); channels() closes it and returns (hit, body)."""

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

    def channels(self):
        self._store(self._slot, self._sum, self._count)
        self._sum, self._count = 0.0, 0
        return channels_from_levels(self.levels)


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


def _window_max(values, half):
    """max over [i-half, i+half] for every i (sliding window, O(n))."""
    n = len(values)
    out = [0.0] * n
    window = deque()
    nxt = 0
    for i in range(n):
        hi = min(n - 1, i + half)
        while nxt <= hi:
            while window and values[window[-1]] <= values[nxt]:
                window.pop()
            window.append(nxt)
            nxt += 1
        while window[0] < i - half:
            window.popleft()
        out[i] = values[window[0]]
    return out


def _byte(x):
    return int(round(min(max(x, 0.0), 1.0) * 255))


def channels_from_levels(levels):
    """(hit, body): one byte per slot each, as described at the top of this module."""
    n = len(levels)
    reference = _reference(levels)
    if reference <= 0 or n == 0:
        return bytes(n), bytes(n)
    quiet = reference * QUIET_SHARE
    # From the dip just before, not an average: dense kicks (jumpstyle, hardstyle, ~0.25 s apart) leave
    # the last one's tail in any average, and each new kick would barely count as a rise
    rises = [0.0] * n
    for i, v in enumerate(levels):
        base = min(levels[max(0, i - RISE_BASE_SLOTS):i]) if i > 0 else 0.0
        rises[i] = max(0.0, v - base)
    local_rise = _window_max(rises, WINDOW_SLOTS)
    local_level = _window_max(levels, WINDOW_SLOTS)
    # Kicks over a held bass line rise less than the one kick that came in from silence; without the
    # cap that single entry would turn every kick after it into a third of a hit for 2 s
    norm = [max(quiet, min(r, reference * RISE_FULL)) for r in local_rise]
    lows = [-v for v in _window_max([-v for v in levels], BODY_HALF_SLOTS)]
    hit = bytearray(n)
    body = bytearray(n)
    for i in range(n):
        sharp = (rises[i] / norm[i] - HIT_FLOOR) / (1.0 - HIT_FLOOR)
        section = SECTION_MIN + (1.0 - SECTION_MIN) * min(1.0, local_level[i] / reference)
        hit[i] = _byte(sharp * section)
        body[i] = _byte(lows[i] / reference)
    return bytes(hit), bytes(body)


def analyze(samples, rate):
    env = BassEnvelope(rate)
    env.add(samples)
    return env.channels()


# ---- measuring a whole track and caching it ----

# The bass sits below 150 Hz, so 1 kHz keeps all of it (mpv's resampler drops what is above 500 Hz)
# while the sample loop below does an eighth of the work it would at 8 kHz
ANALYSIS_RATE = 1000
MAX_SECONDS = 15 * 60
DECODE_TIMEOUT = 120
CACHE_KEEP = 500
_CHUNK = 1 << 16   # ~33 s of audio per read; the GIL is let go between reads (Windows runs this in-process)


def _cache_path(cache_dir, key):
    import hashlib
    return os.path.join(cache_dir, hashlib.sha1(key.encode("utf-8", "replace")).hexdigest() + ".bp")


def _default_cache_dir():
    import platform_compat as pc
    return os.path.join(pc.get_cache_dir(), "bass")


def _prune(cache_dir):
    try:
        now = time.time()
        for n in os.listdir(cache_dir):
            f = os.path.join(cache_dir, n)
            if n.endswith((".raw", ".tmp")) and now - os.path.getmtime(f) > 3600:
                os.remove(f)   # left behind by a killed measurement
            elif n.endswith(".bass"):
                os.remove(f)   # one-channel pulses from before hit/body: measured again when played
        names = [os.path.join(cache_dir, n) for n in os.listdir(cache_dir) if n.endswith(".bp")]
        if len(names) <= CACHE_KEEP:
            return
        names.sort(key=lambda f: os.path.getmtime(f))
        for f in names[: len(names) - CACHE_KEEP]:
            os.remove(f)
    except OSError:
        pass


def cached(key, cache_dir=None):
    """(hit, body) stored for key ((b"", b"") = measured, nothing usable), or None when not measured yet."""
    path = _cache_path(cache_dir or _default_cache_dir(), key)
    try:
        with open(path, "rb") as f:
            data = f.read()
    except OSError:
        return None
    return data[0::2], data[1::2]   # stored interleaved: hit, body per slot


def measure(url, stream_args, key, cache_dir=None, expect_s=0.0):
    """(hit, body) bytes for the track at url (decoding it once through mpv), or None when decoding failed.
    expect_s: the track's known length; a decode that stops well short of it (a dropped stream) is not cached."""
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
                time.sleep(0)
        if expect_s > 0 and env.n / ANALYSIS_RATE < 0.9 * min(expect_s, MAX_SECONDS):
            sys.stderr.write(f"[bass] decode stopped at {env.n / ANALYSIS_RATE:.0f}s of {expect_s:.0f}s\n")
            return None
        hit, body = env.channels()
    except Exception as e:
        sys.stderr.write(f"[bass] measure failed: {e}\n")
        return None
    finally:
        try:
            os.remove(raw_path)
        except OSError:
            pass
    if not any(hit) and not any(body):
        hit = body = b""
    path = _cache_path(cache_dir, key)
    tmp = path + ".tmp"
    try:
        with open(tmp, "wb") as f:
            f.write(bytes(b for pair in zip(hit, body) for b in pair))
        os.replace(tmp, path)
        _prune(cache_dir)
    except OSError:
        pass
    return hit, body
