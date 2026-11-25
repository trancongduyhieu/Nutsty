#!/usr/bin/env python3
"""DAC output modes: mpv flags and the PipeWire rate drop-in. Temp dirs only, never the real
~/.config/pipewire. Run: python scripts/test_audio_output.py"""
import os
import shutil
import sys
import tempfile
import unittest
from pathlib import Path

BACKEND = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "backend"))
if BACKEND not in sys.path:
    sys.path.insert(0, BACKEND)

import audio_output as ao

RATE_LINE = "default.clock.allowed-rates = [ 44100 48000 88200 96000 176400 192000 ]"


class MpvArgsTest(unittest.TestCase):
    def test_four_combinations(self):
        self.assertEqual(ao.mpv_output_args({"enabled": True, "dac_mode": "exclusive"}), ["--audio-exclusive=yes"])
        self.assertEqual(ao.mpv_output_args({"enabled": False, "dac_mode": "exclusive"}), [])
        self.assertEqual(ao.mpv_output_args({"enabled": True, "dac_mode": "shared"}), [])
        self.assertEqual(ao.mpv_output_args({"enabled": True, "dac_mode": "rate_match"}), [])

    def test_constants(self):
        self.assertEqual(ao.RATES, [44100, 48000, 88200, 96000, 176400, 192000])
        self.assertEqual(ao.PIPEWIRE_DROPIN, Path.home() / ".config/pipewire/pipewire.conf.d/90-nutsty-rates.conf")


class RateDropinTest(unittest.TestCase):
    def setUp(self):
        self.dir = Path(tempfile.mkdtemp(prefix="nutsty_pw_"))

    def tearDown(self):
        shutil.rmtree(self.dir, ignore_errors=True)

    def test_write_creates_dir_and_line(self):
        conf_dir = self.dir / "pipewire.conf.d"
        res = ao.write_rate_dropin(conf_dir)
        self.assertTrue(res["written"])
        self.assertEqual(res["conflicts"], [])
        text = (conf_dir / "90-nutsty-rates.conf").read_text()
        self.assertIn("context.properties", text)
        self.assertIn(RATE_LINE, text)
        self.assertEqual(res["path"], str(conf_dir / "90-nutsty-rates.conf"))

    def test_existing_allowed_rates_blocks_write(self):
        (self.dir / "10-mine.conf").write_text("context.properties = {\n  default.clock.allowed-rates = [ 48000 ]\n}\n")
        (self.dir / "20-other.conf").write_text("context.properties = { default.clock.quantum = 1024 }\n")
        res = ao.write_rate_dropin(self.dir)
        self.assertFalse(res["written"])
        self.assertEqual(len(res["conflicts"]), 1)
        f, line = res["conflicts"][0]
        self.assertTrue(f.endswith("10-mine.conf"))
        self.assertIn("allowed-rates", line)
        self.assertFalse((self.dir / "90-nutsty-rates.conf").exists())

    def test_own_file_is_not_a_conflict(self):
        ao.write_rate_dropin(self.dir)
        self.assertEqual(ao.find_existing_allowed_rates(self.dir), [])
        self.assertTrue(ao.write_rate_dropin(self.dir)["written"])

    def test_missing_dir_has_no_conflicts(self):
        self.assertEqual(ao.find_existing_allowed_rates(self.dir / "nope"), [])

    def test_remove_only_touches_own_file(self):
        other = self.dir / "10-mine.conf"
        other.write_text("x")
        self.assertFalse(ao.remove_rate_dropin(self.dir))
        ao.write_rate_dropin(self.dir)
        self.assertTrue(ao.remove_rate_dropin(self.dir))
        self.assertFalse((self.dir / "90-nutsty-rates.conf").exists())
        self.assertTrue(other.exists())


class RestartKeepPositionTest(unittest.TestCase):
    def setUp(self):
        import json as _json
        from unittest import mock
        import player_daemon as pd
        self.pd = pd
        self.tmp = tempfile.mkdtemp(prefix="nutsty_restart_")
        self.settings = {"losslessEnabled": True, "dacOutputMode": "exclusive"}
        with open(os.path.join(self.tmp, "nutsty_settings.json"), "w") as f:
            _json.dump(self.settings, f)
        self.props = {"path": "/m/a.flac", "time-pos": 61.25, "pause": True, "volume": 70, "audio-exclusive": False}
        self.cmds, self.events = [], []
        self.ao_failed = False

        class FakeSock:
            def close(self):
                pass
        p = lambda n, v: mock.patch.object(pd, n, v)
        self.patches = [
            p("CONFIG_DIR", self.tmp), p("PROFILE_SUFFIX", ""),
            p("EXCLUSIVE_FAILED_FILE", os.path.join(self.tmp, "exfail")),
            p("get_mpv_property", lambda n: self.props.get(n)),
            p("send_mpv_cmd", lambda c, timeout=2.0: self.cmds.append(c) or {"error": "success"}),
            p("_stop_main_mpv", lambda: self.events.append("stop")),
            p("ensure_mpv", lambda force_shared=False: self.events.append(("start", force_shared)) or True),
            p("_ao_failed_in_log", lambda wait_s=2.5: self.ao_failed),
            mock.patch.object(pd.pc, "connect_mpv_socket", lambda *a, **k: FakeSock()),
        ]
        for x in self.patches:
            x.start()

    def tearDown(self):
        for x in reversed(self.patches):
            x.stop()
        shutil.rmtree(self.tmp, ignore_errors=True)

    def _loadfile(self):
        return [c for c in self.cmds if isinstance(c, dict) and c.get("name") == "loadfile"][-1]

    def test_restart_keeps_position_and_pause(self):
        res = self.pd.restart_mpv_keep_position()
        self.assertEqual(res, {"restarted": True, "exclusive_failed": False})
        self.assertEqual(self.events, ["stop", ("start", False)])
        lf = self._loadfile()
        self.assertEqual((lf["url"], lf["options"]["start"], lf["options"]["pause"]), ("/m/a.flac", "61.250", "yes"))
        self.assertNotIn(["set_property", "volume", 70], self.cmds)

    def test_no_restart_when_mode_already_right(self):
        self.props["audio-exclusive"] = True
        self.assertEqual(self.pd.restart_mpv_keep_position(), {"restarted": False, "exclusive_failed": False})
        self.assertEqual(self.events, [])

    def test_device_busy_falls_back_to_shared(self):
        self.ao_failed = True
        res = self.pd.restart_mpv_keep_position()
        self.assertTrue(res["exclusive_failed"])
        self.assertEqual(self.events, ["stop", ("start", False), "stop", ("start", True)])
        self.assertEqual(self._loadfile()["options"]["start"], "61.250")
        self.assertIn(["set_property", "volume", 70], self.cmds)

    def test_leaving_exclusive_restores_volume(self):
        self.settings["dacOutputMode"] = "shared"
        import json as _json
        with open(os.path.join(self.tmp, "nutsty_settings.json"), "w") as f:
            _json.dump(self.settings, f)
        self.props["audio-exclusive"] = True
        self.assertTrue(self.pd.restart_mpv_keep_position()["restarted"])
        self.assertIn(["set_property", "volume", 70], self.cmds)


if __name__ == "__main__":
    unittest.main()
