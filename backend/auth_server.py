#!/usr/bin/env python3
"""
Nutsty 1-Click Auth Webhook & Social/Music Local IPC Server
Listens strictly on 127.0.0.1:17890 and dispatches routes to music_routes and social_routes.
Maintains full backward compatibility by re-exporting CloudRelayClient & identity helpers.
"""
import os
import sys
import json
from http.server import HTTPServer, ThreadingHTTPServer, BaseHTTPRequestHandler
from urllib.parse import urlparse, parse_qs

BACKEND_DIR = os.path.dirname(os.path.abspath(__file__))
if BACKEND_DIR not in sys.path:
    sys.path.insert(0, BACKEND_DIR)

try:
    from . import platform_compat as pc
    from . import ytmusic_helper
    from .cloud_relay_client import (
        get_nutsty_config_dir,
        get_cloud_relay_db_path,
        CloudRelayEngine,
        invalidate_cloud_identity_by_user_id,
        CloudRelayClient,
        GLOBAL_RELAY_CLIENT,
        _cloud_notes_cache,
        resolve_profile_suffix,
        get_cloud_identity_path,
        load_cloud_identity,
        save_cloud_identity,
        ensure_cloud_identity,
        get_canonical_user,
        get_notes_vault_path,
        load_notes_vault,
        save_notes_vault,
        get_events_vault_path,
        load_events_vault,
        save_events_vault,
        get_friends_vault_path,
        load_friends_vault,
        save_friends_vault,
        get_friend_requests_vault_path,
        load_friend_requests_vault,
        save_friend_requests_vault,
        normalize_user_email,
        resolve_canonical_user_email,
        get_user_all_identifiers,
        get_profiles_vault_path,
        load_profiles_vault,
        save_profiles_vault,
        ensure_user_profile,
        regenerate_user_pin,
        get_all_known_users,
        sync_local_friends_files,
    )
    from . import music_routes
    from . import social_routes
except (ImportError, ValueError):
    import platform_compat as pc
    import ytmusic_helper
    from cloud_relay_client import (
        get_nutsty_config_dir,
        get_cloud_relay_db_path,
        CloudRelayEngine,
        invalidate_cloud_identity_by_user_id,
        CloudRelayClient,
        GLOBAL_RELAY_CLIENT,
        _cloud_notes_cache,
        resolve_profile_suffix,
        get_cloud_identity_path,
        load_cloud_identity,
        save_cloud_identity,
        ensure_cloud_identity,
        get_canonical_user,
        get_notes_vault_path,
        load_notes_vault,
        save_notes_vault,
        get_events_vault_path,
        load_events_vault,
        save_events_vault,
        get_friends_vault_path,
        load_friends_vault,
        save_friends_vault,
        get_friend_requests_vault_path,
        load_friend_requests_vault,
        save_friend_requests_vault,
        normalize_user_email,
        resolve_canonical_user_email,
        get_user_all_identifiers,
        get_profiles_vault_path,
        load_profiles_vault,
        save_profiles_vault,
        ensure_user_profile,
        regenerate_user_pin,
        get_all_known_users,
        sync_local_friends_files,
    )
    import music_routes
    import social_routes

pc.configure_windows_ssl()

PORT = 17890
HOST = "127.0.0.1"

_pending_ui_action = None


class AuthWebhookHandler(BaseHTTPRequestHandler):
    def _send_cors_headers(self):
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "POST, GET, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type, Authorization")

    def handle_one_request(self):
        try:
            super().handle_one_request()
        except (ConnectionAbortedError, ConnectionResetError, BrokenPipeError, OSError):
            self.close_connection = True

    def _send_json(self, data, status_code=200):
        try:
            payload = json.dumps(data, ensure_ascii=False).encode("utf-8")
            self.send_response(status_code)
            self._send_cors_headers()
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(payload)))
            self.end_headers()
            self.wfile.write(payload)
        except (BrokenPipeError, ConnectionResetError, ConnectionAbortedError, OSError):
            pass
        except Exception:
            pass

    def _read_post_body(self):
        content_len = int(self.headers.get("Content-Length", 0))
        return self.rfile.read(content_len).decode("utf-8") if content_len > 0 else ""

    def _read_post_json(self):
        post_body = self._read_post_body()
        try:
            return json.loads(post_body) if post_body else {}
        except Exception:
            return {}

    def do_OPTIONS(self):
        self.send_response(204)
        self._send_cors_headers()
        self.end_headers()

    def do_GET(self):
        global _pending_ui_action
        parsed_url = urlparse(self.path)
        path = parsed_url.path
        query = parse_qs(parsed_url.query)

        if path == "/api/auth/status":
            music_routes.handle_get_auth_status(self)
        elif path == "/api/mood":
            music_routes.handle_get_mood(self, query)
        elif path == "/api/home":
            music_routes.handle_get_home(self)
        elif path == "/api/suggestions":
            music_routes.handle_get_suggestions(self, query)
        elif path == "/api/filter_search":
            music_routes.handle_get_filter_search(self, query)
        elif path == "/api/playlist":
            music_routes.handle_get_playlist(self, query)
        elif path == "/api/artist_shuffle":
            music_routes.handle_get_artist_shuffle(self, query)
        elif path == "/api/resolve_cover":
            music_routes.handle_get_resolve_cover(self, query)
        elif path == "/api/notes":
            social_routes.handle_get_notes(self, query)
        elif path == "/api/friends":
            social_routes.handle_get_friends(self, query)
        elif path == "/api/users/me":
            social_routes.handle_get_user_me(self, query)
        elif path == "/api/users/search":
            social_routes.handle_search_users(self, query)
        elif path == "/api/notes/events":
            social_routes.handle_get_note_events(self, query)
        elif path == "/api/clipboard":
            music_routes.handle_get_clipboard(self)
        elif path == "/api/spotify/profile":
            music_routes.handle_get_spotify_profile(self, query)
        elif path == "/api/spotify/playlists":
            music_routes.handle_get_spotify_playlists(self, query)
        elif path == "/api/spotify/import_status":
            music_routes.handle_get_spotify_import_status(self)
        elif path == "/api/check_update":
            force = query.get("force", ["0"])[0] in ("1", "true", "True")
            mock = query.get("mock", ["0"])[0] in ("1", "true", "True")
            try:
                import updater
                res = updater.check_for_updates(force=force, mock=mock)
            except Exception as e:
                res = {"has_update": False, "error": str(e)}
            self._send_json(res, 200)
        elif path == "/api/update/status":
            try:
                import updater
                st = updater.direct_updater.get_status()
            except Exception as e:
                st = {"active": False, "status": "error", "error": str(e)}
            self._send_json(st, 200)
        elif path in ("/api/ui/open_settings", "/api/open_settings"):
            tab = int(query.get("tab", [0])[0])
            mock_upd = query.get("mock", ["0"])[0] in ("1", "true", "True")
            _pending_ui_action = {
                "action": "open_settings",
                "tab": tab,
                "mock_update": mock_upd,
                "current_version": "1.0.1",
                "latest_version": "v1.0.2",
                "release_url": "https://github.com/trancongduyhieu/FrostifyLocal/releases"
            }
            try:
                import launcher_win
                if hasattr(launcher_win, "request_open_settings"):
                    launcher_win.request_open_settings(tab, mock_update=mock_upd)
            except Exception:
                pass
            self._send_json({"success": True}, 200)
        elif path == "/api/ui/pending_action":
            act = _pending_ui_action
            _pending_ui_action = None
            self._send_json(act or {}, 200)
        elif path in ("/api/ui/screenshot", "/api/screenshot"):
            try:
                import launcher_win
                p = launcher_win.grab_screenshot() if hasattr(launcher_win, "grab_screenshot") else ""
                self._send_json({"success": bool(p), "path": p}, 200)
            except Exception as e:
                self._send_json({"success": False, "error": str(e)}, 500)
        elif path == "/api/ui/debug":
            try:
                import launcher_win
                res = {
                    "bridge": str(launcher_win.bridge_ref[0]),
                    "main_win": str(launcher_win.main_win_ref[0]),
                    "engine": str(launcher_win.engine_ref[0]),
                }
                if launcher_win.engine_ref[0]:
                    res["rootObjects"] = [str(o) for o in launcher_win.engine_ref[0].rootObjects()]
                self._send_json(res, 200)
            except Exception as e:
                self._send_json({"error": str(e)}, 500)
        else:
            self.send_response(404)
            self._send_cors_headers()
            self.end_headers()

    def do_POST(self):
        if self.path in ("/api/auth/cookies", "/api/auth/sync"):
            music_routes.handle_post_auth_cookies(self, self._read_post_body())
        elif self.path in ("/api/auth/auto-sync", "/api/auth/auto_sync"):
            music_routes.handle_post_auth_auto_sync(self)
        elif self.path == "/api/open_url":
            try:
                data = self._read_post_json()
                target_url = data.get("url", "")
                if target_url:
                    if sys.platform == "win32" and hasattr(os, "startfile"):
                        os.startfile(target_url)
                    else:
                        import webbrowser
                        webbrowser.open(target_url)
                self._send_json({"success": True}, 200)
            except Exception as e:
                self._send_json({"success": False, "error": str(e)}, 500)
        elif self.path == "/api/update/start":
            try:
                import updater
                data = self._read_post_json()
                dl_url = data.get("download_url") if isinstance(data, dict) else None
                tgt_ver = data.get("target_version") if isinstance(data, dict) else None
                res = updater.direct_updater.start_download_update(dl_url, tgt_ver)
                self._send_json(res, 200 if res.get("success") else 400)
            except Exception as e:
                self._send_json({"success": False, "error": str(e)}, 500)
        elif self.path == "/api/update/apply":
            try:
                import updater
                res = updater.direct_updater.apply_update_and_restart()
                self._send_json(res, 200 if res.get("success") else 400)
            except Exception as e:
                self._send_json({"success": False, "error": str(e)}, 500)
        elif self.path in ("/api/ui/open_settings", "/api/open_settings"):
            try:
                import launcher_win
                data = self._read_post_json()
                tab = int(data.get("tab", 0)) if isinstance(data, dict) else 0
                if hasattr(launcher_win, "request_open_settings"):
                    launcher_win.request_open_settings(tab)
                self._send_json({"success": True}, 200)
            except Exception as e:
                self._send_json({"success": False, "error": str(e)}, 500)
        elif self.path == "/api/spotify/auto-sync":
            music_routes.handle_post_spotify_auto_sync(self)
        elif self.path == "/api/spotify/validate":
            music_routes.handle_post_spotify_validate(self)
        elif self.path == "/api/spotify/resolve_url":
            music_routes.handle_post_spotify_resolve_url(self)
        elif self.path == "/api/spotify/import_playlist":
            music_routes.handle_post_spotify_import(self)
        elif self.path == "/api/spotify/cancel_import":
            music_routes.handle_post_spotify_cancel_import(self)
        elif self.path == "/api/users/update_profile":
            social_routes.handle_post_update_profile(self, self._read_post_json())
        elif self.path == "/api/users/regenerate_pin":
            social_routes.handle_post_regenerate_pin(self, self._read_post_json())
        elif self.path == "/api/users/offline":
            social_routes.handle_post_user_offline(self, self._read_post_json())
        elif self.path == "/api/notes":
            social_routes.handle_post_publish_note(self, self._read_post_json())
        elif self.path == "/api/notes/delete":
            social_routes.handle_post_delete_note(self, self._read_post_json())
        elif self.path == "/api/notes/events":
            social_routes.handle_post_note_event(self, self._read_post_json())
        elif self.path == "/api/now_playing":
            social_routes.handle_post_now_playing(self, self._read_post_json())
        elif self.path == "/api/friends/request":
            social_routes.handle_post_friend_request(self, self._read_post_json())
        elif self.path == "/api/friends/respond":
            social_routes.handle_post_friend_respond(self, self._read_post_json())
        elif self.path == "/api/friends/remove":
            social_routes.handle_post_friend_remove(self, self._read_post_json())
        else:
            self.send_response(404)
            self._send_cors_headers()
            self.end_headers()

    def log_message(self, format, *args):
        # Silence default stderr logging
        pass


def run_server():
    server_address = (HOST, PORT)
    try:
        httpd = ThreadingHTTPServer(server_address, AuthWebhookHandler)
        print(f"Nutsty Local IPC Bridge ready (127.0.0.1:{PORT}) | Global Social: {GLOBAL_RELAY_CLIENT.relay_url}")
        httpd.serve_forever()
    except OSError as e:
        if "Address already in use" in str(e):
            print(f"Nutsty Local IPC Bridge (port {PORT}) already active.")
        else:
            sys.stderr.write(f"Auth server error: {e}\n")


main = run_server

if __name__ == "__main__":
    run_server()
