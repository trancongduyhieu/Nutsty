#!/usr/bin/env python3
"""Offline tests for backend/tidal_source.py: a fake tidalapi session, no network."""
import contextlib
import io
import os
import shutil
import sys
import tempfile
import threading
import time
import unittest
from unittest import mock

backend_dir = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "backend"))
if backend_dir not in sys.path:
    sys.path.insert(0, backend_dir)

import tidal_source as ts

FAKE_TOKEN = "SECRET-ACCESS-TOKEN-123"


class FakeArtist:
    def __init__(self, name):
        self.name = name


class FakeManifest:
    def __init__(self, urls, encrypted=False, codec="FLAC"):
        self._urls = urls
        self.is_encrypted = encrypted
        self._codec = codec

    def get_urls(self):
        return self._urls

    def get_codecs(self):
        return self._codec


class FakeStream:
    def __init__(self, kind, quality, bits, rate, urls=None, encrypted=False):
        self.is_mpd = kind == "mpd"
        self.is_bts = kind == "bts"
        self.audio_quality = quality
        self.bit_depth = bits
        self.sample_rate = rate
        self._manifest = FakeManifest(urls or [], encrypted)

    def get_stream_manifest(self):
        return self._manifest

    def get_manifest_data(self):
        return "<MPD>fake</MPD>"


class FakeTrack:
    def __init__(self, tid, name, artists, duration, stream, version=None, session=None):
        self.id = tid
        self.name = name
        self.version = version
        self.artists = [FakeArtist(a) for a in artists]
        self.duration = duration
        self.audio_modes = ["STEREO"]
        self._stream = stream
        self.session = session
        self.stream_calls = 0

    def get_stream(self):
        self.stream_calls += 1
        if callable(self._stream):
            return self._stream(self)
        return self._stream


class FakeConfig:
    quality = "LOSSLESS"


class FakeUser:
    id = 7
    username = "duy"
    email = "duy@example.com"


class FakeSession:
    def __init__(self, tracks, search_error=None, search_delay=0.0, max_quality="HI_RES_LOSSLESS"):
        self.config = FakeConfig()
        self.user = FakeUser()
        self.access_token = FAKE_TOKEN
        self.tracks = tracks
        self.search_error = search_error
        self.search_delay = search_delay
        self.search_calls = 0
        self.max_quality = max_quality
        for t in tracks:
            t.session = self

    def load_session_from_file(self, path):
        return True

    def save_session_to_file(self, path):
        with open(path, "w") as f:
            f.write('{"access_token": {"data": "%s"}}' % FAKE_TOKEN)

    def check_login(self):
        return True

    def search(self, query, models=None, limit=10):
        self.search_calls += 1
        if self.search_delay:
            time.sleep(self.search_delay)
        if self.search_error:
            raise self.search_error
        return {"tracks": list(self.tracks)}

    def track(self, tid):
        for t in self.tracks:
            if t.id == tid:
                return t
        raise KeyError(tid)

    def subscription_info(self):
        return {"highestSoundQuality": self.max_quality, "subscription": {"type": "HIFI"}}


class Http401(Exception):
    def __init__(self, sub_status=11003):
        super().__init__("401 Client Error")
        self.response = mock.Mock(status_code=401)
        self.response.json = lambda: {"status": 401, "subStatus": sub_status, "userMessage": "x"}


class AuthenticationError(Exception):
    """Same name as tidalapi.exceptions.AuthenticationError: the token refresh itself failed."""


def bts(bits=16, rate=44100, quality="LOSSLESS", url="https://fake/yellow.flac", encrypted=False):
    return FakeStream("bts", quality, bits, rate, [url], encrypted)


class TidalSourceTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp(prefix="nutsty_tidal_test_")
        self.env = mock.patch.dict(os.environ, {
            "HOME": self.tmp,
            "XDG_CONFIG_HOME": os.path.join(self.tmp, "config"),
            "NUTSTY_PROFILE": "",
            "NUTSTY_TEMP_DIR": os.path.join(self.tmp, "tmp"),
        })
        self.env.start()
        ts._reset_for_tests()
        self.yellow = FakeTrack(101, "Yellow", ["Coldplay"], 266, bts())
        self.song24 = FakeTrack(202, "Song24", ["Artist"], 200,
                                FakeStream("mpd", "HI_RES_LOSSLESS", 24, 96000))
        self.session = FakeSession([self.yellow, self.song24])
        ts._session_factory = lambda: self.session
        ts._fetch_subscription = lambda sess: sess.subscription_info()
        ts._finish_login(self.session)

    def tearDown(self):
        ts._reset_for_tests()
        self.env.stop()
        shutil.rmtree(self.tmp, ignore_errors=True)

    # --- title cleaning and scoring -------------------------------------------------
    def test_clean_title_strips_video_noise(self):
        self.assertEqual(ts.clean_title("Nàng Thơ (Official MV) [Lyrics]"), "nàng thơ")
        self.assertEqual(ts.clean_title("Shape of You (feat. X) - Remastered 2017"), "shape of you")

    def test_clean_title_keeps_vietnamese_and_drops_artist_prefix(self):
        self.assertEqual(ts.clean_title("Hoàng Dũng - Nàng Thơ | Official Audio", "Hoàng Dũng"), "nàng thơ")
        self.assertEqual(ts.clean_title("Đi Về Nhà ft. JustaTee"), "đi về nhà")

    def test_rejects_live_and_remix(self):
        self.assertLess(ts.score_candidate("Yellow", "Coldplay", 266, "Yellow (Live)", ["Coldplay"], 280), ts.MATCH_THRESHOLD)
        self.assertLess(ts.score_candidate("Yellow", "Coldplay", 266, "Yellow - Remix", ["Coldplay"], 267), ts.MATCH_THRESHOLD)

    def test_live_source_may_match_live_candidate(self):
        self.assertGreaterEqual(ts.score_candidate("Yellow (Live)", "Coldplay", 280, "Yellow (Live)", ["Coldplay"], 280), ts.MATCH_THRESHOLD)

    def test_duration_over_3s_rejected(self):
        self.assertLess(ts.score_candidate("Yellow", "Coldplay", 266, "Yellow", ["Coldplay"], 270), ts.MATCH_THRESHOLD)
        self.assertGreaterEqual(ts.score_candidate("Yellow", "Coldplay", 266, "Yellow", ["Coldplay"], 268), ts.MATCH_THRESHOLD)

    def test_wrong_artist_rejected(self):
        self.assertLess(ts.score_candidate("Yellow", "Coldplay", 266, "Yellow", ["Katy Perry"], 266), ts.MATCH_THRESHOLD)

    # --- resolve --------------------------------------------------------------------
    def test_resolve_bts_returns_direct_url(self):
        s = ts.resolve("vid1", "Yellow", "Coldplay", 266, "lossless")
        self.assertEqual(s["url"], "https://fake/yellow.flac")
        self.assertEqual((s["bit_depth"], s["sample_rate"]), (16, 44100))
        self.assertEqual(s["tidal_id"], 101)
        self.assertEqual(s["codec"], "FLAC")
        self.assertGreater(s["expires_at"], time.time())

    def test_resolve_mpd_writes_manifest_file(self):
        s = ts.resolve("vid2", "Song24", "Artist", 200, "hires")
        self.assertTrue(s["url"].startswith("file://"))
        self.assertTrue(os.path.exists(s["url"][len("file://"):]))
        self.assertEqual((s["bit_depth"], s["sample_rate"]), (24, 96000))

    def test_quality_is_sent_to_tidal(self):
        ts.resolve("vid2", "Song24", "Artist", 200, "hires")
        self.assertEqual(self.session.config.quality, "HI_RES_LOSSLESS")
        ts._reset_stream_cache_for_tests()
        ts.resolve("vid1", "Yellow", "Coldplay", 266, "lossless")
        self.assertEqual(self.session.config.quality, "LOSSLESS")

    def test_encrypted_stream_returns_none(self):
        self.yellow._stream = bts(encrypted=True)
        self.assertIsNone(ts.resolve("vid1", "Yellow", "Coldplay", 266, "lossless"))

    def test_lossy_stream_returns_none(self):
        self.yellow._stream = bts(quality="HIGH")
        self.assertIsNone(ts.resolve("vid1", "Yellow", "Coldplay", 266, "lossless"))

    def test_no_match_returns_none(self):
        self.assertIsNone(ts.resolve("vid9", "Nothing Like It", "Nobody", 100, "lossless"))

    def test_miss_is_cached_for_7_days(self):
        self.assertIsNone(ts.resolve("vid9", "Nothing Like It", "Nobody", 100, "lossless"))
        self.assertIsNone(ts.resolve("vid9", "Nothing Like It", "Nobody", 100, "lossless"))
        self.assertEqual(self.session.search_calls, 1)
        later = time.time() + ts.MISS_TTL_S + 1
        with mock.patch.object(ts.time, "time", return_value=later):
            ts.resolve("vid9", "Nothing Like It", "Nobody", 100, "lossless")
        self.assertEqual(self.session.search_calls, 2)

    def test_hit_is_cached_and_reuses_track_id(self):
        ts.resolve("vid1", "Yellow", "Coldplay", 266, "lossless")
        ts._reset_stream_cache_for_tests()
        ts.resolve("vid1", "Yellow", "Coldplay", 266, "lossless")
        self.assertEqual(self.session.search_calls, 1)

    def test_stream_url_cached_10_minutes(self):
        ts.resolve("vid1", "Yellow", "Coldplay", 266, "lossless")
        ts.resolve("vid1", "Yellow", "Coldplay", 266, "lossless")
        self.assertEqual(self.yellow.stream_calls, 1)
        later = time.time() + ts.STREAM_TTL_S + 1
        with mock.patch.object(ts.time, "time", return_value=later):
            ts.resolve("vid1", "Yellow", "Coldplay", 266, "lossless")
        self.assertEqual(self.yellow.stream_calls, 2)

    def test_network_error_returns_none(self):
        self.session.search_error = ConnectionError("down")
        self.assertIsNone(ts.resolve("vid1", "Yellow", "Coldplay", 266, "lossless"))

    def test_network_error_is_not_cached_as_miss(self):
        self.session.search_error = ConnectionError("down")
        ts.resolve("vid1", "Yellow", "Coldplay", 266, "lossless")
        self.session.search_error = None
        self.assertIsNotNone(ts.resolve("vid1", "Yellow", "Coldplay", 266, "lossless"))

    def test_budget_exceeded_returns_none_and_caches_later(self):
        self.session.search_delay = 0.3
        self.assertIsNone(ts.resolve("vid1", "Yellow", "Coldplay", 266, "lossless", budget_s=0.05))
        ts._join_background_for_tests(2.0)
        self.session.search_delay = 0
        t0 = time.time()
        s = ts.resolve("vid1", "Yellow", "Coldplay", 266, "lossless", budget_s=0.05)
        self.assertIsNotNone(s)
        self.assertLess(time.time() - t0, 0.05)

    def test_hires_falls_back_to_lossless_quality(self):
        self.song24._stream = FakeStream("bts", "LOSSLESS", 16, 44100, ["https://fake/s16.flac"])
        s = ts.resolve("vid2", "Song24", "Artist", 200, "hires")
        self.assertEqual(s["audio_quality"], "LOSSLESS")
        self.assertEqual(s["bit_depth"], 16)

    def test_401_marks_needs_relogin(self):
        self.session.search_error = Http401()
        self.assertIsNone(ts.resolve("vid1", "Yellow", "Coldplay", 266, "lossless"))
        st = ts.status()
        self.assertTrue(st["needs_relogin"])
        self.assertFalse(st["logged_in"])

    def test_refresh_failure_marks_needs_relogin(self):
        self.session.search_error = AuthenticationError("refresh failed")
        self.assertIsNone(ts.resolve("vid1", "Yellow", "Coldplay", 266, "lossless"))
        self.assertTrue(ts.status()["needs_relogin"])

    def test_track_401_is_a_song_miss_not_a_sign_out(self):
        # subStatus 4005: this one track cannot play in the region or on the plan
        def unavailable(track):
            raise Http401(sub_status=4005)
        self.yellow._stream = unavailable
        self.assertIsNone(ts.resolve("vid1", "Yellow", "Coldplay", 266, "lossless"))
        st = ts.status()
        self.assertFalse(st["needs_relogin"])
        self.assertTrue(st["logged_in"])
        calls = self.session.search_calls
        self.assertIsNone(ts.resolve("vid1", "Yellow", "Coldplay", 266, "lossless"))
        self.assertEqual(self.session.search_calls, calls)   # cached as a miss

    def test_not_logged_in_returns_none_without_network(self):
        ts.logout()
        self.assertIsNone(ts.resolve("vid1", "Yellow", "Coldplay", 266, "lossless"))
        self.assertEqual(self.session.search_calls, 0)

    def test_status_reports_account_and_hires(self):
        st = ts.status()
        self.assertTrue(st["logged_in"])
        self.assertEqual(st["account"], "duy")
        self.assertTrue(st["can_hires"])

    # --- files ----------------------------------------------------------------------
    def test_paths_are_profile_scoped(self):
        with mock.patch.dict(os.environ, {"NUTSTY_PROFILE": "user2"}):
            for p in (ts.session_file(), ts.match_cache_file(), ts.mpd_dir(), ts.status_file()):
                self.assertIn("_user2", str(p))
        for p in (ts.session_file(), ts.match_cache_file(), ts.mpd_dir(), ts.status_file()):
            self.assertNotIn("_user2", str(p))

    def test_request_profile_overrides_process_profile(self):
        # One route worker (NUTSTY_PROFILE "") serves every window; user2 must get its own session
        with ts.using_profile("user2"):
            self.assertIn("_user2", str(ts.session_file()))
            self.assertFalse(ts.status()["logged_in"])
            self.assertIsNone(ts._get_session())
            other = FakeSession([])
            ts._finish_login(other)
            self.assertTrue(ts.status()["logged_in"])
            self.assertIs(ts._get_session(), other)
        self.assertNotIn("_user2", str(ts.session_file()))
        self.assertIs(ts._get_session(), self.session)
        with ts.using_profile("user2"):
            ts.logout()
        self.assertTrue(ts.status()["logged_in"])   # main profile untouched

    def test_empty_request_profile_means_main(self):
        with mock.patch.dict(os.environ, {"NUTSTY_PROFILE": "user1"}):
            with ts.using_profile(""):
                self.assertNotIn("_user1", str(ts.session_file()))

    def test_token_never_printed(self):
        out, err = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            ts.resolve("vid1", "Yellow", "Coldplay", 266, "lossless")
            self.session.search_error = Http401()
            ts.resolve("vid3", "Other", "Coldplay", 266, "lossless")
            ts.status()
        self.assertNotIn(FAKE_TOKEN, out.getvalue() + err.getvalue())

    @unittest.skipIf(sys.platform.startswith("win"), "POSIX permissions")
    def test_session_file_mode_600(self):
        mode = os.stat(ts.session_file()).st_mode & 0o777
        self.assertEqual(mode, 0o600)

    def test_logout_removes_session(self):
        ts.logout()
        self.assertFalse(os.path.exists(ts.session_file()))
        self.assertFalse(ts.status()["logged_in"])


if __name__ == "__main__":
    unittest.main()
