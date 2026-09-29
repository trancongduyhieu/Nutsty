#!/usr/bin/env python3
import unittest
import sys
import os

# Ensure backend is on sys.path
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

from backend.spotify_importer import (
    extract_playlist_id,
    calculate_track_match_score,
    SpotifyImportManager
)


class TestSpotifyImporter(unittest.TestCase):
    def test_extract_playlist_id_from_url(self):
        url = "https://open.spotify.com/playlist/37i9dQZF1DXcBWIGoYBM5M?si=12345"
        self.assertEqual(extract_playlist_id(url), "37i9dQZF1DXcBWIGoYBM5M")

    def test_extract_playlist_id_from_uri(self):
        uri = "spotify:playlist:37i9dQZF1DXcBWIGoYBM5M"
        self.assertEqual(extract_playlist_id(uri), "37i9dQZF1DXcBWIGoYBM5M")

    def test_extract_playlist_id_raw(self):
        raw = "37i9dQZF1DXcBWIGoYBM5M"
        self.assertEqual(extract_playlist_id(raw), "37i9dQZF1DXcBWIGoYBM5M")

    def test_calculate_track_match_score(self):
        # Perfect match: duration delta is 0s
        sp_track = {"name": "Lạ Lùng", "artist": "Vũ", "duration_ms": 262000}
        yt_candidate_exact = {"title": "Lạ Lùng", "artist": "Vũ", "duration": 262}
        yt_candidate_diff = {"title": "Lạ Lùng (Remix)", "artist": "Vũ", "duration": 180}

        score_exact = calculate_track_match_score(sp_track, yt_candidate_exact)
        score_diff = calculate_track_match_score(sp_track, yt_candidate_diff)

        self.assertGreater(score_exact, score_diff)

    def test_import_manager_initial_state(self):
        manager = SpotifyImportManager()
        status = manager.get_status()
        self.assertFalse(status["active"])
        self.assertEqual(status["percent"], 0)
        self.assertIsNone(status["error"])


if __name__ == "__main__":
    unittest.main()
