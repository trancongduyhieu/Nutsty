#!/usr/bin/env python3
"""
Nutsty Music & Authentication HTTP Route Handlers
Extracted from auth_server.py for clean modularity and CodeGraph AST function indexing.
"""
import os
import sys
import json

try:
    from . import ytmusic_helper
except (ImportError, ValueError):
    import ytmusic_helper


def handle_get_auth_status(handler):
    st = ytmusic_helper.get_auth_status()
    handler._send_json(st, 200)


def handle_get_mood(handler, query):
    params = query.get("params", [""])[0]
    title = query.get("title", [""])[0]
    try:
        data = ytmusic_helper.get_mood_feed(params, title)
    except Exception:
        data = {"sections": [], "quick_picks": [], "featured_playlists": []}
    handler._send_json(data, 200)


def handle_get_home(handler):
    try:
        data = ytmusic_helper.get_personalized_home()
    except Exception:
        data = {"moods": [], "sections": [], "quick_picks": [], "featured_playlists": []}
    handler._send_json(data, 200)


def handle_get_suggestions(handler, query):
    q = query.get("q", [""])[0]
    data = ytmusic_helper.get_search_suggestions(q)
    handler._send_json(data, 200)


def handle_get_filter_search(handler, query):
    q = query.get("q", [""])[0]
    flt = query.get("filter", ["songs"])[0]
    limit_val = 30
    if "limit" in query:
        try:
            limit_val = int(query.get("limit", [30])[0])
        except (ValueError, TypeError):
            limit_val = 30
    data = ytmusic_helper.filter_search(q, flt, limit=limit_val)
    handler._send_json(data, 200)


def handle_get_playlist(handler, query):
    pl_id = query.get("id", [""])[0]
    data = ytmusic_helper.get_playlist_tracks(pl_id)
    handler._send_json(data, 200)


def handle_get_artist_shuffle(handler, query):
    name = query.get("name", [""])[0]
    browse_id = query.get("browseId", [""])[0]
    try:
        data = ytmusic_helper.get_artist_shuffle(name, browse_id)
    except Exception as e:
        print(f"[artist_shuffle error]: {e}", flush=True)
        data = {"artist": name, "tracks": []}
    handler._send_json(data, 200)


def handle_get_resolve_cover(handler, query):
    title = query.get("title", [""])[0]
    artist = query.get("artist", [""])[0]
    vid = query.get("videoId", [""])[0]
    curr = query.get("current", [""])[0]
    try:
        data = ytmusic_helper.resolve_square_cover(title, artist, vid, curr)
    except Exception as e:
        sys.stderr.write(f"[resolve_cover error]: {e}\n")
        data = {"url": curr, "is_square": False, "match": "error"}
    handler._send_json(data, 200)


def handle_post_auth_cookies(handler, post_body):
    raw_data = None
    try:
        parsed = json.loads(post_body)
        if isinstance(parsed, dict):
            raw_data = parsed.get("cookies") or parsed.get("youtubeMusic") or parsed.get("data") or parsed
        else:
            raw_data = parsed
    except Exception:
        raw_data = post_body

    res = ytmusic_helper.save_auth(raw_data)
    status_code = 200 if res.get("success") else 400
    handler._send_json(res, status_code)


def handle_post_auth_auto_sync(handler):
    # Phase 0: If current session is already authentic, return immediately with zero browser friction
    try:
        cur_auth = ytmusic_helper.get_auth_status()
        if cur_auth.get("logged_in") and cur_auth.get("name") and cur_auth.get("name") != "Google User":
            handler._send_json({
                "success": True,
                "browser": "Phiên hiện tại",
                "name": cur_auth.get("name"),
                "email": cur_auth.get("email")
            }, 200)
            return
    except Exception:
        pass

    # On Windows, locked browser cookies prevent offline extraction; fail fast so browser opens in 0ms
    if sys.platform == "win32" or os.name == "nt":
        handler._send_json({"success": False, "message": "Opening native browser login..."}, 200)
        return

    res = ytmusic_helper.extract_ytmusic_cookies_from_browsers()
    handler._send_json(res, 200)


def handle_get_clipboard(handler):
    text = ""
    if sys.platform == "win32":
        try:
            import ctypes
            ctypes.windll.user32.OpenClipboard(0)
            try:
                if ctypes.windll.user32.IsClipboardFormatAvailable(13): # CF_UNICODETEXT
                    h = ctypes.windll.user32.GetClipboardData(13)
                    text = ctypes.c_wchar_p(h).value or ""
            finally:
                ctypes.windll.user32.CloseClipboard()
        except Exception:
            pass
    else:
        import subprocess
        try:
            res = subprocess.run(["wl-paste", "-n"], capture_output=True, text=True, timeout=1)
            if res.returncode == 0 and res.stdout:
                text = res.stdout
        except Exception:
            pass
        if not text:
            try:
                res = subprocess.run(["xclip", "-selection", "clipboard", "-o"], capture_output=True, text=True, timeout=1)
                if res.returncode == 0 and res.stdout:
                    text = res.stdout
            except Exception:
                pass
    handler._send_json({"text": text or ""}, 200)


def handle_post_spotify_auto_sync(handler):
    try:
        from . import lyrics_helper
    except (ImportError, ValueError):
        import lyrics_helper

    # Phase 0: If stored sp_dc in settings is already valid, connect instantly
    try:
        stored_spdc = lyrics_helper.get_spotify_spdc()
        if stored_spdc:
            sess = lyrics_helper.get_spotify_session_info(stored_spdc)
            if not sess.get("isAnonymous", True):
                handler._send_json({
                    "success": True,
                    "browser": "Cài đặt Nutsty",
                    "spdc": stored_spdc,
                    "session": sess
                }, 200)
                return
    except Exception:
        pass

    # On Windows, locked browser cookies prevent offline extraction; fail fast so browser opens in 0ms
    if sys.platform == "win32" or os.name == "nt":
        handler._send_json({"success": False, "message": "Opening native browser login..."}, 200)
        return

    res = lyrics_helper.extract_spotify_cookie_from_browsers()
    if res.get("success") and res.get("spdc"):
        # Validate that the extracted cookie is actively authorized by Spotify
        tok = lyrics_helper.get_spotify_access_token(res["spdc"])
        if not tok:
            handler._send_json({
                "success": False,
                "message": f"Tìm thấy cookie từ {res.get('browser', 'trình duyệt')} nhưng cookie đã hết hạn (401 Unauthorized)."
            }, 200)
            return

        # Auto-save to settings
        try:
            import platform_compat as pc
            prof_suffix = pc.get_profile_suffix() if hasattr(pc, "get_profile_suffix") else ""
            p = os.path.join(pc.get_config_dir(), f"nutsty_settings{prof_suffix}.json")
            if not os.path.exists(p):
                p = os.path.join(pc.get_config_dir(), "nutsty_settings.json")
            data = {}
            if os.path.exists(p):
                with open(p, "r", encoding="utf-8") as f:
                    data = json.load(f)
            data["spotifySpdc"] = res["spdc"]
            with open(p, "w", encoding="utf-8") as f:
                json.dump(data, f, indent=2, ensure_ascii=False)
        except Exception as e:
            sys.stderr.write(f"[spotify_auto_sync save error]: {e}\n")
    else:
        res["need_browser_login"] = True
    handler._send_json(res, 200)



def handle_get_spotify_profile(handler, query):
    spdc = query.get("spdc", [""])[0]
    try:
        from . import lyrics_helper
    except (ImportError, ValueError):
        import lyrics_helper
    if not spdc:
        spdc = lyrics_helper.get_spotify_spdc()
    sess = lyrics_helper.get_spotify_session_info(spdc)
    handler._send_json(sess, 200)


def handle_post_spotify_validate(handler):
    body = handler._read_post_json()
    spdc = body.get("spdc", "").strip() if isinstance(body, dict) else ""
    if not spdc:
        handler._send_json({"success": False, "error": "Vui lòng nhập chuỗi cookie sp_dc."}, 400)
        return

    try:
        from . import lyrics_helper
    except (ImportError, ValueError):
        import lyrics_helper

    # Test TOTP exchange directly with official Spotify token endpoint
    access_token = lyrics_helper.get_spotify_access_token(spdc)
    if not access_token:
        handler._send_json({
            "success": False,
            "error": "Cookie sp_dc không hợp lệ hoặc đã hết hạn từ Spotify (401 Unauthorized)."
        }, 200)
        return

    sess = lyrics_helper.get_spotify_session_info(spdc)
    handler._send_json({
        "success": True,
        "message": "Xác thực tài khoản Spotify thành công!",
        "isPremium": sess.get("isPremium", False),
        "userCountry": sess.get("userCountry", "")
    }, 200)


def handle_get_spotify_playlists(handler, query):
    try:
        from . import spotify_importer
        from . import lyrics_helper
    except (ImportError, ValueError):
        import spotify_importer
        import lyrics_helper
    spdc = query.get("spdc", [""])[0].strip()
    if not spdc:
        spdc = lyrics_helper.get_spotify_spdc()
    res = spotify_importer.fetch_user_spotify_playlists(spdc)
    handler._send_json(res, 200)


def handle_post_spotify_resolve_url(handler):
    try:
        from . import spotify_importer
        from . import lyrics_helper
    except (ImportError, ValueError):
        import spotify_importer
        import lyrics_helper
    body = handler._read_post_json()
    url = body.get("url", "") if isinstance(body, dict) else ""
    spdc = body.get("spdc", "") if isinstance(body, dict) else ""
    if not spdc:
        spdc = lyrics_helper.get_spotify_spdc()
    res = spotify_importer.fetch_spotify_playlist_details(url, spdc=spdc)
    handler._send_json(res, 200 if res.get("success") else 400)


def handle_post_spotify_import(handler):
    try:
        from . import spotify_importer
    except (ImportError, ValueError):
        import spotify_importer
    body = handler._read_post_json()
    if not isinstance(body, dict):
        handler._send_json({"success": False, "error": "Dữ liệu không hợp lệ."}, 400)
        return
    playlist_id = body.get("playlist_id", "")
    playlist_title = body.get("playlist_title", "")
    spdc = body.get("spdc", "")
    res = spotify_importer.importer.start_import(playlist_id, playlist_title, spdc)
    handler._send_json(res, 200 if res.get("success") else 400)


def handle_get_spotify_import_status(handler):
    try:
        from . import spotify_importer
    except (ImportError, ValueError):
        import spotify_importer
    st = spotify_importer.importer.get_status()
    handler._send_json(st, 200)


def handle_post_spotify_cancel_import(handler):
    try:
        from . import spotify_importer
    except (ImportError, ValueError):
        import spotify_importer
    spotify_importer.importer.cancel()
    handler._send_json({"success": True, "message": "Đã yêu cầu hủy."}, 200)


