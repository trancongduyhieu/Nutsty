#!/usr/bin/env python3
"""
Nutsty CLI Route Dispatcher
Dispatches HTTP requests from the Rust nutsty-daemon to Python handlers
(music_routes, social_routes, updater).

Two modes:
  --serve   resident worker kept warm by nutsty-daemon: one JSON request per stdin line,
            one JSON response per stdout line. Saves the ~0.8 s Python start + imports per
            request. Exits after IDLE_EXIT_SEC without work (returns the RAM) or after
            MAX_REQUESTS (recycles slow leaks, like gunicorn max_requests); the daemon respawns it.
  default   one request from stdin (or CLI args), then exit.
"""
import os
import sys
import json
from urllib.parse import parse_qs, urlparse

BACKEND_DIR = os.path.dirname(os.path.abspath(__file__))
if BACKEND_DIR not in sys.path:
    sys.path.insert(0, BACKEND_DIR)

try:
    from . import platform_compat as pc
    from . import music_routes
    from . import social_routes
except (ImportError, ValueError):
    import platform_compat as pc
    import music_routes
    import social_routes


class MockResponseHandler:
    def __init__(self, post_body=""):
        self.post_body = post_body or ""
        self.status_code = 200
        self.headers = {"Content-Type": "application/json"}
        self.response_body = ""

    def _send_cors_headers(self):
        self.headers["Access-Control-Allow-Origin"] = "*"
        self.headers["Access-Control-Allow-Methods"] = "POST, GET, OPTIONS"
        self.headers["Access-Control-Allow-Headers"] = "Content-Type, Authorization"

    def send_response(self, code):
        self.status_code = code

    def send_header(self, keyword, value):
        self.headers[keyword] = value

    def end_headers(self):
        pass

    def _send_json(self, data, status_code=200):
        self.status_code = status_code
        self.response_body = json.dumps(data, ensure_ascii=False)

    def _send_raw_json(self, raw_str, status_code=200):
        self.status_code = status_code
        self.response_body = raw_str if isinstance(raw_str, str) else raw_str.decode("utf-8", errors="replace")

    def _read_post_body(self):
        return self.post_body

    def _read_post_json(self):
        if not self.post_body:
            return {}
        try:
            return json.loads(self.post_body)
        except Exception:
            return {}


def dispatch_request(method, path, query_dict, body_str):
    handler = MockResponseHandler(post_body=body_str)
    handler._send_cors_headers()

    clean_path = path.split("?")[0]

    if method == "GET":
        if clean_path == "/api/auth/status":
            music_routes.handle_get_auth_status(handler)
        elif clean_path == "/api/mood":
            music_routes.handle_get_mood(handler, query_dict)
        elif clean_path == "/api/home":
            music_routes.handle_get_home(handler)
        elif clean_path == "/api/suggestions":
            music_routes.handle_get_suggestions(handler, query_dict)
        elif clean_path == "/api/filter_search":
            music_routes.handle_get_filter_search(handler, query_dict)
        elif clean_path == "/api/playlist":
            music_routes.handle_get_playlist(handler, query_dict)
        elif clean_path == "/api/comments":
            music_routes.handle_get_comments(handler, query_dict)
        elif clean_path == "/api/comments/page":
            music_routes.handle_get_comments_page(handler, query_dict)
        elif clean_path == "/api/artist_shuffle":
            music_routes.handle_get_artist_shuffle(handler, query_dict)
        elif clean_path == "/api/resolve_cover":
            music_routes.handle_get_resolve_cover(handler, query_dict)
        elif clean_path == "/api/notes":
            social_routes.handle_get_notes(handler, query_dict)
        elif clean_path == "/api/friends":
            social_routes.handle_get_friends(handler, query_dict)
        elif clean_path == "/api/users/me":
            social_routes.handle_get_user_me(handler, query_dict)
        elif clean_path == "/api/users/search":
            social_routes.handle_search_users(handler, query_dict)
        elif clean_path == "/api/notes/events":
            social_routes.handle_get_note_events(handler, query_dict)
        elif clean_path == "/api/clipboard":
            music_routes.handle_get_clipboard(handler)
        elif clean_path == "/api/spotify/profile":
            music_routes.handle_get_spotify_profile(handler, query_dict)
        elif clean_path == "/api/spotify/playlists":
            music_routes.handle_get_spotify_playlists(handler, query_dict)
        elif clean_path == "/api/spotify/import_status":
            music_routes.handle_get_spotify_import_status(handler)
        elif clean_path == "/api/check_update":
            force = query_dict.get("force", ["0"])[0] in ("1", "true", "True")
            mock = query_dict.get("mock", ["0"])[0] in ("1", "true", "True")
            try:
                import updater
                res = updater.check_for_updates(force=force, mock=mock)
            except Exception as e:
                res = {"has_update": False, "error": str(e)}
            handler._send_json(res, 200)
        elif clean_path == "/api/update/status":
            try:
                import updater
                st = updater.direct_updater.get_status()
            except Exception as e:
                st = {"active": False, "status": "error", "error": str(e)}
            handler._send_json(st, 200)
        else:
            handler._send_json({"error": f"Not found: {clean_path}"}, 404)

    elif method == "POST":
        req_json = handler._read_post_json()
        if clean_path in ("/api/auth/cookies", "/api/auth/sync"):
            music_routes.handle_post_auth_cookies(handler, handler._read_post_body())
        elif clean_path in ("/api/auth/auto-sync", "/api/auth/auto_sync"):
            music_routes.handle_post_auth_auto_sync(handler)
        elif clean_path == "/api/update/start":
            try:
                import updater
                dl_url = req_json.get("download_url") if isinstance(req_json, dict) else None
                tgt_ver = req_json.get("target_version") if isinstance(req_json, dict) else None
                res = updater.direct_updater.start_download_update(dl_url, tgt_ver)
                handler._send_json(res, 200 if res.get("success") else 400)
            except Exception as e:
                handler._send_json({"success": False, "error": str(e)}, 500)
        elif clean_path == "/api/update/apply":
            try:
                import updater
                target_dir = req_json.get("app_dir") if isinstance(req_json, dict) else None
                res = updater.direct_updater.apply_update_and_restart(target_dir=target_dir)
                handler._send_json(res, 200 if res.get("success") else 400)
            except Exception as e:
                handler._send_json({"success": False, "error": str(e)}, 500)
        elif clean_path == "/api/comments/create":
            music_routes.handle_post_comment(handler, req_json)
        elif clean_path == "/api/comments/reply":
            music_routes.handle_post_comment(handler, req_json, reply=True)
        elif clean_path == "/api/spotify/auto-sync":
            music_routes.handle_post_spotify_auto_sync(handler)
        elif clean_path == "/api/spotify/validate":
            music_routes.handle_post_spotify_validate(handler)
        elif clean_path == "/api/spotify/resolve_url":
            music_routes.handle_post_spotify_resolve_url(handler)
        elif clean_path == "/api/spotify/import_playlist":
            music_routes.handle_post_spotify_import(handler)
        elif clean_path == "/api/spotify/cancel_import":
            music_routes.handle_post_spotify_cancel_import(handler)
        elif clean_path == "/api/users/update_profile":
            social_routes.handle_post_update_profile(handler, req_json)
        elif clean_path == "/api/users/regenerate_pin":
            social_routes.handle_post_regenerate_pin(handler, req_json)
        elif clean_path == "/api/users/offline":
            social_routes.handle_post_user_offline(handler, req_json)
        elif clean_path == "/api/notes":
            social_routes.handle_post_publish_note(handler, req_json)
        elif clean_path == "/api/notes/delete":
            social_routes.handle_post_delete_note(handler, req_json)
        elif clean_path == "/api/notes/events":
            social_routes.handle_post_note_event(handler, req_json)
        elif clean_path == "/api/now_playing":
            social_routes.handle_post_now_playing(handler, req_json)
        elif clean_path == "/api/friends/request":
            social_routes.handle_post_friend_request(handler, req_json)
        elif clean_path == "/api/friends/respond":
            social_routes.handle_post_friend_respond(handler, req_json)
        elif clean_path == "/api/friends/remove":
            social_routes.handle_post_friend_remove(handler, req_json)
        else:
            handler._send_json({"error": f"Not found: {clean_path}"}, 404)
    else:
        handler._send_json({"error": f"Method {method} not supported"}, 405)

    return {
        "status": handler.status_code,
        "headers": handler.headers,
        "body": handler.response_body
    }


def _handle_payload(req):
    method = req.get("method", "GET").upper()
    raw_url = req.get("url", req.get("path", "/"))
    parsed = urlparse(raw_url)
    return dispatch_request(method, parsed.path, parse_qs(parsed.query), req.get("body", ""))


try:
    IDLE_EXIT_SEC = max(30, int(os.environ.get("NUTSTY_WORKER_IDLE_SEC", "600")))
except ValueError:
    IDLE_EXIT_SEC = 600
MAX_REQUESTS = 500


def _background_busy():
    """True while an update download or Spotify import started by this worker is running."""
    for mod_name, attr in (("updater", "direct_updater"), ("spotify_importer", "importer")):
        mod = sys.modules.get(mod_name) or sys.modules.get(f"backend.{mod_name}")
        job = getattr(mod, attr, None) if mod else None
        if job is not None and getattr(job, "active", False):
            return True
    return False


def _exit_worker():
    while _background_busy():
        import time
        time.sleep(2)
    try:
        flush = getattr(sys.modules.get("catalog_engine"), "flush_online_tracks", None)
        if flush:
            flush()
    except Exception:
        pass
    os._exit(0)


def _code_changed_since(started):
    """True when a backend .py file changed after this worker loaded (dev edit or applied update)."""
    try:
        for entry in os.scandir(BACKEND_DIR):
            if entry.name.endswith(".py") and entry.stat().st_mtime > started:
                return True
    except OSError:
        pass
    return False


def serve():
    import threading
    import time
    # The real stdout is the response channel: handler prints go to stderr instead
    out = os.fdopen(os.dup(sys.stdout.fileno()), "w", encoding="utf-8")
    sys.stdout = sys.stderr
    state = {"last": time.monotonic(), "busy": False}
    lock = threading.Lock()

    def idle_watch():
        while True:
            time.sleep(15)
            with lock:
                if (not state["busy"] and time.monotonic() - state["last"] > IDLE_EXIT_SEC
                        and not _background_busy()):
                    _exit_worker()

    threading.Thread(target=idle_watch, daemon=True).start()
    started = time.time()
    served = 0
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        with lock:
            state["busy"] = True
        try:
            res = _handle_payload(json.loads(line))
        except Exception as e:
            res = {"status": 500, "headers": {"Content-Type": "application/json"}, "body": json.dumps({"error": str(e)})}
        out.write(json.dumps(res, ensure_ascii=False) + "\n")
        out.flush()
        served += 1
        with lock:
            state["busy"] = False
            state["last"] = time.monotonic()
        # Recycle only between jobs: an update download / Spotify import keeps this worker serving
        if (served >= MAX_REQUESTS or _code_changed_since(started)) and not _background_busy():
            break
    # stdin closed (daemon gone) or recycled: finish any update / import first
    _exit_worker()


def main():
    # nutsty-daemon writes UTF-8 JSON; Windows would otherwise decode stdin as cp1252
    try:
        sys.stdin.reconfigure(encoding="utf-8")
    except Exception:
        pass
    if "--serve" in sys.argv[1:]:
        serve()
        return
    # Read invocation payload from stdin if available, or CLI arguments
    if not sys.stdin.isatty():
        try:
            raw_input = sys.stdin.read()
            if raw_input.strip():
                res = _handle_payload(json.loads(raw_input))
                print(json.dumps(res, ensure_ascii=False))
                return
        except Exception as e:
            err_res = {"status": 500, "headers": {"Content-Type": "application/json"}, "body": json.dumps({"error": str(e)})}
            print(json.dumps(err_res, ensure_ascii=False))
            return

    # Fallback to CLI args: route_dispatcher.py <METHOD> <PATH> [BODY_STRING]
    args = sys.argv[1:]
    if len(args) < 2:
        print("Usage: route_dispatcher.py <METHOD> <PATH> [BODY_STRING]")
        sys.exit(1)

    method = args[0].upper()
    raw_url = args[1]
    parsed = urlparse(raw_url)
    path = parsed.path
    query = parse_qs(parsed.query)
    body = args[2] if len(args) > 2 else ""

    res = dispatch_request(method, path, query, body)
    print(json.dumps(res, ensure_ascii=False))


if __name__ == "__main__":
    main()
