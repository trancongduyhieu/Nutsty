#!/usr/bin/env python3
"""Unit tests for GET /api/listening/genre route in backend/listening_routes.py.

Tests:
1. Cache hit: returns cached genre without network lookup.
2. Miss that gets saved: calls _lookup_genre, saves to cache, returns genre.
3. Failure that is not retried: returns empty genre, records in failure cache,
   subsequent requests do not call _lookup_genre again.
"""

import json
import os
import sys
import tempfile
from pathlib import Path
from unittest.mock import patch

ROOT_DIR = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT_DIR))

from backend import listening_routes


class DummyHandler:
    def __init__(self):
        self.data = None
        self.status = None

    def _send_json(self, data, status_code=200):
        self.data = data
        self.status = status_code


def main():
    with tempfile.TemporaryDirectory() as tmpdir:
        fake_cache_file = os.path.join(tmpdir, "nutsty_artist_genres.json")

        # Start with an existing entry in the cache
        initial_cache = {"radiohead": "Alternative"}
        with open(fake_cache_file, "w", encoding="utf-8") as f:
            json.dump(initial_cache, f)

        # Clear in-memory fail cache for clean test run
        listening_routes._genre_fail_cache.clear()

        with patch.object(listening_routes, "_genre_cache_path", return_value=fake_cache_file):
            lookup_calls = []

            def fake_lookup(artist):
                lookup_calls.append(artist)
                if artist == "Queen":
                    return "Rock"
                return ""

            with patch.object(listening_routes, "_lookup_genre", side_effect=fake_lookup):
                # 1. Cache hit: Radiohead
                h1 = DummyHandler()
                listening_routes.handle_get_listening_genre(h1, {"artist": ["Radiohead"]})
                assert h1.status == 200, f"Expected status 200, got {h1.status}"
                assert h1.data == {"success": True, "genre": "Alternative"}, f"Unexpected data: {h1.data}"
                assert len(lookup_calls) == 0, f"_lookup_genre should not be called on cache hit, got {lookup_calls}"
                print("ok cache hit")

                # 2. Miss that gets saved: Queen
                h2 = DummyHandler()
                listening_routes.handle_get_listening_genre(h2, {"artist": ["Queen"]})
                assert h2.status == 200, f"Expected status 200, got {h2.status}"
                assert h2.data == {"success": True, "genre": "Rock"}, f"Unexpected data: {h2.data}"
                assert lookup_calls == ["Queen"], f"Expected lookup for Queen, got {lookup_calls}"
                # Verify written to disk cache
                with open(fake_cache_file, "r", encoding="utf-8") as f:
                    updated_cache = json.load(f)
                assert updated_cache.get("queen") == "Rock", f"Cache file not updated: {updated_cache}"
                print("ok miss that gets saved")

                # Verify subsequent lookup is a cache hit
                lookup_calls.clear()
                h2_cached = DummyHandler()
                listening_routes.handle_get_listening_genre(h2_cached, {"artist": ["queen"]})
                assert h2_cached.data == {"success": True, "genre": "Rock"}
                assert len(lookup_calls) == 0, "Second call for Queen should hit cache"
                print("ok saved genre now hits cache")

                # 3. Failure that is not retried: Unknown Band
                lookup_calls.clear()
                h3 = DummyHandler()
                listening_routes.handle_get_listening_genre(h3, {"artist": ["Unknown Band"]})
                assert h3.status == 200, f"Expected status 200, got {h3.status}"
                assert h3.data == {"success": True, "genre": ""}, f"Unexpected data: {h3.data}"
                assert lookup_calls == ["Unknown Band"], f"Expected lookup for Unknown Band, got {lookup_calls}"
                print("ok failed lookup returns empty genre")

                # Subsequent call should NOT call _lookup_genre again
                lookup_calls.clear()
                h3_retry = DummyHandler()
                listening_routes.handle_get_listening_genre(h3_retry, {"artist": ["Unknown Band"]})
                assert h3_retry.status == 200
                assert h3_retry.data == {"success": True, "genre": ""}
                assert len(lookup_calls) == 0, f"Failed artist should not be retried, but lookup was called: {lookup_calls}"
                print("ok failure is not retried")

                # 4. Empty artist query
                h4 = DummyHandler()
                listening_routes.handle_get_listening_genre(h4, {"artist": [""]})
                assert h4.status == 200
                assert h4.data == {"success": True, "genre": ""}
                assert len(lookup_calls) == 0
                print("ok empty artist handled cleanly")

    print("\nALL GENRE ROUTE TESTS PASSED")


if __name__ == "__main__":
    main()
