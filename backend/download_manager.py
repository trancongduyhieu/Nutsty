#!/usr/bin/env python3
"""
Nutsty Download Manager (Multi-Thread Architecture)
- Real-time download queue & worker daemon
- Audio extraction (192k AAC/M4A / Opus) via yt-dlp + FFmpeg
- Embedded album art & ID3 metadata
- Automatic synced lyrics (.lrc) fetching
- Desktop notifications & batch summary
- Unix domain socket IPC (/tmp/nutsty_download.sock) & stdout JSON stream
"""

import os
import sys
import glob
import json
import time
import shutil
import socket
import select
import threading
import subprocess

try:
    from . import platform_compat as pc
except (ImportError, ValueError):
    import platform_compat as pc

PROFILE_NAME = os.getenv("NUTSTY_PROFILE", "").strip().lower()
PROFILE_SUFFIX = f"_{PROFILE_NAME}" if PROFILE_NAME else ""

TEMP_DIR = pc.get_temp_dir()
CONFIG_DIR = pc.get_config_dir()
SOCKET_PATH = os.path.join(TEMP_DIR, f"nutsty_download{PROFILE_SUFFIX}.sock")
STATUS_FILE = os.path.join(TEMP_DIR, f"nutsty_download_status{PROFILE_SUFFIX}.json")

HAS_AF_UNIX = hasattr(socket, "AF_UNIX") and not pc.IS_WINDOWS
_in_proc_manager = None
_in_proc_lock = threading.Lock()

def get_in_proc_manager():
    global _in_proc_manager
    with _in_proc_lock:
        if _in_proc_manager is None:
            _in_proc_manager = DownloadManager()
        return _in_proc_manager

STATE_NOT_DOWNLOADED = 0
STATE_PREPARING = 1
STATE_DOWNLOADING = 2
STATE_DOWNLOADED = 3
STATE_FAILED = 4

DOWNLOAD_QUALITY_CONFIG = {
    "high_opus": {
        "format": "774/251/141/140/250/bestaudio/best",
        "codec": "opus",
        "quality": "256",
    },
    "high_aac": {
        "format": "141/774/140/251/250/bestaudio/best",
        "codec": "m4a",
        "quality": "256",
    },
    "medium": {
        "format": "251/140/141/774/250/bestaudio/best",
        "codec": "opus",
        "quality": "128",
    },
    "low": {
        "format": "250/251/140/141/774/bestaudio/best",
        "codec": "m4a",
        "quality": "64",
    },
}

def get_current_download_quality():
    settings_file = os.path.join(CONFIG_DIR, f"nutsty_settings{PROFILE_SUFFIX}.json")
    if not os.path.exists(settings_file) and not PROFILE_SUFFIX:
        settings_file = os.path.join(CONFIG_DIR, "nutsty_settings.json")
    if os.path.exists(settings_file):
        try:
            with open(settings_file, "r", encoding="utf-8") as f:
                data = json.load(f)
                q = data.get("downloadQuality")
                if q in DOWNLOAD_QUALITY_CONFIG:
                    return q
        except Exception:
            pass
    return "high_opus"

def get_download_dir():
    music_dir = pc.get_music_dir()
    target = os.path.join(music_dir, "Downloads_Phone")
    os.makedirs(target, exist_ok=True)
    return target

def send_desktop_notification(title, message):
    try:
        icon_path = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "assets/icons/download-symbolic.svg")
        cmd = ["notify-send", title, message, "-a", "Nutsty"]
        if os.path.exists(icon_path):
            cmd.extend(["-i", icon_path])
        subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except Exception:
        pass

class DownloadManager:
    def __init__(self):
        self.lock = threading.Lock()
        self.queue = []  # list of dict: {videoId, title, artist, thumbnail}
        self.tasks = {}  # videoId -> dict of info & state
        self.cancelled_ids = set()
        self.active_downloads = set()
        self.current_task = None
        self.batch_total = 0
        self.batch_completed = 0
        self.batch_failed = 0
        self.last_song_title = ""
        self.running = True
        self.clients = set()

        if os.path.exists(STATUS_FILE):
            try:
                with open(STATUS_FILE, "r", encoding="utf-8") as f:
                    _data = json.load(f)
                if "tasks" in _data and isinstance(_data["tasks"], dict):
                    dl_dir = get_download_dir()
                    cleaned_tasks = {}
                    for vid, t in _data["tasks"].items():
                        if not isinstance(t, dict):
                            continue
                        st = t.get("state", 0)
                        p = t.get("path", "")
                        if st == STATE_DOWNLOADED and p and os.path.exists(p):
                            cleaned_tasks[vid] = t
                        elif st in (STATE_PREPARING, STATE_DOWNLOADING):
                            # Check if file actually finished downloading on disk before crash/lock
                            title_str = t.get("title") or ""
                            safe_t = "".join(c if c not in '<>:"/\\|?*' else "_" for c in title_str).strip()
                            found_path = ""
                            if p and os.path.exists(p):
                                found_path = p
                            elif safe_t and os.path.exists(dl_dir):
                                for fn in os.listdir(dl_dir):
                                    if fn.lower().startswith(safe_t[:30].lower()) and not fn.endswith(".part"):
                                        cand = os.path.join(dl_dir, fn)
                                        if os.path.getsize(cand) > 30000:
                                            found_path = cand
                                            break
                            if found_path:
                                t["state"] = STATE_DOWNLOADED
                                t["progress"] = 100.0
                                t["path"] = found_path
                                cleaned_tasks[vid] = t
                            # Otherwise discard stale zombie downloading tasks so they never freeze at 0%/66%
                    self.tasks = cleaned_tasks
            except Exception:
                pass
        self._save_status()

        self.worker_thread = threading.Thread(target=self._worker_loop, daemon=True)
        self.worker_thread.start()

    def emit_event(self, data):
        """Emit JSON event to stdout and all connected clients"""
        msg = json.dumps(data, ensure_ascii=False) + "\n"
        try:
            sys.stdout.write(msg)
            sys.stdout.flush()
        except Exception:
            pass

        dead_clients = set()
        with self.lock:
            clients_copy = list(self.clients)
        for client in clients_copy:
            try:
                client.sendall(msg.encode("utf-8"))
            except Exception:
                dead_clients.add(client)

        if dead_clients:
            with self.lock:
                self.clients.difference_update(dead_clients)

        self._save_status()

    def _save_status(self):
        try:
            with self.lock:
                payload = {
                    "active_count": len(self.active_downloads) + len(self.queue),
                    "queue_len": len(self.queue),
                    "batch_total": self.batch_total,
                    "batch_completed": self.batch_completed,
                    "batch_failed": self.batch_failed,
                    "tasks": dict(self.tasks),
                    "queue": list(self.queue)
                }
            raw_json = json.dumps(payload, ensure_ascii=False, indent=2)
            os.makedirs(os.path.dirname(STATUS_FILE), exist_ok=True)
            tmp = f"{STATUS_FILE}.{threading.get_ident()}.tmp"
            with open(tmp, "w", encoding="utf-8") as f:
                f.write(raw_json)
            replaced = False
            for _ in range(5):
                try:
                    os.replace(tmp, STATUS_FILE)
                    replaced = True
                    break
                except Exception:
                    time.sleep(0.015)
            if not replaced:
                try:
                    with open(STATUS_FILE, "w", encoding="utf-8") as f:
                        f.write(raw_json)
                except Exception:
                    pass
                try:
                    if os.path.exists(tmp):
                        os.remove(tmp)
                except Exception:
                    pass
        except Exception:
            pass

    def enqueue(self, video_id, title="Track", artist="Artist", thumbnail="", quality=None):
        if not video_id:
            return False

        with self.lock:
            self.cancelled_ids.discard(video_id)
            # Only skip if actively downloading in worker thread or already waiting in self.queue
            if video_id in self.active_downloads or any(q.get("videoId") == video_id for q in self.queue):
                return False

            task = {
                "videoId": video_id,
                "title": title or "Track",
                "artist": artist or "Artist",
                "thumbnail": thumbnail or "",
                "quality": quality or get_current_download_quality(),
                "state": STATE_PREPARING,
                "progress": 2.0,
                "speed": "Connecting...",
                "eta": "--",
                "path": "",
                "error": ""
            }
            self.tasks[video_id] = task

            was_idle = len(self.active_downloads) == 0 and len(self.queue) == 0
            self.queue.append(task)
            self.batch_total += 1
            self.last_song_title = title or "Track"

            if was_idle:
                self.batch_completed = 0
                self.batch_failed = 0
                send_desktop_notification("Downloading", self.last_song_title)

        self.emit_event({
            "event": "task_enqueued",
            "videoId": video_id,
            "title": title,
            "artist": artist,
            "thumbnail": thumbnail,
            "quality": task["quality"],
            "queue_len": len(self.queue),
            "batch_total": self.batch_total,
            "active_count": len(self.active_downloads) + len(self.queue)
        })
        return True

    def cancel(self, video_id):
        if not video_id:
            return
        with self.lock:
            self.cancelled_ids.add(video_id)
            self.queue = [t for t in self.queue if t.get("videoId") != video_id]
            self.active_downloads.discard(video_id)
            self.tasks.pop(video_id, None)
        self._save_status()
        self.emit_event({
            "event": "task_cancelled",
            "videoId": video_id,
            "queue_len": len(self.queue),
            "active_count": len(self.active_downloads) + len(self.queue)
        })

    def remove(self, video_id):
        if not video_id:
            return
        with self.lock:
            self.cancelled_ids.add(video_id)
            self.queue = [t for t in self.queue if t.get("videoId") != video_id]
            self.active_downloads.discard(video_id)
            self.tasks.pop(video_id, None)
        self._save_status()
        self.emit_event({
            "event": "task_removed",
            "videoId": video_id,
            "queue_len": len(self.queue),
            "active_count": len(self.active_downloads) + len(self.queue)
        })

    def clear_completed(self):
        with self.lock:
            self.tasks = {
                vid: t for vid, t in self.tasks.items()
                if t.get("state") in (STATE_PREPARING, STATE_DOWNLOADING) and (vid in self.active_downloads or any(q.get("videoId") == vid for q in self.queue))
            }
        self._save_status()
        self.emit_event({
            "event": "completed_cleared",
            "tasks": self.tasks,
            "queue_len": len(self.queue),
            "active_count": len(self.active_downloads) + len(self.queue)
        })

    def _worker_loop(self):
        while self.running:
            task = None
            with self.lock:
                while self.queue:
                    cand = self.queue.pop(0)
                    cid = cand.get("videoId")
                    if cid and cid not in self.cancelled_ids:
                        task = cand
                        self.active_downloads.add(cid)
                        self.current_task = task
                        task["state"] = STATE_DOWNLOADING
                        task["progress"] = max(5.0, float(task.get("progress") or 0.0))
                        task["speed"] = "Starting..."
                        break

            if not task:
                time.sleep(0.2)
                continue

            video_id = task["videoId"]
            self.emit_event({
                "event": "task_started",
                "videoId": video_id,
                "title": task["title"],
                "artist": task["artist"],
                "progress": task["progress"],
                "active_count": len(self.active_downloads) + len(self.queue)
            })

            success = self._execute_download(task)

            with self.lock:
                was_cancelled = video_id in self.cancelled_ids
                self.active_downloads.discard(video_id)
                self.current_task = None
                if was_cancelled:
                    self.tasks.pop(video_id, None)
                    self._save_status()
                    continue
                if success:
                    self.batch_completed += 1
                else:
                    self.batch_failed += 1

                is_now_idle = len(self.active_downloads) == 0 and len(self.queue) == 0
                remaining = len(self.active_downloads) + len(self.queue)

            self.emit_event({
                "event": "task_completed" if success else "task_failed",
                "videoId": video_id,
                "title": task["title"],
                "artist": task.get("artist", ""),
                "path": task.get("path", ""),
                "error": task.get("error", ""),
                "active_count": remaining,
                "batch_completed": self.batch_completed,
                "batch_failed": self.batch_failed
            })

            if is_now_idle:
                if self.batch_total == 1:
                    summary = self.last_song_title
                elif self.batch_failed == 0:
                    summary = f"{self.batch_completed} songs downloaded"
                else:
                    summary = f"{self.batch_completed} downloaded, {self.batch_failed} failed"

                title = "Download complete" if self.batch_completed > 0 else "Download failed"
                send_desktop_notification(title, summary)

                with self.lock:
                    self.batch_total = 0
                    self.batch_completed = 0
                    self.batch_failed = 0

    def _get_exported_cookie_file(self):
        try:
            import ytmusic_helper
            cf = ytmusic_helper.get_exported_cookie_file()
            if cf and os.path.exists(cf):
                return cf
        except Exception:
            pass

        auth_file = os.path.join(pc.get_config_dir(), f"ytmusic_auth{PROFILE_SUFFIX}.json")
        if not os.path.exists(auth_file) and not PROFILE_SUFFIX:
            auth_file = os.path.join(pc.get_config_dir(), "ytmusic_auth.json")
        if not os.path.exists(auth_file):
            return None
        try:
            with open(auth_file, "r", encoding="utf-8") as f:
                data = json.load(f)
            raw_cookie = data.get("cookie", "")
            if not raw_cookie:
                return None
            temp_dir = pc.get_temp_dir()
            os.makedirs(temp_dir, exist_ok=True)
            out_path = os.path.join(temp_dir, f"nutsty_yt_cookies{PROFILE_SUFFIX}.txt")
            now = int(time.time()) + 365 * 86400
            lines = ["# Netscape HTTP Cookie File\n"]
            for item in raw_cookie.split(";"):
                item = item.strip()
                if not item or "=" not in item:
                    continue
                k, v = item.split("=", 1)
                lines.append(f".youtube.com\tTRUE\t/\tTRUE\t{now}\t{k.strip()}\t{v.strip()}\n")
            with open(out_path, "w", encoding="utf-8") as f:
                f.writelines(lines)
            return out_path
        except Exception:
            return None

    def _execute_download(self, task):
        import yt_dlp

        video_id = task["videoId"]
        dl_dir = get_download_dir()
        target_url = f"https://www.youtube.com/watch?v={video_id}"

        last_progress_time = [0.0]

        def progress_hook(d):
            if video_id in self.cancelled_ids:
                raise RuntimeError("Cancelled by user")
            status = d.get("status")
            if status == "downloading":
                total = d.get("total_bytes") or d.get("total_bytes_estimate") or 0
                downloaded = d.get("downloaded_bytes") or 0
                pct = (downloaded / total * 100.0) if total > 0 else 0.0

                speed_bytes = d.get("speed") or 0
                speed_str = f"{speed_bytes / (1024*1024):.1f} MB/s" if speed_bytes else "--"
                eta_sec = d.get("eta") or 0
                eta_str = f"{eta_sec // 60:02d}:{eta_sec % 60:02d}" if eta_sec else "--"

                # Throttle progress events to max 5 per second
                now = time.time()
                if now - last_progress_time[0] >= 0.2:
                    last_progress_time[0] = now
                    with self.lock:
                        if video_id in self.cancelled_ids:
                            raise RuntimeError("Cancelled by user")
                        task["progress"] = round(pct, 1)
                        task["speed"] = speed_str
                        task["eta"] = eta_str

                    self.emit_event({
                        "event": "task_progress",
                        "videoId": video_id,
                        "progress": round(pct, 1),
                        "speed": speed_str,
                        "eta": eta_str
                    })

        target_quality = task.get("quality") or get_current_download_quality()
        cfg = DOWNLOAD_QUALITY_CONFIG.get(target_quality, DOWNLOAD_QUALITY_CONFIG["high_opus"])
        target_format = cfg["format"]
        target_codec = cfg["codec"]
        target_quality_val = cfg["quality"]

        has_ffmpeg = bool(shutil.which("ffmpeg") and shutil.which("ffprobe"))
        if not has_ffmpeg:
            target_format = "141/140/251/250/18/bestaudio[ext=m4a]/bestaudio[ext=webm]/bestaudio/best"

        # Tier 0: Fast Direct Stream Download via ytmusic_helper (0ms cache hit if currently playing!)
        if not has_ffmpeg:
            try:
                backend_dir = os.path.dirname(os.path.abspath(__file__))
                if backend_dir not in sys.path:
                    sys.path.insert(0, backend_dir)
                import ytmusic_helper
                import re
                import urllib.request

                resolved = ytmusic_helper.resolve_stream_url(video_id, target_quality)
                if resolved and resolved.get("stream_url"):
                    s_url = resolved["stream_url"]
                    s_ua = resolved.get("user_agent") or "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36"
                    s_codec = str(resolved.get("codec") or "").lower()
                    s_itag = str(resolved.get("itag") or "")
                    ext = ".webm" if ("opus" in s_codec or s_itag in ("250", "251", "774")) else ".m4a"

                    raw_title = task.get("title") or video_id
                    safe_title = re.sub(r'[<>:"/\\|?*\x00-\x1f]', "_", raw_title).strip().strip(".")
                    if not safe_title:
                        safe_title = video_id
                    out_file = os.path.join(dl_dir, f"{safe_title[:140]}{ext}")
                    part_file = out_file + ".part"

                    headers = {"User-Agent": s_ua, "Accept": "*/*"}
                    req = urllib.request.Request(s_url, headers=headers)
                    t_start = time.time()
                    downloaded = 0
                    with urllib.request.urlopen(req, timeout=20) as resp:
                        total = int(resp.headers.get("Content-Length") or 0)
                        with open(part_file, "wb") as out_f:
                            while True:
                                chunk = resp.read(262144)
                                if not chunk:
                                    break
                                out_f.write(chunk)
                                downloaded += len(chunk)
                                elapsed = max(0.001, time.time() - t_start)
                                speed = downloaded / elapsed
                                eta = int((total - downloaded) / speed) if (total > downloaded and speed > 0) else 0
                                progress_hook({
                                    "status": "downloading",
                                    "downloaded_bytes": downloaded,
                                    "total_bytes": total,
                                    "speed": speed,
                                    "eta": eta,
                                })

                    if os.path.exists(part_file) and os.path.getsize(part_file) > 30000:
                        os.replace(part_file, out_file)
                        self._embed_metadata_mutagen(
                            out_file,
                            task.get("title", ""),
                            task.get("artist", ""),
                            task.get("thumbnail", "") or f"https://i.ytimg.com/vi/{video_id}/hqdefault.jpg"
                        )
                        with self.lock:
                            task["state"] = STATE_DOWNLOADED
                            task["progress"] = 100.0
                            task["path"] = out_file
                        self._fetch_lyrics_for_file(out_file, task["title"], task["artist"], video_id)
                        self._trigger_library_rescan(out_file, task.get("title", ""), task.get("artist", ""), video_id, task.get("thumbnail", ""))
                        return True
            except Exception as e:
                sys.stderr.write(f"[DownloadManager Tier 0 fallback]: {e}\n")

        safe_outtmpl = os.path.join(dl_dir, "%(title).150B.%(ext)s")
        base_opts = {
            "format": target_format,
            "outtmpl": safe_outtmpl,
            "windowsfilenames": True,
            "remote_components": ["ejs:github"],
            "extractor_args": {"youtube": {"player_client": ["web_embedded", "mweb", "android", "ios"]}},
            "writethumbnail": has_ffmpeg,
            "embedthumbnail": has_ffmpeg,
            "postprocessors": [
                {
                    "key": "FFmpegExtractAudio",
                    "preferredcodec": target_codec,
                    "preferredquality": target_quality_val,
                },
                {"key": "FFmpegMetadata"},
                {"key": "EmbedThumbnail"},
            ] if has_ffmpeg else [],
            "quiet": True,
            "no_warnings": True,
            "progress_hooks": [progress_hook],
        }

        attempts = [base_opts]
        cookie_file = self._get_exported_cookie_file()
        if cookie_file:
            auth_opts = dict(base_opts)
            auth_opts["cookiefile"] = cookie_file
            auth_opts["extractor_args"] = {"youtube": {"player_client": ["mweb", "web", "web_embedded", "tv"]}}
            attempts.append(auth_opts)

        # Tier 3: Browser cookie extraction fallback
        for browser in ["firefox", "chrome", "chromium", "brave", "edge"]:
            b_opts = dict(base_opts)
            b_opts["cookiesfrombrowser"] = (browser,)
            b_opts["extractor_args"] = {"youtube": {"player_client": ["mweb", "web", "web_embedded", "tv"]}}
            attempts.append(b_opts)

        last_err = None
        for attempt_idx, current_opts in enumerate(attempts):
            try:
                with yt_dlp.YoutubeDL(current_opts) as ydl:
                    info = ydl.extract_info(target_url, download=True)
                    title = info.get("title") or task["title"]
                    task["title"] = title
                    # Find output filename
                    expected_fn = ydl.prepare_filename(info)
                    base, _ = os.path.splitext(expected_fn)
                    downloaded_file = None
                    if os.path.exists(expected_fn):
                        downloaded_file = expected_fn
                    if not downloaded_file:
                        for ext in [f".{target_codec}", ".m4a", ".opus", ".mp3", ".webm", ".flac", ".ogg"]:
                            candidate = base + ext
                            if os.path.exists(candidate):
                                downloaded_file = candidate
                                break

                if downloaded_file and not has_ffmpeg:
                    self._embed_metadata_mutagen(
                        downloaded_file,
                        task.get("title", ""),
                        task.get("artist", ""),
                        task.get("thumbnail", "") or f"https://i.ytimg.com/vi/{video_id}/hqdefault.jpg"
                    )

                with self.lock:
                    task["state"] = STATE_DOWNLOADED
                    task["progress"] = 100.0
                    task["path"] = downloaded_file or ""

                # Fetch synced lyrics alongside the downloaded audio
                if downloaded_file:
                    self._fetch_lyrics_for_file(downloaded_file, task["title"], task["artist"], video_id)

                # Trigger library re-index so the new track appears in Nutsty 0ms
                self._trigger_library_rescan(downloaded_file, task.get("title", ""), task.get("artist", ""), video_id, task.get("thumbnail", ""))
                return True

            except Exception as e:
                last_err = e
                continue

        # Defensive fallback: if audio file was successfully written despite a thumbnail or tag error
        if last_err:
            dl_dir = get_download_dir()
            candidate_files = []
            for ext in [f".{target_codec}", ".m4a", ".opus", ".mp3", ".webm"]:
                matches = glob.glob(os.path.join(dl_dir, f"*{ext}"))
                for m in matches:
                    try:
                        if (time.time() - os.path.getmtime(m)) < 120 and os.path.getsize(m) > 50000:
                            candidate_files.append(m)
                    except Exception:
                        pass
            if candidate_files:
                candidate_files.sort(key=lambda x: os.path.getmtime(x), reverse=True)
                downloaded_file = candidate_files[0]
                if not has_ffmpeg:
                    self._embed_metadata_mutagen(
                        downloaded_file,
                        task.get("title", ""),
                        task.get("artist", ""),
                        task.get("thumbnail", "") or f"https://i.ytimg.com/vi/{video_id}/hqdefault.jpg"
                    )
                with self.lock:
                    task["state"] = STATE_DOWNLOADED
                    task["progress"] = 100.0
                    task["path"] = downloaded_file
                self._fetch_lyrics_for_file(downloaded_file, task["title"], task["artist"], video_id)
                self._trigger_library_rescan(downloaded_file, task.get("title", ""), task.get("artist", ""), video_id, task.get("thumbnail", ""))
                return True

        with self.lock:
            task["state"] = STATE_FAILED
            task["error"] = str(last_err)
        return False

    def _embed_metadata_mutagen(self, audio_path, title, artist, thumb_url):
        """Pure-Python metadata & cover art embedder when FFmpeg is unavailable"""
        try:
            if not audio_path or not os.path.exists(audio_path):
                return
            ext = os.path.splitext(audio_path)[1].lower()
            if ext == ".m4a":
                from mutagen.mp4 import MP4, MP4Cover
                import urllib.request
                audio = MP4(audio_path)
                if title:
                    audio["\xa9nam"] = [title]
                if artist:
                    audio["\xa9ART"] = [artist]
                if thumb_url and thumb_url.startswith("http"):
                    try:
                        req = urllib.request.Request(thumb_url, headers={"User-Agent": "Mozilla/5.0"})
                        with urllib.request.urlopen(req, timeout=6) as resp:
                            img_bytes = resp.read()
                        if img_bytes:
                            fmt = MP4Cover.FORMAT_PNG if thumb_url.lower().endswith(".png") else MP4Cover.FORMAT_JPEG
                            audio["covr"] = [MP4Cover(img_bytes, imageformat=fmt)]
                    except Exception:
                        pass
                audio.save()
        except Exception:
            pass

    def _fetch_lyrics_for_file(self, audio_path, title, artist, video_id):
        try:
            base, _ = os.path.splitext(audio_path)
            target_lrc = base + ".lrc"
            if os.path.exists(target_lrc):
                return

            backend_dir = os.path.dirname(os.path.abspath(__file__))
            if backend_dir not in sys.path:
                sys.path.insert(0, backend_dir)
            try:
                import lyrics_helper
                lines = lyrics_helper.get_lyrics(title, artist or "", video_id or "")
                if lines and isinstance(lines, list):
                    lrc_lines = []
                    for item in lines:
                        t = float(item.get("time", 0.0))
                        txt = item.get("text", "")
                        mins = int(t // 60)
                        secs = t % 60
                        lrc_lines.append(f"[{mins:02d}:{secs:05.2f}]{txt}")
                    with open(target_lrc, "w", encoding="utf-8") as f:
                        f.write("\n".join(lrc_lines))
                    return
            except Exception:
                pass

            lyrics_script = os.path.join(backend_dir, "lyrics_helper.py")
            if os.path.exists(lyrics_script):
                cmd = [sys.executable, lyrics_script, title, artist or "", video_id or ""]
                res = subprocess.run(cmd, capture_output=True, text=True, timeout=10, **pc.get_daemon_popen_kwargs())
                if res.returncode == 0 and res.stdout.strip():
                    lines = json.loads(res.stdout)
                    if lines and isinstance(lines, list):
                        lrc_lines = []
                        for item in lines:
                            t = float(item.get("time", 0.0))
                            txt = item.get("text", "")
                            mins = int(t // 60)
                            secs = t % 60
                            lrc_lines.append(f"[{mins:02d}:{secs:05.2f}]{txt}")
                        with open(target_lrc, "w", encoding="utf-8") as f:
                            f.write("\n".join(lrc_lines))
        except Exception:
            pass

    def _trigger_library_rescan(self, audio_path="", title="", artist="", video_id="", image=""):
        bin_name = "nutsty-library.exe" if sys.platform == "win32" else "nutsty-library"
        rust_bin = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "bin", bin_name)

        # 1. Instant single-track add into library.json (<2ms via Rust binary)
        if audio_path and os.path.exists(audio_path):
            if os.path.exists(rust_bin) and (sys.platform == "win32" or os.access(rust_bin, os.X_OK)):
                try:
                    subprocess.run([
                        rust_bin, "add", audio_path, title or "", artist or "", video_id or "", image or ""
                    ], check=True, timeout=2)
                    return
                except Exception as e:
                    print(f"[DownloadManager] rust add_track error: {e}", file=sys.stderr)
            try:
                backend_dir = os.path.dirname(os.path.abspath(__file__))
                if backend_dir not in sys.path:
                    sys.path.insert(0, backend_dir)
                import library
                library.add_track(audio_path, title=title, artist=artist, video_id=video_id, image=image)
                return
            except Exception as e:
                print(f"[DownloadManager] add_track error: {e}", file=sys.stderr)

        # 2. Asynchronous full scan in background thread if single track add was not possible
        def do_rescan():
            if os.path.exists(rust_bin) and (sys.platform == "win32" or os.access(rust_bin, os.X_OK)):
                try:
                    subprocess.run([rust_bin, "scan"], timeout=5)
                    return
                except Exception:
                    pass
            try:
                backend_dir = os.path.dirname(os.path.abspath(__file__))
                if backend_dir not in sys.path:
                    sys.path.insert(0, backend_dir)
                import library
                library.scan_library()
            except Exception:
                pass
        threading.Thread(target=do_rescan, daemon=True).start()

def run_daemon():
    """Run resident download daemon listening on Unix domain socket & printing stdout events"""
    if not HAS_AF_UNIX:
        manager = get_in_proc_manager()
        manager._save_status()
        manager.emit_event({"event": "daemon_ready", "socket": "in_proc"})
        return

    if os.path.exists(SOCKET_PATH):
        try:
            os.remove(SOCKET_PATH)
        except Exception:
            pass

    server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    server.bind(SOCKET_PATH)
    server.listen(10)
    server.setblocking(False)

    manager = DownloadManager()
    manager.emit_event({"event": "daemon_ready", "socket": SOCKET_PATH})

    read_sockets = [server]

    try:
        while True:
            readable, _, _ = select.select(read_sockets, [], [], 0.5)
            for s in readable:
                if s is server:
                    client_socket, _ = server.accept()
                    client_socket.setblocking(False)
                    read_sockets.append(client_socket)
                    with manager.lock:
                        manager.clients.add(client_socket)
                    # Send immediate status dump to new client
                    with manager.lock:
                        status_dump = {
                            "event": "status_dump",
                            "tasks": manager.tasks,
                            "queue_len": len(manager.queue),
                            "active_count": len(manager.active_downloads) + len(manager.queue),
                            "batch_total": manager.batch_total,
                            "batch_completed": manager.batch_completed
                        }
                    try:
                        client_socket.sendall((json.dumps(status_dump) + "\n").encode("utf-8"))
                    except Exception:
                        pass
                else:
                    try:
                        data = s.recv(4096)
                        if data:
                            lines = data.decode("utf-8").splitlines()
                            for line in lines:
                                if not line.strip():
                                    continue
                                try:
                                    cmd = json.loads(line)
                                    action = cmd.get("action")
                                    if action == "enqueue":
                                        manager.enqueue(
                                            cmd.get("videoId"),
                                            cmd.get("title", "Track"),
                                            cmd.get("artist", "Artist"),
                                            cmd.get("thumbnail", ""),
                                            cmd.get("quality")
                                        )
                                    elif action == "cancel":
                                        manager.cancel(cmd.get("videoId"))
                                    elif action in ("remove", "delete"):
                                        manager.remove(cmd.get("videoId"))
                                    elif action == "clear_completed":
                                        manager.clear_completed()
                                    elif action == "status":
                                        with manager.lock:
                                            resp = {
                                                "event": "status_dump",
                                                "tasks": manager.tasks,
                                                "queue_len": len(manager.queue),
                                                "active_count": len(manager.active_downloads) + len(manager.queue)
                                            }
                                        s.sendall((json.dumps(resp) + "\n").encode("utf-8"))
                                except Exception:
                                    pass
                        else:
                            # Client disconnected
                            read_sockets.remove(s)
                            with manager.lock:
                                manager.clients.discard(s)
                            s.close()
                    except Exception:
                        if s in read_sockets:
                            read_sockets.remove(s)
                        with manager.lock:
                            manager.clients.discard(s)
                        s.close()
    except KeyboardInterrupt:
        pass
    finally:
        server.close()
        if os.path.exists(SOCKET_PATH):
            try:
                os.remove(SOCKET_PATH)
            except Exception:
                pass

def client_enqueue(video_id, title="Track", artist="Artist", thumbnail="", quality=None):
    """CLI client helper to enqueue a download"""
    if not HAS_AF_UNIX:
        mgr = get_in_proc_manager()
        mgr.enqueue(video_id, title, artist, thumbnail, quality)
        print(json.dumps({"success": True, "videoId": video_id, "title": title}))
        return True

    def is_socket_alive():
        if not os.path.exists(SOCKET_PATH):
            return False
        try:
            s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            s.connect(SOCKET_PATH)
            s.close()
            return True
        except Exception:
            return False

    if not is_socket_alive():
        script = os.path.abspath(__file__)
        subprocess.Popen(
            ["python3", script, "daemon"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            start_new_session=True
        )
        for _ in range(30):
            time.sleep(0.1)
            if is_socket_alive():
                break

    try:
        s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        s.connect(SOCKET_PATH)
        payload = {
            "action": "enqueue",
            "videoId": video_id,
            "title": title,
            "artist": artist,
            "thumbnail": thumbnail,
            "quality": quality
        }
        s.sendall((json.dumps(payload) + "\n").encode("utf-8"))
        s.close()
        print(json.dumps({"success": True, "videoId": video_id, "title": title}))
        return True
    except Exception as e:
        print(json.dumps({"success": False, "error": str(e)}))
        return False

def client_clear_completed():
    """CLI client helper to clear completed downloads"""
    if os.path.exists(STATUS_FILE):
        try:
            with open(STATUS_FILE, "r", encoding="utf-8") as f:
                data = json.load(f)
            if "tasks" in data:
                data["tasks"] = {vid: t for vid, t in data["tasks"].items() if t.get("state") in (STATE_PREPARING, STATE_DOWNLOADING)}
            with open(STATUS_FILE, "w", encoding="utf-8") as f:
                json.dump(data, f, ensure_ascii=False, indent=2)
        except Exception:
            pass

    if not HAS_AF_UNIX:
        if _in_proc_manager:
            _in_proc_manager.clear_completed()
        print(json.dumps({"success": True, "action": "clear_completed"}))
        return True

    if os.path.exists(SOCKET_PATH):
        try:
            s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            s.connect(SOCKET_PATH)
            payload = {"action": "clear_completed"}
            s.sendall((json.dumps(payload) + "\n").encode("utf-8"))
            s.close()
            print(json.dumps({"success": True, "action": "clear_completed"}))
            return True
        except Exception as e:
            print(json.dumps({"success": False, "error": str(e)}))
            return False
    return True

def client_remove(video_id):
    """CLI client helper to remove a task from status"""
    if os.path.exists(STATUS_FILE):
        try:
            with open(STATUS_FILE, "r", encoding="utf-8") as f:
                data = json.load(f)
            if "tasks" in data and video_id in data["tasks"]:
                del data["tasks"][video_id]
            with open(STATUS_FILE, "w", encoding="utf-8") as f:
                json.dump(data, f, ensure_ascii=False, indent=2)
        except Exception:
            pass

    if not HAS_AF_UNIX:
        if _in_proc_manager:
            _in_proc_manager.remove(video_id)
        print(json.dumps({"success": True, "action": "remove", "videoId": video_id}))
        return True

    if os.path.exists(SOCKET_PATH):
        try:
            s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            s.connect(SOCKET_PATH)
            payload = {"action": "remove", "videoId": video_id}
            s.sendall((json.dumps(payload) + "\n").encode("utf-8"))
            s.close()
            print(json.dumps({"success": True, "action": "remove", "videoId": video_id}))
            return True
        except Exception as e:
            print(json.dumps({"success": False, "error": str(e)}))
            return False
    return True

def get_status():
    if os.path.exists(STATUS_FILE):
        try:
            with open(STATUS_FILE, "r", encoding="utf-8") as f:
                print(f.read())
                return
        except Exception:
            pass
    print(json.dumps({"active_count": 0, "queue_len": 0, "tasks": {}}))

def client_cancel(video_id):
    if os.path.exists(STATUS_FILE):
        try:
            with open(STATUS_FILE, "r", encoding="utf-8") as f:
                data = json.load(f)
            if "tasks" in data and video_id in data["tasks"]:
                del data["tasks"][video_id]
            if "queue" in data and isinstance(data["queue"], list):
                data["queue"] = [q for q in data["queue"] if q.get("videoId") != video_id]
            with open(STATUS_FILE, "w", encoding="utf-8") as f:
                json.dump(data, f, ensure_ascii=False, indent=2)
        except Exception:
            pass
    if not HAS_AF_UNIX:
        if _in_proc_manager:
            _in_proc_manager.cancel(video_id)
        print(json.dumps({"success": True, "action": "cancel", "videoId": video_id}))
        return True
    if os.path.exists(SOCKET_PATH):
        try:
            s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            s.connect(SOCKET_PATH)
            payload = {"action": "cancel", "videoId": video_id}
            s.sendall((json.dumps(payload) + "\n").encode("utf-8"))
            s.close()
            print(json.dumps({"success": True, "action": "cancel", "videoId": video_id}))
            return True
        except Exception as e:
            print(json.dumps({"success": False, "error": str(e)}))
            return False
    return True

def handle_cli(args):
    """Thread-safe CLI entrypoint for in-process Windows execution without holding sys_argv_lock"""
    if not args:
        run_daemon()
        return
    cmd = args[0]
    if cmd == "daemon":
        run_daemon()
    elif cmd in ("add", "enqueue"):
        vid = args[1] if len(args) > 1 else ""
        t = args[2] if len(args) > 2 else "Track"
        a = args[3] if len(args) > 3 else "Artist"
        thumb = args[4] if len(args) > 4 else ""
        qual = args[5] if len(args) > 5 else ""
        client_enqueue(vid, t, a, thumb, qual)
    elif cmd == "cancel":
        vid = args[1] if len(args) > 1 else ""
        client_cancel(vid)
    elif cmd in ("remove", "delete"):
        vid = args[1] if len(args) > 1 else ""
        client_remove(vid)
    elif cmd in ("clear", "clear_completed"):
        client_clear_completed()
    elif cmd == "status":
        get_status()
    elif cmd == "test_download":
        vid = args[1] if len(args) > 1 else "dQw4w9WgXcQ"
        mgr = get_in_proc_manager()
        mgr.enqueue(vid, "Test Track", "Test Artist")

def main():
    handle_cli(sys.argv[1:])

if __name__ == "__main__":
    main()
