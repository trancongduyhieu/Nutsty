#!/usr/bin/env python3
"""
Nutsty Song Metadata Enrichment & Artwork Engine
Handles detailed song credits, engagement statistics, related content,
Apple Music animated cover artwork extraction, and square cover resolution.
"""
import sys
import os
import json
import time
import re
import urllib.request

try:
    from . import platform_compat as pc
    from .ytmusic_auth import (
        PROFILE_NAME, PROFILE_SUFFIX, AUTH_FILE,
        load_json, save_json,
        create_resilient_session,
        get_ytmusic_client
    )
    from .catalog_engine import (
        clean_artist_name, clean_thumbnail_url, normalize_track,
        load_disliked_songs, save_disliked_songs, add_disliked_song,
        remove_disliked_song, is_song_disliked,
        load_artist_avatars, save_artist_avatars, cache_artist_avatar,
        get_cached_artist_avatar, DISLIKED_SONGS_FILE, ARTIST_AVATARS_FILE
    )
    from .stream_resolver import resolve_video_id_for_track
    from . import lyrics_helper
except (ImportError, ValueError):
    import platform_compat as pc
    from ytmusic_auth import (
        PROFILE_NAME, PROFILE_SUFFIX, AUTH_FILE,
        load_json, save_json,
        create_resilient_session,
        get_ytmusic_client
    )
    from catalog_engine import (
        clean_artist_name, clean_thumbnail_url, normalize_track,
        load_disliked_songs, save_disliked_songs, add_disliked_song,
        remove_disliked_song, is_song_disliked,
        load_artist_avatars, save_artist_avatars, cache_artist_avatar,
        get_cached_artist_avatar, DISLIKED_SONGS_FILE, ARTIST_AVATARS_FILE
    )
    from stream_resolver import resolve_video_id_for_track
    import lyrics_helper

SQUARE_COVERS_CACHE_FILE = os.path.join(pc.get_cache_dir(), "square_covers.json")

def get_song_details(video_id):
    """
    Fetch comprehensive song metadata and engagement statistics:
    - Title, Artist, Author, Subscribers, AuthorThumbnail
    - Album (real album name, or 'Single'), AlbumBrowseId
    - DateText, PublishDate, Description
    - View count, Like count, Dislike count, Like status
    """
    if not video_id:
        return {}

    clean_vid = str(video_id).strip().replace("ytdl://", "").replace("yt_", "")
    if len(clean_vid) != 11 or " " in clean_vid or "/" in clean_vid or "." in clean_vid:
        try:
            ytm = get_ytmusic_client()
            search_res = ytm.search(clean_vid, filter="songs", limit=1)
            if not search_res:
                search_res = ytm.search(clean_vid, filter="videos", limit=1)
            if search_res and search_res[0].get("videoId"):
                clean_vid = search_res[0]["videoId"]
            else:
                return {}
        except Exception as e:
            sys.stderr.write(f"[resolve videoId error for '{clean_vid}']: {e}\n")
            return {}

    details = {
        "videoId": clean_vid,
        "title": "",
        "artist": "",
        "author": "",
        "subscribers": "",
        "authorThumbnail": "",
        "dateText": "",
        "publishDate": "",
        "year": "",
        "description": "",
        "album": "Single",
        "albumBrowseId": "",
        "views": 0,
        "viewsStr": "--",
        "likes": 0,
        "likesStr": "--",
        "dislikes": 0,
        "dislikesStr": "--",
        "rating": 5.0,
        "likeRatio": 100.0,
        "likeStatus": "INDIFFERENT"
    }

    # 1. Fetch YouTube Innertube next endpoint for Author, Subscribers, Thumbnail, Date, and Description
    try:
        req = urllib.request.Request(
            "https://www.youtube.com/youtubei/v1/next?prettyPrint=false",
            data=json.dumps({
                "context": {"client": {"clientName": "WEB", "clientVersion": "2.20230515.01.00"}},
                "videoId": clean_vid
            }).encode(),
            headers={"Content-Type": "application/json", "User-Agent": "Mozilla/5.0"}
        )
        with urllib.request.urlopen(req, timeout=3.0) as resp:
            next_data = json.loads(resp.read().decode())

        contents = next_data.get("contents", {}).get("twoColumnWatchNextResults", {}).get("results", {}).get("results", {}).get("contents", [])
        for c in contents:
            if "videoSecondaryInfoRenderer" in c:
                sec = c["videoSecondaryInfoRenderer"]
                owner = sec.get("owner", {}).get("videoOwnerRenderer", {})
                author = owner.get("title", {}).get("runs", [{}])[0].get("text", "")
                details["author"] = re.sub(r' - Topic| - Chủ đề', '', author).strip()
                details["artist"] = details["author"]
                details["subscribers"] = owner.get("subscriberCountText", {}).get("simpleText", "")
                thumbs = owner.get("thumbnail", {}).get("thumbnails", [])
                if thumbs:
                    details["authorThumbnail"] = thumbs[-1].get("url", "").replace("s48", "s960").replace("s88", "s960")
                    if details.get("artist"):
                        cache_artist_avatar(details["artist"], details["authorThumbnail"])
                details["description"] = sec.get("attributedDescription", {}).get("content", "")
            if "videoPrimaryInfoRenderer" in c:
                prim = c["videoPrimaryInfoRenderer"]
                details["dateText"] = prim.get("dateText", {}).get("simpleText", "")
                details["publishDate"] = details["dateText"]
                t_runs = prim.get("title", {}).get("runs", [])
                if t_runs:
                    details["title"] = t_runs[0].get("text", "")
    except Exception as e:
        sys.stderr.write(f"[Innertube next error for {clean_vid}]: {e}\n")

    # 2. Fetch watch playlist for Album info and Like status
    try:
        ytm = get_ytmusic_client()
        wp = ytm.get_watch_playlist(clean_vid, limit=1)
        if wp and "tracks" in wp and len(wp["tracks"]) > 0:
            tr0 = wp["tracks"][0]
            alb = tr0.get("album")
            if isinstance(alb, dict) and alb.get("name"):
                details["album"] = alb["name"]
                details["albumBrowseId"] = alb.get("id", "")
            elif isinstance(alb, str) and alb.strip():
                details["album"] = alb.strip()

            ls = tr0.get("likeStatus")
            if ls in ("LIKE", "DISLIKE", "INDIFFERENT"):
                details["likeStatus"] = ls

            if not details["title"]:
                details["title"] = tr0.get("title", "")
            if not details["artist"]:
                artists = tr0.get("artists", [])
                details["artist"] = ", ".join(a.get("name", "") for a in artists if a.get("name")) or details.get("author", "")
    except Exception as e:
        sys.stderr.write(f"[watch_playlist error for {clean_vid}]: {e}\n")

    # 3. Fetch YouTube Dislike & Engagement stats via Return YouTube Dislike API
    try:
        ryd_url = f"https://returnyoutubedislikeapi.com/votes?videoId={clean_vid}"
        req = urllib.request.Request(ryd_url, headers={"User-Agent": "Mozilla/5.0"})
        with urllib.request.urlopen(req, timeout=2.5) as resp:
            ryd_data = json.loads(resp.read().decode("utf-8"))
            likes = ryd_data.get("likes", 0)
            dislikes = ryd_data.get("dislikes", 0)
            rating = ryd_data.get("rating", 5.0)
            view_count = ryd_data.get("viewCount", 0)

            details["likes"] = likes
            details["dislikes"] = dislikes
            details["rating"] = round(rating, 2)
            if view_count:
                details["views"] = view_count
                if view_count >= 1000000:
                    details["viewsStr"] = f"{view_count / 1000000:.1f}M"
                elif view_count >= 1000:
                    details["viewsStr"] = f"{view_count / 1000:.1f}K"
                else:
                    details["viewsStr"] = f"{view_count:,}"

            if likes >= 1000000:
                details["likesStr"] = f"{likes / 1000000:.1f}M"
            elif likes >= 1000:
                details["likesStr"] = f"{likes / 1000:.1f}K"
            else:
                details["likesStr"] = str(likes)

            if dislikes >= 1000000:
                details["dislikesStr"] = f"{dislikes / 1000000:.1f}M"
            elif dislikes >= 1000:
                details["dislikesStr"] = f"{dislikes / 1000:.1f}K"
            else:
                details["dislikesStr"] = str(dislikes)

            total_votes = likes + dislikes
            if total_votes > 0:
                details["likeRatio"] = round((likes / total_votes) * 100.0, 1)
            else:
                details["likeRatio"] = 100.0
    except Exception as e:
        sys.stderr.write(f"[RYD API error for {clean_vid}]: {e}\n")

    # 4. Fallback check for empty fields via get_song
    if not details["description"] or not details["publishDate"]:
        try:
            ytm = get_ytmusic_client()
            song = ytm.get_song(clean_vid)
            v_details = song.get("videoDetails", {})
            if not details["title"]:
                details["title"] = v_details.get("title", "")
            if not details["artist"]:
                details["artist"] = v_details.get("author", "")
            if not details["author"]:
                details["author"] = v_details.get("author", "")

            mf = song.get("microformat", {}).get("microformatDataRenderer", {})
            pub_date = mf.get("publishDate", "") or mf.get("uploadDate", "")
            if pub_date and not details["publishDate"]:
                details["publishDate"] = pub_date[:10]
                details["dateText"] = pub_date[:10]
            if pub_date and not details["year"]:
                details["year"] = pub_date[:4]

            if not details["description"]:
                desc = ""
                if "description" in mf:
                    d_val = mf["description"]
                    desc = d_val.get("simpleText", "") if isinstance(d_val, dict) else str(d_val)
                if not desc and "shortDescription" in v_details:
                    desc = v_details["shortDescription"]
                if desc:
                    details["description"] = desc
        except Exception:
            pass

    # Ensure album is never empty or weird
    if not details["album"] or details["album"].lower() in ("single / simpmusic", "single / nutsty"):
        details["album"] = "Single"

    # Enforce blacklist check on likeStatus
    if is_song_disliked(clean_vid):
        details["likeStatus"] = "DISLIKE"

    return details

def rate_song_action(video_id, rating):
    clean_vid = str(video_id).strip().replace("ytdl://", "").replace("yt_", "")
    upper_rating = str(rating).upper().strip()
    if upper_rating not in ("LIKE", "DISLIKE", "INDIFFERENT"):
        upper_rating = "INDIFFERENT"

    if upper_rating == "DISLIKE":
        add_disliked_song(clean_vid)
    elif upper_rating in ("LIKE", "INDIFFERENT"):
        remove_disliked_song(clean_vid)

    res = {"success": True, "videoId": clean_vid, "rating": upper_rating}
    try:
        ytm = get_ytmusic_client()
        ytm.rate_song(clean_vid, upper_rating)
    except Exception as e:
        sys.stderr.write(f"[rate_song error for {clean_vid}]: {e}\n")
        res["ytm_error"] = str(e)
RELATED_CACHE_DIR = os.path.join(pc.get_cache_dir(), "related")

def get_song_related_content(video_id, title="", artist=""):
    clean_vid = resolve_video_id_for_track(video_id, title, artist)
    if not clean_vid:
        return {"you_might_also_like": [], "recommended_playlists": [], "similar_artists": []}

    os.makedirs(RELATED_CACHE_DIR, exist_ok=True)
    cache_path = os.path.join(RELATED_CACHE_DIR, f"{clean_vid}.json")
    if os.path.exists(cache_path):
        cached = load_json(cache_path)
        if cached and (time.time() - cached.get("timestamp", 0) < 86400):
            return cached

    clients = [get_ytmusic_client()]
    try:
        from ytmusicapi import YTMusic
        clients.append(YTMusic(requests_session=create_resilient_session()))
    except Exception:
        pass

    for yt in clients:
        try:
            wp = yt.get_watch_playlist(clean_vid, limit=1)
            rel_id = wp.get("related")
            if not rel_id:
                continue

            rel_sections = yt.get_song_related(rel_id)
            you_might_like = []
            rec_playlists = []
            similar_artists = []

            for sec in rel_sections:
                sec_title = sec.get("title", "")
                contents = sec.get("contents", [])
                if "You might also like" in sec_title or "bạn có thể thích" in sec_title.lower():
                    for item in contents:
                        norm = normalize_track(item)
                        if norm:
                            you_might_like.append(norm)
                elif "Recommended playlists" in sec_title or "danh sách phát" in sec_title.lower():
                    for item in contents:
                        p_id = item.get("playlistId", "")
                        p_title = item.get("title", "")
                        thumbs = item.get("thumbnails", [])
                        img = thumbs[-1].get("url", "") if thumbs else ""
                        desc = item.get("description", "")
                        if p_id and p_title:
                            rec_playlists.append({
                                "playlistId": p_id,
                                "id": p_id,
                                "title": p_title,
                                "image": img,
                                "description": desc,
                                "isOnline": True
                            })
                elif "Similar artists" in sec_title or "nghệ sĩ tương tự" in sec_title.lower():
                    for item in contents:
                        a_name = item.get("title", "")
                        a_id = item.get("browseId", "")
                        thumbs = item.get("thumbnails", [])
                        img = thumbs[-1].get("url", "") if thumbs else ""
                        subs = item.get("subscribers", "")
                        if a_name:
                            similar_artists.append({
                                "name": a_name,
                                "channelId": a_id,
                                "image": img,
                                "subscribers": subs
                            })

            res = {
                "timestamp": time.time(),
                "videoId": clean_vid,
                "you_might_also_like": you_might_like[:16],
                "recommended_playlists": rec_playlists[:12],
                "similar_artists": similar_artists[:12]
            }
            save_json(cache_path, res)
            return res
        except Exception as e:
            sys.stderr.write(f"[get_song_related error for {clean_vid}]: {e}\n")
            continue

    return {"you_might_also_like": [], "recommended_playlists": [], "similar_artists": []}

def get_youtube_lyrics(video_id):
    """Fallback: Fetch plain lyrics directly from YouTube Music InnerTube API."""
    if not video_id:
        return None
    if video_id.startswith("ytdl://"):
        video_id = video_id.replace("ytdl://", "")

    clients = [get_ytmusic_client()]
    try:
        from ytmusicapi import YTMusic
        clients.append(YTMusic(requests_session=create_resilient_session()))
    except Exception:
        pass

    for yt in clients:
        try:
            wp = yt.get_watch_playlist(video_id, limit=1)
            lyrics_id = wp.get("lyrics")
            if lyrics_id:
                lyr_data = yt.get_lyrics(lyrics_id)
                lyrics_text = lyr_data.get("lyrics", "")
                if lyrics_text and lyrics_text.strip():
                    return lyrics_text.strip()
        except Exception:
            continue
    return None
# ==============================================================================
# APPLE MUSIC ANIMATED ALBUM ARTWORK EXTRACTION (Item 25)
# ==============================================================================
AM_TOKEN_CACHE_FILE = os.path.join(pc.get_cache_dir(), "am_token.json")
ANIMATED_ARTWORK_CACHE_FILE = os.path.join(pc.get_cache_dir(), "animated_artworks.json")

def get_am_token():
    """Scrapes the public web-player bearer token (JWT) from music.apple.com."""
    import base64
    if os.path.exists(AM_TOKEN_CACHE_FILE):
        try:
            with open(AM_TOKEN_CACHE_FILE, "r", encoding="utf-8") as f:
                d = json.load(f)
                if time.time() - d.get("time", 0) < 43200:  # 12 hours
                    return d.get("token")
        except Exception:
            pass

    try:
        ssl_ctx = pc.get_ssl_context()
        req = urllib.request.Request("https://music.apple.com", headers={"User-Agent": "Mozilla/5.0 (X11; Linux x86_64)"})
        html = urllib.request.urlopen(req, timeout=8, context=ssl_ctx).read().decode("utf-8", errors="ignore")
        m = re.search(r"/assets/index~[^/\"]+\.js", html)
        if not m:
            return None
        js_url = "https://music.apple.com" + m.group(0)
        js_req = urllib.request.Request(js_url, headers={"User-Agent": "Mozilla/5.0 (X11; Linux x86_64)"})
        js = urllib.request.urlopen(js_req, timeout=12, context=ssl_ctx).read().decode("utf-8", errors="ignore")
        jwts = re.findall(r"eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+", js)
        token = None
        for j in jwts:
            try:
                p = j.split(".")[1]
                pad = len(p) % 4
                pay = base64.urlsafe_b64decode(p + "=" * (4 - pad if pad else 0)).decode("utf-8", errors="ignore")
                if "AMPWebPlay" in pay:
                    token = j
                    break
            except Exception:
                pass
        if not token and jwts:
            token = jwts[0]

        if token:
            os.makedirs(os.path.dirname(AM_TOKEN_CACHE_FILE), exist_ok=True)
            with open(AM_TOKEN_CACHE_FILE, "w", encoding="utf-8") as f:
                json.dump({"token": token, "time": time.time()}, f)
        return token
    except Exception as e:
        sys.stderr.write(f"[Apple Music Token Scrape Error]: {e}\n")
        return None

def select_am_rendition(master_url):
    """
    Parses HLS master playlist from Apple Music and selects optimal avc1 video rendition:
    codec is decided before quality (avc1 over 10-bit HEVC), picking ~768x768 or resolution >= 720px.
    """
    if not master_url:
        return ""
    try:
        import urllib.parse
        req = urllib.request.Request(master_url, headers={"User-Agent": "Mozilla/5.0"})
        content = urllib.request.urlopen(req, timeout=6).read().decode("utf-8", errors="ignore")
        lines = content.splitlines()

        variants = []
        cur_inf = None
        for line in lines:
            line = line.strip()
            if line.startswith("#EXT-X-STREAM-INF:"):
                cur_inf = line
            elif line and not line.startswith("#") and cur_inf:
                codec_m = re.search(r'CODECS="([^"]+)"', cur_inf)
                res_m = re.search(r'RESOLUTION=(\d+)x(\d+)', cur_inf)
                bw_m = re.search(r'BANDWIDTH=(\d+)', cur_inf)
                codec = codec_m.group(1) if codec_m else ""
                w = int(res_m.group(1)) if res_m else 0
                h = int(res_m.group(2)) if res_m else 0
                bw = int(bw_m.group(1)) if bw_m else 0

                v_url = line if line.startswith("http") else urllib.parse.urljoin(master_url, line)
                variants.append({
                    "url": v_url,
                    "codec": codec,
                    "width": w,
                    "height": h,
                    "bandwidth": bw
                })
                cur_inf = None

        avc1_variants = [v for v in variants if "avc1" in v["codec"].lower()]
        if not avc1_variants:
            avc1_variants = variants

        suitable = [v for v in avc1_variants if v["width"] >= 720]
        if suitable:
            suitable.sort(key=lambda x: (x["width"], x["bandwidth"]))
            return suitable[0]["url"]
        elif avc1_variants:
            avc1_variants.sort(key=lambda x: -x["width"])
            return avc1_variants[0]["url"]

        return master_url
    except Exception as e:
        sys.stderr.write(f"[select_am_rendition error]: {e}\n")
        return master_url

def clean_for_search(text):
    if not text:
        return ""
    s = re.sub(r"\((feat\.|ft\.|cùng với|con|mukana|com|avec|official|mv|lyrics|audio).*?\)", "", text, flags=re.IGNORECASE)
    s = re.sub(r"\[.*?\]", "", s)
    s = re.sub(r"\((.*?)\)", r"\1", s)
    s = re.sub(r"\s+", " ", s).strip()
    return s

def normalize_for_match(text):
    if not text:
        return ""
    cleaned = "".join(c if c.isalnum() else " " for c in text.lower())
    tokens = [w for w in cleaned.split() if w]
    return " ".join(tokens)

def match_key(text):
    norm = normalize_for_match(text)
    return norm if norm else text.strip().lower()

def matches_loosely(a, b):
    ka = match_key(a)
    kb = match_key(b)
    if not ka or not kb:
        return False
    if ka == kb or ka in kb or kb in ka:
        return True
    sa = set(ka.split())
    sb = set(kb.split())
    if sa and sb:
        overlap = sa & sb
        if len(overlap) / min(len(sa), len(sb)) >= 0.5:
            return True
    return False

def artist_agrees(cand_artist, query_artist):
    if not query_artist:
        return True
    if not cand_artist:
        return False
    return matches_loosely(cand_artist, query_artist)

def match_score(candidate, subject):
    c = match_key(candidate)
    s = match_key(subject)
    if not c or not s:
        return None
    if c == s:
        return (0, 0)
    if c.startswith(s):
        return (1, len(c) - len(s))
    if s in c:
        return (2, len(c) - len(s))
    if c in s:
        # If candidate is a substring of subject, ensure it is substantial (at least 60% of length or >= 12 chars)
        if len(c) >= 12 or (len(c) / max(1, len(s))) >= 0.60:
            return (3, len(s) - len(c))
        return None
    return None

def get_apple_music_animated_artwork(title, artist, duration_seconds=0, album_hint=""):
    """
    Searches Apple Music catalog for an album's editorialVideo animated artwork.
    Strictly follows SimpMusic's pickSongMatch architecture:
    1. Artist MUST agree (matches_loosely).
    2. Song title MUST match closely (tiers 0-3: exact, prefix, substring, superstring).
    3. EditorialVideo is ONLY inspected on albums directly associated with the MATCHED song candidate.
    4. Arbitrary album fallback is strictly forbidden to prevent unrelated animated covers.
    """
    if not title:
        return {"found": False}
    import urllib.parse
    clean_title = clean_for_search(title)
    clean_artist = clean_for_search(artist)
    cache_key = f"{match_key(clean_title)}_{match_key(clean_artist)}"

    cached_data = load_json(ANIMATED_ARTWORK_CACHE_FILE, {})
    if cache_key in cached_data:
        entry = cached_data[cache_key]
        if time.time() - entry.get("timestamp", 0) < 86400 * 7:  # 7 days cache
            return entry

    token = get_am_token()
    if not token:
        return {"found": False, "error": "token_unavailable"}

    try:
        query = f"{clean_title} {clean_artist}".strip()
        # Query storefront "vn" first (covers Vietnamese catalog and international releases), then "us"
        for sf in ["vn", "us"]:
            encoded_query = urllib.parse.quote(query)
            search_url = (
                f"https://amp-api-edge.music.apple.com/v1/catalog/{sf}/search?"
                f"term={encoded_query}&types=songs&include[songs]=albums&format[resources]=map&extend=editorialVideo&limit=5&platform=web"
            )
            req = urllib.request.Request(
                search_url,
                headers={
                    "Authorization": f"Bearer {token}",
                    "Origin": "https://music.apple.com",
                    "User-Agent": "Mozilla/5.0 (X11; Linux x86_64)"
                }
            )
            try:
                ssl_ctx = pc.get_ssl_context()
                with urllib.request.urlopen(req, timeout=5, context=ssl_ctx) as resp:
                    data = json.loads(resp.read().decode("utf-8", errors="ignore"))
            except Exception:
                continue

            albums = data.get("resources", {}).get("albums", {})
            songs = data.get("resources", {}).get("songs", {})

            candidates = []
            for rank, (sid, s) in enumerate(songs.items()):
                attrs = s.get("attributes", {})
                cand_name = attrs.get("name", "")
                cand_artist = attrs.get("artistName", "")

                # 1. Artist MUST agree
                if not artist_agrees(cand_artist, clean_artist):
                    continue

                # 2. Title MUST match
                score = match_score(cand_name, clean_title)
                if score is None:
                    continue

                cand_dur = (attrs.get("durationInMillis") or 0) / 1000.0
                dur_misses = False
                if duration_seconds > 0 and cand_dur > 0:
                    if abs(cand_dur - duration_seconds) > 5.5:
                        dur_misses = True

                # 3. Check if any associated album of THIS SPECIFIC song has editorialVideo
                rel_albums = s.get("relationships", {}).get("albums", {}).get("data", [])
                has_artwork = False
                matched_album_name = ""
                found_video = None
                album_hint_misses = False

                for a_ref in rel_albums:
                    aid = a_ref.get("id")
                    if aid in albums:
                        a_data = albums[aid]
                        a_name = a_data.get("attributes", {}).get("name", "")
                        if album_hint and a_name:
                            alb_sc = match_score(a_name, album_hint)
                            if not alb_sc or alb_sc[0] != 0:
                                album_hint_misses = True

                        ev = a_data.get("attributes", {}).get("editorialVideo", {})
                        if ev:
                            for k in ["motionSquareVideo1x1", "motionDetailSquare", "motionDetailTall", "motionTallVideo3x4"]:
                                if k in ev and "video" in ev[k]:
                                    found_video = ev[k]["video"]
                                    break
                            if not found_video:
                                for k, v in ev.items():
                                    if isinstance(v, dict) and "video" in v:
                                        found_video = v["video"]
                                        break
                            if found_video:
                                has_artwork = True
                                matched_album_name = a_name
                                break

                # Penalty / Demote (SimpMusic formula: durationMisses=4, hintMisses=2, hasNoArtwork=1)
                demote = (4 if dur_misses else 0) + (2 if album_hint_misses else 0) + (0 if has_artwork else 1)
                tier, extra_len = score
                candidates.append({
                    "tier": tier,
                    "extra_len": extra_len,
                    "demote": demote,
                    "rank": rank,
                    "has_artwork": has_artwork,
                    "album_name": matched_album_name,
                    "video_url": found_video,
                    "cand_name": cand_name,
                    "cand_artist": cand_artist
                })

            if candidates:
                # Rank candidates: tier -> extra_len -> demote -> rank
                candidates.sort(key=lambda x: (x["tier"], x["extra_len"], x["demote"], x["rank"]))
                best = candidates[0]
                if best["has_artwork"] and best["video_url"]:
                    rendition_url = select_am_rendition(best["video_url"])
                    res = {
                        "found": True,
                        "video_url": rendition_url,
                        "master_url": best["video_url"],
                        "album_name": best["album_name"],
                        "storefront": sf,
                        "timestamp": time.time()
                    }
                    cached_data[cache_key] = res
                    save_json(ANIMATED_ARTWORK_CACHE_FILE, cached_data)
                    return res
                else:
                    # The genuine matched song's album has no animated artwork.
                    # Do NOT fallback to random albums!
                    res = {
                        "found": False,
                        "reason": "no_animated_artwork_on_album",
                        "storefront": sf,
                        "timestamp": time.time()
                    }
                    cached_data[cache_key] = res
                    save_json(ANIMATED_ARTWORK_CACHE_FILE, cached_data)
                    return res

        # No candidate song matched across storefronts
        res = {"found": False, "reason": "no_song_candidate_matched", "timestamp": time.time()}
        cached_data[cache_key] = res
        save_json(ANIMATED_ARTWORK_CACHE_FILE, cached_data)
        return res

    except Exception as e:
        sys.stderr.write(f"[Apple Music Animated Artwork Error for {title}]: {e}\n")
        return {"found": False, "error": str(e)}

_square_cover_cache = None

def _get_square_covers_cache():
    global _square_cover_cache
    if _square_cover_cache is None:
        _square_cover_cache = load_json(SQUARE_COVERS_CACHE_FILE, {})
    return _square_cover_cache

def _save_square_covers_cache():
    global _square_cover_cache
    if _square_cover_cache is not None:
        save_json(SQUARE_COVERS_CACHE_FILE, _square_cover_cache)

def resolve_square_cover(title, artist="", video_id=None, current_image=None):
    """
    2-Tier Resolver for 1:1 Square Album Artwork:
    Tier 0: If current_image is already a Google CDN square artwork, upscale to 1200px and return immediately.
    Tier 1: Search official song release on YouTube Music (filter='songs', limit=5).
            If a matching song candidate exists, extract native square 1:1 artwork.
    Tier 2 (Fallback): Return current_image or maxresdefault.jpg.
    """
    clean_title = str(title or "").strip()
    clean_artist = str(artist or "").strip()
    clean_vid = str(video_id or "").strip().replace("ytdl://", "").replace("yt_", "")
    curr_img = str(current_image or "").strip()

    # Tier 0: Already native square Google CDN or Apple Music image
    if curr_img and ("googleusercontent.com" in curr_img or "ggpht.com" in curr_img):
        upgraded = re.sub(r'=w\d+-h\d+.*', '=w1200-h1200-l90-rj', curr_img)
        if "=w1200-h1200-l90-rj" not in upgraded:
            if "=" in upgraded:
                upgraded = upgraded.split("=")[0] + "=w1200-h1200-l90-rj"
            else:
                upgraded = upgraded + "=w1200-h1200-l90-rj"
        return {"url": upgraded, "is_square": True, "cached": True}

    if curr_img and "mzstatic.com" in curr_img:
        upgraded = re.sub(r'\d+x\d+bb', '1200x1200bb', curr_img)
        return {"url": upgraded, "is_square": True, "cached": True}

    search_title = clean_for_search(clean_title)
    if "|" in search_title:
        search_title = search_title.split("|")[0].strip()
    if " - " in search_title:
        parts = [p.strip() for p in search_title.split(" - ") if p.strip()]
        if len(parts) >= 2:
            search_title = parts[0]

    cache_key = clean_vid if clean_vid else f"{clean_title}_{clean_artist}".lower()
    if cache_key:
        cached_data = _get_square_covers_cache().get(cache_key)
        if cached_data and cached_data.get("is_square"):
            return cached_data

    # Tier 1: Search official song release on YouTube Music (1:1 Google CDN)
    ytm = get_ytmusic_client()
    query = f"{search_title} {clean_artist}".strip()
    if not query and search_title:
        query = search_title

    if query and ytm:
        try:
            results = ytm.search(query, filter="songs", limit=5)
            for r in results:
                t = r.get("title", "")
                r_artists = [a.get("name", "") for a in r.get("artists", []) if isinstance(a, dict)]
                cand_artist_str = ", ".join(r_artists)

                sc = match_score(t, search_title) or match_score(t, clean_title)
                agree = artist_agrees(cand_artist_str, clean_artist) if clean_artist else True
                if (sc is not None) and agree:
                    thumbs = r.get("thumbnails", [])
                    if thumbs:
                        thumb_url = thumbs[-1].get("url", "")
                        if "googleusercontent.com" in thumb_url or "ggpht.com" in thumb_url:
                            upgraded = re.sub(r'=w\d+-h\d+.*', '=w1200-h1200-l90-rj', thumb_url)
                            if "=w1200-h1200-l90-rj" not in upgraded:
                                if "=" in upgraded:
                                    upgraded = upgraded.split("=")[0] + "=w1200-h1200-l90-rj"
                                else:
                                    upgraded = upgraded + "=w1200-h1200-l90-rj"
                            res = {
                                "url": upgraded,
                                "is_square": True,
                                "title": t,
                                "videoId": r.get("videoId", ""),
                                "match": "official_ytm_song"
                            }
                            if cache_key:
                                _get_square_covers_cache()[cache_key] = res
                                _save_square_covers_cache()
                            return res
        except Exception as e:
            sys.stderr.write(f"[resolve_square_cover YTM error]: {e}\n")

    # Tier 1.5: Search official song release on iTunes / Apple Music (1200x1200bb 1:1)
    if query:
        try:
            import urllib.request, urllib.parse
            itunes_url = f"https://itunes.apple.com/search?term={urllib.parse.quote(query)}&entity=song&limit=5"
            it_req = urllib.request.Request(itunes_url, headers={"User-Agent": "Mozilla/5.0"})
            ssl_ctx = pc.get_ssl_context()
            with urllib.request.urlopen(it_req, timeout=3.5, context=ssl_ctx) as resp:
                it_data = json.loads(resp.read().decode("utf-8", errors="ignore"))
                for r in it_data.get("results", []):
                    t = r.get("trackName", "")
                    cand_artist = r.get("artistName", "")
                    sc = match_score(t, search_title) or match_score(t, clean_title)
                    agree = artist_agrees(cand_artist, clean_artist) if clean_artist else True
                    if (sc is not None) and agree:
                        art = r.get("artworkUrl100", "")
                        if art:
                            art1200 = re.sub(r'\d+x\d+bb', '1200x1200bb', art)
                            res = {
                                "url": art1200,
                                "is_square": True,
                                "title": t,
                                "artist": cand_artist,
                                "match": "official_itunes_song"
                            }
                            if cache_key:
                                _get_square_covers_cache()[cache_key] = res
                                _save_square_covers_cache()
                            return res
        except Exception as e:
            sys.stderr.write(f"[resolve_square_cover iTunes error]: {e}\n")

    # Tier 2 Fallback: YouTube HD Thumbnail (maxresdefault.jpg 1280x720)
    fallback_url = curr_img
    if not fallback_url and clean_vid:
        fallback_url = f"https://i.ytimg.com/vi/{clean_vid}/maxresdefault.jpg"
    elif fallback_url and "i.ytimg.com" in fallback_url:
        clean_yt = fallback_url.split("?")[0]
        if "maxresdefault.jpg" not in clean_yt:
            fallback_url = re.sub(r'/(hqdefault|mqdefault|sddefault|default|hq720)\.jpg', '/maxresdefault.jpg', clean_yt)
        else:
            fallback_url = clean_yt

    # Fast verification: if fallback_url is maxresdefault.jpg, check HEAD
    if fallback_url and "maxresdefault.jpg" in fallback_url:
        try:
            import http.client, urllib.parse
            p = urllib.parse.urlparse(fallback_url)
            conn = http.client.HTTPSConnection(p.netloc, timeout=1.0)
            conn.request("HEAD", p.path)
            resp = conn.getresponse()
            conn.close()
            if resp.status != 200:
                fallback_url = fallback_url.replace("maxresdefault.jpg", "hqdefault.jpg")
        except Exception:
            pass

    # Do not permanently cache fallback covers so future attempts or corrected metadata can resolve the official square art
    return {"url": fallback_url, "is_square": False, "match": "fallback"}


SPOTIFY_CANVAS_CACHE_FILE = os.path.join(pc.get_cache_dir(), "spotify_canvas_cache.json")

def get_spotify_canvas(title, artist, duration_seconds=0):
    """
    Fetch Spotify Canvas looping video (.cnvs.mp4) for a track.
    Requires user to have sp_dc cookie connected (or anonymous client token fallback).
    """
    if not title:
        return {"found": False}
    clean_title = clean_for_search(title)
    clean_artist = clean_for_search(artist)
    cache_key = f"{match_key(clean_title)}_{match_key(clean_artist)}"

    cached_data = load_json(SPOTIFY_CANVAS_CACHE_FILE, {})
    if cache_key in cached_data:
        entry = cached_data[cache_key]
        if time.time() - entry.get("timestamp", 0) < 86400 * 7:  # 7 days cache
            return entry

    spdc = lyrics_helper.get_spotify_spdc()
    if not spdc:
        return {"found": False, "reason": "no_spotify_cookie"}

    access_token = lyrics_helper.get_spotify_access_token(spdc)
    if not access_token:
        return {"found": False, "reason": "spotify_token_failed"}

    client_token = lyrics_helper._spotify_get_client_token()
    query = f"{clean_title} {clean_artist}".strip() if clean_artist else clean_title
    track_id = lyrics_helper._spotify_search_track(query, access_token, client_token, duration_seconds)
    if not track_id and clean_title != title:
        track_id = lyrics_helper._spotify_search_track(clean_title, access_token, client_token, duration_seconds)

    if not track_id:
        res = {"found": False, "reason": "track_not_found_on_spotify", "timestamp": time.time()}
        cached_data[cache_key] = res
        save_json(SPOTIFY_CANVAS_CACHE_FILE, cached_data)
        return res

    try:
        # Protobuf binary payload:
        # message CanvasRequest { repeated Track tracks = 1; }
        # message Track { string track_uri = 1; }
        uri = f"spotify:track:{track_id}".encode("utf-8")
        inner = bytes([0x0a, len(uri)]) + uri
        outer = bytes([0x0a, len(inner)]) + inner

        canvas_req = urllib.request.Request(
            "https://spclient.wg.spotify.com/canvaz-cache/v0/canvases",
            data=outer,
            headers={
                "Authorization": f"Bearer {access_token}",
                "Client-Token": client_token,
                "Accept": "application/protobuf",
                "Content-Type": "application/protobuf",
                "User-Agent": "Spotify/9.0.34.593 iOS/18.4 (iPhone15,3)",
            },
            method="POST"
        )
        ssl_ctx = pc.get_ssl_context()
        with urllib.request.urlopen(canvas_req, timeout=6, context=ssl_ctx) as resp:
            content = resp.read()
            urls = re.findall(rb"https://[^\x00-\x1f\s\"]+\.cnvs\.mp4", content)
            if urls:
                canvas_url = urls[0].decode("utf-8")
                res = {
                    "found": True,
                    "video_url": canvas_url,
                    "master_url": canvas_url,
                    "type": "spotify_canvas",
                    "track_id": track_id,
                    "timestamp": time.time()
                }
                cached_data[cache_key] = res
                save_json(SPOTIFY_CANVAS_CACHE_FILE, cached_data)
                return res
    except Exception as e:
        sys.stderr.write(f"[get_spotify_canvas error]: {e}\n")

    res = {"found": False, "reason": "no_canvas_for_track", "track_id": track_id, "timestamp": time.time()}
    cached_data[cache_key] = res
    save_json(SPOTIFY_CANVAS_CACHE_FILE, cached_data)
    return res


def get_animated_background(title, artist, duration_seconds=0, album_hint="", preference="apple_first"):
    """
    Fetch animated background video (Apple Music Animated Cover or Spotify Canvas)
    based on user's preference:
    - 'apple_first': Apple Music > Spotify Canvas (Default)
    - 'spotify_first': Spotify Canvas > Apple Music
    - 'apple_only': Apple Music only
    - 'spotify_only': Spotify Canvas only
    - 'off': None
    """
    pref = (preference or "apple_first").lower().strip()
    if pref == "off":
        return {"found": False, "reason": "disabled_by_user"}

    if pref == "apple_only":
        return get_apple_music_animated_artwork(title, artist, duration_seconds, album_hint)

    if pref == "spotify_only":
        return get_spotify_canvas(title, artist, duration_seconds)

    if pref == "spotify_first":
        sc = get_spotify_canvas(title, artist, duration_seconds)
        if sc and sc.get("found"):
            return sc
        return get_apple_music_animated_artwork(title, artist, duration_seconds, album_hint)

    # Default: apple_first
    am = get_apple_music_animated_artwork(title, artist, duration_seconds, album_hint)
    if am and am.get("found"):
        return am
    return get_spotify_canvas(title, artist, duration_seconds)



