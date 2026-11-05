#!/usr/bin/env python3
"""
Nutsty Multi-Source Parallel Lyrics Resolver
Brought from Mochy-Music (vivi/mochymusic) architecture:
- Queries multiple lyrics providers in parallel (LRCLIB, SimpMusic, BetterLyrics, KuGou, NetEase, YouTube)
- High-precision grading algorithm `pickBest`:
  1. Original script detection (prevents Chinese machine-translated lyrics for English/Vietnamese/Japanese songs)
  2. Sync quality ranking: Word-by-word (Karaoke) > Line-by-line > Plain
  3. Duet & vocal voice tags ({agent:v1}, {agent:v2})
  4. Duration tolerance matching
- Fast bounded timeout (max 3.0s total)
"""
import sys
import os
import json
import re
import html
import time
import base64
import urllib.request
import urllib.parse
from concurrent.futures import ThreadPoolExecutor, as_completed
import threading
from typing import List, Dict, Any, Optional

backend_dir = os.path.dirname(os.path.abspath(__file__))
if backend_dir not in sys.path:
    sys.path.insert(0, backend_dir)

try:
    from . import platform_compat as pc
    from .lyrics_engine.parsers import parse_lrc, parse_ttml_body, strip_rich_sync_tags, parse_rich_sync_words
except (ImportError, ValueError):
    import platform_compat as pc
    from lyrics_engine.parsers import parse_lrc, parse_ttml_body, strip_rich_sync_tags, parse_rich_sync_words

CACHE_DIR = os.path.join(pc.get_cache_dir(), "lyrics")
os.makedirs(CACHE_DIR, exist_ok=True)

DEFAULT_TIMEOUT = 3.0

# ──────────────────────────────────────────────────────────────────────────────
# SCRIPT & LANGUAGE ANALYSIS (Ported from Mochy-Music LyricsUtils.kt)
# ──────────────────────────────────────────────────────────────────────────────

class Script:
    LATIN = "LATIN"
    HAN = "HAN"          # Chinese characters (Hanzi / Kanji / Hanja)
    KANA = "KANA"        # Japanese Hiragana / Katakana
    HANGUL = "HANGUL"    # Korean Hangul
    CYRILLIC = "CYRILLIC"
    ARABIC = "ARABIC"
    DEVANAGARI = "DEVANAGARI"
    THAI = "THAI"
    GREEK = "GREEK"
    HEBREW = "HEBREW"
    UNKNOWN = "UNKNOWN"

class SyncKind:
    NONE = 0
    PLAIN = 1
    LINE = 2
    WORD = 3

def script_of_char(ch: str) -> Optional[str]:
    """Map unicode codepoint to writing script."""
    code = ord(ch)
    if (0x0041 <= code <= 0x024F) or (0x1E00 <= code <= 0x1EFF):
        return Script.LATIN
    elif 0x0370 <= code <= 0x03FF:
        return Script.GREEK
    elif 0x0400 <= code <= 0x052F:
        return Script.CYRILLIC
    elif 0x0590 <= code <= 0x05FF:
        return Script.HEBREW
    elif (0x0600 <= code <= 0x06FF) or (0x0750 <= code <= 0x077F):
        return Script.ARABIC
    elif 0x0900 <= code <= 0x097F:
        return Script.DEVANAGARI
    elif 0x0E00 <= code <= 0x0E7F:
        return Script.THAI
    elif 0x3040 <= code <= 0x30FF:
        return Script.KANA
    elif (0xAC00 <= code <= 0xD7AF) or (0x1100 <= code <= 0x11FF):
        return Script.HANGUL
    elif (0x3400 <= code <= 0x4DBF) or (0x4E00 <= code <= 0x9FFF) or (0xF900 <= code <= 0xFAFF):
        return Script.HAN
    return None

def dominant_script(text: str) -> str:
    """
    Find dominant writing script in text.
    Key Mochy rule: Kana wins over Han whenever ANY kana is present!
    (Because Japanese songs use Kanji + Kana, but Chinese songs never use Kana).
    """
    if not text:
        return Script.UNKNOWN
    counts: Dict[str, int] = {}
    total = 0
    for ch in text:
        s = script_of_char(ch)
        if s:
            counts[s] = counts.get(s, 0) + 1
            total += 1
    if total == 0:
        return Script.UNKNOWN
    if counts.get(Script.KANA, 0) > 0:
        return Script.KANA
    if counts.get(Script.HANGUL, 0) * 4 >= total:
        return Script.HANGUL
    return max(counts.items(), key=lambda x: x[1])[0]

def detect_sync_kind(raw_lyrics: str) -> int:
    """Detect if lyrics are Word-level (karaoke), Line-level synced, Plain, or None."""
    if not raw_lyrics or not raw_lyrics.strip():
        return SyncKind.NONE

    # Look for word-level sync tags: <00:12.34> or <0:12.345>
    rich_tags = len(re.findall(r'<\d{1,2}:\d{2}(?:\.\d{2,3})?>', raw_lyrics))
    line_tags = len(re.findall(r'\[\d{1,2}:\d{2}(?:\.\d{2,3})?\]', raw_lyrics))

    if rich_tags >= 3:
        return SyncKind.WORD
    elif line_tags >= 2:
        return SyncKind.LINE
    elif any(c.isalpha() for c in raw_lyrics):
        return SyncKind.PLAIN
    return SyncKind.NONE

def clean_search_title(title: str) -> str:
    """Clean video titles (e.g. 'Song (Official Music Video)') for accurate lyrics search."""
    if not title:
        return ""
    t = title
    t = re.sub(r'[\(\[\{【].*?(?:official|audio|mv|video|lyrics|lyric|visualizer|remix|hd|hq|4k|ver|version|performance|live).*?[\)\]\}】]', '', t, flags=re.IGNORECASE)
    t = re.sub(r'\s*[-|]\s*(?:official|audio|mv|video|lyrics|visualizer).*$', '', t, flags=re.IGNORECASE)
    t = re.sub(r'[\(\[](?:feat\.|ft\.).*?[\)\]]', '', t, flags=re.IGNORECASE)
    return t.strip()

# ──────────────────────────────────────────────────────────────────────────────
# LYRICS CANDIDATE DATA STRUCTURE
# ──────────────────────────────────────────────────────────────────────────────

class LyricsCandidate:
    def __init__(
        self,
        provider: str,
        raw_lyrics: str,
        sync_kind: int,
        script: str,
        duration_sec: Optional[float] = None,
        has_voice_tags: bool = False,
        has_duet: bool = False,
        is_ttml: bool = False
    ):
        self.provider = provider
        self.raw_lyrics = raw_lyrics
        self.sync_kind = sync_kind
        self.script = script
        self.duration_sec = duration_sec
        self.has_voice_tags = has_voice_tags
        self.has_duet = has_duet
        self.is_ttml = is_ttml
        self.score: float = 0.0

    def __repr__(self):
        return f"<Candidate {self.provider} sync={self.sync_kind} script={self.script} score={self.score}>"

# ──────────────────────────────────────────────────────────────────────────────
# INDIVIDUAL PROVIDER FETCHERS
# ──────────────────────────────────────────────────────────────────────────────

def fetch_youlyplus_candidate(title: str, artist: str = "") -> Optional[LyricsCandidate]:
    """
    Fetch studio word-level karaoke from YouLyPlus API (Mochy-Music source).
    Uses https://lyricsplus.binimum.org/v2/lyrics/get without duration to avoid timeout.
    """
    clean_t = clean_search_title(title)
    clean_a = clean_search_title(artist) if artist else ""
    params = {"title": clean_t}
    if clean_a:
        params["artist"] = clean_a

    endpoints = [
        "https://lyricsplus.binimum.org/v2/lyrics/get",
        "https://lyricsplus.prjktla.my.id/v2/lyrics/get"
    ]
    for ep in endpoints:
        try:
            url = f"{ep}?{urllib.parse.urlencode(params)}"
            req = urllib.request.Request(url, headers={
                "User-Agent": "Mochy (+https://github.com/realidkroo/Mochy-Music)",
                "Accept": "application/json"
            })
            with urllib.request.urlopen(req, timeout=2.5) as resp:
                data = json.loads(resp.read().decode("utf-8", errors="ignore"))
            items = data.get("lyrics", [])
            if not items:
                continue

            lines = []
            has_voice = False
            voices = set()
            for item in items:
                t_ms = item.get("time", 0)
                mins = (t_ms // 1000) // 60
                secs = (t_ms // 1000) % 60
                ms = t_ms % 1000
                stamp = f"[{mins:02d}:{secs:02d}.{ms:03d}]"
                singer = item.get("element", {}).get("singer", "")
                if singer:
                    has_voice = True
                    voices.add(singer)
                    marker = f"{{agent:{singer}}}"
                else:
                    marker = ""

                syls = item.get("syllabus", [])
                if syls:
                    w_str = ""
                    for s in syls:
                        sm = (s.get("time", 0) // 1000) // 60
                        ss = (s.get("time", 0) // 1000) % 60
                        sms = s.get("time", 0) % 1000
                        stxt = s.get("text", "")
                        w_str += f"<{sm:02d}:{ss:02d}.{sms:03d}>{stxt}"
                    lines.append(f"{stamp}{marker}{w_str.strip()}")
                else:
                    txt = item.get("text", "")
                    lines.append(f"{stamp}{marker}{txt}")

            raw = "\n".join(lines)
            if not raw.strip():
                continue

            sync = detect_sync_kind(raw)
            scr = dominant_script(raw)
            has_duet = len(voices) > 1

            return LyricsCandidate(
                provider="YouLyPlus",
                raw_lyrics=raw,
                sync_kind=sync,
                script=scr,
                has_voice_tags=has_voice,
                has_duet=has_duet
            )
        except Exception:
            continue
    return None

def fetch_simpmusic_candidate(video_id: str, title: str, artist: str, duration_sec: Optional[float] = None) -> Optional[LyricsCandidate]:
    """Fetch lyrics from SimpMusic API (richSync word-level & synced)."""
    vid = video_id
    if vid.startswith("ytdl://"):
        vid = vid.replace("ytdl://", "")
    if "watch?v=" in vid:
        vid = vid.split("watch?v=")[1].split("&")[0]

    if not vid:
        try:
            try:
                from .catalog_engine import search_ytmusic
            except (ImportError, ValueError):
                from catalog_engine import search_ytmusic
            q = f"{clean_search_title(title)} {artist}".strip()
            hits = search_ytmusic(q)
            if hits and "videoId" in hits[0]:
                vid = hits[0]["videoId"]
        except Exception:
            pass

    if not vid:
        return None

    endpoints = [
        f"https://api-lyrics.simpmusic.org/v1/{vid}",
        f"https://musicfy-yt-music-server.onrender.com/v1/{vid}"
    ]
    for url in endpoints:
        try:
            req = urllib.request.Request(url, headers={
                "User-Agent": "SimpMusicLyrics/1.0",
                "Accept": "application/json"
            })
            with urllib.request.urlopen(req, timeout=DEFAULT_TIMEOUT) as resp:
                data = json.loads(resp.read().decode("utf-8", errors="ignore"))
            items = data.get("data", [])
            if not items:
                continue

            # Pick closest duration if possible
            best_item = None
            if duration_sec and len(items) > 1:
                best_item = min(items, key=lambda x: abs((x.get("duration") or 0) - duration_sec))
            else:
                best_item = items[0]

            raw = best_item.get("richSyncLyrics") or best_item.get("syncedLyrics") or best_item.get("plainLyrics")
            if not raw or not raw.strip():
                continue

            sync = detect_sync_kind(raw)
            scr = dominant_script(raw)
            has_voice = "{agent:" in raw or "{bg}" in raw
            has_duet = False
            if has_voice:
                agents = set(re.findall(r'\{agent:([^}]+)\}', raw))
                has_duet = len(agents) > 1

            return LyricsCandidate(
                provider="SimpMusic",
                raw_lyrics=raw,
                sync_kind=sync,
                script=scr,
                duration_sec=best_item.get("duration"),
                has_voice_tags=has_voice,
                has_duet=has_duet
            )
        except Exception:
            continue
    return None

def fetch_lrclib_candidate(title: str, artist: str, duration_sec: Optional[float] = None) -> Optional[LyricsCandidate]:
    """Fetch lyrics from LRCLIB (synced and plain)."""
    clean_t = clean_search_title(title)
    clean_a = artist or ""

    # 1. Exact match attempt
    params = {"track_name": clean_t, "artist_name": clean_a}
    if duration_sec and duration_sec > 0:
        params["duration"] = int(round(duration_sec))

    url = f"https://lrclib.net/api/get?{urllib.parse.urlencode(params)}"
    try:
        req = urllib.request.Request(url, headers={"User-Agent": "Nutsty (+https://github.com/nutsty)"})
        with urllib.request.urlopen(req, timeout=DEFAULT_TIMEOUT) as resp:
            data = json.loads(resp.read().decode("utf-8", errors="ignore"))
        raw = data.get("syncedLyrics") or data.get("plainLyrics")
        if raw and raw.strip():
            sync = detect_sync_kind(raw)
            scr = dominant_script(raw)
            return LyricsCandidate(
                provider="LRCLIB",
                raw_lyrics=raw,
                sync_kind=sync,
                script=scr,
                duration_sec=data.get("duration")
            )
    except Exception:
        pass

    # 2. Relaxed search attempt
    try:
        q = f"{clean_t} {clean_a}".strip()
        url_search = f"https://lrclib.net/api/search?{urllib.parse.urlencode({'q': q})}"
        req = urllib.request.Request(url_search, headers={"User-Agent": "Nutsty (+https://github.com/nutsty)"})
        with urllib.request.urlopen(req, timeout=DEFAULT_TIMEOUT) as resp:
            items = json.loads(resp.read().decode("utf-8", errors="ignore"))
        if items and isinstance(items, list):
            cand = None
            if duration_sec:
                cand = min(items, key=lambda x: abs((x.get("duration") or 0) - duration_sec))
            else:
                cand = items[0]
            raw = cand.get("syncedLyrics") or cand.get("plainLyrics")
            if raw and raw.strip():
                return LyricsCandidate(
                    provider="LRCLIB",
                    raw_lyrics=raw,
                    sync_kind=detect_sync_kind(raw),
                    script=dominant_script(raw),
                    duration_sec=cand.get("duration")
                )
    except Exception:
        pass
    return None

def fetch_betterlyrics_candidate(title: str, artist: str, duration_sec: Optional[float] = None) -> Optional[LyricsCandidate]:
    """Fetch TTML Apple Music lyrics from BetterLyrics API."""
    clean_t = clean_search_title(title)
    params = {"s": clean_t, "a": artist or ""}
    if duration_sec and duration_sec > 0:
        params["d"] = int(duration_sec)

    url = f"https://lyrics-api.boidu.dev/getLyrics?{urllib.parse.urlencode(params)}"
    try:
        req = urllib.request.Request(url, headers={
            "User-Agent": "Mochy (+https://github.com/realidkroo/Mochy-Music)",
            "Accept": "application/json"
        })
        with urllib.request.urlopen(req, timeout=DEFAULT_TIMEOUT) as resp:
            data = json.loads(resp.read().decode("utf-8", errors="ignore"))
        ttml = data.get("ttml", "")
        if not ttml or not ttml.strip():
            return None

        has_voice = "ttm:agent" in ttml or "agent=" in ttml
        has_duet = len(set(re.findall(r'ttm:agent="([^"]+)"', ttml))) > 1
        scr = dominant_script(re.sub(r'<[^>]+>', ' ', ttml))

        return LyricsCandidate(
            provider="BetterLyrics",
            raw_lyrics=ttml,
            sync_kind=SyncKind.WORD,
            script=scr,
            has_voice_tags=has_voice,
            has_duet=has_duet,
            is_ttml=True
        )
    except Exception:
        return None

def fetch_kugou_candidate(title: str, artist: str, duration_sec: Optional[float] = None) -> Optional[LyricsCandidate]:
    """Fetch Asian / C-Pop / K-Pop / J-Pop lyrics from KuGou."""
    clean_t = clean_search_title(title)
    query = clean_t
    dur_ms = int(duration_sec * 1000) if (duration_sec and duration_sec > 0) else None

    # Search KuGou lyrics endpoint
    url = f"https://lyrics.kugou.com/search?ver=1&man=yes&client=pc&keyword={urllib.parse.quote(query)}"
    if dur_ms:
        url += f"&duration={dur_ms}"

    try:
        req = urllib.request.Request(url, headers={"User-Agent": "KuGou/1.0"})
        with urllib.request.urlopen(req, timeout=DEFAULT_TIMEOUT) as resp:
            data = json.loads(resp.read().decode("utf-8", errors="ignore"))
        candidates = data.get("candidates", [])
        if not candidates:
            return None

        c = candidates[0]
        cid = c.get("id")
        accesskey = c.get("accesskey")
        down_url = f"https://lyrics.kugou.com/download?fmt=lrc&charset=utf8&client=pc&ver=1&id={cid}&accesskey={accesskey}"
        with urllib.request.urlopen(urllib.request.Request(down_url, headers={"User-Agent": "KuGou/1.0"}), timeout=DEFAULT_TIMEOUT) as dresp:
            down_data = json.loads(dresp.read().decode("utf-8", errors="ignore"))
            raw_b64 = down_data.get("content", "")
            raw = base64.b64decode(raw_b64).decode("utf-8", errors="ignore")

        if not raw or not raw.strip():
            return None

        return LyricsCandidate(
            provider="KuGou",
            raw_lyrics=raw,
            sync_kind=detect_sync_kind(raw),
            script=dominant_script(raw)
        )
    except Exception:
        return None

def fetch_netease_candidate(title: str, artist: str, duration_sec: Optional[float] = None) -> Optional[LyricsCandidate]:
    """Fetch lyrics from NetEase Cloud Music via syncedlyrics."""
    clean_t = clean_search_title(title)
    q = f"{clean_t} {artist}".strip()
    try:
        import syncedlyrics
        lrc = syncedlyrics.search(q, providers=["netease"])
        if lrc and lrc.strip():
            return LyricsCandidate(
                provider="NetEase",
                raw_lyrics=lrc,
                sync_kind=detect_sync_kind(lrc),
                script=dominant_script(lrc)
            )
    except Exception:
        pass
    return None

def fetch_spotify_candidate(title: str, artist: str, duration_sec: Optional[float] = None) -> Optional[LyricsCandidate]:
    """Fetch Spotify word-level lyrics if user has configured sp_dc cookie."""
    try:
        try:
            from . import lyrics_helper
        except (ImportError, ValueError):
            import lyrics_helper
        if not hasattr(lyrics_helper, "get_spotify_spdc") or not lyrics_helper.get_spotify_spdc():
            return None
        res = lyrics_helper.fetch_spotify_lyrics(clean_search_title(title), artist, duration_sec)
        if res and isinstance(res, list):
            # Convert list back to LRC or candidate
            lines_txt = []
            for item in res:
                t_sec = item.get("time", 0.0)
                m = int(t_sec // 60)
                s = t_sec % 60
                w_str = ""
                for w in item.get("words", []):
                    wm = int(w["start"] // 60)
                    ws = w["start"] % 60
                    w_str += f"<{wm:02d}:{ws:05.2f}>{w['text']} "
                lines_txt.append(f"[{m:02d}:{s:05.2f}]{w_str.strip() or item.get('text', '')}")
            raw = "\n".join(lines_txt)
            sync = detect_sync_kind(raw)
            return LyricsCandidate(
                provider="Spotify",
                raw_lyrics=raw,
                sync_kind=sync,
                script=dominant_script(raw),
                duration_sec=duration_sec
            )
    except Exception:
        pass
    return None

def fetch_youtube_captions_candidate(video_id: str) -> Optional[LyricsCandidate]:
    """Fetch YouTube captions/transcript via InnerTube as last resort."""
    vid = video_id
    if vid.startswith("ytdl://"):
        vid = vid.replace("ytdl://", "")
    if "watch?v=" in vid:
        vid = vid.split("watch?v=")[1].split("&")[0]
    if not vid:
        return None
    try:
        try:
            from .song_enrichment import get_youtube_lyrics
        except (ImportError, ValueError):
            from song_enrichment import get_youtube_lyrics
        plain = get_youtube_lyrics(vid)
        if plain and plain.strip():
            return LyricsCandidate(
                provider="YouTube",
                raw_lyrics=plain,
                sync_kind=SyncKind.PLAIN,
                script=dominant_script(plain)
            )
    except Exception:
        pass
    return None

# ──────────────────────────────────────────────────────────────────────────────
# PARALLEL QUERY ORCHESTRATOR
# ──────────────────────────────────────────────────────────────────────────────

_MEMORY_LYRICS_CACHE = {}
_MEMORY_CACHE_LOCK = threading.Lock()
LYRICS_CACHE_TTL = 900.0  # 15 minutes in memory

def fetch_all_candidates_parallel(
    title: str,
    artist: str = "",
    video_id: str = "",
    duration_sec: Optional[float] = None,
    preferred_provider: str = "auto"
) -> List[LyricsCandidate]:
    """Run all enabled providers concurrently with fast early-settle optimization."""
    candidates: List[LyricsCandidate] = []
    thunks = [
        ("YouLyPlus", lambda: fetch_youlyplus_candidate(title, artist)),
        ("SimpMusic", lambda: fetch_simpmusic_candidate(video_id, title, artist, duration_sec)),
        ("BetterLyrics", lambda: fetch_betterlyrics_candidate(title, artist, duration_sec)),
        ("LRCLIB", lambda: fetch_lrclib_candidate(title, artist, duration_sec)),
        ("KuGou", lambda: fetch_kugou_candidate(title, artist, duration_sec)),
        ("NetEase", lambda: fetch_netease_candidate(title, artist, duration_sec)),
        ("Spotify", lambda: fetch_spotify_candidate(title, artist, duration_sec)),
    ]

    pref_lower = (preferred_provider or "auto").strip().lower()
    if pref_lower and pref_lower != "auto":
        target_name = {
            "youlyplus": "YouLyPlus",
            "simpmusic": "SimpMusic",
            "betterlyrics": "BetterLyrics",
            "lrclib": "LRCLIB",
            "kugou": "KuGou",
            "netease": "NetEase",
            "spotify": "Spotify",
            "youtube": "YouTube"
        }.get(pref_lower)
        if target_name:
            thunks.sort(key=lambda x: 0 if x[0] == target_name else 1)

    with ThreadPoolExecutor(max_workers=7, thread_name_prefix="nutsty_lyr") as pool:
        futures = {pool.submit(fn): name for name, fn in thunks}
        has_top_tier_word = False
        settle_deadline = None

        for fut in as_completed(futures, timeout=DEFAULT_TIMEOUT):
            try:
                res = fut.result()
                if res and res.raw_lyrics:
                    candidates.append(res)
                    # Fast-path early settle: If a studio word-level candidate arrived,
                    # don't wait for remaining slow network timeouts!
                    if res.sync_kind == SyncKind.WORD and res.provider in ("YouLyPlus", "SimpMusic", "BetterLyrics", "Spotify"):
                        has_top_tier_word = True
                        if settle_deadline is None:
                            settle_deadline = time.time() + 0.25
            except Exception:
                pass

            if has_top_tier_word and settle_deadline and time.time() >= settle_deadline:
                break

    # If all primary providers returned nothing, try YouTube captions fallback
    if not candidates and video_id:
        yt_cand = fetch_youtube_captions_candidate(video_id)
        if yt_cand:
            candidates.append(yt_cand)

    return candidates

# ──────────────────────────────────────────────────────────────────────────────
# GRADING & PICK_BEST ALGORITHM (Ported from Mochy-Music LyricsHelper.kt)
# ──────────────────────────────────────────────────────────────────────────────

def grade_candidate(
    candidate: LyricsCandidate,
    track_info: Dict[str, Any],
    reference_script: str,
    majority_script: Optional[str] = None,
    preferred_provider: str = "auto"
) -> float:
    """
    Score a candidate based on:
    1. Script match (original language vs translation)
    2. Sync quality (Word > Line > Plain)
    3. Duet tags
    4. Duration matching
    5. Provider order
    """
    cand_script = candidate.script
    cand_sync = candidate.sync_kind

    # 1. Script Match Score
    script_score = 0
    if reference_script == Script.LATIN:
        if cand_script == Script.LATIN:
            script_score = 80
        elif cand_script == Script.HAN:
            # FATAL PENALTY: Chinese machine-translation of English/Vietnamese/Latin song!
            script_score = -250
        elif cand_script in (Script.KANA, Script.HANGUL):
            script_score = -120
        else:
            script_score = 10
    elif reference_script == Script.KANA:
        if cand_script == Script.KANA:
            script_score = 90
        elif cand_script == Script.HAN:
            # Chinese translation of Japanese song
            script_score = -180
        elif cand_script == Script.LATIN:
            # Romanization or English translation
            script_score = 25
        else:
            script_score = 0
    elif reference_script == Script.HANGUL:
        if cand_script == Script.HANGUL:
            script_score = 90
        elif cand_script == Script.HAN:
            script_score = -180
        elif cand_script == Script.LATIN:
            script_score = 25
        else:
            script_score = 0
    elif reference_script == Script.HAN:
        if cand_script == Script.HAN:
            script_score = 80
        else:
            script_score = 10
    else:
        # Reference script unknown from metadata
        if majority_script and cand_script == majority_script:
            script_score = 70
        elif cand_script == Script.HAN:
            script_score = 10
        else:
            script_score = 30

    # 2. Sync Kind Score (Karaoke Word > Line > Plain)
    sync_score = 0
    if cand_sync == SyncKind.WORD:
        sync_score = 100
    elif cand_sync == SyncKind.LINE:
        sync_score = 60
    elif cand_sync == SyncKind.PLAIN:
        sync_score = 15
    else:
        sync_score = -100

    # 3. Duet & Voice Tagging
    duet_score = 0
    if candidate.has_duet:
        duet_score = 25
    elif candidate.has_voice_tags:
        duet_score = 12

    # 4. Duration Match Bonus
    dur_score = 0
    track_dur = track_info.get("duration_sec")
    cand_dur = candidate.duration_sec
    if track_dur and track_dur > 0 and cand_dur and cand_dur > 0:
        diff = abs(track_dur - cand_dur)
        if diff <= 2.0:
            dur_score = 15
        elif diff <= 5.0:
            dur_score = 8
        elif diff > 15.0:
            dur_score = -30

    # 5. Provider Weight Tie-Breaker
    provider_weight = {
        "YouLyPlus": 8,
        "BetterLyrics": 7,
        "SimpMusic": 6,
        "Spotify": 5,
        "LRCLIB": 4,
        "KuGou": 3,
        "NetEase": 2,
        "YouTube": 1
    }.get(candidate.provider, 0)

    # 6. User Manual Preference Bonus (+150 points)
    user_pref_bonus = 0
    pref_clean = (preferred_provider or "").strip().lower()
    if pref_clean and pref_clean != "auto":
        if candidate.provider.lower() == pref_clean or (pref_clean == "betterlyrics" and candidate.provider == "BetterLyrics"):
            user_pref_bonus = 150

    total_score = script_score + sync_score + duet_score + dur_score + provider_weight + user_pref_bonus
    return total_score

def pick_best_candidate(
    candidates: List[LyricsCandidate],
    track_info: Dict[str, Any],
    preferred_provider: str = "auto"
) -> Optional[LyricsCandidate]:
    """Pick the best candidate using Mochy-Music grading principles."""
    if not candidates:
        return None

    # Determine reference script from song metadata (Title, Artist, Album)
    title = track_info.get("title", "")
    artist = track_info.get("artist", "")
    album = track_info.get("album", "")
    meta_text = f"{title} {artist} {album}".strip()
    reference_script = dominant_script(meta_text)

    # Special case: If metadata had Han (e.g. Japanese song in Kanji like '米津玄師'),
    # but any candidate came back with Kana, the song is definitely Japanese!
    if reference_script == Script.HAN and any(c.script == Script.KANA for c in candidates):
        reference_script = Script.KANA

    # Determine majority script among candidates
    majority_script = None
    if reference_script == Script.UNKNOWN:
        counts: Dict[str, int] = {}
        for c in candidates:
            if c.script != Script.UNKNOWN:
                counts[c.script] = counts.get(c.script, 0) + 1
        if counts:
            majority_script = max(counts.items(), key=lambda x: x[1])[0]

    # Grade each candidate
    for cand in candidates:
        cand.score = grade_candidate(cand, track_info, reference_script, majority_script, preferred_provider)

    # Filter out candidates with severe penalties (e.g. negative scores from wrong language)
    valid_candidates = [c for c in candidates if c.score > 0]
    if not valid_candidates:
        valid_candidates = candidates

    # Return highest scoring candidate
    valid_candidates.sort(key=lambda c: c.score, reverse=True)
    return valid_candidates[0]

# ──────────────────────────────────────────────────────────────────────────────
# CONVERT CANDIDATE TO NUTSTY STANDARD JSON LINES
# ──────────────────────────────────────────────────────────────────────────────

def candidate_to_nutsty_lines(cand: LyricsCandidate) -> List[Dict[str, Any]]:
    """Convert winning candidate lyrics into Nutsty line objects."""
    if not cand or not cand.raw_lyrics:
        return []

    lines: List[Dict[str, Any]] = []

    # Case 1: BetterLyrics TTML
    if cand.is_ttml:
        try:
            lines = parse_ttml_body(cand.raw_lyrics)
        except Exception:
            lines = []

    # Case 2: Standard or Rich-Sync LRC
    if not lines and cand.raw_lyrics:
        lines = parse_lrc(cand.raw_lyrics)

    # Tag source
    for it in lines:
        it["source"] = cand.provider

    # Fill in agent tags if present in LRC (e.g. {agent:v1})
    for it in lines:
        txt = it.get("text", "")
        m_agent = re.search(r'\{agent:([^}]+)\}', txt)
        if m_agent:
            it["agent"] = m_agent.group(1).strip()
            it["text"] = re.sub(r'\{agent:[^}]+\}', '', txt).strip()
        if "{bg}" in txt:
            it["isBackground"] = True
            it["text"] = txt.replace("{bg}", "").strip()

    return lines

# ──────────────────────────────────────────────────────────────────────────────
# MASTER RESOLVER ENTRY POINT
# ──────────────────────────────────────────────────────────────────────────────

def resolve_lyrics_parallel(
    title: str,
    artist: Optional[str] = None,
    video_id: Optional[str] = None,
    duration_sec: Optional[float] = None,
    file_path: Optional[str] = None,
    preferred_provider: str = "auto"
) -> List[Dict[str, Any]]:
    """
    Main entry point: Queries all providers in parallel with fast early-settle,
    grades candidates via pickBest, caches results, and returns Nutsty-compatible lines.
    """
    if not title:
        return []

    cache_key = f"{title}_{artist or ''}_{preferred_provider or 'auto'}".lower().strip()
    now = time.time()
    with _MEMORY_CACHE_LOCK:
        if cache_key in _MEMORY_LYRICS_CACHE:
            entry = _MEMORY_LYRICS_CACHE[cache_key]
            if now - entry.get("timestamp", 0) < LYRICS_CACHE_TTL:
                return entry.get("lines", [])

    track_info = {
        "title": title,
        "artist": artist or "",
        "video_id": video_id or "",
        "duration_sec": duration_sec
    }

    candidates = fetch_all_candidates_parallel(
        title=title,
        artist=artist or "",
        video_id=video_id or "",
        duration_sec=duration_sec,
        preferred_provider=preferred_provider
    )

    if not candidates:
        return []

    best = pick_best_candidate(candidates, track_info, preferred_provider=preferred_provider)
    if not best:
        return []

    lines = candidate_to_nutsty_lines(best)
    if lines:
        with _MEMORY_CACHE_LOCK:
            _MEMORY_LYRICS_CACHE[cache_key] = {"lines": lines, "timestamp": now}
    return lines

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: multi_lyrics_resolver.py <title> [artist] [videoId] [duration_sec]")
        sys.exit(0)

    t_arg = sys.argv[1]
    a_arg = sys.argv[2] if len(sys.argv) > 2 else ""
    v_arg = sys.argv[3] if len(sys.argv) > 3 else ""
    d_arg = float(sys.argv[4]) if len(sys.argv) > 4 and sys.argv[4] else None

    t0 = time.time()
    res = resolve_lyrics_parallel(t_arg, a_arg, v_arg, d_arg)
    elapsed = time.time() - t0
    sys.stderr.write(f"[multi_lyrics_resolver]: Resolved {len(res)} lines from {res[0].get('source') if res else 'None'} in {elapsed:.2f}s\n")
    print(json.dumps(res, ensure_ascii=False))
