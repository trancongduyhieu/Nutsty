#!/usr/bin/env python3
import json
import os
import subprocess
import sys
import threading
from http.server import HTTPServer, BaseHTTPRequestHandler
from urllib.parse import urlparse, parse_qs

# Add repo root to sys.path
REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
if REPO_ROOT not in sys.path:
    sys.path.insert(0, REPO_ROOT)

from backend.ytmusic_helper import search_ytmusic, resolve_stream_url, find_audio_disk_cache
from backend.lyrics_helper import get_lyrics

CACHE_DIR = "/tmp/swiftify_yt"
os.makedirs(CACHE_DIR, exist_ok=True)

def parse_duration_ms(d):
    if not d:
        return 0
    if isinstance(d, (int, float)):
        return int(d * 1000)
    if isinstance(d, str):
        parts = d.strip().split(":")
        try:
            if len(parts) == 3:
                return (int(parts[0]) * 3600 + int(parts[1]) * 60 + int(parts[2])) * 1000
            elif len(parts) == 2:
                return (int(parts[0]) * 60 + int(parts[1])) * 1000
            elif len(parts) == 1:
                return int(parts[0]) * 1000
        except ValueError:
            return 0
    return 0

def lines_to_lrc(lines):
    lrc = []
    for l in lines:
        t = l.get('time', 0.0)
        m = int(t // 60)
        s = t % 60
        text = l.get("text", "").strip()
        if text:
            lrc.append(f"[{m:02d}:{s:05.2f}]{text}")
    return "\n".join(lrc)

class BridgeHandler(BaseHTTPRequestHandler):
    def log_message(self, format, *args):
        pass

    def do_GET(self):
        parsed = urlparse(self.path)
        params = parse_qs(parsed.query)

        if parsed.path == "/search":
            query = params.get("q", [""])[0]
            if not query:
                self.send_json({"tracks": []})
                return
            
            try:
                results = search_ytmusic(query)
                tracks = []
                for item in results:
                    vid = item.get("id", "")
                    if vid.startswith("yt_"):
                        vid = vid[3:]
                    title = item.get("title", "") or item.get("name", "Unknown")
                    artist = item.get("artist", "Unknown")
                    album = item.get("album", "")
                    thumb = item.get("image", "") or item.get("thumbnail", "") or item.get("cover", "")
                    duration = item.get("durationMs", 0) or parse_duration_ms(item.get("duration", 0))
                    
                    tracks.append({
                        "id": vid,
                        "name": title,
                        "artists": [{"name": artist}],
                        "album": {
                            "name": album or title,
                            "images": [{"url": thumb}] if thumb else []
                        },
                        "duration_ms": duration,
                        "uri": f"yt:{vid}"
                    })
                self.send_json({"tracks": tracks})
            except Exception as e:
                self.send_error(500, str(e))

        elif parsed.path == "/resolve":
            vid = params.get("id", [""])[0]
            title = params.get("title", [""])[0]
            artist = params.get("artist", [""])[0]

            if vid.startswith("yt_"):
                vid = vid[3:]
            if not vid:
                self.send_error(400, "Missing id")
                return

            m4a_target = os.path.join(CACHE_DIR, f"{vid}.m4a")
            lrc_target = os.path.join(CACHE_DIR, f"{vid}.lrc")

            # Check if target audio exists
            if not os.path.exists(m4a_target):
                nutsty_cache = find_audio_disk_cache(vid)
                if nutsty_cache and os.path.exists(nutsty_cache):
                    if nutsty_cache.endswith(".m4a"):
                        m4a_target = nutsty_cache
                    else:
                        subprocess.run(
                            ["ffmpeg", "-y", "-i", nutsty_cache, "-c:a", "aac", "-b:a", "192k", m4a_target],
                            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
                        )
                else:
                    cmd = [
                        "yt-dlp",
                        "-f", "140/bestaudio[ext=m4a]/bestaudio",
                        "-o", m4a_target,
                        "--force-overwrites",
                        f"https://www.youtube.com/watch?v={vid}"
                    ]
                    subprocess.run(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

            # Resolve lyrics via Nutsty's lyrics_helper (LRCLIB, SimpMusic, NetEase, etc.)
            if not os.path.exists(lrc_target):
                try:
                    lines = get_lyrics(title=title, artist=artist, video_id=vid)
                    if lines:
                        lrc_text = lines_to_lrc(lines)
                        if lrc_text:
                            with open(lrc_target, "w", encoding="utf-8") as f:
                                f.write(lrc_text)
                except Exception as e:
                    pass

            self.send_json({"local_path": m4a_target})

        else:
            self.send_error(404, "Not Found")

    def send_json(self, data):
        body = json.dumps(data).encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()
        self.wfile.write(body)

def run_server(port=17895):
    server = HTTPServer(("127.0.0.1", port), BridgeHandler)
    server.serve_forever()

if __name__ == "__main__":
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 17895
    print(f"Starting Swiftify YouTube Bridge on 127.0.0.1:{port}...")
    run_server(port)
