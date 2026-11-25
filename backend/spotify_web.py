#!/usr/bin/env python3
"""
Spotify web-player GraphQL client used by two-way sync (backend/spotify_sync.py).

Talks to the same private endpoint the open.spotify.com web player uses, with the
user's OWN sp_dc cookie (never a shared pool). Read ops: me, library playlists,
playlist items, liked songs, search. Write ops (only when the user turns on
write-back): add/remove playlist items, add/remove liked songs.

Persisted-query hashes rotate when Spotify ships a new web player; a rotated hash
surfaces as SpotifyQueryChanged so the UI can say "Spotify changed, update Nutsty"
instead of silently returning nothing.
"""
import json
import sys
import time
import urllib.error
import urllib.request
from dataclasses import dataclass, field

PATHFINDER_URL = "https://api-partner.spotify.com/pathfinder/v1/query"
USER_AGENT = ("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
              "(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36")

# operationName -> sha256Hash. fetchPlaylist / searchTracks are the ones Nutsty already
# uses in production (spotify_importer.py, lyrics_helper.py); the rest come from the
# Spatial Flow web-player table (references/SpatialFlow-apk .../x47.java).
PERSISTED_QUERIES = {
    "profileAttributes": "53bcb064f6cd18c23f752bc324a791194d20df612d8e1239c735144ab0399ced",
    "libraryV3": "973e511ca44261fda7eebac8b653155e7caee3675abb4fb110cc1b8c78b091c3",
    "fetchPlaylist": "7982b11e21535cd2594badc40030b745671b61a1fa66766e569d45e6364f3422",
    "fetchLibraryTracks": "087278b20b743578a6262c2b0b4bcd20d879c503cc359a2285baf083ef944240",
    "searchTracks": "bc1ca2fcd0ba1013a0fc88e6cc4f190af501851e3dafd3e1ef85840297694428",
    "addToPlaylist": "47b2a1234b17748d332dd0431534f22450e9ecbb3d5ddcdacbd83368636a0990",
    "removeFromPlaylist": "47b2a1234b17748d332dd0431534f22450e9ecbb3d5ddcdacbd83368636a0990",
    "addToLibrary": "7c5a69420e2bfae3da5cc4e14cbc8bb3f6090f80afc00ffc179177f19be3f33d",
    "removeFromLibrary": "7c5a69420e2bfae3da5cc4e14cbc8bb3f6090f80afc00ffc179177f19be3f33d",
}

PLAYLIST_PAGE = 100
LIBRARY_PAGE = 50


class SpotifyError(Exception):
    code = "error"

    def __init__(self, message="", code=None):
        super().__init__(message or self.code)
        if code:
            self.code = code


class SpotifyAuthError(SpotifyError):
    code = "auth_expired"


class SpotifyRateLimited(SpotifyError):
    code = "rate_limited"

    def __init__(self, message="", retry_after=60.0):
        super().__init__(message)
        self.retry_after = retry_after


class SpotifyQueryChanged(SpotifyError):
    code = "query_changed"


class SpotifyNetworkError(SpotifyError):
    code = "network"


@dataclass
class RemoteList:
    items: list = field(default_factory=list)
    total: int = 0
    revision: str = ""
    complete: bool = False


def _urllib_transport(url, payload, headers):
    """Default transport: POST JSON, return (status, headers, body-dict)."""
    try:
        import platform_compat as pc
        ctx = pc.get_ssl_context()
    except Exception:
        ctx = None
    req = urllib.request.Request(url, data=json.dumps(payload).encode("utf-8"),
                                 headers=headers, method="POST")
    try:
        with urllib.request.urlopen(req, timeout=15, context=ctx) as resp:
            raw = resp.read().decode("utf-8", "replace")
            return resp.status, dict(resp.headers), (json.loads(raw) if raw.strip() else {})
    except urllib.error.HTTPError as e:
        try:
            raw = e.read().decode("utf-8", "replace")
            body = json.loads(raw) if raw.strip() else {}
        except Exception:
            body = {}
        return e.code, dict(e.headers or {}), body
    except (urllib.error.URLError, OSError, ValueError) as e:
        raise SpotifyNetworkError(str(e))


def _default_token(spdc):
    import lyrics_helper
    return lyrics_helper.get_spotify_access_token(spdc) or ""


def _default_client_token():
    try:
        import lyrics_helper
        return lyrics_helper._spotify_get_client_token() or ""
    except Exception:
        return ""


def _tail(uri):
    return (uri or "").rsplit(":", 1)[-1]


def _first_source(obj):
    try:
        return obj["sources"][0]["url"]
    except (KeyError, IndexError, TypeError):
        return ""


def parse_track(data, uri=None):
    """Web-player track node -> sync item (without uid)."""
    data = data or {}
    uri = uri or data.get("uri") or data.get("_uri") or ""
    artists = [((a or {}).get("profile") or {}).get("name", "")
               for a in ((data.get("artists") or {}).get("items") or [])]
    album = data.get("albumOfTrack") or {}
    dur = data.get("duration") or data.get("trackDuration") or {}
    return {
        "spotifyId": _tail(uri),
        "name": data.get("name", ""),
        "artist": ", ".join(a for a in artists if a),
        "album": album.get("name", ""),
        "duration_ms": int(dur.get("totalMilliseconds") or 0),
        "image": _first_source(album.get("coverArt") or {}),
    }


class SpotifyWebClient:
    def __init__(self, spdc, transport=None, min_interval=0.4,
                 token_provider=None, client_token_provider=None):
        self.spdc = spdc
        self.transport = transport or _urllib_transport
        self.min_interval = min_interval
        self._token_provider = token_provider or (lambda: _default_token(self.spdc))
        self._client_token_provider = client_token_provider or _default_client_token
        self._token = ""
        self._client_token = None
        self._last_call = 0.0
        self._me = None

    # -- plumbing ---------------------------------------------------------
    def _headers(self):
        if not self._token:
            self._token = self._token_provider() or ""
            if not self._token:
                raise SpotifyAuthError("no access token (sp_dc expired or missing)")
        if self._client_token is None:
            self._client_token = self._client_token_provider() if self._client_token_provider else ""
        h = {
            "authorization": f"Bearer {self._token}",
            "content-type": "application/json",
            "origin": "https://open.spotify.com",
            "referer": "https://open.spotify.com/",
            "user-agent": USER_AGENT,
            "app-platform": "WebPlayer",
        }
        if self._client_token:
            h["client-token"] = self._client_token
        return h

    def _throttle(self):
        if self.min_interval > 0:
            wait = self._last_call + self.min_interval - time.monotonic()
            if wait > 0:
                time.sleep(wait)
        self._last_call = time.monotonic()

    def query(self, op, variables):
        payload = {
            "variables": variables,
            "operationName": op,
            "extensions": {"persistedQuery": {"version": 1, "sha256Hash": PERSISTED_QUERIES[op]}},
        }
        headers = self._headers()
        self._throttle()
        status, rheaders, body = self.transport(PATHFINDER_URL, payload, headers)
        if status == 401:
            self._token = ""
            raise SpotifyAuthError(f"{op}: 401")
        if status == 429:
            ra = {k.lower(): v for k, v in (rheaders or {}).items()}.get("retry-after", "60")
            try:
                retry = float(ra)
            except (TypeError, ValueError):
                retry = 60.0
            raise SpotifyRateLimited(f"{op}: 429", retry_after=retry)
        if status in (400, 404) and self._looks_like_query_changed(body):
            raise SpotifyQueryChanged(f"{op}: persisted query not found")
        if status >= 500 or status == 0:
            raise SpotifyNetworkError(f"{op}: HTTP {status}")
        if status >= 400:
            raise SpotifyError(f"{op}: HTTP {status}", code="http_error")
        body = body or {}
        if self._looks_like_query_changed(body):
            raise SpotifyQueryChanged(f"{op}: persisted query not found")
        if body.get("errors") and not body.get("data"):
            raise SpotifyError(f"{op}: {body['errors'][0].get('message', '')}", code="graphql_error")
        return body.get("data") or {}

    @staticmethod
    def _looks_like_query_changed(body):
        for err in (body or {}).get("errors") or []:
            msg = str((err or {}).get("message", "")).lower()
            if "persistedquery" in msg.replace(" ", "") or "unknown operation" in msg:
                return True
        return False

    # -- read ops ---------------------------------------------------------
    def me(self):
        if self._me is None:
            data = self.query("profileAttributes", {})
            prof = ((data.get("me") or {}).get("profile")) or {}
            uid = prof.get("username") or _tail(prof.get("uri", ""))
            self._me = {"id": uid, "name": prof.get("name") or uid}
        return self._me

    def library_playlists(self):
        my_id = self.me()["id"]
        out, offset, total = [], 0, None
        while True:
            data = self.query("libraryV3", {
                "filters": ["Playlists"], "order": None, "textFilter": "",
                "features": ["LIKED_SONGS", "YOUR_EPISODES_V2", "PRERELEASES", "EVENTS"],
                "limit": LIBRARY_PAGE, "offset": offset, "flatten": True,
                "expandedFolders": [], "folderUri": None, "includeFoldersWhenFlattening": False,
            })
            lib = (data.get("me") or {}).get("libraryV3") or {}
            total = int(lib.get("totalCount") or 0)
            items = lib.get("items") or []
            for wrap in items:
                item = (wrap or {}).get("item") or {}
                node = item.get("data") or {}
                if node.get("__typename") != "Playlist":
                    continue
                uri = item.get("_uri") or node.get("uri") or ""
                owner = ((node.get("ownerV2") or {}).get("data")) or {}
                owner_id = _tail(owner.get("uri", "")) or owner.get("id", "")
                count = ((node.get("content") or {}).get("totalCount")) or node.get("totalCount") or 0
                out.append({
                    "id": _tail(uri),
                    "title": node.get("name", ""),
                    "image": _first_source(((node.get("images") or {}).get("items") or [{}])[0]),
                    "ownerId": owner_id,
                    "ownerName": owner.get("name", ""),
                    "owned": bool(my_id) and owner_id == my_id,
                    "spotifyMade": owner_id == "spotify",
                    "revision": node.get("revisionId", "") or "",
                    "trackCount": int(count or 0),
                })
            offset += len(items)
            if not items or offset >= total:
                break
        return out

    def playlist_items(self, pid):
        items, offset, total, revision = [], 0, None, ""
        while True:
            data = self.query("fetchPlaylist", {
                "uri": f"spotify:playlist:{pid}", "offset": offset,
                "limit": PLAYLIST_PAGE, "enableWatchFeedEntrypoint": False,
            })
            pl = data.get("playlistV2") or {}
            if pl.get("__typename") and pl["__typename"] != "Playlist":
                raise SpotifyError(f"playlist {pid} unavailable", code="not_found")
            content = pl.get("content") or {}
            total = int(content.get("totalCount") or 0)
            revision = pl.get("revisionId", revision) or revision
            page = content.get("items") or []
            for row in page:
                node = (row or {}).get("itemV2") or {}
                track = node.get("data") or {}
                uri = node.get("_uri") or track.get("uri") or ""
                if not uri.startswith("spotify:track:"):
                    continue  # episodes, local files: not syncable
                it = parse_track(track, uri)
                it["uid"] = row.get("uid") or node.get("uid") or ""
                items.append(it)
            offset += len(page)
            if not page or offset >= total:
                break
        return RemoteList(items=items, total=total, revision=revision, complete=offset >= total)

    def liked_items(self):
        items, offset, total = [], 0, None
        while True:
            data = self.query("fetchLibraryTracks", {"offset": offset, "limit": LIBRARY_PAGE})
            tracks = (((data.get("me") or {}).get("library") or {}).get("tracks")) or {}
            total = int(tracks.get("totalCount") or 0)
            page = tracks.get("items") or []
            for row in page:
                t = (row or {}).get("track") or {}
                uri = t.get("_uri") or t.get("uri") or ""
                it = parse_track(t.get("data") or {}, uri)
                it["uid"] = ""
                items.append(it)
            offset += len(page)
            if not page or offset >= total:
                break
        return RemoteList(items=items, total=total, revision="", complete=offset >= total)

    def search_tracks(self, title, artist, limit=10):
        q = f"{title} {artist}".strip()
        data = self.query("searchTracks", {
            "searchTerm": q, "offset": 0, "limit": limit,
            "numberOfTopResults": 5, "includeAudiobooks": False, "includePreReleases": False,
        })
        rows = (((data.get("searchV2") or {}).get("tracksV2") or {}).get("items")) or []
        out = []
        for row in rows:
            node = ((row or {}).get("item") or {}).get("data") or {}
            if node.get("uri", "").startswith("spotify:track:"):
                out.append(parse_track(node))
        return out

    # -- write ops (write-back only) -------------------------------------
    def add_to_playlist(self, pid, uris):
        return self.query("addToPlaylist", {
            "playlistItemUris": list(uris), "playlistUri": f"spotify:playlist:{pid}",
            "newPosition": {"moveType": "BOTTOM_OF_PLAYLIST", "fromUid": None},
        })

    def remove_from_playlist(self, pid, uids):
        return self.query("removeFromPlaylist", {
            "playlistUri": f"spotify:playlist:{pid}", "uids": list(uids),
        })

    def add_to_library(self, uris):
        return self.query("addToLibrary", {"libraryItemUris": list(uris)})

    def remove_from_library(self, uris):
        return self.query("removeFromLibrary", {"libraryItemUris": list(uris)})


if __name__ == "__main__":
    sys.stderr.write("spotify_web is a library; see scripts/spotify_sync_smoke.py\n")
