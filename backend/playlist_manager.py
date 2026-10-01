#!/usr/bin/env python3
"""
Nutsty Custom Playlist Manager
Manages user custom playlists saved in ~/.config/noctalia/custom_playlists.json
"""
import os
import sys
import json
import time

try:
    from . import platform_compat as pc
except (ImportError, ValueError):
    import platform_compat as pc

PROFILE_NAME = os.getenv("NUTSTY_PROFILE", "").strip().lower()
PROFILE_SUFFIX = f"_{PROFILE_NAME}" if PROFILE_NAME else ""

CONFIG_DIR = pc.get_config_dir()
PLAYLISTS_FILE = os.path.join(CONFIG_DIR, f"custom_playlists{PROFILE_SUFFIX}.json")
FAVORITE_PLAYLISTS_FILE = os.path.join(CONFIG_DIR, f"favorite_playlists{PROFILE_SUFFIX}.json")

def load_playlists():
    p = PLAYLISTS_FILE
    if not os.path.exists(p) and not PROFILE_SUFFIX:
        p = os.path.join(CONFIG_DIR, "custom_playlists.json")
    if not os.path.exists(p):
        return []
    try:
        with open(p, "r", encoding="utf-8") as f:
            data = json.load(f)
            if not isinstance(data, list):
                return []
            needs_save = False
            for item in data:
                if isinstance(item, dict):
                    if not item.get("isCustom"):
                        item["isCustom"] = True
                        needs_save = True
                    if not item.get("isLocal"):
                        item["isLocal"] = True
                        needs_save = True
                    if not item.get("type"):
                        item["type"] = "custom"
                        needs_save = True
                    if not item.get("id") and item.get("playlistId"):
                        item["id"] = item["playlistId"]
                        needs_save = True
                    if not item.get("playlistId") and item.get("id"):
                        item["playlistId"] = item["id"]
                        needs_save = True
                    if not item.get("name") and item.get("title"):
                        item["name"] = item["title"]
                    if not item.get("title") and item.get("name"):
                        item["title"] = item["name"]
                    if not item.get("customCover") and item.get("image"):
                        item["customCover"] = item["image"]
            if needs_save:
                save_playlists(data)
            return data
    except Exception:
        return []

def save_playlists(playlists):
    os.makedirs(CONFIG_DIR, exist_ok=True)
    tmp = PLAYLISTS_FILE + ".tmp"
    try:
        with open(tmp, "w", encoding="utf-8") as f:
            json.dump(playlists, f, ensure_ascii=False, indent=2)
        os.replace(tmp, PLAYLISTS_FILE)
        return True
    except Exception as e:
        sys.stderr.write(f"Error saving custom playlists: {e}\n")
        return False

def get_track_unique_key(track):
    if not track:
        return ""
    if isinstance(track, str):
        if track.startswith("ytdl://"):
            return f"yt_{track.replace('ytdl://', '')}"
        return f"local_{track}"
    if isinstance(track, dict):
        if track.get("videoId"):
            return f"yt_{track['videoId']}"
        if track.get("path"):
            p = track["path"]
            if p.startswith("ytdl://"):
                return f"yt_{p.replace('ytdl://', '')}"
            return f"local_{p}"
        if track.get("id"):
            return f"id_{track['id']}"
        return track.get("title", "")
    return str(track)

def create_playlist(title, initial_tracks=None, description="", custom_cover=""):
    if not title or not title.strip():
        title = "New Playlist"
    playlists = load_playlists()
    pl_id = f"custom_pl_{int(time.time() * 1000)}"
    tracks = []
    if initial_tracks:
        if isinstance(initial_tracks, str):
            try:
                tracks = json.loads(initial_tracks)
            except Exception:
                tracks = []
        elif isinstance(initial_tracks, list):
            tracks = initial_tracks

    new_pl = {
        "id": pl_id,
        "playlistId": pl_id,
        "title": title.strip(),
        "name": title.strip(),
        "description": description.strip() if description else "",
        "customCover": custom_cover.strip() if custom_cover else "",
        "isLocal": True,
        "isCustom": True,
        "createdAt": int(time.time()),
        "tracks": tracks,
        "trackCount": len(tracks),
        "image": custom_cover if custom_cover else (tracks[0].get("image", "") if tracks else "")
    }
    playlists.append(new_pl)
    save_playlists(playlists)
    return new_pl

def rename_playlist(pl_id, new_title, new_description=None):
    playlists = load_playlists()
    target = None
    for p in playlists:
        if p.get("id") == pl_id:
            target = p
            break
    if not target:
        return {"success": False, "error": "Playlist not found"}

    if new_title and new_title.strip():
        target["title"] = new_title.strip()
        target["name"] = new_title.strip()
    if new_description is not None:
        target["description"] = new_description.strip()
    save_playlists(playlists)
    return {"success": True, "playlist": target}

def set_playlist_cover(pl_id, image_path):
    playlists = load_playlists()
    target = None
    for p in playlists:
        if p.get("id") == pl_id:
            target = p
            break
    if not target:
        return {"success": False, "error": "Playlist not found"}

    target["customCover"] = image_path.strip() if image_path else ""
    target["image"] = target["customCover"] or (target["tracks"][0].get("image", "") if target.get("tracks") else "")
    save_playlists(playlists)
    return {"success": True, "playlist": target}

def reorder_tracks(pl_id, from_index, to_index):
    playlists = load_playlists()
    target = None
    for p in playlists:
        if p.get("id") == pl_id:
            target = p
            break
    if not target:
        return {"success": False, "error": "Playlist not found"}

    tracks = target.get("tracks", [])
    if 0 <= from_index < len(tracks) and 0 <= to_index < len(tracks):
        item = tracks.pop(from_index)
        tracks.insert(to_index, item)
        target["tracks"] = tracks
        if not target.get("customCover") and tracks:
            target["image"] = tracks[0].get("image", "")
        save_playlists(playlists)
        return {"success": True, "playlist": target}
    return {"success": False, "error": "Invalid indices"}

def delete_playlist(pl_id):
    playlists = load_playlists()
    filtered = [p for p in playlists if p.get("id") != pl_id]
    save_playlists(filtered)
    # Also clean up from favorite playlists if present
    try:
        favs = load_favorite_playlists()
        filtered_favs = [p for p in favs if str(p.get("id") or p.get("playlistId") or p.get("browseId") or "") != str(pl_id)]
        if len(filtered_favs) != len(favs):
            save_favorite_playlists(filtered_favs)
    except Exception as e:
        sys.stderr.write(f"Error updating favorite playlists on delete: {e}\n")
    return {"success": True, "remaining": len(filtered)}

def add_tracks_to_playlist(pl_id, new_tracks):
    playlists = load_playlists()
    target = None
    for p in playlists:
        if p.get("id") == pl_id:
            target = p
            break
    if not target:
        return {"success": False, "error": "Playlist not found"}

    if isinstance(new_tracks, str):
        try:
            new_tracks = json.loads(new_tracks)
        except Exception:
            new_tracks = []

    existing_keys = set(get_track_unique_key(t) for t in target.get("tracks", []) if get_track_unique_key(t))
    added = 0
    for t in new_tracks:
        k = get_track_unique_key(t)
        if k and k not in existing_keys:
            target["tracks"].append(t)
            existing_keys.add(k)
            added += 1

    target["trackCount"] = len(target["tracks"])
    if not target.get("customCover") and not target.get("image") and target["tracks"]:
        target["image"] = target["tracks"][0].get("image", "")

    save_playlists(playlists)
    return {"success": True, "added": added, "total": len(target["tracks"])}

def remove_track_from_playlist(pl_id, track_identifier):
    playlists = load_playlists()
    target = None
    for p in playlists:
        if p.get("id") == pl_id:
            target = p
            break
    if not target:
        return {"success": False, "error": "Playlist not found"}

    target_key = get_track_unique_key(track_identifier)
    target_str = str(track_identifier) if not isinstance(track_identifier, dict) else ""

    target["tracks"] = [
        t for t in target.get("tracks", [])
        if get_track_unique_key(t) != target_key
        and (not target_str or (t.get("path") != target_str and t.get("videoId") != target_str))
    ]
    target["trackCount"] = len(target["tracks"])
    if not target.get("customCover"):
        target["image"] = target["tracks"][0].get("image", "") if target["tracks"] else ""
    save_playlists(playlists)
    return {"success": True, "total": len(target["tracks"])}

def load_favorite_playlists():
    p = FAVORITE_PLAYLISTS_FILE
    if not os.path.exists(p) and not PROFILE_SUFFIX:
        p = os.path.join(CONFIG_DIR, "favorite_playlists.json")
    if not os.path.exists(p):
        return []
    try:
        with open(p, "r", encoding="utf-8") as f:
            data = json.load(f)
            return data if isinstance(data, list) else []
    except Exception:
        return []

def save_favorite_playlists(favs):
    os.makedirs(CONFIG_DIR, exist_ok=True)
    tmp = FAVORITE_PLAYLISTS_FILE + ".tmp"
    try:
        with open(tmp, "w", encoding="utf-8") as f:
            json.dump(favs, f, ensure_ascii=False, indent=2)
        os.replace(tmp, FAVORITE_PLAYLISTS_FILE)
        return True
    except Exception as e:
        sys.stderr.write(f"Error saving favorite playlists: {e}\n")
        return False

def toggle_favorite_playlist(pl_data):
    if not pl_data:
        return {"success": False, "error": "No playlist data"}
    if isinstance(pl_data, str):
        try:
            pl_data = json.loads(pl_data)
        except Exception:
            return {"success": False, "error": "Invalid JSON"}
    if not isinstance(pl_data, dict):
        return {"success": False, "error": "Invalid playlist format"}

    pl_id = str(pl_data.get("id") or pl_data.get("playlistId") or pl_data.get("browseId") or "")
    if not pl_id:
        return {"success": False, "error": "No playlist ID"}

    favs = load_favorite_playlists()
    existing_idx = -1
    for idx, item in enumerate(favs):
        curr_id = str(item.get("id") or item.get("playlistId") or item.get("browseId") or "")
        if curr_id == pl_id:
            existing_idx = idx
            break

    if existing_idx >= 0:
        favs.pop(existing_idx)
        save_favorite_playlists(favs)
        return {"success": True, "isFavorite": False, "playlistId": pl_id, "favorites": favs}
    else:
        title = pl_data.get("title") or pl_data.get("name") or "Playlist"
        subtitle = pl_data.get("subtitle") or pl_data.get("artist") or pl_data.get("author") or ""
        img = pl_data.get("image") or pl_data.get("thumbnail") or ""
        if not img and isinstance(pl_data.get("thumbnails"), list) and pl_data["thumbnails"]:
            img = pl_data["thumbnails"][-1].get("url", "")

        normalized = {
            "id": pl_id,
            "playlistId": pl_id,
            "browseId": pl_id,
            "title": title,
            "name": title,
            "subtitle": subtitle,
            "artist": pl_data.get("artist") or subtitle,
            "image": img,
            "thumbnail": img,
            "type": pl_data.get("type", "playlist"),
            "trackCount": pl_data.get("trackCount") or pl_data.get("itemCount") or len(pl_data.get("tracks", [])),
            "addedAt": int(time.time()),
            "tracks": pl_data.get("tracks", [])
        }
        favs.insert(0, normalized)
        save_favorite_playlists(favs)
        return {"success": True, "isFavorite": True, "playlistId": pl_id, "favorites": favs}

def remove_favorite_playlist(pl_id):
    if not pl_id:
        return {"success": False}
    favs = load_favorite_playlists()
    filtered = [
        p for p in favs
        if str(p.get("id") or p.get("playlistId") or p.get("browseId") or "") != str(pl_id)
    ]
    save_favorite_playlists(filtered)
    return {"success": True, "favorites": filtered}

def handle_cli(args=None):
    if args is None:
        args = sys.argv[1:] if len(sys.argv) > 1 else []
    cmd = args[0] if len(args) > 0 else "list"

    if cmd == "list":
        print(json.dumps(load_playlists(), ensure_ascii=False))
    elif cmd == "list_favorites":
        print(json.dumps(load_favorite_playlists(), ensure_ascii=False))
    elif cmd == "toggle_favorite" and len(args) > 1:
        print(json.dumps(toggle_favorite_playlist(args[1]), ensure_ascii=False))
    elif cmd == "remove_favorite" and len(args) > 1:
        print(json.dumps(remove_favorite_playlist(args[1]), ensure_ascii=False))
    elif cmd == "create" and len(args) > 1:
        title = args[1]
        trks = args[2] if len(args) > 2 else None
        desc = args[3] if len(args) > 3 else ""
        cover = args[4] if len(args) > 4 else ""
        print(json.dumps(create_playlist(title, trks, desc, cover), ensure_ascii=False))
    elif cmd == "rename" and len(args) > 2:
        pl_id = args[1]
        new_title = args[2]
        desc = args[3] if len(args) > 3 else None
        print(json.dumps(rename_playlist(pl_id, new_title, desc), ensure_ascii=False))
    elif cmd == "set_cover" and len(args) > 2:
        pl_id = args[1]
        cover_path = args[2]
        print(json.dumps(set_playlist_cover(pl_id, cover_path), ensure_ascii=False))
    elif cmd == "reorder" and len(args) > 3:
        pl_id = args[1]
        f_idx = int(args[2])
        t_idx = int(args[3])
        print(json.dumps(reorder_tracks(pl_id, f_idx, t_idx), ensure_ascii=False))
    elif cmd == "delete" and len(args) > 1:
        print(json.dumps(delete_playlist(args[1]), ensure_ascii=False))
    elif cmd == "add" and len(args) > 2:
        print(json.dumps(add_tracks_to_playlist(args[1], args[2]), ensure_ascii=False))
    elif cmd == "remove" and len(args) > 2:
        print(json.dumps(remove_track_from_playlist(args[1], args[2]), ensure_ascii=False))
    else:
        print(json.dumps(load_playlists(), ensure_ascii=False))

def main():
    handle_cli(sys.argv[1:] if len(sys.argv) > 1 else [])

if __name__ == "__main__":
    main()

