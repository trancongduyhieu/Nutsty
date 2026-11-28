#!/usr/bin/env python3
"""
Spotify web-player GraphQL client used by two-way sync (backend/spotify_sync.py).

Talks to the same private endpoint the open.spotify.com web player uses, with the
user's OWN sp_dc cookie (never a shared pool). Read ops: me, library playlists,
playlist items, liked songs, search. Write ops (only when the user turns on
write-back): add/remove playlist items, add/remove liked songs, rename a playlist, set its cover.

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
# The web player's own playlist endpoints, for the writes its queries do not cover: a playlist's name, and
# taking a playlist out of the library (removeFromLibrary refuses playlist URIs).
# Not api.spotify.com: that refuses web-player tokens (429 QUOTA_EXCEEDED, Retry-After 86400).
PLAYLIST_CHANGES_URL = "https://spclient.wg.spotify.com/playlist/v2/playlist/{}/changes"
ROOTLIST_CHANGES_URL = "https://spclient.wg.spotify.com/playlist/v2/user/{}/rootlist/changes"
# A playlist cover, as the web player sets one: the JPEG goes to the image-upload host (raw bytes,
# answers {uploadToken}), register-image turns the token into a picture id ({picture}, base64 bytes),
# and that id goes in as the list's picture attribute, like a rename.
IMAGE_UPLOAD_URL = "https://image-upload.spotify.com/v4/playlist"
REGISTER_IMAGE_URL = "https://spclient.wg.spotify.com/playlist/v2/playlist/{}/register-image"
_REM = 3                      # playlist4 Op.Kind
_UPDATE_LIST_ATTRIBUTES = 6
USER_AGENT = ("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
              "(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36")

# operationName -> sha256Hash. fetchPlaylist / searchTracks are the ones Nutsty already
# uses in production (spotify_importer.py, lyrics_helper.py); the rest come from the
# Spatial Flow web-player table (references/SpatialFlow-apk .../x47.java).
PERSISTED_QUERIES = {
    "profileAttributes": "53bcb064f6cd18c23f752bc324a791194d20df612d8e1239c735144ab0399ced",
    "libraryV3": "973e511ca44261fda7eebac8b653155e7caee3675abb4fb110cc1b8c78b091c3",
    "fetchPlaylist": "7982b11e21535cd2594badc40030b745671b61a1fa66766e569d45e6364f3422",
    "getAlbum": "b9bfabef66ed756e5e13f68a942deb60bd4125ec1f1be8cc42769dc0259b4b10",
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


def _json_or_empty(raw):
    """A reply that is not JSON (spclient answers in protobuf) reads as an empty body."""
    try:
        return json.loads(raw) if raw.strip() else {}
    except ValueError:
        return {}


def _urllib_transport(url, payload, headers):
    """Default transport: POST JSON, return (status, headers, body-dict)."""
    return _urllib_raw_transport(url, json.dumps(payload).encode("utf-8"), headers)


def _urllib_raw_transport(url, data, headers):
    """POST raw bytes (the body's type is in `headers`), return (status, headers, body-dict)."""
    try:
        import platform_compat as pc
        ctx = pc.get_ssl_context()
    except Exception:
        ctx = None
    req = urllib.request.Request(url, data=data, headers=headers, method="POST")
    try:
        with urllib.request.urlopen(req, timeout=15, context=ctx) as resp:
            raw = resp.read().decode("utf-8", "replace")
            return resp.status, dict(resp.headers), _json_or_empty(raw)
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
    # require_user: an anonymous token reads every list as empty, which would look like "delete all"
    return lyrics_helper.get_spotify_access_token(spdc, require_user=True) or ""


def _default_cover_token(spdc):
    """The desktop web player's token: the default (mobile web player) one gets 401 "insufficient
    scope" from the image-upload host."""
    import lyrics_helper
    return lyrics_helper.get_spotify_access_token(spdc, require_user=True, product_type="web-player") or ""


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


def _required(data, *path, op=""):
    """Walk `path` in a GraphQL answer. A missing `me` means no signed-in user; any other missing
    node is a malformed answer. Both raise, so a 200 without data never reads as an empty list."""
    node = data
    for key in path:
        node = node.get(key) if isinstance(node, dict) else None
        if not isinstance(node, dict):
            if key == "me":
                raise SpotifyAuthError(f"{op}: no signed-in user")
            raise SpotifyNetworkError(f"{op}: answer without {key}")
    return node


class SpotifyWebClient:
    def __init__(self, spdc, transport=None, min_interval=0.4,
                 token_provider=None, client_token_provider=None, upload_transport=None,
                 cover_token_provider=None):
        self.spdc = spdc
        self.transport = transport or _urllib_transport
        self.upload_transport = upload_transport or _urllib_raw_transport
        self.min_interval = min_interval
        self._token_provider = token_provider or (lambda: _default_token(self.spdc))
        self._cover_token_provider = cover_token_provider or (lambda: _default_cover_token(self.spdc))
        self._cover_token = ""
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
        return self._headers_for(self._token)

    def _cover_headers(self):
        if not self._cover_token:
            self._cover_token = self._cover_token_provider() or ""
            if not self._cover_token:
                raise SpotifyAuthError("no web-player access token (sp_dc expired or missing)")
        return self._headers_for(self._cover_token)

    def _headers_for(self, token):
        if self._client_token is None:
            self._client_token = self._client_token_provider() if self._client_token_provider else ""
        h = {
            "authorization": f"Bearer {token}",
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
        if status in (400, 404) and self._looks_like_query_changed(body):
            raise SpotifyQueryChanged(f"{op}: persisted query not found")
        self._raise_for_status(op, status, rheaders)
        body = body or {}
        if self._looks_like_query_changed(body):
            raise SpotifyQueryChanged(f"{op}: persisted query not found")
        if body.get("errors") and not body.get("data"):
            raise SpotifyError(f"{op}: {body['errors'][0].get('message', '')}", code="graphql_error")
        return body.get("data") or {}

    def _raise_for_status(self, op, status, rheaders):
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
        if status >= 500 or status == 0:
            raise SpotifyNetworkError(f"{op}: HTTP {status}")
        if status >= 400:
            raise SpotifyError(f"{op}: HTTP {status}", code="http_error")

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
            if not uid:
                raise SpotifyAuthError("profileAttributes: no signed-in user")
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
            lib = _required(data, "me", "libraryV3", op="libraryV3")
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
                owned = bool(my_id) and owner_id == my_id
                caps = node.get("currentUserCapabilities")
                # canEditItems also covers collaborative playlists someone else owns
                editable = bool(caps.get("canEditItems")) if isinstance(caps, dict) else owned
                out.append({
                    "id": _tail(uri),
                    "title": node.get("name", ""),
                    "image": _first_source(((node.get("images") or {}).get("items") or [{}])[0]),
                    "ownerId": owner_id,
                    "ownerName": owner.get("name", ""),
                    "owned": owned,
                    "editable": editable and owner_id != "spotify",
                    "spotifyMade": owner_id == "spotify",
                    "revision": node.get("revisionId", "") or "",
                    "trackCount": int(count or 0),
                })
            offset += len(items)
            if not items or offset >= total:
                break
        return out

    def library_albums(self):
        """Saved albums, as read-only choices next to the playlists (kind "album", never editable)."""
        out, offset = [], 0
        while True:
            data = self.query("libraryV3", {
                "filters": ["Albums"], "order": None, "textFilter": "",
                "features": ["LIKED_SONGS", "YOUR_EPISODES_V2", "PRERELEASES", "EVENTS"],
                "limit": LIBRARY_PAGE, "offset": offset, "flatten": True,
                "expandedFolders": [], "folderUri": None, "includeFoldersWhenFlattening": False,
            })
            lib = _required(data, "me", "libraryV3", op="libraryV3")
            total = int(lib.get("totalCount") or 0)
            items = lib.get("items") or []
            for wrap in items:
                item = (wrap or {}).get("item") or {}
                node = item.get("data") or {}
                if node.get("__typename") != "Album":
                    continue
                artists = [((a or {}).get("profile") or {}).get("name", "")
                           for a in ((node.get("artists") or {}).get("items") or [])]
                out.append({
                    "id": _tail(item.get("_uri") or node.get("uri") or ""),
                    "title": node.get("name", ""),
                    "image": _first_source(node.get("coverArt") or {}),
                    "ownerId": "",
                    "ownerName": ", ".join(a for a in artists if a),
                    "owned": False, "editable": False, "spotifyMade": False,
                    "revision": "", "trackCount": 0, "kind": "album",
                })
            offset += len(items)
            if not items or offset >= total:
                break
        return out

    def album_items(self, aid):
        items, offset, total = [], 0, 0
        while True:
            data = self.query("getAlbum", {"uri": f"spotify:album:{aid}", "locale": "",
                                           "offset": offset, "limit": PLAYLIST_PAGE})
            al = data.get("albumUnion")
            if not al or (al.get("__typename") and al["__typename"] != "Album"):
                raise SpotifyError(f"album {aid} unavailable", code="not_found")
            tracks = _required(al, "tracksV2", op="getAlbum")
            total = int(tracks.get("totalCount") or 0)
            page = tracks.get("items") or []
            for row in page:
                t = (row or {}).get("track") or {}
                # album tracks carry no album of their own: the album's name and cover stand in
                it = parse_track(dict(t, albumOfTrack={"name": al.get("name", ""),
                                                       "coverArt": al.get("coverArt") or {}}))
                it["uid"] = (row or {}).get("uid") or ""
                items.append(it)
            offset += len(page)
            if not page or offset >= total:
                break
        return RemoteList(items=items, total=total, revision="", complete=offset >= total)

    def playlist_items(self, pid):
        items, offset, total, revision, skipped = [], 0, None, "", 0
        while True:
            data = self.query("fetchPlaylist", {
                "uri": f"spotify:playlist:{pid}", "offset": offset,
                "limit": PLAYLIST_PAGE, "enableWatchFeedEntrypoint": False,
            })
            pl = data.get("playlistV2")
            if not pl or (pl.get("__typename") and pl["__typename"] != "Playlist"):
                raise SpotifyError(f"playlist {pid} unavailable", code="not_found")
            content = _required(pl, "content", op="fetchPlaylist")
            total = int(content.get("totalCount") or 0)
            revision = pl.get("revisionId", revision) or revision
            page = content.get("items") or []
            for row in page:
                node = (row or {}).get("itemV2") or {}
                track = node.get("data") or {}
                uri = node.get("_uri") or track.get("uri") or ""
                if not uri.startswith("spotify:track:"):
                    skipped += 1  # episodes, local files: not syncable, and not counted in total
                    continue
                it = parse_track(track, uri)
                it["uid"] = row.get("uid") or node.get("uid") or ""
                items.append(it)
            offset += len(page)
            if not page or offset >= total:
                break
        return RemoteList(items=items, total=total - skipped, revision=revision, complete=offset >= total)

    def liked_items(self):
        items, offset, total = [], 0, None
        while True:
            data = self.query("fetchLibraryTracks", {"offset": offset, "limit": LIBRARY_PAGE})
            tracks = _required(data, "me", "library", "tracks", op="fetchLibraryTracks")
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

    def _set_list_attributes(self, op, pid, values, headers=None):
        """One UPDATE_LIST_ATTRIBUTES change, as the web player sends it; a list the user may not edit gets 4xx."""
        payload = {"deltas": [{"ops": [{"kind": _UPDATE_LIST_ATTRIBUTES, "updateListAttributes": {
                       "newAttributes": {"values": values, "noValue": []}}}],
                   "info": {"source": {"client": 5}}}],
                   "wantResultingRevisions": False, "wantSyncResult": False, "nonces": []}
        headers = headers or self._headers()
        self._throttle()
        status, rheaders, _body = self.transport(PLAYLIST_CHANGES_URL.format(pid), payload, headers)
        self._raise_for_status(op, status, rheaders)

    def rename_playlist(self, pid, name):
        self._set_list_attributes("renamePlaylist", pid, {"name": name})

    def set_playlist_cover(self, pid, jpeg):
        """Make `jpeg` (bytes, a square JPEG) the playlist's cover. An answer without the expected
        token or id means Spotify changed the flow: raised as query_changed. All three calls carry the
        desktop web player's token (see _default_cover_token)."""
        try:
            headers = self._cover_headers()
            self._throttle()
            status, rheaders, body = self.upload_transport(IMAGE_UPLOAD_URL, bytes(jpeg),
                                                           dict(headers, **{"content-type": "image/jpeg"}))
            self._raise_for_status("uploadImage", status, rheaders)
            token = (body or {}).get("uploadToken")
            if not token:
                raise SpotifyQueryChanged("uploadImage: answer without uploadToken")
            self._throttle()
            # without accept: json spclient answers in protobuf, which reads as no picture
            status, rheaders, body = self.transport(REGISTER_IMAGE_URL.format(pid), {"uploadToken": token},
                                                    dict(headers, accept="application/json"))
            self._raise_for_status("registerImage", status, rheaders)
            picture = (body or {}).get("picture")
            if not picture:
                raise SpotifyQueryChanged("registerImage: answer without picture")
            self._set_list_attributes("setPlaylistCover", pid, {"picture": picture}, headers)
        except SpotifyAuthError:
            self._cover_token = ""
            raise

    def remove_playlist(self, pid):
        """Take a playlist out of the user's library, as the web player's Delete / Remove does: one REM
        on their rootlist. Spotify keeps a deleted own playlist recoverable from the account page."""
        payload = {"deltas": [{"ops": [{"kind": _REM, "rem": {
                       "items": [{"uri": f"spotify:playlist:{pid}"}], "itemsAsKey": True}}],
                   "info": {"source": {"client": 5}}}],
                   "wantResultingRevisions": False, "wantSyncResult": False, "nonces": []}
        url = ROOTLIST_CHANGES_URL.format(self.me()["id"])
        headers = self._headers()
        self._throttle()
        status, rheaders, _body = self.transport(url, payload, headers)
        self._raise_for_status("removePlaylist", status, rheaders)

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
