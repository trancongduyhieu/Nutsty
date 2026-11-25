#!/usr/bin/env python3
"""Truthful quality label data: get_audio_specs_dict and audio_output.read_alsa_running_rate.
No real mpv and no real /proc: both are faked. Run: python scripts/test_audio_specs.py"""
import json
import os
import shutil
import sys
import tempfile
import unittest
from unittest import mock

BACKEND = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "backend"))
if BACKEND not in sys.path:
    sys.path.insert(0, BACKEND)

import audio_output
import player_daemon as pd


def make_card(root, card, status, rate):
    d = os.path.join(root, card, "pcm0p", "sub0")
    os.makedirs(d)
    with open(os.path.join(d, "status"), "w") as f:
        f.write(f"state: {status}\nowner_pid   : 1234\n")
    with open(os.path.join(d, "hw_params"), "w") as f:
        f.write("closed\n" if rate is None else f"access: RW_INTERLEAVED\nformat: S32_LE\nchannels: 2\nrate: {rate} ({rate}/1)\n")


class AlsaRateTest(unittest.TestCase):
    def setUp(self):
        self.root = tempfile.mkdtemp(prefix="nutsty_asound_")

    def tearDown(self):
        shutil.rmtree(self.root, ignore_errors=True)

    def test_running_card_rate(self):
        make_card(self.root, "card0", "closed", None)
        make_card(self.root, "card1", "RUNNING", 48000)
        self.assertEqual(audio_output.read_alsa_running_rate(self.root), 48000)

    def test_no_running_card(self):
        make_card(self.root, "card0", "closed", None)
        make_card(self.root, "card1", "PREPARED", 44100)
        self.assertIsNone(audio_output.read_alsa_running_rate(self.root))

    def test_missing_root(self):
        self.assertIsNone(audio_output.read_alsa_running_rate(os.path.join(self.root, "nope")))


class AudioSpecsTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp(prefix="nutsty_specs_")
        self.props = {}
        self.settings = {"losslessEnabled": True, "losslessQuality": "lossless", "dacOutputMode": "shared"}
        with open(os.path.join(self.tmp, "nutsty_settings.json"), "w") as f:
            json.dump(self.settings, f)
        self.alsa_rate = None
        self.patches = [
            mock.patch.object(pd, "get_mpv_property", lambda name: self.props.get(name)),
            mock.patch.object(pd, "CONFIG_DIR", self.tmp),
            mock.patch.object(pd, "PROFILE_SUFFIX", ""),
            mock.patch.object(pd, "NOW_SOURCE_FILE", os.path.join(self.tmp, "now.json")),
            mock.patch.object(pd, "LOSSLESS_SUSPEND_FILE", os.path.join(self.tmp, "suspended")),
            mock.patch.object(audio_output, "read_alsa_running_rate", lambda *a: self.alsa_rate),
            mock.patch.object(pd.pc, "IS_WINDOWS", False),
        ]
        for p in self.patches:
            p.start()

    def tearDown(self):
        for p in reversed(self.patches):
            p.stop()
        shutil.rmtree(self.tmp, ignore_errors=True)

    def test_unknown_is_not_made_up(self):
        s = pd.get_audio_specs_dict()
        self.assertEqual(s["codec"], "")
        self.assertIsNone(s["sample_rate"])
        self.assertIsNone(s["bitrate_kbps"])
        self.assertIsNone(s["bit_depth"])
        self.assertIsNone(s["channels"])
        self.assertFalse(s["lossless"])
        self.assertEqual((s["bitrate_str"], s["sample_rate_str"], s["channels_str"]), ("", "", ""))

    def test_local_flac_24bit(self):
        self.props = {"audio-codec-name": "flac", "path": "/home/u/Music/a.flac",
                      "audio-params": {"samplerate": 96000, "format": "s32", "channel-count": 2}}
        s = pd.get_audio_specs_dict()
        self.assertEqual((s["codec"], s["bit_depth"], s["sample_rate"], s["lossless"]), ("FLAC", 24, 96000, True))
        self.assertEqual(s["source"], "local")
        self.assertEqual(s["channels"], 2)

    def test_flac_16bit(self):
        self.props = {"audio-codec-name": "flac", "path": "/m/b.flac",
                      "audio-params": {"samplerate": 44100, "format": "s16", "channel-count": 2}}
        self.assertEqual(pd.get_audio_specs_dict()["bit_depth"], 16)

    def test_opus_is_lossy(self):
        self.props = {"audio-codec-name": "opus", "audio-bitrate": 141000,
                      "path": "https://rr1.googlevideo.com/videoplayback?id=x",
                      "audio-params": {"samplerate": 48000, "format": "floatp", "channel-count": 2}}
        s = pd.get_audio_specs_dict()
        self.assertFalse(s["lossless"])
        self.assertIsNone(s["bit_depth"])
        self.assertEqual((s["codec"], s["bitrate_kbps"], s["source"]), ("OPUS", 141, "youtube"))

    def test_tidal_bit_depth_from_stream(self):
        url = "file:///tmp/nutsty_tidal/tidal_1_HI_RES_LOSSLESS.mpd"
        pd.record_now_source("vid1", "tidal", {"url": url, "bit_depth": 24, "sample_rate": 192000})
        self.props = {"audio-codec-name": "flac", "path": url,
                      "audio-params": {"samplerate": 192000, "format": "floatp", "channel-count": 2}}
        s = pd.get_audio_specs_dict()
        self.assertEqual((s["source"], s["bit_depth"], s["lossless"]), ("tidal", 24, True))

    def test_stale_tidal_record_not_trusted(self):
        pd.record_now_source("vid1", "tidal", {"url": "https://tidal/old.flac", "bit_depth": 24})
        self.props = {"audio-codec-name": "opus", "path": "https://rr1.googlevideo.com/x",
                      "audio-params": {"samplerate": 48000, "format": "floatp"}}
        self.assertEqual(pd.get_audio_specs_dict()["source"], "youtube")

    def test_output_rate_only_when_different(self):
        self.props = {"audio-codec-name": "flac", "path": "/m/b.flac",
                      "audio-params": {"samplerate": 44100, "format": "s16"}}
        self.alsa_rate = 48000
        self.assertEqual(pd.get_audio_specs_dict()["output_rate"], 48000)
        self.alsa_rate = 44100
        self.assertIsNone(pd.get_audio_specs_dict()["output_rate"])

    def test_windows_mixer_flag(self):
        self.props = {"audio-codec-name": "flac", "path": "C:\\Music\\a.flac",
                      "audio-params": {"samplerate": 44100, "format": "s16"}}
        with mock.patch.object(pd.pc, "IS_WINDOWS", True):
            s = pd.get_audio_specs_dict()
            self.assertTrue(s["via_windows_mixer"])
            self.assertIsNone(s["output_rate"])
        with open(os.path.join(self.tmp, "nutsty_settings.json"), "w") as f:
            json.dump(dict(self.settings, dacOutputMode="exclusive"), f)
        with mock.patch.object(pd.pc, "IS_WINDOWS", True):
            self.assertFalse(pd.get_audio_specs_dict()["via_windows_mixer"])

    def test_suspended_flag(self):
        self.props = {"audio-codec-name": "opus", "path": "https://rr1.googlevideo.com/x"}
        self.assertFalse(pd.get_audio_specs_dict()["lossless_suspended"])
        open(pd.LOSSLESS_SUSPEND_FILE, "w").close()
        self.assertTrue(pd.get_audio_specs_dict()["lossless_suspended"])


if __name__ == "__main__":
    unittest.main()
