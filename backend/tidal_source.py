#!/usr/bin/env python3
"""
Tidal lossless source (Deep Module).

The user's own Tidal account, through tidalapi. Public surface:
  login_start() / login_poll() / logout() / status()
  resolve(video_id, title, artist, duration_s, quality, budget_s) -> TidalStream | None

Never raises to the caller and never prints tokens: any failure returns None so playback
falls back to YouTube. Every process (player_daemon CLI, route worker) is short-lived, so all
state (session, pending login, match cache, stream cache, status) lives in files scoped by
the profile suffix.
"""
import contextlib
import contextvars
import difflib
import json
import os
import re
import sys
import threading
import time
import unicodedata
from pathlib import Path

try:
    from . import platform_compat as pc
except ImportError:
    import platform_compat as pc

MATCH_THRESHOLD = 0.75
MISS_TTL_S = 7 * 86400
NO_LOSSLESS_TTL_S = 86400   # matched, but Tidal only has it lossy (or encrypted) at this quality
STREAM_TTL_S = 600
REQUEST_TIMEOUT_S = 15    # tidalapi sets none; a stalled request must not hold the process
DURATION_TOLERANCE_S = 3.0
QUALITY_MAP = {"hires": "HI_RES_LOSSLESS", "lossless": "LOSSLESS"}
LOSSLESS_QUALITIES = ("LOSSLESS", "HI_RES_LOSSLESS", "HI_RES")

_session_factory = None   # callable returning a tidalapi.Session (tests inject a fake)
_sessions = {}           # profile suffix -> logged-in tidalapi.Session
_saved_tokens = {}       # profile suffix -> access token last written to the session file
_profile_ctx = contextvars.ContextVar("tidal_profile", default=None)
_bg_threads = []
_lock = threading.Lock()


def _default_session_factory():
    import tidalapi
    return tidalapi.Session()


def _new_session():
    sess = (_session_factory or _default_session_factory)()
    _apply_request_timeout(sess)
    return sess


def _apply_request_timeout(sess):
    """Every tidalapi call goes through request_session.request (post() calls it too)."""
    rs = getattr(sess, "request_session", None)
    if rs is None or getattr(rs, "_nutsty_timeout", False):
        return
    orig = rs.request

    def request(method, url, **kw):
        kw.setdefault("timeout", REQUEST_TIMEOUT_S)
        return orig(method, url, **kw)
    rs.request = request
    rs._nutsty_timeout = True


def _fetch_subscription(session):
    """{"highestSoundQuality": ..., "subscription": {"type": ...}} for the logged-in user."""
    resp = session.request.request("GET", f"users/{session.user.id}/subscription")
    return resp.json()


# --- files -----------------------------------------------------------------------------

def _suffix():
    """Profile of this request (route worker serving several windows), else of this process."""
    p = _profile_ctx.get()
    if p is None:
        return pc.get_profile_suffix()
    return pc.get_profile_suffix(p or "default")


@contextlib.contextmanager
def using_profile(profile):
    """Scope every file and the session to one profile ("" is the main profile)."""
    token = _profile_ctx.set(str(profile or "").strip().lower())
    try:
        yield
    finally:
        _profile_ctx.reset(token)


def _temp_dir():
    return os.environ.get("NUTSTY_TEMP_DIR") or pc.get_temp_dir()


def session_file():
    return Path(pc.get_config_dir()) / f"tidal_session{_suffix()}.json"


def status_file():
    return Path(pc.get_config_dir()) / f"tidal_status{_suffix()}.json"


def match_cache_file():
    return Path(pc.get_cache_dir()) / f"tidal_matches{_suffix()}.json"


def mpd_dir():
    return Path(_temp_dir()) / f"nutsty_tidal{_suffix()}"


def _stream_cache_file():
    return mpd_dir() / "streams.json"


def _pending_login_file():
    return mpd_dir() / "pending_login.json"


def _read_json(path, default):
    try:
        with open(path, "r", encoding="utf-8") as f:
            return json.load(f)
    except Exception:
        return default


def _ensure_dir(path):
    """mkdir; the per-profile temp dir (MPD manifests, stream links) is owner-only."""
    path = Path(path)
    if path == mpd_dir():
        path.mkdir(parents=True, exist_ok=True, mode=0o700)
        if not pc.IS_WINDOWS:
            try:
                os.chmod(path, 0o700)
            except OSError:
                pass
    else:
        path.mkdir(parents=True, exist_ok=True)


def _open_private(path, mode="w"):
    """Open for writing with mode 0600 from the start, so the content is never readable by others."""
    path = Path(path)
    _ensure_dir(path.parent)
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    _chmod_private(path)  # an existing file keeps its old mode through O_CREAT
    return os.fdopen(fd, mode, encoding="utf-8")


def _write_private_json(path, data):
    path = Path(path)
    tmp = path.with_name(path.name + ".tmp")
    with _open_private(tmp) as f:
        json.dump(data, f, ensure_ascii=False)
    os.replace(tmp, path)


def _save_session(session):
    """tidalapi opens the file with "w", which keeps the mode of a file that already exists."""
    path = session_file()
    _open_private(path).close()
    session.save_session_to_file(path)
    _chmod_private(path)
    _saved_tokens[_suffix()] = getattr(session, "access_token", None)


def _save_if_refreshed(session):
    """tidalapi refreshes an expired token in memory only; keep the file current."""
    token = getattr(session, "access_token", None)
    # a logout during the lookup removed the session: never write it back
    if _sessions.get(_suffix()) is not session or not session_file().exists():
        return
    if token and token != _saved_tokens.get(_suffix()):
        try:
            _save_session(session)
        except Exception as e:
            _log(f"session save failed: {type(e).__name__}")


def _chmod_private(path):
    if not pc.IS_WINDOWS:
        try:
            os.chmod(path, 0o600)
        except OSError:
            pass


def _log(msg):
    sys.stderr.write(f"[tidal_source] {msg}\n")


# --- session ---------------------------------------------------------------------------

def _get_session():
    """Logged-in session or None. Loads the saved session once per process."""
    cached = _sessions.get(_suffix())
    if cached is not None:
        return cached
    if not session_file().exists() or _read_json(status_file(), {}).get("needs_relogin"):
        return None
    try:
        sess = _new_session()
        if not sess.load_session_from_file(session_file()):
            return None
        _sessions[_suffix()] = sess
        _saved_tokens[_suffix()] = getattr(sess, "access_token", None)
        return sess
    except Exception as e:
        _log(f"session load failed: {type(e).__name__}")
        return None


def _finish_login(session):
    """Persist a freshly authorised session and its account summary."""
    _save_session(session)
    account, subscription, can_hires = "", "", False
    try:
        user = session.user
        account = getattr(user, "username", "") or getattr(user, "email", "") or ""
    except Exception:
        pass
    try:
        sub = _fetch_subscription(session) or {}
        subscription = str((sub.get("subscription") or {}).get("type") or "")
        highest = str(sub.get("highestSoundQuality") or "")
        can_hires = highest.startswith("HI_RES")
        can_lossless = can_hires or highest == "LOSSLESS"
    except Exception as e:
        _log(f"subscription lookup failed: {type(e).__name__}")
        can_lossless = True  # unknown: let the stream itself tell
    _write_private_json(status_file(), {
        "account": account, "subscription": subscription,
        "can_hires": can_hires, "can_lossless": can_lossless, "needs_relogin": False,
    })
    _sessions[_suffix()] = session


def _mark_needs_relogin():
    st = _read_json(status_file(), {})
    st["needs_relogin"] = True
    _write_private_json(status_file(), st)
    _sessions.pop(_suffix(), None)


# 401 subStatus values that mean the session itself is gone. tidalapi refreshes an expired
# token on its own and raises AuthenticationError only when that refresh fails. Other 401s
# (4005 "asset not ready": region, plan) are about one track, not the account.
AUTH_SUB_STATUSES = {6001, 6002, 6003, 6004, 11001, 11002, 11003}


def _sub_status(e):
    try:
        return int(e.response.json().get("subStatus"))
    except Exception:
        return None


def _is_auth_error(e):
    if type(e).__name__ == "AuthenticationError":
        return True
    if getattr(getattr(e, "response", None), "status_code", None) != 401:
        return False
    sub = _sub_status(e)
    return sub is None or sub in AUTH_SUB_STATUSES


def _is_track_unavailable(e):
    return getattr(getattr(e, "response", None), "status_code", None) == 401 and not _is_auth_error(e)


def login_start():
    """Start device login. Returns {url, code, expires_in}; url already carries the code."""
    try:
        sess = _new_session()
        link = sess.get_link_login()
        url = str(link.verification_uri_complete)
        if not url.startswith("http"):
            url = "https://" + url
        _write_private_json(_pending_login_file(), {
            "device_code": link.device_code, "interval": float(link.interval),
            "user_code": link.user_code, "url": url,
            "expires_at": time.time() + float(link.expires_in),
        })
        return {"url": url, "code": link.user_code, "expires_in": int(link.expires_in)}
    except Exception as e:
        _log(f"login start failed: {type(e).__name__}")
        return {"url": "", "code": "", "expires_in": 0, "error": type(e).__name__}


class _PendingLink:
    def __init__(self, data):
        self.device_code = data["device_code"]
        self.interval = float(data.get("interval", 2.0))
        self.user_code = data.get("user_code", "")
        self.expires_in = 1.0


def login_poll():
    """One check of the pending device login. {state, account, subscription}."""
    pending = _read_json(_pending_login_file(), None)
    if not pending:
        st = status()
        return {"state": "ok" if st["logged_in"] else "error",
                "account": st["account"], "subscription": st["subscription"]}
    if time.time() > float(pending.get("expires_at", 0)):
        _clear_pending()
        return {"state": "expired", "account": "", "subscription": ""}
    try:
        sess = _new_session()
        sess.process_link_login(_PendingLink(pending), until_expiry=False)
    except TimeoutError:
        return {"state": "pending", "account": "", "subscription": ""}
    except Exception as e:
        _log(f"login poll failed: {type(e).__name__}")
        return {"state": "pending" if time.time() < float(pending.get("expires_at", 0)) else "error",
                "account": "", "subscription": ""}
    _finish_login(sess)
    _clear_pending()
    st = status()
    return {"state": "ok", "account": st["account"], "subscription": st["subscription"]}


def _clear_pending():
    try:
        _pending_login_file().unlink()
    except OSError:
        pass


def logout():
    _sessions.pop(_suffix(), None)
    _saved_tokens.pop(_suffix(), None)
    for p in (session_file(), status_file(), _stream_cache_file(), _pending_login_file()):
        try:
            Path(p).unlink()
        except OSError:
            pass


def status():
    """Offline: reads saved files only, never the network."""
    st = _read_json(status_file(), {})
    needs = bool(st.get("needs_relogin"))
    return {
        "logged_in": session_file().exists() and not needs,
        "account": st.get("account", ""),
        "subscription": st.get("subscription", ""),
        "can_hires": bool(st.get("can_hires")),
        "can_lossless": bool(st.get("can_lossless", True)),
        "needs_relogin": needs,
    }


# --- matching --------------------------------------------------------------------------

_NOISE_RE = re.compile(r"[\(\[\{][^\)\]\}]*[\)\]\}]")
_TAIL_RE = re.compile(r"\s+(?:-\s+)?(?:feat\.?|ft\.?|featuring|remaster(?:ed)?)\b.*$", re.IGNORECASE)
_DASH_TAIL_RE = re.compile(r"\s+-\s+(?:\d{4}\s+)?remaster(?:ed)?.*$", re.IGNORECASE)
_PIPE_RE = re.compile(r"\s*[|｜].*$")
_VARIANT_WORDS = ("live", "remix", "acoustic", "instrumental", "karaoke", "sped up",
                  "slowed", "nightcore", "cover", "8d", "lofi", "lo-fi")


def _norm(s):
    return unicodedata.normalize("NFC", str(s or "")).lower().strip()


def clean_title(title, artist=""):
    t = _norm(title)
    a = _norm(artist)
    if a and " - " in t:
        left, right = t.split(" - ", 1)
        if left.strip() == a or left.strip() in a or a in left.strip():
            t = right
        elif right.strip() == a or a in right.strip():
            t = left  # "Hello - Adele": the artist after the dash
    t = _PIPE_RE.sub("", t)
    t = _NOISE_RE.sub(" ", t)
    t = _DASH_TAIL_RE.sub("", t)
    t = _TAIL_RE.sub("", t)
    t = re.sub(r"\s+", " ", t).strip(" -–—")
    return t


def _variants(raw):
    s = _norm(raw)
    return {w for w in _VARIANT_WORDS if re.search(r"\b" + re.escape(w) + r"\b", s)}


def score_candidate(title, artist, duration_s, cand_title, cand_artists, cand_duration_s):
    """0..1. Variants the source lacks (live, remix...) or a duration off by > 3 s score 0."""
    if _variants(cand_title) - _variants(title):
        return 0.0
    try:
        d, cd = float(duration_s or 0), float(cand_duration_s or 0)
    except (TypeError, ValueError):
        d, cd = 0.0, 0.0
    if d > 0 and cd > 0 and abs(d - cd) > DURATION_TOLERANCE_S:
        return 0.0
    src_t = clean_title(title, artist)
    cand_t = clean_title(cand_title)
    t_score = difflib.SequenceMatcher(None, src_t, cand_t).ratio() if src_t and cand_t else 0.0
    src_a = _norm(artist)
    a_score = 0.0
    for ca in cand_artists or []:
        ca = _norm(ca)
        if not ca:
            continue
        if ca in src_a or (src_a and src_a in ca):
            a_score = 1.0
            break
        a_score = max(a_score, difflib.SequenceMatcher(None, src_a, ca).ratio())
    if a_score < 0.6:
        return min(t_score * 0.6, 0.5)
    if d > 0 and cd > 0:
        return 0.6 * t_score + 0.3 * a_score + 0.1
    return 0.65 * t_score + 0.35 * a_score


def _track_title(track):
    name = getattr(track, "name", "") or ""
    version = getattr(track, "version", None)
    return f"{name} ({version})" if version else name


def _find_track(sess, title, artist, duration_s):
    query = f"{artist} {clean_title(title, artist)}".strip()
    try:
        import tidalapi
        models = [tidalapi.Track]
    except Exception:
        models = None
    res = sess.search(query, models=models, limit=10)
    tracks = res.get("tracks", []) if isinstance(res, dict) else getattr(res, "tracks", [])
    best, best_score = None, 0.0
    for tr in tracks or []:
        modes = getattr(tr, "audio_modes", None) or ["STEREO"]
        if "STEREO" not in modes:
            continue
        sc = score_candidate(title, artist, duration_s, _track_title(tr),
                             [getattr(a, "name", "") for a in getattr(tr, "artists", []) or []],
                             getattr(tr, "duration", 0))
        if sc > best_score:
            best, best_score = tr, sc
    return best if best_score >= MATCH_THRESHOLD else None


# --- streams ---------------------------------------------------------------------------

def _stream_of(sess, track, quality_key):
    sess.config.quality = QUALITY_MAP.get(quality_key, "LOSSLESS")
    stream = track.get_stream()
    if str(getattr(stream, "audio_quality", "")) not in LOSSLESS_QUALITIES:
        return None
    manifest = stream.get_stream_manifest()
    if getattr(manifest, "is_encrypted", False):
        return None
    codec = str(manifest.get_codecs() or "FLAC").upper()
    if stream.is_mpd:
        p = mpd_dir() / f"tidal_{track.id}_{quality_key}.mpd"
        with _open_private(p) as f:
            f.write(stream.get_manifest_data())
        url = p.as_uri()
    else:
        urls = manifest.get_urls() or []
        if not urls:
            return None
        url = urls[0]
    return {
        "url": url, "codec": codec,
        "bit_depth": int(getattr(stream, "bit_depth", 16) or 16),
        "sample_rate": int(getattr(stream, "sample_rate", 44100) or 44100),
        "audio_quality": str(stream.audio_quality),
        "tidal_id": track.id,
        "expires_at": time.time() + STREAM_TTL_S,
    }


def _cached_stream(video_id, quality_key):
    entry = _read_json(_stream_cache_file(), {}).get(f"{video_id}:{quality_key}")
    if not entry or float(entry.get("expires_at", 0)) <= time.time():
        return None
    url = entry.get("url", "")
    if url.startswith("file://") and not os.path.exists(file_url_to_path(url)):
        return None
    return entry


def file_url_to_path(url):
    """file:///C:/x.mpd -> C:\\x.mpd on Windows, file:///tmp/x.mpd -> /tmp/x.mpd elsewhere
    (slicing off "file://" leaves "/C:/x.mpd", which never exists on Windows)."""
    from urllib.parse import urlparse
    from urllib.request import url2pathname
    return url2pathname(urlparse(url).path)


def _work(video_id, title, artist, duration_s, quality_key):
    """Match + stream. Returns TidalStream or None; writes both caches."""
    sess = _get_session()
    if sess is None:
        return None
    try:
        matches = _read_json(match_cache_file(), {})
        m = matches.get(video_id)
        now = time.time()
        if m and m.get("tidal_id") is None and now - float(m.get("ts", 0)) < MISS_TTL_S:
            return None
        if m and m.get("no_lossless") == quality_key and now - float(m.get("ts", 0)) < NO_LOSSLESS_TTL_S:
            return None
        if m and m.get("tidal_id") is not None:
            track = sess.track(m["tidal_id"])
        else:
            track = _find_track(sess, title, artist, duration_s)
            with _lock:
                matches = _read_json(match_cache_file(), {})
                matches[video_id] = {"tidal_id": track.id if track else None, "ts": now}
                _write_private_json(match_cache_file(), matches)
            if track is None:
                return None
        result = _stream_of(sess, track, quality_key)
        if not result:
            with _lock:
                matches = _read_json(match_cache_file(), {})
                matches[video_id] = {"tidal_id": track.id, "no_lossless": quality_key, "ts": now}
                _write_private_json(match_cache_file(), matches)
        if result:
            with _lock:
                cache = _read_json(_stream_cache_file(), {})
                cache = {k: v for k, v in cache.items() if float(v.get("expires_at", 0)) > now}
                cache[f"{video_id}:{quality_key}"] = result
                _write_private_json(_stream_cache_file(), cache)
        return result
    except Exception as e:
        if _is_auth_error(e):
            _mark_needs_relogin()
            _log("authorisation rejected, re-login needed")
        elif _is_track_unavailable(e):
            with _lock:
                matches = _read_json(match_cache_file(), {})
                matches[video_id] = {"tidal_id": None, "ts": time.time()}
                _write_private_json(match_cache_file(), matches)
            _log(f"track not playable on this account (subStatus {_sub_status(e)})")
        else:
            _log(f"resolve failed: {type(e).__name__}")
        return None
    finally:
        _save_if_refreshed(sess)


def resolve(video_id, title, artist, duration_s, quality, budget_s=4.0):
    """TidalStream for a YouTube track, or None (play YouTube). Bounded by budget_s:
    past it, returns None and lets the lookup finish in the background for next time."""
    st = status()
    # a plan without lossless (Free, or HIGH only) never gets FLAC: no lookup at all
    if not video_id or not st["logged_in"] or not st["can_lossless"]:
        return None
    quality_key = quality if quality in QUALITY_MAP else "lossless"
    cached = _cached_stream(video_id, quality_key)
    if cached:
        return cached
    box = {}

    def run():
        box["result"] = _work(video_id, title, artist, duration_s, quality_key)

    ctx = contextvars.copy_context()
    th = threading.Thread(target=lambda: ctx.run(run), name=f"tidal-resolve-{video_id}", daemon=False)
    th.start()
    th.join(budget_s)
    if th.is_alive():
        _bg_threads.append(th)
        _log(f"over {budget_s:.1f}s budget, playing YouTube this time")
        return None
    return box.get("result")


# --- test hooks ------------------------------------------------------------------------

def _reset_for_tests():
    global _session_factory
    _join_background_for_tests(2.0)
    _sessions.clear()
    _saved_tokens.clear()
    _session_factory = None


def _reset_stream_cache_for_tests():
    try:
        _stream_cache_file().unlink()
    except OSError:
        pass


def _join_background_for_tests(timeout):
    while _bg_threads:
        _bg_threads.pop().join(timeout)
