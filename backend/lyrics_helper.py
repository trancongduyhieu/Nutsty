#!/usr/bin/env python3
"""
Nutsty Synced Lyrics Helper — 7-Tier Pipeline
Priority (highest → lowest):
  0. Local SQLite DB (SimpMusic exported — has rich syllable timestamps)
  1. Local .lrc file next to audio file
  2. Persistent .lrc cache (~/.cache/nutsty/lyrics/)
  3. BetterLyrics TTML (lyrics-api.boidu.dev) — Apple Music WORD-LEVEL, best quality
  4. Spotify spclient (sp_dc cookie) — word-level, requires user cookie
  5. LRCLIB /api/get with duration-matched query — precise line sync, no drift
  6. NetEase / syncedlyrics fallback (may have rich-sync tags)
  7. YouTube Music InnerTube plain lyrics (last resort, unsynced)

isSynthetic flag: lines from plain LRC (no <mm:ss.xx> word tags) are marked
isSynthetic=True so QML renders Full-Line Solid Highlight instead of WordFlow.
"""
import sys
import json
import os
import re
import html
import sqlite3
import urllib.request
import urllib.parse
import urllib.error
import time
import hmac
import hashlib
import struct
import base64

# Ensure backend directory is in sys.path
backend_dir = os.path.dirname(os.path.abspath(__file__))
if backend_dir not in sys.path:
    sys.path.insert(0, backend_dir)

import platform_compat as pc
pc.configure_windows_ssl()

CACHE_DIR = os.path.join(pc.get_cache_dir(), "lyrics")
def _get_settings_path():
    prof_suffix = pc.get_profile_suffix() if hasattr(pc, "get_profile_suffix") else ""
    return os.path.join(pc.get_config_dir(), f"nutsty_settings{prof_suffix}.json")

def _load_settings():
    try:
        p = _get_settings_path()
        if not os.path.exists(p):
            p = os.path.join(pc.get_config_dir(), "nutsty_settings.json")
        with open(p, "r", encoding="utf-8") as f:
            return json.load(f)
    except Exception:
        return {}

def get_spotify_spdc():
    """Return sp_dc cookie string from nutsty_settings.json, or empty string."""
    return _load_settings().get("spotifySpdc", "").strip()

def get_lyrics_source_preference():
    """Return user's preferred lyrics source: 'auto' (default), 'spotify', 'betterlyrics', 'lrclib', 'netease'."""
    return _load_settings().get("lyricsSource", "auto").strip().lower()

def get_spotify_session_info(spdc):
    """Fetch Spotify session info (account type, country) using sp_dc cookie."""
    if not spdc:
        return {"isAnonymous": True, "isPremium": False}
    try:
        import base64
        url = "https://open.spotify.com/"
        req = urllib.request.Request(url, headers={
            "Cookie": f"sp_dc={spdc}",
            "User-Agent": "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
            "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
        })
        with urllib.request.urlopen(req, timeout=8) as r:
            html = r.read().decode("utf-8", errors="ignore")
        m = re.search(r'<script[^>]*id="appServerConfig"[^>]*>(.*?)</script>', html)
        if m:
            raw = m.group(1).strip()
            pad = len(raw) % 4
            if pad:
                raw += "=" * (4 - pad)
            conf = json.loads(base64.b64decode(raw).decode("utf-8"))
            return {
                "isAnonymous": conf.get("isAnonymous", False),
                "isPremium": conf.get("isPremium", False),
                "userCountry": conf.get("userCountry", ""),
            }
    except Exception:
        pass
    return {"isAnonymous": False, "isPremium": False}

def _decrypt_aes_gcm_win(key: bytes, iv: bytes, ciphertext_with_tag: bytes) -> bytes:
    try:
        import ctypes, ctypes.wintypes
        bcrypt = ctypes.windll.bcrypt
        BCRYPT_CHAINING_MODE = 'ChainingMode'
        BCRYPT_CHAIN_MODE_GCM = 'ChainingModeGCM'

        class BCRYPT_AUTHENTICATED_CIPHER_MODE_INFO(ctypes.Structure):
            _fields_ = [
                ('cbSize', ctypes.wintypes.ULONG),
                ('dwInfoVersion', ctypes.wintypes.ULONG),
                ('pbNonce', ctypes.c_void_p),
                ('cbNonce', ctypes.wintypes.ULONG),
                ('pbAuthData', ctypes.c_void_p),
                ('cbAuthData', ctypes.wintypes.ULONG),
                ('pbTag', ctypes.c_void_p),
                ('cbTag', ctypes.wintypes.ULONG),
                ('pbMacContext', ctypes.c_void_p),
                ('cbMacContext', ctypes.wintypes.ULONG),
                ('cbAAD', ctypes.wintypes.ULONG),
                ('cbData', ctypes.wintypes.LARGE_INTEGER),
                ('dwFlags', ctypes.wintypes.ULONG),
            ]

        hAlg = ctypes.c_void_p()
        status = bcrypt.BCryptOpenAlgorithmProvider(ctypes.byref(hAlg), 'AES', None, 0)
        if status != 0:
            return b""
        try:
            chain_mode = BCRYPT_CHAIN_MODE_GCM.encode('utf-16le') + b'\x00\x00'
            chain_prop = BCRYPT_CHAINING_MODE.encode('utf-16le') + b'\x00\x00'
            bcrypt.BCryptSetProperty(hAlg, chain_prop, chain_mode, len(chain_mode), 0)
            hKey = ctypes.c_void_p()
            status = bcrypt.BCryptGenerateSymmetricKey(hAlg, ctypes.byref(hKey), None, 0, key, len(key), 0)
            if status != 0:
                return b""
            try:
                tag = ciphertext_with_tag[-16:]
                ct = ciphertext_with_tag[:-16]
                auth_info = BCRYPT_AUTHENTICATED_CIPHER_MODE_INFO()
                auth_info.cbSize = ctypes.sizeof(auth_info)
                auth_info.dwInfoVersion = 1
                auth_info.pbNonce = ctypes.cast(iv, ctypes.c_void_p)
                auth_info.cbNonce = len(iv)
                auth_info.pbTag = ctypes.cast(tag, ctypes.c_void_p)
                auth_info.cbTag = len(tag)
                cbPlain = ctypes.wintypes.ULONG()
                status = bcrypt.BCryptDecrypt(hKey, ct, len(ct), ctypes.byref(auth_info), None, 0, None, 0, ctypes.byref(cbPlain), 0)
                if status != 0:
                    return b""
                plain = ctypes.create_string_buffer(cbPlain.value)
                cbResult = ctypes.wintypes.ULONG()
                status = bcrypt.BCryptDecrypt(hKey, ct, len(ct), ctypes.byref(auth_info), None, 0, plain, len(plain), ctypes.byref(cbResult), 0)
                if status != 0:
                    return b""
                return plain.raw[:cbResult.value]
            finally:
                bcrypt.BCryptDestroyKey(hKey)
        finally:
            bcrypt.BCryptCloseAlgorithmProvider(hAlg, 0)
    except Exception:
        return b""

def extract_spotify_cookie_from_browsers():
    """
    Auto-detect and extract sp_dc cookie from all installed browsers
    (Edge, Chrome, Brave, Opera, Opera GX, Vivaldi, CocCoc, Firefox) across Linux and Windows.
    """
    import glob, shutil, tempfile

    # 1. Firefox
    if sys.platform == "win32":
        ff_patterns = [
            os.path.expandvars(r"%APPDATA%\Mozilla\Firefox\Profiles\*\cookies.sqlite"),
            os.path.expandvars(r"%LOCALAPPDATA%\Mozilla\Firefox\Profiles\*\cookies.sqlite")
        ]
    else:
        ff_patterns = [
            os.path.expanduser("~/.mozilla/firefox/*/cookies.sqlite"),
            os.path.expanduser("~/.var/app/org.mozilla.firefox/.mozilla/firefox/*/cookies.sqlite")
        ]

    for pat in ff_patterns:
        for p in glob.glob(pat):
            try:
                with tempfile.NamedTemporaryFile(suffix=".sqlite", delete=False) as tmp:
                    tmp_path = tmp.name
                shutil.copy2(p, tmp_path)
                conn = sqlite3.connect(tmp_path)
                cur = conn.cursor()
                cur.execute("SELECT value FROM moz_cookies WHERE name='sp_dc' AND (host LIKE '%spotify.com%' OR host LIKE '%spotify%')")
                row = cur.fetchone()
                conn.close()
                try: os.remove(tmp_path)
                except Exception: pass
                if row and row[0]:
                    val = str(row[0]).strip()
                    if len(val) > 20:
                        sess = get_spotify_session_info(val)
                        return {"success": True, "browser": "Firefox", "spdc": val, "session": sess}
            except Exception:
                pass

    # 2. Chromium-based browsers
    candidates = []
    nutsty_profile_dir = os.path.join(pc.get_config_dir(), "browser_auth")
    nutsty_spotify_dir = os.path.join(pc.get_config_dir(), "browser_spotify")
    if sys.platform == "win32":
        candidates = [
            ("Nutsty Spotify Profile", nutsty_spotify_dir),
            ("Nutsty Browser Profile", nutsty_profile_dir),
            ("Edge", os.path.expandvars(r"%LOCALAPPDATA%\Microsoft\Edge\User Data")),
            ("Chrome", os.path.expandvars(r"%LOCALAPPDATA%\Google\Chrome\User Data")),
            ("Brave", os.path.expandvars(r"%LOCALAPPDATA%\BraveSoftware\Brave-Browser\User Data")),
            ("Opera", os.path.expandvars(r"%APPDATA%\Opera Software\Opera Stable")),
            ("Opera GX", os.path.expandvars(r"%APPDATA%\Opera Software\Opera GX Stable")),
            ("Vivaldi", os.path.expandvars(r"%LOCALAPPDATA%\Vivaldi\User Data")),
            ("CocCoc", os.path.expandvars(r"%LOCALAPPDATA%\CocCoc\Browser\User Data")),
        ]
    else:
        candidates = [
            ("Nutsty Spotify Profile", nutsty_spotify_dir),
            ("Nutsty Browser Profile", nutsty_profile_dir),
            ("Chrome", os.path.expanduser("~/.config/google-chrome"), "google-chrome"),
            ("Chromium", os.path.expanduser("~/.config/chromium"), "chromium"),
            ("Brave", os.path.expanduser("~/.config/BraveSoftware/Brave-Browser"), "brave"),
            ("Edge", os.path.expanduser("~/.config/microsoft-edge"), "microsoft-edge"),
            ("Opera", os.path.expanduser("~/.config/opera"), "opera"),
            ("Vivaldi", os.path.expanduser("~/.config/vivaldi"), "vivaldi"),
        ]

    for item in candidates:
        b_name = item[0]
        u_dir = item[1]
        app_key = item[2] if len(item) > 2 else ""

        if not os.path.exists(u_dir):
            continue

        master_key = None
        if sys.platform == "win32":
            ls_path = os.path.join(u_dir, "Local State")
            if os.path.exists(ls_path):
                try:
                    import ctypes, ctypes.wintypes
                    with open(ls_path, "r", encoding="utf-8") as f:
                        ls = json.load(f)
                    enc_key = base64.b64decode(ls["os_crypt"]["encrypted_key"])
                    enc_key = enc_key[5:]
                    class DATA_BLOB(ctypes.Structure):
                        _fields_ = [("cbData", ctypes.wintypes.DWORD), ("pbData", ctypes.POINTER(ctypes.c_char))]
                    b_in = DATA_BLOB(len(enc_key), ctypes.cast(ctypes.create_string_buffer(enc_key), ctypes.POINTER(ctypes.c_char)))
                    b_out = DATA_BLOB()
                    if ctypes.windll.crypt32.CryptUnprotectData(ctypes.byref(b_in), None, None, None, None, 0, ctypes.byref(b_out)):
                        master_key = ctypes.string_at(b_out.pbData, b_out.cbData)
                except Exception:
                    pass
        else:
            import hashlib
            pwd = ""
            if app_key:
                try:
                    import subprocess
                    r = subprocess.run(["secret-tool", "lookup", "application", app_key], capture_output=True, text=True, timeout=1)
                    if r.returncode == 0 and r.stdout.strip():
                        pwd = r.stdout.strip()
                except Exception:
                    pass
            if not pwd:
                pwd = "peanuts"
            master_key = hashlib.pbkdf2_hmac("sha1", pwd.encode("utf-8"), b"saltysalt", 1, 16)

        profiles = ["Default", "Profile 1", "Profile 2", "Profile 3", "Profile 4", "."]
        for prof in profiles:
            c_path = os.path.join(u_dir, prof, "Network", "Cookies")
            if not os.path.exists(c_path):
                c_path = os.path.join(u_dir, prof, "Cookies")
            if not os.path.exists(c_path):
                continue

            try:
                with tempfile.NamedTemporaryFile(suffix=".sqlite", delete=False) as tmp:
                    tmp_p = tmp.name
                shutil.copy2(c_path, tmp_p)
                conn = sqlite3.connect(tmp_p)
                cur = conn.cursor()
                cur.execute(
                    "SELECT name, encrypted_value FROM cookies "
                    "WHERE (host_key LIKE '%spotify%' OR host_key LIKE '%.spotify.com') "
                    "AND name = 'sp_dc'"
                )
                rows = cur.fetchall()
                conn.close()
                try: os.remove(tmp_p)
                except Exception: pass

                if not rows:
                    continue

                for rname, enc in rows:
                    if not enc:
                        continue
                    dec_val = ""
                    if sys.platform == "win32":
                        if enc.startswith(b"v10") or enc.startswith(b"v11"):
                            try:
                                raw_bytes = _decrypt_aes_gcm_win(master_key, enc[3:15], enc[15:])
                                if raw_bytes:
                                    dec_val = raw_bytes.decode("utf-8", errors="ignore")
                            except Exception:
                                pass
                            if not dec_val:
                                try:
                                    from cryptography.hazmat.primitives.ciphers.aead import AESGCM
                                    aesgcm = AESGCM(master_key)
                                    dec_val = aesgcm.decrypt(enc[3:15], enc[15:], None).decode("utf-8", errors="ignore")
                                except Exception:
                                    try:
                                        from Crypto.Cipher import AES
                                        dec_val = AES.new(master_key, AES.MODE_GCM, enc[3:15]).decrypt(enc[15:])[:-16].decode("utf-8", errors="ignore")
                                    except Exception:
                                        pass
                        else:
                            try:
                                import ctypes, ctypes.wintypes
                                class DATA_BLOB(ctypes.Structure):
                                    _fields_ = [("cbData", ctypes.wintypes.DWORD), ("pbData", ctypes.POINTER(ctypes.c_char))]
                                b_in = DATA_BLOB(len(enc), ctypes.cast(ctypes.create_string_buffer(enc), ctypes.POINTER(ctypes.c_char)))
                                b_out = DATA_BLOB()
                                if ctypes.windll.crypt32.CryptUnprotectData(ctypes.byref(b_in), None, None, None, None, 0, ctypes.byref(b_out)):
                                    dec_val = ctypes.string_at(b_out.pbData, b_out.cbData).decode("utf-8", errors="ignore")
                            except Exception:
                                pass
                    else:
                        try:
                            from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes
                            from cryptography.hazmat.backends import default_backend
                            c = Cipher(algorithms.AES(master_key), modes.CBC(b" " * 16), backend=default_backend())
                            dec = c.decryptor().update(enc[3:]) + c.decryptor().finalize()
                            pad = dec[-1]
                            dec = dec[:-pad]
                            dec_val = dec[32:].decode("utf-8", errors="ignore") if enc.startswith(b"v11") else dec.decode("utf-8", errors="ignore")
                        except Exception:
                            pass

                    dec_val = (dec_val or "").strip()
                    if dec_val and len(dec_val) > 20:
                        sess = get_spotify_session_info(dec_val)
                        return {"success": True, "browser": b_name, "spdc": dec_val, "session": sess}
            except Exception:
                continue

    return {"success": False, "message": "Không tìm thấy cookie Spotify trong các trình duyệt đã cài đặt."}

# ──────────────────────────────────────────────────────────────────────────────
# Filename / cache utilities
# ──────────────────────────────────────────────────────────────────────────────

def sanitize_filename(name):
    if not name:
        return ""
    return re.sub(r'[\\/*?:"<>|]', "", name).strip()

def get_cache_path(title, artist=None):
    os.makedirs(CACHE_DIR, exist_ok=True)
    clean_t = sanitize_filename(title)
    clean_a = sanitize_filename(artist) if artist else ""
    filename = f"{clean_a} - {clean_t}.lrc" if clean_a else f"{clean_t}.lrc"
    return os.path.join(CACHE_DIR, filename)

def clean_search_title(title):
    if not title:
        return ""
    t = re.sub(r'\[.*?\]|\(.*?\)|\|.*?$', '', title)
    t = re.sub(r'\b(official\s+video|official\s+audio|lyric\s+video|mv|vietsub)\b', '', t, flags=re.IGNORECASE)
    t = re.sub(r'\s+', ' ', t).strip()
    return t or title

# ──────────────────────────────────────────────────────────────────────────────
# LRC / Rich-sync parsers
# ──────────────────────────────────────────────────────────────────────────────

def strip_rich_sync_tags(text):
    if not text:
        return ""
    t = re.sub(r'<[0-9:.]+>', ' ', text)
    t = html.unescape(t)
    return re.sub(r'\s+', ' ', t).strip()

def parse_rich_sync_words(line_str, default_start=0.0):
    """Parse <mm:ss.xx> word timestamps embedded in a LRC line."""
    if not line_str or "<" not in line_str or ">" not in line_str:
        return []
    pattern = re.compile(r'<(\d{1,2}):(\d{1,2}(?:\.\d+)?)>\s*([^<]*)')
    matches = list(pattern.finditer(line_str))
    if not matches:
        return []
    words = []
    for i, m in enumerate(matches):
        mins, secs = int(m.group(1)), float(m.group(2))
        start_t = round(mins * 60.0 + secs, 3)
        txt = html.unescape(m.group(3).strip())
        if not txt:
            continue
        if i + 1 < len(matches):
            nm = matches[i + 1]
            end_t = round(int(nm.group(1)) * 60.0 + float(nm.group(2)), 3)
        else:
            end_t = round(start_t + 0.5, 3)
        dur = max(0.08, round(end_t - start_t, 3))
        words.append({
            "text": txt,
            "start": start_t,
            "end": end_t,
            "duration": dur,
            "isHeld": dur >= 0.85,
        })
    return words

def parse_lrc(lrc_text):
    """Parse LRC text → list of lyric line dicts.
    Lines with <mm:ss.xx> tags get hasWords=True (real syllable data).
    Plain lines get hasWords=False + isSynthetic=True → Full-Line Highlight in QML.
    """
    if not lrc_text:
        return []
    results = []
    time_regex = re.compile(r'\[(\d{1,2}):(\d{1,2}(?:\.\d+)?)\]')

    for line in lrc_text.splitlines():
        line = line.strip()
        if not line:
            continue
        if re.match(r'^\[[a-zA-Z]+:', line):
            continue
        matches = list(time_regex.finditer(line))
        if not matches:
            continue
        last_match = matches[-1]
        raw_text = line[last_match.end():].strip()
        # Filter music note placeholders
        clean_text = strip_rich_sync_tags(raw_text)
        if not clean_text or clean_text in ("♪", "♫", "🎵"):
            continue
        syllable_words = parse_rich_sync_words(raw_text)
        for m in matches:
            mins, secs = int(m.group(1)), float(m.group(2))
            total_sec = round(mins * 60.0 + secs, 3)
            end_sec = max((w["end"] for w in syllable_words), default=None)
            results.append({
                "time": total_sec,
                "endTime": end_sec if end_sec is not None else round(total_sec + 4.5, 3),
                "text": clean_text,
                "hasWords": bool(syllable_words),
                "isSynthetic": not bool(syllable_words),
                "words": syllable_words,
            })
    results.sort(key=lambda x: x["time"])

    # Fill in endTime for lines without syllable timestamps
    for i, it in enumerate(results):
        if not it.get("hasWords"):
            if i + 1 < len(results):
                it["endTime"] = results[i + 1]["time"]
            else:
                it["endTime"] = round(it["time"] + 5.0, 3)
    return results

# ──────────────────────────────────────────────────────────────────────────────
# TTML parser (Apple Music word-level via BetterLyrics)
# ──────────────────────────────────────────────────────────────────────────────

def _parse_ttml_time(t):
    """Parse TTML time '1:23.456' or '83.456' → float seconds."""
    t = t.strip()
    parts = t.split(":")
    if len(parts) == 3:
        h, m, s = parts
        return int(h) * 3600 + int(m) * 60 + float(s)
    elif len(parts) == 2:
        m, s = parts
        return int(m) * 60 + float(s)
    else:
        return float(t)

def parse_ttml(ttml_str):
    """Convert Apple Music TTML → Nutsty lyric line list with real word timestamps."""
    if not ttml_str:
        return []

    p_re = re.compile(
        r'<p\s[^>]*begin="([^"]+)"[^>]*end="([^"]+)"[^>]*>([\s\S]*?)</p>'
    )
    span_re = re.compile(
        r'<span\s[^>]*begin="([^"]+)"[^>]*end="([^"]+)"[^>]*>(.*?)</span>'
    )

    results = []
    for pm in p_re.finditer(ttml_str):
        line_start = round(_parse_ttml_time(pm.group(1)), 3)
        line_end   = round(_parse_ttml_time(pm.group(2)), 3)
        inner      = pm.group(3)

        spans = span_re.findall(inner)
        if spans:
            words = []
            for sp_begin, sp_end, sp_text in spans:
                sp_text = html.unescape(sp_text.strip())
                if not sp_text:
                    continue
                start = round(_parse_ttml_time(sp_begin), 3)
                end   = round(_parse_ttml_time(sp_end), 3)
                dur   = max(0.08, round(end - start, 3))
                words.append({
                    "text": sp_text,
                    "start": start,
                    "end": end,
                    "duration": dur,
                    "isHeld": dur >= 0.85,
                })
            if words:
                plain = " ".join(w["text"] for w in words)
                results.append({
                    "time": line_start,
                    "endTime": line_end,
                    "text": plain,
                    "hasWords": True,
                    "isSynthetic": False,
                    "words": words,
                })
        else:
            plain = html.unescape(re.sub(r'<[^>]+>', '', inner).strip())
            if plain:
                results.append({
                    "time": line_start,
                    "endTime": line_end,
                    "text": plain,
                    "hasWords": False,
                    "isSynthetic": True,
                    "words": [],
                })

    results.sort(key=lambda x: x["time"])
    return results

# ──────────────────────────────────────────────────────────────────────────────
# Spotify word-level parser (color-lyrics JSON)
# ──────────────────────────────────────────────────────────────────────────────

def parse_spotify_lyrics(data):
    """Convert Spotify color-lyrics v2 JSON → Nutsty line list."""
    try:
        lines_raw = data["lyrics"]["lines"]
    except (KeyError, TypeError):
        return []

    sync_type = data.get("lyrics", {}).get("syncType", "")
    is_line_synced = sync_type == "LINE_SYNCED"

    results = []
    for i, line in enumerate(lines_raw):
        start_ms = int(line.get("startTimeMs", 0))
        start_sec = round(start_ms / 1000.0, 3)
        raw_words = line.get("words", "")

        # endTime: use next line start or +5s
        if i + 1 < len(lines_raw):
            next_ms = int(lines_raw[i + 1].get("startTimeMs", 0))
            end_sec = round(next_ms / 1000.0, 3)
        else:
            end_sec = round(start_sec + 5.0, 3)

        # Spotify LINE_SYNCED → no word timing
        if is_line_synced or not raw_words or "<" not in raw_words:
            clean = html.unescape(raw_words.strip()) if raw_words else ""
            if not clean:
                continue
            results.append({
                "time": start_sec,
                "endTime": end_sec,
                "text": clean,
                "hasWords": False,
                "isSynthetic": True,
                "words": [],
            })
        else:
            # RICH_SYNCED: Spotify embeds <mm:ss.xx>word format
            syllable_words = parse_rich_sync_words(raw_words, default_start=start_sec)
            clean = strip_rich_sync_tags(raw_words)
            if not clean:
                continue
            results.append({
                "time": start_sec,
                "endTime": end_sec,
                "text": clean,
                "hasWords": bool(syllable_words),
                "isSynthetic": not bool(syllable_words),
                "words": syllable_words,
            })

    return results

# ──────────────────────────────────────────────────────────────────────────────
# HTTP helper (no external deps beyond stdlib)
# ──────────────────────────────────────────────────────────────────────────────

def _http_get(url, headers=None, timeout=8):
    """Simple HTTP GET, returns response body as str or None on error."""
    h = {"User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36"}
    if headers:
        h.update(headers)
    req = urllib.request.Request(url, headers=h)
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            return r.read().decode("utf-8", errors="replace")
    except Exception as e:
        sys.stderr.write(f"[http_get {url[:60]}]: {e}\n")
        return None

# ──────────────────────────────────────────────────────────────────────────────
# TẦNG 2.5: SimpMusic Cloud API (YouTube Video ID — rich-sync syllable-level)
# ──────────────────────────────────────────────────────────────────────────────

def fetch_simpmusic_lyrics(video_id):
    """
    Fetch rich-sync syllable lyrics from api-lyrics.simpmusic.org/v1/{video_id}.
    Returns parsed lyric line dicts with real syllables (hasWords=True) if available,
    or line-synced lyrics if available, or [].
    """
    if not video_id:
        return []
    clean_vid = str(video_id).replace("ytdl://", "").replace("yt_", "").strip()
    if not clean_vid or len(clean_vid) < 5:
        return []
    url = f"https://api-lyrics.simpmusic.org/v1/{clean_vid}"
    body = _http_get(url, headers={"User-Agent": "SimpMusicLyrics/1.0"}, timeout=6)
    if not body:
        return []
    try:
        data = json.loads(body)
        items = data.get("data", [])
        if not items:
            return []
        item = items[0]
        rich_sync = item.get("richSyncLyrics", "")
        if rich_sync:
            parsed = parse_lrc(rich_sync)
            if parsed and _has_real_syllables(parsed):
                return parsed
        synced = item.get("syncedLyrics", "")
        if synced:
            parsed = parse_lrc(synced)
            if parsed:
                return parsed
        plain = item.get("plainLyric", "")
        if plain:
            lines = [html.unescape(l.strip()) for l in plain.splitlines() if l.strip()]
            if lines:
                return [{
                    "time": idx * 3.5,
                    "endTime": idx * 3.5 + 3.5,
                    "text": line,
                    "hasWords": False,
                    "isSynthetic": True,
                    "words": [],
                } for idx, line in enumerate(lines)]
        return []
    except Exception as e:
        sys.stderr.write(f"[SimpMusic lyrics error]: {e}\n")
        return []

# ──────────────────────────────────────────────────────────────────────────────
# TẦNG 3: BetterLyrics TTML (Apple Music word-level)
# ──────────────────────────────────────────────────────────────────────────────

def fetch_betterlyrics_ttml(title, artist, duration_sec=None):
    """
    Fetch TTML from lyrics-api.boidu.dev — Apple Music internal TTML with
    per-span word timestamps. Best quality source after local DB.
    """
    params = {"s": title, "a": artist or ""}
    if duration_sec and duration_sec > 0:
        params["d"] = int(duration_sec)
    url = "https://lyrics-api.boidu.dev/getLyrics?" + urllib.parse.urlencode(params)
    body = _http_get(url, timeout=10)
    if not body:
        return []
    try:
        data = json.loads(body)
        ttml = data.get("ttml", "")
        if not ttml:
            return []
        parsed = parse_ttml(ttml)
        return parsed if parsed else []
    except Exception as e:
        sys.stderr.write(f"[BetterLyrics parse error]: {e}\n")
        return []

# ──────────────────────────────────────────────────────────────────────────────
# TẦNG 4: Spotify spclient (sp_dc cookie) — word-level & TOTP token
# ──────────────────────────────────────────────────────────────────────────────

_SPOTIFY_TOKEN_CACHE = {"token": "", "expires_at": 0}
_SPOTIFY_SECRETS_CACHE = {"secrets": None, "fetched_at": 0}

def get_spotify_access_token(spdc=None):
    """Exchange sp_dc cookie for a valid Spotify personal access token via TOTP."""
    global _SPOTIFY_TOKEN_CACHE, _SPOTIFY_SECRETS_CACHE
    if not spdc:
        spdc = get_spotify_spdc()
    if not spdc:
        return ""

    now = time.time()
    if _SPOTIFY_TOKEN_CACHE["token"] and (now < _SPOTIFY_TOKEN_CACHE["expires_at"] - 60):
        return _SPOTIFY_TOKEN_CACHE["token"]

    try:
        # 1. Fetch latest secret dict from xyloflake/spot-secrets-go
        secrets = None
        if _SPOTIFY_SECRETS_CACHE["secrets"] and (now - _SPOTIFY_SECRETS_CACHE["fetched_at"] < 86400):
            secrets = _SPOTIFY_SECRETS_CACHE["secrets"]
        else:
            sec_url = "https://raw.githubusercontent.com/xyloflake/spot-secrets-go/refs/heads/main/secrets/secretDict.json"
            sec_body = _http_get(sec_url, timeout=5)
            if sec_body:
                secrets = json.loads(sec_body)
                _SPOTIFY_SECRETS_CACHE = {"secrets": secrets, "fetched_at": now}

        if secrets:
            version_str, cipher_bytes = list(secrets.items())[-1]
            version = int(version_str)
        else:
            version = 61
            cipher_bytes = [44,55,47,42,70,40,34,114,76,74,50,111,120,97,75,76,94,102,43,69,49,120,118,80,64,78]

        # 2. Transform bytes to base32 secret
        transformed = [b ^ ((i % 33) + 9) for i, b in enumerate(cipher_bytes)]
        joined = "".join(str(x) for x in transformed)
        raw_bytes = bytes.fromhex(joined.encode("utf-8").hex())
        b32 = base64.b32encode(raw_bytes).decode("ascii").rstrip("=")

        # 3. Get server time from Spotify
        time_url = "https://open.spotify.com/api/server-time"
        time_body = _http_get(time_url, headers={
            "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36",
            "Cookie": f"sp_dc={spdc}",
        }, timeout=5)
        if time_body:
            server_time = json.loads(time_body).get("serverTime", int(now))
        else:
            server_time = int(now)

        # 4. Generate TOTP code
        pad_len = (8 - len(b32) % 8) % 8
        key = base64.b32decode(b32 + "=" * pad_len)
        counter = struct.pack(">Q", int(server_time) // 30)
        h = hmac.new(key, counter, hashlib.sha1).digest()
        offset = h[-1] & 0x0f
        code = ((struct.unpack(">I", h[offset:offset+4])[0] & 0x7fffffff) % 1000000)
        otp = f"{code:06d}"

        # 5. Request access token
        params = urllib.parse.urlencode({
            "reason": "transport",
            "productType": "mobile-web-player",
            "totp": otp,
            "totpServer": otp,
            "totpVer": version,
        })
        token_url = f"https://open.spotify.com/api/token?{params}"
        token_body = _http_get(token_url, headers={
            "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36",
            "Cookie": f"sp_dc={spdc}",
            "Accept": "application/json",
            "Origin": "https://open.spotify.com",
            "Referer": "https://open.spotify.com/",
        }, timeout=6)

        if token_body:
            data = json.loads(token_body)
            acc_tok = data.get("accessToken", "")
            exp_ms = data.get("accessTokenExpirationTimestampMs", (now + 3600) * 1000)
            if acc_tok:
                _SPOTIFY_TOKEN_CACHE = {"token": acc_tok, "expires_at": exp_ms / 1000}
                return acc_tok
    except Exception as e:
        sys.stderr.write(f"[Spotify get_spotify_access_token error]: {e}\n")

    return ""

def _spotify_get_client_token():
    """Get anonymous Spotify client token (no sp_dc needed)."""
    import json as _json
    body = _json.dumps({
        "client_data": {
            "client_version": "1.2.61.20.g3b4cd5b2",
            "client_id": "d8a5ed958d274c2e8ee717e6a4b0971d",
            "js_sdk_data": {
                "device_brand": "Apple",
                "device_model": "MacBookPro",
                "os": "macos",
                "os_version": "14.4",
            }
        }
    }).encode("utf-8")
    req = urllib.request.Request(
        "https://clienttoken.spotify.com/v1/clienttoken",
        data=body,
        headers={
            "Content-Type": "application/json",
            "Accept": "application/json",
            "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 Chrome/135.0.0.0 Safari/537.36",
        },
        method="POST"
    )
    try:
        with urllib.request.urlopen(req, timeout=6) as r:
            d = json.loads(r.read().decode())
            return d.get("granted_token", {}).get("token", "")
    except Exception as e:
        sys.stderr.write(f"[Spotify client token error]: {e}\n")
        return ""

def _spotify_get_personal_token(spdc):
    """Exchange sp_dc cookie for a personal access token via TOTP."""
    return get_spotify_access_token(spdc)

def _spotify_search_track(query, access_token, client_token, duration_sec=None):
    """Search Spotify for a track, return trackId string or ''."""
    sha = "bc1ca2fcd0ba1013a0fc88e6cc4f190af501851e3dafd3e1ef85840297694428"
    variable = json.dumps({
        "searchTerm": query, "offset": 0, "limit": 5,
        "numberOfTopResults": 5, "includeAudiobooks": True, "includePreReleases": False
    })
    params = urllib.parse.urlencode({
        "operationName": "searchTracks",
        "variables": variable,
        "extensions": json.dumps({"persistedQuery": {"version": 1, "sha256Hash": sha}})
    })
    url = f"https://api-partner.spotify.com/pathfinder/v1/query?{params}"
    body = _http_get(url, headers={
        "Authorization": f"Bearer {access_token}",
        "Client-Token": client_token,
        "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 Chrome/135.0.0.0 Safari/537.36",
    }, timeout=8)
    if not body:
        return ""
    try:
        data = json.loads(body)
        items = data["data"]["searchV2"]["tracksV2"]["items"]
        if not items:
            return ""
        # Try to find best duration match if duration_sec provided
        if duration_sec and duration_sec > 0:
            for item in items:
                dur_ms = item.get("item", {}).get("data", {}).get("duration", {}).get("totalMilliseconds", 0)
                if abs(dur_ms / 1000 - duration_sec) <= 12:
                    uri = item["item"]["data"]["uri"]
                    return uri.split(":")[-1]
        # Fall back to first result
        uri = items[0]["item"]["data"]["uri"]
        return uri.split(":")[-1]
    except Exception as e:
        sys.stderr.write(f"[Spotify search parse error]: {e}\n")
        return ""

def _spotify_get_lyrics(track_id, access_token, client_token):
    """Fetch lyrics from Spotify spclient."""
    url = f"https://spclient.wg.spotify.com/color-lyrics/v2/track/{track_id}?format=json&vocalRemoval=false&market=from_token"
    body = _http_get(url, headers={
        "Authorization": f"Bearer {access_token}",
        "Client-Token": client_token,
        "App-platform": "WebPlayer",
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/74.0.3729.157 Safari/537.36",
    }, timeout=8)
    if not body:
        return []
    try:
        return parse_spotify_lyrics(json.loads(body))
    except Exception as e:
        sys.stderr.write(f"[Spotify lyrics parse error]: {e}\n")
        return []

def fetch_spotify_lyrics(title, artist, duration_sec=None):
    """Full Spotify lyrics fetch flow. Returns [] if sp_dc not configured."""
    spdc = get_spotify_spdc()
    if not spdc:
        return []

    access_token = _spotify_get_personal_token(spdc)
    if not access_token:
        sys.stderr.write("[Spotify] Could not get personal token from sp_dc\n")
        return []

    client_token = _spotify_get_client_token()
    if not client_token:
        sys.stderr.write("[Spotify] Could not get client token\n")
        return []

    cleaned = clean_search_title(title)
    query = f"{cleaned} {artist}".strip() if artist else cleaned
    # Sanitize query the same way SimpMusic does
    query = re.sub(r'\((feat\.|ft\.) ', ' ', query)
    query = re.sub(r'( và | & | и | e | und |, |和| dan)', ' ', query)
    query = re.sub(r'[()]', '', query).replace('.', ' ')
    query = re.sub(r'\s+', ' ', query).strip()

    track_id = _spotify_search_track(query, access_token, client_token, duration_sec)
    if not track_id:
        sys.stderr.write(f"[Spotify] Track not found for query: {query}\n")
        return []

    return _spotify_get_lyrics(track_id, access_token, client_token)

# ──────────────────────────────────────────────────────────────────────────────
# TẦNG 5: LRCLIB /api/get with duration matching (precision line sync)
# ──────────────────────────────────────────────────────────────────────────────

def fetch_lrclib(title, artist, duration_sec=None):
    """
    LRCLIB /api/get — duration-matched lookup prevents wrong-version matches.
    Returns parsed lyric list or [].
    """
    cleaned = clean_search_title(title)
    params = {"track_name": cleaned, "artist_name": artist or ""}
    if duration_sec and duration_sec > 0:
        params["duration"] = int(duration_sec)
    url = "https://lrclib.net/api/get?" + urllib.parse.urlencode(params)
    body = _http_get(url, timeout=8)
    if not body:
        return []
    try:
        data = json.loads(body)
        synced = data.get("syncedLyrics", "")
        if synced:
            parsed = parse_lrc(synced)
            if parsed:
                return parsed
        plain = data.get("plainLyrics", "")
        if plain:
            lines = [html.unescape(l.strip()) for l in plain.splitlines() if l.strip()]
            return [{
                "time": i * 3.5, "endTime": i * 3.5 + 3.5,
                "text": l, "hasWords": False, "isSynthetic": True, "words": []
            } for i, l in enumerate(lines)]
    except Exception as e:
        sys.stderr.write(f"[LRCLIB parse error]: {e}\n")
    return []

# ──────────────────────────────────────────────────────────────────────────────
# Local SQLite DB (SimpMusic exported)
# ──────────────────────────────────────────────────────────────────────────────

def get_lyrics_from_local_db(title, artist=None, video_id=None):
    p1 = os.path.join(pc.get_music_dir(), "Nutsty", "extracted", "Music Database")
    p2 = os.path.join(pc.get_music_dir(), "SimpMusic", "extracted", "Music Database")
    db_path = p1 if os.path.exists(p1) else p2
    if not os.path.exists(db_path):
        return []

    try:
        conn = sqlite3.connect(db_path)
        c = conn.cursor()

        raw_lines = None
        if video_id:
            r = c.execute('SELECT lines FROM lyrics WHERE videoId = ?', (video_id,)).fetchone()
            if r and r[0]:
                raw_lines = r[0]

        clean_artist = artist.strip().lower() if artist and artist.strip() else ""
        candidates = [title.strip()]
        cleaned = clean_search_title(title)
        if cleaned and cleaned.lower() != title.strip().lower():
            candidates.append(cleaned)

        if not raw_lines:
            for t_query in candidates:
                if raw_lines:
                    break
                rows = c.execute('''
                    SELECT l.lines, s.artistName, s.title FROM lyrics l
                    JOIN song s ON s.videoId = l.videoId
                    WHERE LOWER(s.title) = LOWER(?) AND l.lines IS NOT NULL AND l.lines != ""
                ''', (t_query,)).fetchall()
                for r_lines, r_art, r_title in rows:
                    if clean_artist:
                        r_art_str = (r_art or "").lower()
                        if clean_artist in r_art_str or r_art_str in clean_artist:
                            raw_lines = r_lines
                            break
                    else:
                        raw_lines = r_lines
                        break

        if not raw_lines:
            return []

        parsed = json.loads(raw_lines)
        results = []
        for line in parsed:
            w = line.get('words', '').strip()
            clean_w = strip_rich_sync_tags(w)
            st = int(line.get('startTimeMs', 0))
            if clean_w:
                start_sec = round(st / 1000.0, 3)
                syllable_words = parse_rich_sync_words(w, default_start=start_sec)
                end_sec = max((item["end"] for item in syllable_words), default=None)
                results.append({
                    'time': start_sec,
                    'endTime': end_sec if end_sec is not None else round(start_sec + 4.5, 3),
                    'text': clean_w,
                    'hasWords': bool(syllable_words),
                    'isSynthetic': not bool(syllable_words),
                    'words': syllable_words,
                })
        for i, it in enumerate(results):
            if not it.get("hasWords"):
                if i + 1 < len(results):
                    it["endTime"] = results[i + 1]["time"]
                else:
                    it["endTime"] = round(it["time"] + 5.0, 3)
                it["words"] = []
                it["isSynthetic"] = True
        return results
    except Exception:
        return []

# ──────────────────────────────────────────────────────────────────────────────
# Main orchestrator
# ──────────────────────────────────────────────────────────────────────────────

def _has_real_syllables(lyric_list):
    """Returns True if any line has genuine word-level timestamps."""
    return lyric_list and any(
        item.get("hasWords") and not item.get("isSynthetic") and item.get("words")
        for item in lyric_list
    )

def _has_synced(lyric_list):
    """Returns True if any line has a real timestamp (not all synthetic/unsynced)."""
    return lyric_list and any(item.get("time", 0) > 0 for item in lyric_list)

def get_lyrics(title, artist=None, video_id=None, file_path=None, duration_sec=None):
    if not title:
        return []

    # ──────────────────────────────────────────────────────────────────────
    # TẦNG 0: Local SQLite (SimpMusic DB — rich syllable)
    # ──────────────────────────────────────────────────────────────────────
    db_lyrics = get_lyrics_from_local_db(title, artist, video_id)
    if _has_real_syllables(db_lyrics):
        return db_lyrics

    # ──────────────────────────────────────────────────────────────────────
    # TẦNG 1: Local .lrc file next to audio
    # ──────────────────────────────────────────────────────────────────────
    if file_path:
        base, _ = os.path.splitext(file_path)
        local_lrc = base + ".lrc"
        if os.path.exists(local_lrc):
            try:
                with open(local_lrc, "r", encoding="utf-8", errors="ignore") as f:
                    res = parse_lrc(f.read())
                    if res:
                        return res
            except Exception:
                pass

    # ──────────────────────────────────────────────────────────────────────
    # TẦNG 2: Persistent .lrc cache
    # ──────────────────────────────────────────────────────────────────────
    cache_paths = []
    if artist and artist.strip():
        cache_paths.append(get_cache_path(title, artist))
    cache_paths.append(get_cache_path(title, None))
    for cp in cache_paths:
        if os.path.exists(cp):
            try:
                with open(cp, "r", encoding="utf-8", errors="ignore") as f:
                    res = parse_lrc(f.read())
                    if res:
                        # Prefer cache only if it has syllable data; otherwise
                        # still try upstream sources for better quality
                        if _has_real_syllables(res):
                            return res
                        cached_plain = res  # save for fallback below
            except Exception:
                pass
    else:
        cached_plain = None

    # ──────────────────────────────────────────────────────────────────────
    # ONLINE PIPELINE: Configurable source preference with fallback
    # Auto order: SimpMusic (video_id syllable) -> BetterLyrics TTML -> Spotify (sp_dc) -> LRCLIB -> NetEase
    # ──────────────────────────────────────────────────────────────────────
    cleaned_title = clean_search_title(title)
    pref = get_lyrics_source_preference()

    def _run_simpmusic():
        vid = video_id
        if not vid:
            try:
                import ytmusic_helper
                q = f"{cleaned_title} {artist}".strip() if artist else cleaned_title
                results = ytmusic_helper.filter_search(q, "songs")
                if results and results[0].get("videoId"):
                    vid = results[0].get("videoId")
            except Exception:
                pass
        if vid:
            res = fetch_simpmusic_lyrics(vid)
            if res:
                _save_lrc_cache_from_lines(res, title, artist)
                return res
        return None

    def _run_spotify():
        if not get_spotify_spdc():
            return None
        res = fetch_spotify_lyrics(cleaned_title, artist, duration_sec)
        if res:
            _save_lrc_cache_from_lines(res, title, artist)
        return res

    def _run_betterlyrics():
        res = fetch_betterlyrics_ttml(cleaned_title, artist, duration_sec)
        if _has_real_syllables(res):
            _save_ttml_as_lrc_cache(res, title, artist)
            return res
        return None

    def _run_lrclib():
        res = fetch_lrclib(cleaned_title, artist, duration_sec)
        if res:
            _save_lrc_cache_from_lines(res, title, artist)
            return res
        return None

    def _run_netease():
        try:
            import syncedlyrics
            queries = []
            if artist and artist.strip() and artist.lower() not in title.lower():
                queries.append(f"{cleaned_title} {artist}".strip())
            queries.append(cleaned_title)
            if cleaned_title != title:
                if artist and artist.strip():
                    queries.append(f"{title} {artist}".strip())
                queries.append(title.strip())

            for q in queries:
                try:
                    lrc = syncedlyrics.search(q, providers=["netease", "lrclib"])
                    if lrc:
                        parsed = parse_lrc(lrc)
                        if parsed:
                            try:
                                with open(get_cache_path(title, artist), "w", encoding="utf-8") as f:
                                    f.write(lrc)
                            except Exception:
                                pass
                            return parsed
                except Exception as e:
                    sys.stderr.write(f"[syncedlyrics '{q}']: {e}\n")
        except ImportError:
            sys.stderr.write("[syncedlyrics not installed]\n")
        return None

    if pref == "spotify":
        sp_res = _run_spotify()
        if sp_res:
            return sp_res
        for fn in [_run_betterlyrics, _run_simpmusic, _run_lrclib, _run_netease]:
            res = fn()
            if res:
                return res
    elif pref == "betterlyrics":
        bl_res = _run_betterlyrics()
        if bl_res:
            return bl_res
        for fn in [_run_simpmusic, _run_spotify, _run_lrclib, _run_netease]:
            res = fn()
            if res:
                return res
    elif pref == "lrclib":
        for fn in [_run_lrclib, _run_simpmusic, _run_spotify, _run_betterlyrics, _run_netease]:
            res = fn()
            if res:
                return res
    elif pref == "netease":
        for fn in [_run_netease, _run_simpmusic, _run_spotify, _run_betterlyrics, _run_lrclib]:
            res = fn()
            if res:
                return res
    else:  # 'auto' default: Pass 1 (Syllables) -> Pass 2 (Line sync)
        # Pass 1: True syllable-level word highlights
        # If user has Spotify cookie configured, check Spotify syllable-level first!
        sp_res = None
        if get_spotify_spdc():
            sp_res = _run_spotify()
            if sp_res and _has_real_syllables(sp_res):
                return sp_res

        # 1a. BetterLyrics (Apple Music TTML word-level)
        bl_res = _run_betterlyrics()
        if bl_res and _has_real_syllables(bl_res):
            return bl_res

        # 1b. SimpMusic API (video_id available or resolved - rich syllable timestamps)
        simp_res = _run_simpmusic()
        if simp_res and _has_real_syllables(simp_res):
            return simp_res

        # Pass 2: Line-synced Fallback (if no provider had real syllables)
        if sp_res and (_has_synced(sp_res) or sp_res):
            return sp_res
        if not sp_res and get_spotify_spdc():
            sp_res = _run_spotify()
            if sp_res and (_has_synced(sp_res) or sp_res):
                return sp_res

        if simp_res and (_has_synced(simp_res) or simp_res):
            return simp_res

        lrc_res = _run_lrclib()
        if lrc_res:
            return lrc_res

        ne_res = _run_netease()
        if ne_res:
            return ne_res

    # Return plain cache if we have it
    if cached_plain:
        return cached_plain

    # ──────────────────────────────────────────────────────────────────────
    # TẦNG 7: YouTube Music InnerTube plain lyrics (last resort)
    # ──────────────────────────────────────────────────────────────────────
    if video_id:
        try:
            import ytmusic_helper
            yt_lyrics = ytmusic_helper.get_youtube_lyrics(video_id)
            if yt_lyrics:
                lines = [l.strip() for l in yt_lyrics.split("\n") if l.strip()]
                if lines:
                    return [{
                        "time": idx * 3.5,
                        "endTime": idx * 3.5 + 3.5,
                        "text": line,
                        "hasWords": False,
                        "isSynthetic": True,
                        "words": [],
                    } for idx, line in enumerate(lines)]
        except Exception as ye:
            sys.stderr.write(f"[YouTube lyrics fallback]: {ye}\n")

    # Final fallback: plain DB lyrics
    return db_lyrics or get_lyrics_from_local_db(title, artist, video_id)

# ──────────────────────────────────────────────────────────────────────────────
# Cache write helpers
# ──────────────────────────────────────────────────────────────────────────────

def _save_ttml_as_lrc_cache(lines, title, artist):
    """Serialize TTML-parsed lines back to a basic LRC for local caching."""
    try:
        out = []
        for ln in lines:
            mm = int(ln["time"] // 60)
            ss = ln["time"] % 60
            if ln.get("words"):
                word_tags = "".join(
                    f"<{int(w['start']//60):02d}:{w['start']%60:05.2f}>{w['text']} "
                    for w in ln["words"]
                ).rstrip()
                out.append(f"[{mm:02d}:{ss:05.2f}]{word_tags}")
            else:
                out.append(f"[{mm:02d}:{ss:05.2f}]{ln['text']}")
        path = get_cache_path(title, artist)
        with open(path, "w", encoding="utf-8") as f:
            f.write("\n".join(out))
    except Exception:
        pass

def _save_lrc_cache_from_lines(lines, title, artist):
    """Save timestamped LRC from parsed line list (preserving rich sync if present)."""
    try:
        out = []
        for ln in lines:
            mm = int(ln["time"] // 60)
            ss = ln["time"] % 60
            if ln.get("words"):
                word_tags = "".join(
                    f"<{int(w['start']//60):02d}:{w['start']%60:05.2f}>{w['text']} "
                    for w in ln["words"]
                ).rstrip()
                out.append(f"[{mm:02d}:{ss:05.2f}]{word_tags}")
            else:
                out.append(f"[{mm:02d}:{ss:05.2f}]{ln['text']}")
        path = get_cache_path(title, artist)
        with open(path, "w", encoding="utf-8") as f:
            f.write("\n".join(out))
    except Exception:
        pass

# ──────────────────────────────────────────────────────────────────────────────
# CLI entrypoints
# ──────────────────────────────────────────────────────────────────────────────

def handle_cli(args):
    """Entry point for thread-safe in-process execution without modifying sys.argv."""
    if len(args) < 1:
        print("[]")
        return
    title_arg  = args[0] if len(args) > 0 else ""
    artist_arg = args[1] if len(args) > 1 and args[1].strip() != "" else None
    vid_arg    = args[2] if len(args) > 2 and args[2].strip() != "" else None
    path_arg   = args[3] if len(args) > 3 and args[3].strip() != "" else None
    dur_arg    = float(args[4]) if len(args) > 4 and args[4].strip() != "" else None

    res = get_lyrics(title_arg, artist_arg, vid_arg, path_arg, dur_arg)
    print(json.dumps(res, ensure_ascii=False))

def main():
    if len(sys.argv) < 2:
        print("[]")
        return

    title_arg  = sys.argv[1] if len(sys.argv) > 1 else ""
    artist_arg = sys.argv[2] if len(sys.argv) > 2 and sys.argv[2].strip() != "" else None
    vid_arg    = sys.argv[3] if len(sys.argv) > 3 and sys.argv[3].strip() != "" else None
    path_arg   = sys.argv[4] if len(sys.argv) > 4 and sys.argv[4].strip() != "" else None
    dur_arg    = float(sys.argv[5]) if len(sys.argv) > 5 and sys.argv[5].strip() != "" else None

    res = get_lyrics(title_arg, artist_arg, vid_arg, path_arg, dur_arg)
    print(json.dumps(res, ensure_ascii=False))

if __name__ == '__main__':
    main()
