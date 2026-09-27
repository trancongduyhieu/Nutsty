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
        else:
            self.send_response(404)
            self._send_cors_headers()
            self.end_headers()

    def do_POST(self):
        if self.path in ("/api/auth/cookies", "/api/auth/sync"):
            music_routes.handle_post_auth_cookies(self, self._read_post_body())
        elif self.path == "/api/spotify/auto-sync":
            music_routes.handle_post_spotify_auto_sync(self)
        elif self.path == "/api/spotify/validate":
            music_routes.handle_post_spotify_validate(self)
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
