#!/usr/bin/env python3
"""Tidal in the play path of player_daemon: resolve order, Listen Along suspension,
mid-song recovery. No mpv, no network: every outside call is faked."""
import contextlib
import io
import json
import os
import shutil
import sys
import tempfile
import types
import unittest
from unittest import mock

backend_dir = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "backend"))
if backend_dir not in sys.path:
    sys.path.insert(0, backend_dir)

import player_daemon as pd

TIDAL = {"url": "https://tidal/yellow.flac", "codec": "FLAC", "bit_depth": 16, "sample_rate": 44100,
         "audio_quality": "LOSSLESS", "tidal_id": 101, "expires_at": 9e12}


class FakeTidal:
    def __init__(self):
        self.calls = []
        self.result = dict(TIDAL)
        self.logged_in = True
        self.on_call = None

    def resolve(self, video_id, title, artist, duration_s, quality, budget_s=4.0):
        self.calls.append((video_id, title, artist, duration_s, quality))
        if self.on_call:
            self.on_call()
        return self.result

    def status(self):
        return {"logged_in": self.logged_in, "account": "duy", "can_hires": True, "needs_relogin": False}


def fake_ytmusic():
    m = types.ModuleType("ytmusic_helper")
    m.STREAM_CACHE_FILE = "/nonexistent"
    m.load_json = lambda path, default: {}
    m.invalidate_cached_stream_url = lambda vid: None
    m.resolve_stream_url = lambda vid, q, force_fresh=False: {"stream_url": f"https://yt/{vid}", "user_agent": "UA"}
    return m


class LosslessResolveTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp(prefix="nutsty_lossless_test_")
        self.settings = {"losslessEnabled": True, "losslessQuality": "lossless", "dacOutputMode": "shared"}
        self._write_settings()
        self.tidal = FakeTidal()
        self.mpv_cmds = []
        self.props = {"time-pos": 42.5, "pause": False, "path": "https://tidal/yellow.flac"}
        self.local_file = None
        p = lambda name, val: mock.patch.object(pd, name, val)
        self.patches = [
            p("CONFIG_DIR", self.tmp),
            p("PROFILE_SUFFIX", ""),
            p("LOSSLESS_SUSPEND_FILE", os.path.join(self.tmp, "suspended")),
            p("NOW_SOURCE_FILE", os.path.join(self.tmp, "now_source.json")),
            p("TIDAL_SKIP_FILE", os.path.join(self.tmp, "tidal_skip.json")),
            p("PLAY_REQ_FILE", os.path.join(self.tmp, "active_play.json")),
            p("_load_tidal", lambda: self.tidal),
            p("send_mpv_cmd", self._send),
            p("get_mpv_property", lambda name: self.props.get(name)),
            p("find_local_downloaded_file", lambda vid="", title="", artist="": self.local_file),
            mock.patch.dict(sys.modules, {"ytmusic_helper": fake_ytmusic()}),
        ]
        for x in self.patches:
            x.start()

    def tearDown(self):
        for x in reversed(self.patches):
            x.stop()
        shutil.rmtree(self.tmp, ignore_errors=True)

    def _write_settings(self):
        with open(os.path.join(self.tmp, "nutsty_settings.json"), "w") as f:
            json.dump(self.settings, f)

    def _send(self, cmd, timeout=2.0):
        self.mpv_cmds.append(cmd)
        return {"error": "success"}

    def _loadfiles(self):
        return [c for c in self.mpv_cmds if (isinstance(c, dict) and c.get("name") == "loadfile")
                or (isinstance(c, list) and c and c[0] == "loadfile")]

    def _run(self, *args):
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            pd.execute_command(list(args))
        return json.loads(out.getvalue().strip().splitlines()[-1])

    # --- resolve order ---------------------------------------------------------------
    def test_tidal_used_when_enabled(self):
        box = {}
        url = pd.resolve_media_path("ytdl://vid1", "Yellow", "Coldplay", source_out=box, duration_s=266)
        self.assertEqual(url, TIDAL["url"])
        self.assertEqual(box["source"], "tidal")
        self.assertEqual(box["tidal"]["bit_depth"], 16)
        self.assertEqual(self.tidal.calls[0], ("vid1", "Yellow", "Coldplay", 266, "lossless"))

    def test_tidal_skipped_when_disabled(self):
        self.settings["losslessEnabled"] = False
        self._write_settings()
        box = {}
        url = pd.resolve_media_path("ytdl://vid1", "Yellow", "Coldplay", source_out=box)
        self.assertEqual(url, "https://yt/vid1")
        self.assertEqual(box["source"], "youtube")
        self.assertEqual(self.tidal.calls, [])

    def test_tidal_skipped_when_logged_out(self):
        self.tidal.logged_in = False
        self.assertEqual(pd.resolve_media_path("ytdl://vid1", "Yellow", "Coldplay"), "https://yt/vid1")
        self.assertEqual(self.tidal.calls, [])

    def test_quality_setting_is_passed(self):
        self.settings["losslessQuality"] = "hires"
        self._write_settings()
        pd.resolve_media_path("ytdl://vid1", "Yellow", "Coldplay")
        self.assertEqual(self.tidal.calls[0][4], "hires")

    def test_downloaded_file_still_wins(self):
        self.local_file = os.path.join(self.tmp, "Yellow.opus")
        open(self.local_file, "w").close()
        box = {}
        self.assertEqual(pd.resolve_media_path("ytdl://vid1", "Yellow", "Coldplay", source_out=box), self.local_file)
        self.assertEqual(box["source"], "local")
        self.assertEqual(self.tidal.calls, [])

    def test_tidal_none_falls_back_to_youtube(self):
        self.tidal.result = None
        self.assertEqual(pd.resolve_media_path("ytdl://vid1", "Yellow", "Coldplay"), "https://yt/vid1")

    def test_tidal_exception_falls_back_to_youtube(self):
        def boom():
            raise RuntimeError("tidal broke")
        self.tidal.on_call = boom
        self.assertEqual(pd.resolve_media_path("ytdl://vid1", "Yellow", "Coldplay"), "https://yt/vid1")

    def test_suspended_skips_tidal(self):
        open(pd.LOSSLESS_SUSPEND_FILE, "w").close()
        self.assertEqual(pd.resolve_media_path("ytdl://vid1", "Yellow", "Coldplay"), "https://yt/vid1")
        self.assertEqual(self.tidal.calls, [])

    def test_skip_tidal_argument(self):
        self.assertEqual(pd.resolve_media_path("ytdl://vid1", "Yellow", "Coldplay", skip_tidal=True), "https://yt/vid1")
        self.assertEqual(self.tidal.calls, [])

    def test_superseded_epoch_ignores_tidal_result(self):
        pd.record_active_play_epoch(100, "ytdl://vid1", "vid1")
        self.tidal.on_call = lambda: pd.record_active_play_epoch(200, "ytdl://vid2", "vid2")
        self.assertEqual(pd.resolve_media_path("ytdl://vid1", "Yellow", "Coldplay", my_epoch=100), "")

    def test_crossfade_path_uses_tidal(self):
        url, ua, path, vid = pd._resolve_for_crossfade("ytdl://vid1", "Yellow", "Coldplay", 0)
        self.assertEqual(url, TIDAL["url"])
        self.assertEqual(vid, "vid1")

    def test_lossless_settings_normalized(self):
        self.settings = {"losslessEnabled": True, "losslessQuality": "ultra", "dacOutputMode": "weird"}
        self._write_settings()
        self.assertEqual(pd.get_lossless_settings(), {"enabled": True, "quality": "lossless", "dac_mode": "shared"})

    def test_dac_mode_without_tidal(self):
        # chosen in Settings with Tidal off: local FLAC still goes to the DAC that way
        self.settings = {"losslessEnabled": False, "dacOutputMode": "rate_match", "dacModeStandalone": True}
        self._write_settings()
        with mock.patch.object(pd.pc, "IS_WINDOWS", False):
            self.assertEqual(pd.get_lossless_settings()["dac_mode"], "rate_match")

    def test_exclusive_is_windows_only(self):
        # Linux: PipeWire refuses an exclusive stream while the shell keeps one on the DAC
        self.settings = {"dacOutputMode": "exclusive", "dacModeStandalone": True}
        self._write_settings()
        with mock.patch.object(pd.pc, "IS_WINDOWS", False):
            self.assertEqual(pd.get_lossless_settings()["dac_mode"], "shared")
        with mock.patch.object(pd.pc, "IS_WINDOWS", True):
            self.assertEqual(pd.get_lossless_settings()["dac_mode"], "exclusive")

    def test_old_dac_mode_saved_with_tidal_off_stays_shared(self):
        # saved before the DAC mode stood alone, it only counted while lossless was on
        self.settings = {"losslessEnabled": False, "dacOutputMode": "exclusive"}
        self._write_settings()
        self.assertEqual(pd.get_lossless_settings()["dac_mode"], "shared")

    # --- Listen Along suspension -----------------------------------------------------
    def test_suspend_reloads_youtube_at_position(self):
        pd.record_now_source("vid1", "tidal", TIDAL)
        pd.record_active_play_epoch(100, "ytdl://vid1", "vid1")
        res = self._run("lossless_suspend", "1")
        self.assertEqual(res, {"suspended": True, "reloaded": True})
        self.assertTrue(os.path.exists(pd.LOSSLESS_SUSPEND_FILE))
        lf = self._loadfiles()[-1]
        self.assertEqual(lf["url"], "https://yt/vid1")
        self.assertEqual(lf["options"]["start"], "42.500")
        self.assertEqual(self.tidal.calls, [])
        self.assertEqual(pd.read_now_source()["source"], "youtube")

    def test_suspend_noop_when_playing_youtube(self):
        pd.record_now_source("vid1", "youtube")
        self.assertEqual(self._run("lossless_suspend", "1"), {"suspended": True, "reloaded": False})
        self.assertEqual(self._loadfiles(), [])

    def test_suspend_noop_when_another_song_was_requested(self):
        pd.record_now_source("vid1", "tidal", TIDAL)
        pd.record_active_play_epoch(200, "ytdl://vid2", "vid2")
        self.assertEqual(self._run("lossless_suspend", "1"), {"suspended": True, "reloaded": False})

    def test_unsuspend_does_not_reload(self):
        open(pd.LOSSLESS_SUSPEND_FILE, "w").close()
        pd.record_now_source("vid1", "youtube")
        self.assertEqual(self._run("lossless_suspend", "0"), {"suspended": False, "reloaded": False})
        self.assertFalse(os.path.exists(pd.LOSSLESS_SUSPEND_FILE))
        self.assertEqual(self._loadfiles(), [])

    def test_flag_set_during_tidal_lookup_falls_back(self):
        # Listen Along started while Tidal was answering: the slow answer must not win
        self.tidal.on_call = lambda: open(pd.LOSSLESS_SUSPEND_FILE, "w").close()
        box = {}
        self.assertEqual(pd.resolve_media_path("ytdl://vid1", "Yellow", "Coldplay", source_out=box), "https://yt/vid1")
        self.assertEqual(box["source"], "youtube")

    def test_play_that_lost_the_race_reloads_youtube(self):
        # lossless_suspend ran before play recorded its Tidal source, so it reloaded nothing
        pd.record_active_play_epoch(100, "ytdl://vid1", "vid1")
        pd.record_now_source("vid1", "tidal", TIDAL)
        open(pd.LOSSLESS_SUSPEND_FILE, "w").close()
        self.assertTrue(pd.enforce_listen_along_suspension())
        self.assertEqual(self._loadfiles()[-1]["url"], "https://yt/vid1")
        self.assertEqual(pd.read_now_source()["source"], "youtube")

    def test_enforce_is_noop_without_flag(self):
        pd.record_now_source("vid1", "tidal", TIDAL)
        self.assertFalse(pd.enforce_listen_along_suspension())
        self.assertEqual(self._loadfiles(), [])

    # --- mid-song stream failure -----------------------------------------------------
    def test_tidal_stream_error_falls_back_at_position(self):
        pd.record_now_source("vid1", "tidal", TIDAL)
        pd.record_active_play_epoch(100, "ytdl://vid1", "vid1")
        res = self._run("stream_failed", "30")
        self.assertTrue(res["reloaded"])
        lf = self._loadfiles()[-1]
        self.assertEqual(lf["url"], "https://yt/vid1")
        self.assertEqual(lf["options"]["start"], "30.000")
        # the song now skips Tidal for a while instead of failing again
        self.tidal.calls.clear()
        pd.resolve_media_path("ytdl://vid1", "Yellow", "Coldplay")
        self.assertEqual(self.tidal.calls, [])
        pd.resolve_media_path("ytdl://vid7", "Other", "Coldplay")
        self.assertEqual(len(self.tidal.calls), 1)

    def test_stream_failed_ignored_for_youtube(self):
        pd.record_now_source("vid1", "youtube")
        self.assertFalse(self._run("stream_failed", "30")["reloaded"])
        self.assertEqual(self._loadfiles(), [])


if __name__ == "__main__":
    unittest.main()
