#!/usr/bin/env python3
"""
Manual, READ-ONLY smoke test of backend/spotify_web.py against the real web player,
using the sp_dc cookie the user saved in Nutsty settings (their own account).
Not part of CI. Never calls a write op.

Usage: python scripts/spotify_sync_smoke.py
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "backend"))

import lyrics_helper  # noqa: E402
import spotify_web as sw  # noqa: E402


def step(name, fn):
    try:
        out = fn()
        print(f"[ok]   {name}: {out}")
        return True
    except sw.SpotifyError as e:
        print(f"[FAIL] {name}: {e.code} {e}")
    except Exception as e:  # shape changes show up as KeyError/TypeError
        print(f"[FAIL] {name}: {type(e).__name__} {e}")
    return False


def main():
    spdc = lyrics_helper.get_spotify_spdc()
    if not spdc:
        print("No Spotify cookie saved in Nutsty settings; sign in first.")
        return 2
    c = sw.SpotifyWebClient(spdc)
    ok = step("me", lambda: c.me())
    pls = []

    def lib():
        pls.extend(c.library_playlists())
        return f"{len(pls)} playlists, owned={sum(p['owned'] for p in pls)}, spotifyMade={sum(p['spotifyMade'] for p in pls)}"
    ok &= step("library_playlists", lib)
    if pls:
        p = pls[0]
        ok &= step(f"playlist_items({p['title']!r})",
                   lambda: (lambda r: f"total={r.total} got={len(r.items)} complete={r.complete} rev={r.revision[:12]!r} firstUid={(r.items[0]['uid'] if r.items else '')!r}")(c.playlist_items(p["id"])))
    ok &= step("liked_items", lambda: (lambda r: f"total={r.total} got={len(r.items)} complete={r.complete}")(c.liked_items()))
    ok &= step("search_tracks", lambda: [(t["name"], t["artist"], t["duration_ms"]) for t in c.search_tracks("Hello", "Adele")[:2]])
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
