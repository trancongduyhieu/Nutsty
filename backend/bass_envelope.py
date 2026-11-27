"""How hard a track's bass hits over time, for the artwork backdrop's pulse.

Port of SimpMusic's BassEnvelope (core/domain/.../player/BassEnvelope.kt): mono samples go through two
one-pole low-passes at 150 Hz, each 25 ms slot keeps the RMS of what passed, and a slot's pulse is judged
against the hardest hit within 2 s either side (never less than 0.15 of the track's loud hits), so a quiet
verse pulses as plainly as a loud drop. The whole track is measured, then every slot's pulse is stored as
one byte (0..255).
"""
import math
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
