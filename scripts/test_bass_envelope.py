#!/usr/bin/env python3
"""Bass pulse: SimpMusic's BassEnvelope cases, ported (a bass hit pulses, treble and silence do not)."""
import math
import os
import shutil
import struct
import subprocess
import sys
import tempfile
import wave

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "backend"))
import bass_envelope as be  # noqa: E402

RATE = 8000


def envelope(seconds=2, amplitude=lambda ms: 0.8, between=lambda n: 0.0):
    """SimpMusic's fixture: a 60 Hz burst for the first 100 ms of every 500 ms, `between` in the gaps."""
    out = []
    for n in range(RATE * seconds):
        ms = n * 1000 // RATE
        if ms % 500 < 100:
            out.append(amplitude(ms) * math.sin(2 * math.pi * 60 * n / RATE))
        else:
            out.append(between(n))
    return be.pulses_from_samples(out, RATE)


def at(p, ms):
    i = ms * be.SLOTS_PER_SECOND // 1000
    return p[i] / 255.0 if 0 <= i < len(p) else 0.0


def pulses_on_hits_and_rests_between():
    p = envelope()
    assert at(p, 50) > 0.8 and at(p, 1050) > 0.8, (at(p, 50), at(p, 1050))
    assert at(p, 300) < 0.05 and at(p, 1300) < 0.05, (at(p, 300), at(p, 1300))


def high_frequencies_do_not_pulse():
    p = envelope(between=lambda n: 0.8 * math.sin(2 * math.pi * 2000 * n / RATE))
    assert at(p, 50) > 0.8, at(p, 50)
    assert at(p, 300) < 0.05, at(p, 300)


def quiet_verse_kicks_pulse_as_plainly_as_the_drop():
    p = envelope(seconds=8, amplitude=lambda ms: 0.2 if ms < 4000 else 0.8)
    assert at(p, 1050) > 0.8 and at(p, 6050) > 0.8, (at(p, 1050), at(p, 6050))
    assert at(p, 1300) < 0.05, at(p, 1300)


def silence_and_short():
    assert all(v == 0 for v in be.pulses_from_samples([0.0] * (RATE // 2), RATE))
    assert be.pulses_from_samples([], RATE) == b""


def local_wav_end_to_end():
    tmp = tempfile.mkdtemp()
    try:
        wav = os.path.join(tmp, "kicks.wav")
        with wave.open(wav, "wb") as w:
            w.setnchannels(1)
            w.setsampwidth(2)
            w.setframerate(RATE)
            frames = []
            for n in range(RATE * 6):
                ms = n * 1000 // RATE
                v = 0.8 * math.sin(2 * math.pi * 60 * n / RATE) if ms % 500 < 100 else 0.0
                frames.append(struct.pack("<h", int(v * 32767)))
            w.writeframes(b"".join(frames))
        cache = os.path.join(tmp, "cache")
        p = be.measure(wav, [], wav, cache_dir=cache)
        assert p is not None and abs(len(p) - 240) <= 4, None if p is None else len(p)
        assert max(p) >= 250 and at(p, 300) < 0.05, (max(p), at(p, 300))
        assert len(os.listdir(cache)) == 1
        real_run = subprocess.run

        def no_run(*a, **k):
            raise AssertionError("mpv ran although the pulse was cached")
        subprocess.run = no_run
        try:
            assert be.measure(wav, [], wav, cache_dir=cache) == p
        finally:
            subprocess.run = real_run
        # a decode that stops well short of the known length (a dropped stream) is not cached
        short_cache = os.path.join(tmp, "short")
        assert be.measure(wav, [], wav, cache_dir=short_cache, expect_s=60.0) is None
        assert not os.listdir(short_cache), os.listdir(short_cache)
        assert be.measure(wav, [], wav, cache_dir=short_cache, expect_s=6.0) is not None
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def missing_file():
    tmp = tempfile.mkdtemp()
    try:
        cache = os.path.join(tmp, "cache")
        assert be.measure(os.path.join(tmp, "nope.flac"), [], "nope", cache_dir=cache) is None
        assert not os.path.isdir(cache) or not os.listdir(cache)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def main():
    for case in (pulses_on_hits_and_rests_between, high_frequencies_do_not_pulse,
                 quiet_verse_kicks_pulse_as_plainly_as_the_drop, silence_and_short,
                 local_wav_end_to_end, missing_file):
        case()
    print("test_bass_envelope: OK")


if __name__ == "__main__":
    main()
