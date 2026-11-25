#!/usr/bin/env python3
"""
Manual smoke test of backend/spotify_web.py against the real web player,
using the sp_dc cookie the user saved in Nutsty settings (their own account). Not part of CI.

Usage:
  python scripts/spotify_sync_smoke.py                      read-only checks
  python scripts/spotify_sync_smoke.py --write <playlistId> add one track to a throwaway playlist
      you made by hand, read it back, remove it again. Refuses a playlist you do not own or one
      holding more than 5 tracks, so a real playlist is never touched.
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


def write_check(c, pid):
    me = c.me()
    owned = {p["id"]: p for p in c.library_playlists() if p["owned"]}
    if pid not in owned:
        print(f"[stop] {pid} is not a playlist owned by {me.get('name')!r}; nothing written.")
        return 1
    before = c.playlist_items(pid)
    if len(before.items) > 5:
        print(f"[stop] {owned[pid]['title']!r} holds {len(before.items)} tracks; use an empty throwaway playlist.")
        return 1
    hits = c.search_tracks("Hello", "Adele")
    if not hits:
        print("[FAIL] search returned nothing")
        return 1
    sid = hits[0]["spotifyId"]
    ok = step(f"add_to_playlist({owned[pid]['title']!r}, {hits[0]['name']!r})",
              lambda: (c.add_to_playlist(pid, [f"spotify:track:{sid}"]), "sent")[1])
    after = c.playlist_items(pid)
    uids = [i["uid"] for i in after.items if i["spotifyId"] == sid]
    ok &= step("read back after add", lambda: f"present={bool(uids)} uids={uids}")
    if uids:
        ok &= step("remove_from_playlist", lambda: (c.remove_from_playlist(pid, uids), "sent")[1])
        gone = c.playlist_items(pid)
        ok &= step("read back after remove",
                   lambda: f"present={any(i['spotifyId'] == sid for i in gone.items)} total={gone.total}")
    return 0 if ok and uids else 1


def main():
    if len(sys.argv) == 3 and sys.argv[1] == "--write":
        spdc = lyrics_helper.get_spotify_spdc()
        if not spdc:
            print("No Spotify cookie saved in Nutsty settings; sign in first.")
            return 2
        return write_check(sw.SpotifyWebClient(spdc), sys.argv[2])
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
