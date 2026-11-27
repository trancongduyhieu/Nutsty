#!/usr/bin/env python3
"""Bass pulse: SimpMusic's BassEnvelope cases, ported (a bass hit pulses, treble and silence do not)."""
import math
import os
import sys

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


def main():
    for case in (pulses_on_hits_and_rests_between, high_frequencies_do_not_pulse,
                 quiet_verse_kicks_pulse_as_plainly_as_the_drop, silence_and_short):
        case()
    print("test_bass_envelope: OK")


if __name__ == "__main__":
    main()
