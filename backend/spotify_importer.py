#!/usr/bin/env python3
"""
Nutsty Spotify Playlist Importer & Audio Resolution Engine
Extracts Spotify playlists and resolves audio streams to YouTube Music for offline/online persistence.
Follows DRY & SSOT principles by reusing lyrics_helper, playlist_manager, and ytmusic_helper.
"""

import os
import sys
import re
import json
import time
import threading
import urllib.request
import urllib.error
import urllib.parse

try:
    from . import lyrics_helper
    from . import playlist_manager
    from . import ytmusic_helper
    from . import platform_compat as pc
except (ImportError, ValueError):
    import lyrics_helper
    import playlist_manager
    import ytmusic_helper
    import platform_compat as pc

pc.configure_windows_ssl()


def extract_playlist_id(url_or_id):
    """
    Extracts the 22-character Spotify playlist ID from URLs, URIs, or raw strings.
    Example:
      https://open.spotify.com/playlist/37i9dQZF1DXcBWIGoYBM5M?si=... -> 37i9dQZF1DXcBWIGoYBM5M
      spotify:playlist:37i9dQZF1DXcBWIGoYBM5M -> 37i9dQZF1DXcBWIGoYBM5M
    """
    if not url_or_id:
        return ""
    text = str(url_or_id).strip()
    match = re.search(r"(?:playlist/|playlist:)([a-zA-Z0-9]{22})", text)
    if match:
        return match.group(1)
    if re.match(r"^[a-zA-Z0-9]{22}$", text):
        return text
    return text


def calculate_track_match_score(sp_track, yt_candidate):
    """
    Scores how well a YouTube Music search candidate matches the Spotify track.
    Considers title similarity, artist presence, and duration delta (SpotDL matching heuristic).
    """
    score = 100.0

    # 1. Duration delta penalty/bonus
    sp_sec = int(sp_track.get("duration_ms", 0)) / 1000.0
    yt_sec = float(yt_candidate.get("duration", 0) or 0)

    delta = abs(sp_sec - yt_sec)
    if delta <= 2.0:
        score += 20.0
    elif delta <= 5.0:
        score += 10.0
    elif delta <= 10.0:
        score -= 10.0
    else:
        score -= min(50.0, delta * 3.0)

    # 2. Title matching
    sp_title = sp_track.get("name", "").lower()
    yt_title = yt_candidate.get("title", "").lower()

    if sp_title in yt_title or yt_title in sp_title:
        score += 15.0

    # 3. Artist matching
    sp_artist = sp_track.get("artist", "").lower()
    yt_artist = yt_candidate.get("artist", "").lower()

    if sp_artist and yt_artist and (sp_artist in yt_artist or yt_artist in sp_artist):
        score += 15.0

    # Penalize karaoke / instrumental unless requested
    if "karaoke" in yt_title and "karaoke" not in sp_title:
        score -= 40.0
    if "instrumental" in yt_title and "instrumental" not in sp_title:
        score -= 30.0

    return score


def fetch_user_spotify_playlists(spdc=None, limit=50):
    """
    Fetches the authenticated user's Spotify playlists using the stored or provided sp_dc cookie.
    """
    if not spdc:
        spdc = lyrics_helper.get_spotify_spdc()
    if not spdc:
        return {"success": False, "error": "Chưa có cookie Spotify (sp_dc).", "playlists": []}

    cached_p = os.path.join(pc.get_config_dir(), "spotify_cached_playlists.json")
    if os.path.exists(cached_p):
        try:
            with open(cached_p, "r", encoding="utf-8") as cf:
                cdata = json.load(cf)
            if isinstance(cdata, list) and len(cdata) > 0:
                return {"success": True, "playlists": cdata}
        except Exception:
            pass

    token = lyrics_helper.get_spotify_access_token(spdc)
    if not token:
        return {"success": False, "error": "Cookie Spotify đã hết hạn hoặc không hợp lệ.", "playlists": []}

    url = f"https://api.spotify.com/v1/me/playlists?limit={min(limit, 50)}"
    req = urllib.request.Request(url, headers={
        "Authorization": f"Bearer {token}",
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36"
    })

    try:
        with urllib.request.urlopen(req, timeout=10, context=pc.get_ssl_context()) as resp:
            data = json.loads(resp.read().decode("utf-8"))
            items = data.get("items", [])
            playlists = []
            for item in items:
                if not item:
                    continue
                images = item.get("images") or []
                cover_url = images[0].get("url") if images else ""
                playlists.append({
                    "id": item.get("id"),
                    "title": item.get("name"),
                    "description": item.get("description", ""),
                    "image": cover_url,
                    "trackCount": item.get("tracks", {}).get("total", 0),
                    "owner": item.get("owner", {}).get("display_name", "")
                })
            return {"success": True, "playlists": playlists}
    except Exception as e:
        return {"success": False, "error": f"Lỗi gọi Spotify API: {str(e)}", "playlists": []}


_PLAYLIST_TRACKS_CACHE = {}


def fetch_spotify_playlist_from_embed(playlist_id):
    """
    Scrapes playlist metadata and tracks from Spotify embed page.
    Immune to Spotify Web API 429 rate limits and requires zero OAuth token.
    """
    pid = extract_playlist_id(playlist_id)
    if not pid:
        return None
    url = f"https://open.spotify.com/embed/playlist/{pid}"
    req = urllib.request.Request(url, headers={
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36",
        "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8"
    })
    try:
        with urllib.request.urlopen(req, timeout=10, context=pc.get_ssl_context()) as r:
            html = r.read().decode("utf-8", errors="ignore")
        m = re.search(r'<script id="__NEXT_DATA__" type="application/json">(.*?)</script>', html)
        if not m:
            return None
        data = json.loads(m.group(1))
        entity = data.get("props", {}).get("pageProps", {}).get("state", {}).get("data", {}).get("entity", {})
        if not entity:
            return None

        tracks = []
        for item in entity.get("trackList", []):
            tracks.append({
                "name": item.get("title", ""),
                "artist": item.get("subtitle", ""),
                "album": entity.get("name", ""),
                "duration_ms": item.get("duration", 0),
                "image": "",
                "isrc": item.get("uri", "")
            })

        cover_sources = entity.get("coverArt", {}).get("sources", [])
        cover_url = cover_sources[0].get("url", "") if cover_sources else ""

        res = {
            "success": True,
            "id": pid,
            "title": entity.get("name", "Spotify Playlist"),
            "description": entity.get("subtitle", ""),
            "image": cover_url,
            "trackCount": len(tracks),
            "owner": entity.get("subtitle", ""),
            "tracks": tracks
        }
        _PLAYLIST_TRACKS_CACHE[pid] = tracks
        return res
    except Exception as e:
        sys.stderr.write(f"[spotify_importer] Embed scrape note for {pid}: {e}\n")
        return None


def fetch_spotify_playlist_details(playlist_id, token=None, spdc=None):
    """
    Fetches Spotify playlist metadata (title, description, image).
    Tries ultra-fast rate-limit-immune embed parser first, then falls back to Web API.
    """
    pid = extract_playlist_id(playlist_id)
    if not pid:
        return {"success": False, "error": "ID playlist không hợp lệ."}

    # Fast path: Embed scraper (0ms auth, 0 rate limit, 100% reliable)
    embed_res = fetch_spotify_playlist_from_embed(pid)
    if embed_res and embed_res.get("success"):
        return {
            "success": True,
            "id": embed_res["id"],
            "title": embed_res["title"],
            "description": embed_res["description"],
            "image": embed_res["image"],
            "trackCount": embed_res["trackCount"],
            "owner": embed_res["owner"]
        }

    if not token:
        if not spdc:
            spdc = lyrics_helper.get_spotify_spdc()
        token = lyrics_helper.get_spotify_access_token(spdc) if spdc else None

    if not token:
        return {"success": False, "error": "Không có token xác thực Spotify."}

    url = f"https://api.spotify.com/v1/playlists/{pid}"
    req = urllib.request.Request(url, headers={
        "Authorization": f"Bearer {token}",
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36"
    })
    try:
        with urllib.request.urlopen(req, timeout=10, context=pc.get_ssl_context()) as resp:
            data = json.loads(resp.read().decode("utf-8"))
            images = data.get("images") or []
            cover_url = images[0].get("url") if images else ""
            return {
                "success": True,
                "id": data.get("id"),
                "title": data.get("name"),
                "description": data.get("description", ""),
                "image": cover_url,
                "trackCount": data.get("tracks", {}).get("total", 0),
                "owner": data.get("owner", {}).get("display_name", "")
            }
    except Exception as e:
        return {"success": False, "error": f"Không thể lấy thông tin playlist: {str(e)}"}


def fetch_spotify_playlist_tracks(playlist_id, token):
    """
    Fetches all tracks from a Spotify playlist, handling pagination (100 tracks per page).
    """
    pid = extract_playlist_id(playlist_id)
    if pid in _PLAYLIST_TRACKS_CACHE and _PLAYLIST_TRACKS_CACHE[pid]:
        return _PLAYLIST_TRACKS_CACHE[pid]

    embed_res = fetch_spotify_playlist_from_embed(pid)
    if embed_res and embed_res.get("tracks"):
        return embed_res["tracks"]

    tracks = []
    offset = 0
    limit = 100

    while True:
        url = f"https://api.spotify.com/v1/playlists/{pid}/tracks?limit={limit}&offset={offset}"
        req = urllib.request.Request(url, headers={
            "Authorization": f"Bearer {token}",
            "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36"
        })
        try:
            with urllib.request.urlopen(req, timeout=12, context=pc.get_ssl_context()) as resp:
                data = json.loads(resp.read().decode("utf-8"))
                items = data.get("items", [])
                if not items:
                    break

                for item in items:
                    t = item.get("track")
                    if not t or not t.get("name"):
                        continue
                    artists = ", ".join([a.get("name", "") for a in t.get("artists", []) if a.get("name")])
                    album = t.get("album", {})
                    album_images = album.get("images") or []
                    cover_url = album_images[0].get("url") if album_images else ""
                    tracks.append({
                        "name": t.get("name"),
                        "artist": artists,
                        "album": album.get("name", ""),
                        "duration_ms": t.get("duration_ms", 0),
                        "image": cover_url,
                        "isrc": t.get("external_ids", {}).get("isrc", "")
                    })

                offset += len(items)
                if offset >= data.get("total", 0):
                    break
        except Exception as e:
            sys.stderr.write(f"[spotify_importer] Error fetching tracks at offset {offset}: {e}\n")
            break

    return tracks


def match_spotify_track_to_ytmusic(sp_track):
    """
    Searches YouTube Music for the best matching videoId corresponding to the Spotify track.
    Uses ytmusic_helper.filter_search and score evaluation.
    """
    name = sp_track.get("name", "")
    artist = sp_track.get("artist", "")
    query = f"{name} {artist}".strip()
    if not query:
        return None

    try:
        search_res = ytmusic_helper.filter_search(query, "songs", limit=5)
        candidates = search_res.get("items", []) if isinstance(search_res, dict) else []
        if not candidates:
            # Fallback to general search without filter
            search_res = ytmusic_helper.filter_search(query, "videos", limit=5)
            candidates = search_res.get("items", []) if isinstance(search_res, dict) else []

        if not candidates:
            return None

        # Score candidates
        best_candidate = None
        best_score = -9999.0
        for cand in candidates:
            score = calculate_track_match_score(sp_track, cand)
            if score > best_score:
                best_score = score
                best_candidate = cand

        if best_candidate and best_candidate.get("videoId"):
            vid = best_candidate["videoId"]
            return {
                "title": sp_track.get("name") or best_candidate.get("title"),
                "artist": sp_track.get("artist") or best_candidate.get("artist"),
                "album": sp_track.get("album") or best_candidate.get("album", ""),
                "duration": int(best_candidate.get("duration") or (sp_track.get("duration_ms", 0) // 1000)),
                "videoId": vid,
                "path": f"ytdl://{vid}",
                "image": sp_track.get("image") or best_candidate.get("image", ""),
                "source": "spotify_import"
            }
    except Exception as e:
        sys.stderr.write(f"[spotify_importer] Track match error for '{query}': {e}\n")

    return None


class SpotifyImportManager:
    """
    Thread-safe background worker manager for importing Spotify playlists.
    Tracks live progress (current, total, percent, current_track, completed, error).
    """
    _instance = None
    _lock = threading.Lock()

    def __new__(cls):
        with cls._lock:
            if cls._instance is None:
                cls._instance = super().__new__(cls)
                cls._instance._init_state()
            return cls._instance

    def _init_state(self):
        self.active = False
        self.cancel_requested = False
        self.playlist_id = ""
        self.playlist_title = ""
        self.current = 0
        self.total = 0
        self.percent = 0
        self.current_track = ""
        self.completed = False
        self.error = None
        self.imported_playlist_id = None
        self._thread = None

    def get_status(self):
        with self._lock:
            return {
                "active": self.active,
                "playlistId": self.playlist_id,
                "playlistTitle": self.playlist_title,
                "current": self.current,
                "total": self.total,
                "percent": self.percent,
                "currentTrack": self.current_track,
                "completed": self.completed,
                "error": self.error,
                "importedPlaylistId": self.imported_playlist_id
            }

    def cancel(self):
        with self._lock:
            if self.active:
                self.cancel_requested = True
                self.active = False
                self.error = "Đã hủy bởi người dùng."
                return True
        return False

    def start_import(self, playlist_id, playlist_title=None, spdc=None):
        with self._lock:
            if self.active:
                return {"success": False, "error": "Một tiến trình import khác đang chạy."}

            pid = extract_playlist_id(playlist_id)
            if not pid:
                return {"success": False, "error": "ID hoặc đường dẫn Playlist không hợp lệ."}

            self.active = True
            self.cancel_requested = False
            self.playlist_id = pid
            self.playlist_title = playlist_title or "Spotify Playlist"
            self.current = 0
            self.total = 0
            self.percent = 0
            self.current_track = "Đang kết nối Spotify..."
            self.completed = False
            self.error = None
            self.imported_playlist_id = None

            self._thread = threading.Thread(
                target=self._run_import,
                args=(pid, self.playlist_title, spdc),
                daemon=True
            )
            self._thread.start()
            return {"success": True, "message": "Đã bắt đầu chuyển giao playlist."}

    def _run_import(self, pid, fallback_title, spdc):
        try:
            if not spdc:
                spdc = lyrics_helper.get_spotify_spdc()
            token = lyrics_helper.get_spotify_access_token(spdc) if spdc else None

            if not token:
                with self._lock:
                    self.active = False
                    self.error = "Không thể lấy token xác thực Spotify. Vui lòng kiểm tra lại Cookie."
                return

            # Fetch details
            details = fetch_spotify_playlist_details(pid, token=token)
            title = details.get("title") or fallback_title or "Spotify Playlist"
            cover_image = details.get("image") or ""
            desc = details.get("description") or f"Chuyển giao từ Spotify ({time.strftime('%d/%m/%Y')})"

            with self._lock:
                self.playlist_title = title
                self.current_track = "Đang tải danh sách bài hát..."

            # Fetch tracks
            sp_tracks = fetch_spotify_playlist_tracks(pid, token)
            total_tracks = len(sp_tracks)
            if total_tracks == 0:
                with self._lock:
                    self.active = False
                    self.error = "Không tìm thấy bài hát nào trong playlist này."
                return

            with self._lock:
                self.total = total_tracks

            resolved_tracks = []
            for idx, sp_t in enumerate(sp_tracks):
                if self.cancel_requested:
                    break

                track_label = f"{sp_t.get('name', '')} - {sp_t.get('artist', '')}".strip(" -")
                with self._lock:
                    self.current = idx + 1
                    self.current_track = track_label
                    self.percent = int((self.current / total_tracks) * 100)

                matched = match_spotify_track_to_ytmusic(sp_t)
                if matched:
                    resolved_tracks.append(matched)

                # Gentle pacing to avoid YouTube Music rate limits
                time.sleep(0.05)

            if not resolved_tracks and not self.cancel_requested:
                with self._lock:
                    self.active = False
                    self.error = "Không thể tìm thấy nguồn âm thanh phù hợp cho các bài hát."
                return

            # Save to custom_playlists.json via playlist_manager (SSOT)
            existing_playlists = playlist_manager.load_playlists()
            new_id = f"custom_spotify_{pid}_{int(time.time())}"
            new_playlist = {
                "id": new_id,
                "playlistId": new_id,
                "title": title,
                "description": desc,
                "image": cover_image,
                "trackCount": len(resolved_tracks),
                "tracks": resolved_tracks,
                "source": "spotify_import",
                "spotifyId": pid,
                "createdAt": int(time.time() * 1000)
            }
            existing_playlists.insert(0, new_playlist)
            playlist_manager.save_playlists(existing_playlists)

            with self._lock:
                self.active = False
                self.completed = True
                self.percent = 100
                self.imported_playlist_id = new_id
                self.current_track = f"Đã chuyển thành công {len(resolved_tracks)}/{total_tracks} bài hát!"
        except Exception as e:
            with self._lock:
                self.active = False
                self.error = f"Lỗi trong quá trình chuyển giao: {str(e)}"


# Singleton instance
importer = SpotifyImportManager()
