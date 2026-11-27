#!/usr/bin/env python3
"""Bass pulse: a hit pulses, treble and silence do not, a drop hits harder than a verse, a held bass breathes."""
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


def kicks(seconds, amplitude=lambda ms: 0.8, between=lambda n: 0.0):
    """SimpMusic's fixture: a 60 Hz burst for the first 100 ms of every 500 ms, `between` in the gaps."""
    out = []
    for n in range(RATE * seconds):
        ms = n * 1000 // RATE
        if ms % 500 < 100:
            out.append(amplitude(ms) * math.sin(2 * math.pi * 60 * n / RATE))
        else:
            out.append(between(n))
    return out


def held(seconds, amp=0.8):
    return [amp * math.sin(2 * math.pi * 60 * n / RATE) for n in range(int(RATE * seconds))]


def analyze(samples):
    return be.analyze(samples, RATE)


def peak(ch, ms0, ms1):
    """The strongest value (0..1) of a channel between two times."""
    a, b = ms0 * be.SLOTS_PER_SECOND // 1000, max(ms0 * be.SLOTS_PER_SECOND // 1000 + 1, ms1 * be.SLOTS_PER_SECOND // 1000)
    return max(ch[a:b] or b"\0") / 255.0


def pulses_on_hits_and_rests_between():
    hit, _ = analyze(kicks(2))
    assert peak(hit, 0, 100) > 0.8 and peak(hit, 1000, 1100) > 0.8, (peak(hit, 0, 100), peak(hit, 1000, 1100))
    assert peak(hit, 250, 450) < 0.05 and peak(hit, 1250, 1450) < 0.05, (peak(hit, 250, 450), peak(hit, 1250, 1450))


def high_frequencies_do_not_pulse():
    hit, body = analyze(kicks(2, between=lambda n: 0.8 * math.sin(2 * math.pi * 2000 * n / RATE)))
    assert peak(hit, 1000, 1100) > 0.8, peak(hit, 1000, 1100)
    assert peak(hit, 250, 450) < 0.05 and peak(body, 250, 450) < 0.05, (peak(hit, 250, 450), peak(body, 250, 450))


def drop_hits_harder_but_verse_still_pulses():
    hit, _ = analyze(kicks(8, amplitude=lambda ms: 0.2 if ms < 4000 else 0.8))
    verse, drop = peak(hit, 1000, 1100), peak(hit, 6000, 6100)
    assert verse > 0.35, verse                    # a quiet verse's kicks still show
    assert drop > 0.85, drop
    assert drop - verse > 0.25, (verse, drop)     # and the drop plainly hits harder
    assert peak(hit, 1250, 1450) < 0.05


def held_bass_breathes_instead_of_holding_the_pulse():
    # two seconds of kicks, then four seconds of one held 60 Hz note as loud as the kicks
    hit, body = analyze(kicks(2) + held(4.0))
    assert peak(hit, 2000, 2150) > 0.6, peak(hit, 2000, 2150)          # its start is a hit
    assert peak(hit, 2600, 5700) < 0.1, peak(hit, 2600, 5700)          # holding it is not
    assert min(body[int(2.6 * 40):int(5.7 * 40)]) / 255 > 0.6, min(body[104:228])  # it fills the body
    assert peak(body, 300, 1900) < 0.2, peak(body, 300, 1900)          # spaced kicks do not


def silence_and_short():
    hit, body = analyze([0.0] * (RATE // 2))
    assert not any(hit) and not any(body)
    assert analyze([]) == (b"", b"")


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
        assert p is not None and abs(len(p[0]) - 240) <= 4 and len(p[1]) == len(p[0]), p and len(p[0])
        assert max(p[0]) >= 200 and peak(p[0], 250, 450) < 0.05, (max(p[0]), peak(p[0], 250, 450))
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
                 drop_hits_harder_but_verse_still_pulses, held_bass_breathes_instead_of_holding_the_pulse,
                 silence_and_short,
                 local_wav_end_to_end, missing_file):
        case()
    print("test_bass_envelope: OK")


if __name__ == "__main__":
    main()
