#!/usr/bin/env python3
"""
Nutsty Library Scanner
Scans tracks from local folders and phone downloads into library.json
"""
import os
import sys
import json
import time
import subprocess
import glob
# ffprobe/ffmpeg are console programs: keep them from flashing a window on Windows
_NO_WINDOW = {"creationflags": 0x08000000} if sys.platform == "win32" else {}
HOME =os.path.expanduser("~")
SIMP_DIR = os.path.join(HOME, "Music", "SimpMusic", "Tracks")
LOCAL_DIR = os.path.join(HOME, "Music", "Nutsty", "Tracks") if os.path.exists(os.path.join(HOME, "Music", "Nutsty", "Tracks")) else SIMP_DIR
DOWNLOADS_DIR = os.path.join(HOME, "Music", "Downloads_Phone")
OUT_JSON = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "library.json")

def get_duration(file_path):
    try:
        cmd = [
            "ffprobe", "-v", "error", "-show_entries", "format=duration",
            "-of", "default=noprint_wrappers=1:nokey=1", file_path
        ]
        res = subprocess.run(cmd, capture_output=True, text=True, timeout=2, **_NO_WINDOW)
        val = float(res.stdout.strip())
        m = int(val // 60)
        s = int(val % 60)
        return f"{m}:{s:02d}", val
    except Exception:
        return "--:--", 0.0

import sqlite3
import hashlib

THUMB_DIR = os.path.join(HOME, ".cache", "nutsty", "thumbnails")
os.makedirs(THUMB_DIR, exist_ok=True)

def get_file_metadata(file_path):
    """Extract metadata (title, artist, duration) from audio file using ffprobe."""
    meta = {"title": "", "artist": "", "duration": "--:--", "duration_sec": 0.0}
    try:
        cmd = [
            "ffprobe", "-v", "quiet", "-print_format", "json",
            "-show_format", file_path
        ]
        res = subprocess.run(cmd, capture_output=True, text=True, timeout=2, **_NO_WINDOW)
        if res.returncode == 0 and res.stdout:
            data = json.loads(res.stdout).get("format", {})
            dur = float(data.get("duration", 0))
            if dur > 0:
                m = int(dur // 60)
                s = int(dur % 60)
                meta["duration"] = f"{m}:{s:02d}"
                meta["duration_sec"] = dur
            tags = data.get("tags", {})
            for k, v in tags.items():
                k_lower = k.lower()
                if k_lower == "title" and v and not meta["title"]:
                    meta["title"] = v.strip()
                elif k_lower in ("artist", "author", "album_artist") and v and not meta["artist"]:
                    meta["artist"] = v.strip()
                elif k_lower == "album" and v and not meta.get("album"):
                    meta["album"] = v.strip()
                elif k_lower in ("date", "year") and v and not meta.get("year"):
                    meta["year"] = v.strip()[:4]
    except Exception:
        pass
    return meta

def extract_embedded_cover(file_path):
    """Extract embedded album art from audio file using ffmpeg and cache it."""
    if not file_path or not os.path.exists(file_path):
        return ""
    
    # Check if a sibling image exists (e.g. song.jpg, song.png, cover.jpg)
    base_no_ext = os.path.splitext(file_path)[0]
    for ext in (".jpg", ".jpeg", ".png", ".webp"):
        sibling = base_no_ext + ext
        if os.path.exists(sibling) and os.path.getsize(sibling) > 1000:
            return sibling

    # Create deterministic hash path in ~/.cache/nutsty/thumbnails/
    f_hash = hashlib.md5(file_path.encode("utf-8")).hexdigest()
    out_thumb = os.path.join(THUMB_DIR, f"{f_hash}.jpg")

    if os.path.exists(out_thumb) and os.path.getsize(out_thumb) > 1000:
        return out_thumb

    try:
        cmd = ["ffmpeg", "-y", "-i", file_path, "-an", "-frames:v", "1", "-update", "1", out_thumb]
        res = subprocess.run(cmd, capture_output=True, timeout=3, **_NO_WINDOW)
        if res.returncode == 0 and os.path.exists(out_thumb) and os.path.getsize(out_thumb) > 1000:
            return out_thumb
    except Exception:
        pass

    return ""

def scan_library():
    tracks = []

    # Build mapping from Local Database
    p_db1 = os.path.join(HOME, "Music", "Nutsty", "extracted", "Music Database")
    p_db2 = os.path.join(HOME, "Music", "SimpMusic", "extracted", "Music Database")
    db_path = p_db1 if os.path.exists(p_db1) else p_db2
    title_artist_map = {}
    title_map = {}
    import re
    if os.path.exists(db_path):
        try:
            conn = sqlite3.connect(db_path)
            c = conn.cursor()
            rows = c.execute("SELECT title, artistName, videoId, thumbnails FROM song WHERE videoId IS NOT NULL").fetchall()
            for t_title, a_name, v_id, thumb_json in rows:
                if not t_title or not v_id:
                    continue
                t_clean = t_title.strip().lower()
                thumb_url = thumb_json if (thumb_json and ("googleusercontent.com" in thumb_json or "ggpht.com" in thumb_json)) else f"https://i.ytimg.com/vi/{v_id}/hqdefault.jpg"
                if "googleusercontent.com" in thumb_url or "ggpht.com" in thumb_url:
                    thumb_url = re.sub(r'=w\d+-h\d+.*', '=w1200-h1200-l90-rj', thumb_url)
                info = (thumb_url, v_id)
                artists = []
                if a_name:
                    try:
                        parsed_a = json.loads(a_name)
                        if isinstance(parsed_a, list):
                            artists = [str(x).strip().lower() for x in parsed_a]
                        else:
                            artists = [str(parsed_a).strip().lower()]
                    except Exception:
                        artists = [a_name.strip().lower()]
                for art in artists:
                    title_artist_map[(t_clean, art)] = info
                title_map[t_clean] = info
            conn.close()
        except Exception as e:
            print("DB read error:", e)

    def find_thumbnail(title_str, artist_str):
        lower_t = title_str.strip().lower()
        lower_a = artist_str.strip().lower()

        # 1. Exact title + artist match
        if (lower_t, lower_a) in title_artist_map:
            return title_artist_map[(lower_t, lower_a)]

        for sub_a in [x.strip() for x in re.split(r'[,&/]', lower_a)]:
            if (lower_t, sub_a) in title_artist_map:
                return title_artist_map[(lower_t, sub_a)]

        # 2. Match by artist + loose title
        for (m_title, m_art), val in title_artist_map.items():
            if m_art == lower_a or m_art in lower_a or lower_a in m_art:
                if m_title in lower_t or lower_t in m_title:
                    return val

        # 3. Cleaned title match (without brackets/extra notes)
        c_title = re.sub(r'[\(\[\{].*?[\)\]\}]', '', lower_t).strip()
        if c_title in title_map:
            return title_map[c_title]

        return ("", "")
    
    # 1. Scan Nutsty local library
    if os.path.exists(LOCAL_DIR):
        for f in sorted(os.listdir(LOCAL_DIR)):
            if f.endswith((".opus", ".m4a", ".mp3", ".webm", ".flac")):
                full_path = os.path.join(LOCAL_DIR, f)
                base = os.path.splitext(f)[0]
                if " - " in base:
                    artist, title = base.split(" - ", 1)
                else:
                    artist = "Unknown Artist"
                    title = base
                
                # Priority 1: Real embedded album art inside file
                thumb = extract_embedded_cover(full_path)
                # Priority 2: DB thumbnail match
                db_thumb, db_vid = find_thumbnail(title, artist)
                if not thumb:
                    thumb = db_thumb

                try:
                    mtime = int(os.path.getmtime(full_path))
                except Exception:
                    mtime = 0

                file_meta = get_file_metadata(full_path)
                dur = file_meta.get("duration", "--:--")

                tracks.append({
                    "id": len(tracks) + 1,
                    "title": title.strip(),
                    "name": title.strip(),
                    "artist": artist.strip(),
                    "source": "Nutsty",
                    "path": full_path,
                    "filename": f,
                    "duration": dur,
                    "image": thumb,
                    "videoId": db_vid,
                    "mtime": mtime
                })

    # 2. Scan Downloads_Phone
    if os.path.exists(DOWNLOADS_DIR):
        for f in sorted(os.listdir(DOWNLOADS_DIR)):
            if f.endswith((".mp3", ".m4a", ".opus", ".flac")):
                full_path = os.path.join(DOWNLOADS_DIR, f)
                base = os.path.splitext(f)[0]
                
                # Extract accurate ID3 / MP4 tags
                file_meta = get_file_metadata(full_path)
                title = file_meta.get("title", "")
                artist = file_meta.get("artist", "")

                if not title or not artist:
                    if " - " in base:
                        f_artist, f_title = base.split(" - ", 1)
                        if not artist: artist = f_artist.strip()
                        if not title: title = f_title.strip()
                    else:
                        if not title: title = base.strip()
                        if not artist: artist = "Downloaded"
                
                # Priority 1: Real embedded album art inside file
                thumb = extract_embedded_cover(full_path)
                # Priority 2: DB thumbnail match
                db_thumb, db_vid = find_thumbnail(title, artist)
                if not thumb:
                    thumb = db_thumb

                try:
                    mtime = int(os.path.getmtime(full_path))
                except Exception:
                    mtime = 0

                dur = file_meta.get("duration", "--:--")
                alb_name = file_meta.get("album", "") or ""
                yr_val = file_meta.get("year", "") or ""

                tracks.append({
                    "id": len(tracks) + 1,
                    "title": title.strip(),
                    "name": title.strip(),
                    "artist": artist.strip(),
                    "album": alb_name,
                    "year": yr_val,
                    "source": "Downloads",
                    "path": full_path,
                    "filename": f,
                    "duration": dur,
                    "image": thumb,
                    "videoId": db_vid,
                    "mtime": mtime
                })

    with open(OUT_JSON, "w", encoding="utf-8") as f:
        json.dump(tracks, f, ensure_ascii=False, indent=2)

    print(f"Scanned {len(tracks)} tracks into {OUT_JSON}")
    return tracks

def delete_track(path="", filename="", title=""):
    deleted_files = []

    # 1. Determine candidate file paths
    candidate_paths = []
    if path and not path.startswith("ytdl://"):
        candidate_paths.append(path)
    if filename:
        candidate_paths.append(os.path.join(SIMP_DIR, filename))
        candidate_paths.append(os.path.join(DOWNLOADS_DIR, filename))

    for cp in candidate_paths:
        if os.path.exists(cp):
            try:
                os.remove(cp)
                deleted_files.append(cp)
            except Exception as e:
                print(f"Error removing file {cp}: {e}", file=sys.stderr)

            # Also check and remove associated .lrc
            lrc_path = os.path.splitext(cp)[0] + ".lrc"
            if os.path.exists(lrc_path):
                try:
                    os.remove(lrc_path)
                    deleted_files.append(lrc_path)
                except Exception:
                    pass

    # 2. Update library.json atomically
    if os.path.exists(OUT_JSON):
        try:
            with open(OUT_JSON, "r", encoding="utf-8") as f:
                tracks = json.load(f)

            def should_remove(t):
                t_path = t.get("path", "")
                t_fn = t.get("filename", "")
                t_title = t.get("title", "") or t.get("name", "")
                if path and t_path == path:
                    return True
                if filename and (t_fn == filename or t_path.endswith(filename)):
                    return True
                if title and t_title and t_title.lower() == title.lower():
                    return True
                return False

            new_tracks = [t for t in tracks if not should_remove(t)]
            for i, t in enumerate(new_tracks):
                t["id"] = i + 1

            tmp_json = OUT_JSON + ".tmp"
            with open(tmp_json, "w", encoding="utf-8") as f:
                json.dump(new_tracks, f, ensure_ascii=False, indent=2)
            os.replace(tmp_json, OUT_JSON)

            print(json.dumps({
                "success": True,
                "deleted_files": deleted_files,
                "remaining_tracks": len(new_tracks)
            }))
            return True
        except Exception as e:
            print(json.dumps({"success": False, "error": str(e)}))
            return False
    else:
        print(json.dumps({"success": True, "deleted_files": deleted_files, "remaining_tracks": 0}))
        return True

def add_track(audio_path, title="", artist="", video_id="", image=""):
    """Instantly adds or updates a single downloaded track in library.json (0ms latency)."""
    if not audio_path or not os.path.exists(audio_path):
        return None

    dur_str, _ = get_duration(audio_path)
    meta = get_file_metadata(audio_path)
    final_title = title or meta.get("title") or os.path.splitext(os.path.basename(audio_path))[0]
    final_artist = artist or meta.get("artist") or "Unknown Artist"
    cover = image or extract_embedded_cover(audio_path)
    try:
        mtime = int(os.path.getmtime(audio_path))
    except Exception:
        mtime = int(time.time())

    tracks = []
    if os.path.exists(OUT_JSON):
        try:
            with open(OUT_JSON, "r", encoding="utf-8") as f:
                tracks = json.load(f)
        except Exception:
            tracks = []

    # If track exists, update metadata
    for t in tracks:
        if t.get("path") == audio_path or t.get("filename") == os.path.basename(audio_path):
            t["title"] = final_title
            t["name"] = final_title
            t["artist"] = final_artist
            t["duration"] = dur_str
            t["mtime"] = mtime
            if cover:
                t["image"] = cover
            if video_id:
                t["videoId"] = video_id
            tmp_json = OUT_JSON + ".tmp"
            with open(tmp_json, "w", encoding="utf-8") as f:
                json.dump(tracks, f, ensure_ascii=False, indent=2)
            os.replace(tmp_json, OUT_JSON)
            return t

    new_track = {
        "id": len(tracks) + 1,
        "title": final_title,
        "name": final_title,
        "artist": final_artist,
        "source": "Downloads",
        "path": audio_path,
        "filename": os.path.basename(audio_path),
        "duration": dur_str,
        "image": cover,
        "videoId": video_id or "",
        "mtime": mtime
    }
    tracks.insert(0, new_track)

    tmp_json = OUT_JSON + ".tmp"
    with open(tmp_json, "w", encoding="utf-8") as f:
        json.dump(tracks, f, ensure_ascii=False, indent=2)
    os.replace(tmp_json, OUT_JSON)
    print(f"Instantly indexed '{final_title}' into {OUT_JSON} (total {len(tracks)} tracks)")
    return new_track

def batch_delete_tracks(paths):
    deleted_files = []
    if not isinstance(paths, list):
        try:
            paths = json.loads(paths)
        except Exception:
            paths = [paths]

    paths_set = set(p for p in paths if p and not p.startswith("ytdl://"))
    for p in paths_set:
        if os.path.exists(p):
            try:
                os.remove(p)
                deleted_files.append(p)
            except Exception as e:
                print(f"Error removing {p}: {e}", file=sys.stderr)
        lrc_path = os.path.splitext(p)[0] + ".lrc"
        if os.path.exists(lrc_path):
            try:
                os.remove(lrc_path)
                deleted_files.append(lrc_path)
            except Exception:
                pass

    if os.path.exists(OUT_JSON):
        try:
            with open(OUT_JSON, "r", encoding="utf-8") as f:
                tracks = json.load(f)
            new_tracks = [t for t in tracks if t.get("path") not in paths_set]
            for i, t in enumerate(new_tracks):
                t["id"] = i + 1
            tmp_json = OUT_JSON + ".tmp"
            with open(tmp_json, "w", encoding="utf-8") as f:
                json.dump(new_tracks, f, ensure_ascii=False, indent=2)
            os.replace(tmp_json, OUT_JSON)
            print(json.dumps({
                "success": True,
                "deleted_count": len(deleted_files),
                "remaining_tracks": len(new_tracks)
            }))
            return True
        except Exception as e:
            print(json.dumps({"success": False, "error": str(e)}))
            return False
    return True

def get_grouped_albums():
    if not os.path.exists(OUT_JSON):
        scan_library()
    try:
        with open(OUT_JSON, "r", encoding="utf-8") as f:
            tracks = json.load(f)
    except Exception:
        tracks = []

    albums_map = {}
    for t in tracks:
        alb_name = (t.get("album") or "").strip()
        art_name = (t.get("artist") or "Downloaded").strip()
        if not alb_name:
            alb_name = f"{art_name} - Singles"
        
        key = alb_name
        if key not in albums_map:
            alb_id = f"local_alb_{hashlib.md5(key.encode('utf-8')).hexdigest()[:12]}"
            albums_map[key] = {
                "id": alb_id,
                "browseId": alb_id,
                "type": "album",
                "isLocal": True,
                "title": key,
                "name": key,
                "artist": art_name,
                "year": t.get("year", ""),
                "image": t.get("image", ""),
                "tracks": []
            }
        albums_map[key]["tracks"].append(t)
        if not albums_map[key]["image"] and t.get("image"):
            albums_map[key]["image"] = t.get("image")

    albums = []
    for k, v in albums_map.items():
        v["trackCount"] = len(v["tracks"])
        dur_secs = 0
        for trk in v["tracks"]:
            dur_str = trk.get("duration", "0:00")
            parts = dur_str.split(":")
            if len(parts) == 2 and parts[0].isdigit() and parts[1].isdigit():
                dur_secs += int(parts[0]) * 60 + int(parts[1])
        if dur_secs > 0:
            m = dur_secs // 60
            s = dur_secs % 60
            v["duration"] = f"{m} mins, {s} secs" if m > 0 else f"{s} secs"
        else:
            v["duration"] = f"{len(v['tracks'])} songs"
        albums.append(v)

    albums.sort(key=lambda a: a["title"].lower())
    return albums

def main():
    if len(sys.argv) > 1 and sys.argv[1] == "delete":
        p = sys.argv[2] if len(sys.argv) > 2 else ""
        fn = sys.argv[3] if len(sys.argv) > 3 else ""
        t = sys.argv[4] if len(sys.argv) > 4 else ""
        delete_track(p, fn, t)
    elif len(sys.argv) > 1 and sys.argv[1] == "add" and len(sys.argv) > 2:
        audio_path = sys.argv[2]
        title = sys.argv[3] if len(sys.argv) > 3 else ""
        artist = sys.argv[4] if len(sys.argv) > 4 else ""
        vid = sys.argv[5] if len(sys.argv) > 5 else ""
        img = sys.argv[6] if len(sys.argv) > 6 else ""
        add_track(audio_path, title, artist, vid, img)
    elif len(sys.argv) > 1 and sys.argv[1] == "batch_delete" and len(sys.argv) > 2:
        batch_delete_tracks(sys.argv[2])
    elif len(sys.argv) > 1 and sys.argv[1] == "albums":
        print(json.dumps(get_grouped_albums(), ensure_ascii=False))
    else:
        scan_library()

if __name__ == "__main__":
    main()
