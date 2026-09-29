#!/usr/bin/env python3
"""
Nutsty Cloud Relay Client, Local SQLite D1 Engine, and Identity/Vault Single Source of Truth (SSOT).
Extracted from auth_server.py for clean modularity and CodeGraph AST indexing.
"""
import os
import sys
import json
import time
import glob
import uuid
import random
import sqlite3
import ssl
import urllib.request
import urllib.error
import urllib.parse
from datetime import datetime

BACKEND_DIR = os.path.dirname(os.path.abspath(__file__))
if BACKEND_DIR not in sys.path:
    sys.path.insert(0, BACKEND_DIR)

try:
    from . import platform_compat as pc
except (ImportError, ValueError):
    import platform_compat as pc

pc.configure_windows_ssl()

def get_nutsty_config_dir():
    return pc.get_config_dir()

def get_cloud_relay_db_path():
    return os.path.join(get_nutsty_config_dir(), "nutsty_cloud_relay.db")


class CloudRelayEngine:
    """Local SQLite engine mirroring Cloudflare D1 schema for Nutsty Global Relay."""
    def __init__(self, db_path=None):
        self.db_path = db_path or get_cloud_relay_db_path()
        self._init_db()

    def _get_conn(self):
        conn = sqlite3.connect(self.db_path, timeout=10.0)
        conn.row_factory = sqlite3.Row
        return conn

    def _init_db(self):
        with self._get_conn() as conn:
            conn.executescript("""
            CREATE TABLE IF NOT EXISTS nutsty_users (
                id TEXT PRIMARY KEY,
                secret_key TEXT NOT NULL,
                username TEXT NOT NULL,
                discriminator TEXT NOT NULL,
                tag TEXT NOT NULL UNIQUE,
                avatar_url TEXT DEFAULT '',
                now_playing TEXT DEFAULT '',
                created_at INTEGER NOT NULL,
                updated_at INTEGER NOT NULL,
                last_active_at INTEGER NOT NULL
            );

            CREATE INDEX IF NOT EXISTS idx_users_tag ON nutsty_users(tag);
            CREATE INDEX IF NOT EXISTS idx_users_username ON nutsty_users(username);
            CREATE INDEX IF NOT EXISTS idx_users_discriminator ON nutsty_users(discriminator);

            CREATE TABLE IF NOT EXISTS nutsty_friendships (
                id TEXT PRIMARY KEY,
                user_id_1 TEXT NOT NULL,
                user_id_2 TEXT NOT NULL,
                status TEXT NOT NULL,
                initiated_by TEXT NOT NULL,
                created_at INTEGER NOT NULL,
                updated_at INTEGER NOT NULL,
                FOREIGN KEY(user_id_1) REFERENCES nutsty_users(id),
                FOREIGN KEY(user_id_2) REFERENCES nutsty_users(id),
                UNIQUE(user_id_1, user_id_2)
            );

            CREATE INDEX IF NOT EXISTS idx_friendships_u1 ON nutsty_friendships(user_id_1);
            CREATE INDEX IF NOT EXISTS idx_friendships_u2 ON nutsty_friendships(user_id_2);

            CREATE TABLE IF NOT EXISTS nutsty_events (
                id TEXT PRIMARY KEY,
                to_user_id TEXT NOT NULL,
                from_user_id TEXT NOT NULL,
                event_type TEXT NOT NULL,
                payload TEXT NOT NULL,
                consumed INTEGER DEFAULT 0,
                created_at INTEGER NOT NULL
            );

            CREATE INDEX IF NOT EXISTS idx_events_to_user ON nutsty_events(to_user_id, consumed);
            """)

    def find_available_discriminator(self, username, preferred=None):
        clean_user = username.strip()
        with self._get_conn() as conn:
            if preferred and len(str(preferred)) == 4 and str(preferred).isdigit():
                cand = f"{clean_user}#{str(preferred).zfill(4)}"
                row = conn.execute("SELECT id FROM nutsty_users WHERE tag = ?", (cand,)).fetchone()
                if not row:
                    return str(preferred).zfill(4)
            for _ in range(30):
                rnd = str(random.randint(1000, 9999))
                cand = f"{clean_user}#{rnd}"
                row = conn.execute("SELECT id FROM nutsty_users WHERE tag = ?", (cand,)).fetchone()
                if not row:
                    return rnd
            for i in range(1, 10000):
                pad = str(i).zfill(4)
                cand = f"{clean_user}#{pad}"
                row = conn.execute("SELECT id FROM nutsty_users WHERE tag = ?", (cand,)).fetchone()
                if not row:
                    return pad
        return "0001"

    def register(self, username, avatar_url="", client_secret=None, user_id=None, preferred_discriminator=None):
        clean_user = (username or "User").strip()[:32]
        now = int(time.time() * 1000)
        with self._get_conn() as conn:
            if user_id and client_secret:
                row = conn.execute("SELECT * FROM nutsty_users WHERE id = ? AND secret_key = ?", (user_id, client_secret)).fetchone()
                if row:
                    if avatar_url or clean_user != row["username"]:
                        new_avatar = avatar_url if avatar_url else row["avatar_url"]
                        conn.execute("UPDATE nutsty_users SET avatar_url = ?, last_active_at = ? WHERE id = ?", (new_avatar, now, user_id))
                    else:
                        conn.execute("UPDATE nutsty_users SET last_active_at = ? WHERE id = ?", (now, user_id))
                    refreshed = conn.execute("SELECT id, username, discriminator, tag, avatar_url, now_playing FROM nutsty_users WHERE id = ?", (user_id,)).fetchone()
                    return {"success": True, "user": dict(refreshed), "secret_key": client_secret, "restored": True}

            new_user_id = f"usr_{uuid.uuid4().hex[:16]}"
            new_secret = uuid.uuid4().hex + uuid.uuid4().hex
            disc = self.find_available_discriminator(clean_user, preferred_discriminator)
            tag = f"{clean_user}#{disc}"
            conn.execute(
                "INSERT INTO nutsty_users (id, secret_key, username, discriminator, tag, avatar_url, now_playing, created_at, updated_at, last_active_at) VALUES (?, ?, ?, ?, ?, ?, '', ?, ?, ?)",
                (new_user_id, new_secret, clean_user, disc, tag, avatar_url or "", now, now, now)
            )
            return {
                "success": True,
                "user": {
                    "id": new_user_id,
                    "username": clean_user,
                    "discriminator": disc,
                    "tag": tag,
                    "avatar_url": avatar_url or "",
                    "now_playing": ""
                },
                "secret_key": new_secret,
                "restored": False
            }

    def update_profile(self, user_id, secret_key, new_username=None, new_discriminator=None, avatar_url=None):
        now = int(time.time() * 1000)
        with self._get_conn() as conn:
            user = conn.execute("SELECT * FROM nutsty_users WHERE id = ? AND secret_key = ?", (user_id, secret_key)).fetchone()
            if not user:
                return {"success": False, "error": "Unauthorized"}
            target_username = (new_username.strip()[:32] if new_username is not None and new_username.strip() else user["username"])
            target_disc = user["discriminator"]
            if new_discriminator is not None:
                d_str = str(new_discriminator).strip().zfill(4)
                if not (len(d_str) == 4 and d_str.isdigit() and d_str != "0000"):
                    return {"success": False, "error": "Discriminator must be 4 digits (0001-9999)"}
                target_disc = d_str
            target_tag = f"{target_username}#{target_disc}"
            if target_tag != user["tag"]:
                collision = conn.execute("SELECT id FROM nutsty_users WHERE tag = ? AND id != ?", (target_tag, user_id)).fetchone()
                if collision:
                    sugg = self.find_available_discriminator(target_username)
                    return {
                        "success": False,
                        "error": "Tag already taken",
                        "suggested_discriminator": sugg,
                        "suggested_tag": f"{target_username}#{sugg}" if sugg else None
                    }
            target_avatar = avatar_url if avatar_url is not None else user["avatar_url"]
            conn.execute(
                "UPDATE nutsty_users SET username = ?, discriminator = ?, tag = ?, avatar_url = ?, updated_at = ?, last_active_at = ? WHERE id = ?",
                (target_username, target_disc, target_tag, target_avatar, now, now, user_id)
            )
            updated = conn.execute("SELECT id, username, discriminator, tag, avatar_url, now_playing FROM nutsty_users WHERE id = ?", (user_id,)).fetchone()
            return {"success": True, "user": dict(updated)}

    def search(self, q, caller_user_id=None):
        clean_q = (q or "").strip()
        if not clean_q:
            return {"results": []}
        with self._get_conn() as conn:
            if "#" in clean_q:
                parts = clean_q.split("#", 1)
                u = parts[0].strip()
                d = parts[1].strip()
                if d:
                    rows = conn.execute(
                        "SELECT id, username, discriminator, tag, avatar_url, now_playing, last_active_at FROM nutsty_users WHERE tag LIKE ? LIMIT 20",
                        (f"{u}#{d}%",)
                    ).fetchall()
                else:
                    rows = conn.execute(
                        "SELECT id, username, discriminator, tag, avatar_url, now_playing, last_active_at FROM nutsty_users WHERE username LIKE ? LIMIT 20",
                        (f"%{u}%",)
                    ).fetchall()
            elif clean_q.isdigit() and len(clean_q) <= 4:
                pad = clean_q.zfill(4)
                rows = conn.execute(
                    "SELECT id, username, discriminator, tag, avatar_url, now_playing, last_active_at FROM nutsty_users WHERE discriminator = ? OR username LIKE ? LIMIT 20",
                    (pad, f"%{clean_q}%")
                ).fetchall()
            else:
                rows = conn.execute(
                    "SELECT id, username, discriminator, tag, avatar_url, now_playing, last_active_at FROM nutsty_users WHERE username LIKE ? LIMIT 20",
                    (f"%{clean_q}%",)
                ).fetchall()

            processed = []
            for r in rows:
                item = dict(r)
                if caller_user_id and item["id"] == caller_user_id:
                    continue
                status = "none"
                initiated_by = ""
                if caller_user_id:
                    u1 = min(caller_user_id, item["id"])
                    u2 = max(caller_user_id, item["id"])
                    f = conn.execute("SELECT status, initiated_by FROM nutsty_friendships WHERE user_id_1 = ? AND user_id_2 = ?", (u1, u2)).fetchone()
                    if f:
                        status = f["status"]
                        initiated_by = f["initiated_by"]
                item["friendship_status"] = status
                item["is_friend"] = (status == "accepted")
                item["has_outgoing_request"] = (status == "pending" and initiated_by == caller_user_id)
                item["has_incoming_request"] = (status == "pending" and initiated_by != caller_user_id)
                processed.append(item)
            return {"results": processed}

    def friend_request(self, from_user_id, secret_key, target_user_id):
        now = int(time.time() * 1000)
        with self._get_conn() as conn:
            caller = conn.execute("SELECT * FROM nutsty_users WHERE id = ? AND secret_key = ?", (from_user_id, secret_key)).fetchone()
            if not caller:
                return {"success": False, "error": "Unauthorized"}
            if not target_user_id or target_user_id == from_user_id:
                return {"success": False, "error": "Invalid target user"}
            target = conn.execute("SELECT * FROM nutsty_users WHERE id = ?", (target_user_id,)).fetchone()
            if not target:
                return {"success": False, "error": "Target user not found"}
            u1 = min(from_user_id, target_user_id)
            u2 = max(from_user_id, target_user_id)
            existing = conn.execute("SELECT * FROM nutsty_friendships WHERE user_id_1 = ? AND user_id_2 = ?", (u1, u2)).fetchone()
            if existing:
                if existing["status"] == "accepted":
                    return {"success": True, "message": "Already friends", "status": "accepted"}
                if existing["status"] == "pending":
                    if existing["initiated_by"] == from_user_id:
                        return {"success": True, "message": "Request already sent", "status": "pending"}
                    else:
                        conn.execute("UPDATE nutsty_friendships SET status = 'accepted', updated_at = ? WHERE id = ?", (now, existing["id"]))
                        evt_id = f"evt_{uuid.uuid4().hex[:16]}"
                        conn.execute(
                            "INSERT INTO nutsty_events (id, to_user_id, from_user_id, event_type, payload, consumed, created_at) VALUES (?, ?, ?, 'friend_accepted', ?, 0, ?)",
                            (evt_id, target_user_id, from_user_id, json.dumps({"id": caller["id"], "username": caller["username"], "tag": caller["tag"], "avatar_url": caller["avatar_url"]}), now)
                        )
                        return {"success": True, "message": "Mutual request auto-accepted", "status": "accepted"}
            rel_id = f"rel_{uuid.uuid4().hex[:16]}"
            conn.execute(
                "INSERT OR REPLACE INTO nutsty_friendships (id, user_id_1, user_id_2, status, initiated_by, created_at, updated_at) VALUES (?, ?, ?, 'pending', ?, ?, ?)",
                (rel_id, u1, u2, from_user_id, now, now)
            )
            evt_id = f"evt_{uuid.uuid4().hex[:16]}"
            conn.execute(
                "INSERT INTO nutsty_events (id, to_user_id, from_user_id, event_type, payload, consumed, created_at) VALUES (?, ?, ?, 'friend_request', ?, 0, ?)",
                (evt_id, target_user_id, from_user_id, json.dumps({"id": caller["id"], "username": caller["username"], "tag": caller["tag"], "avatar_url": caller["avatar_url"]}), now)
            )
            return {"success": True, "message": "Friend request sent", "status": "pending"}

    def friend_respond(self, user_id, secret_key, from_user_id, action):
        now = int(time.time() * 1000)
        with self._get_conn() as conn:
            caller = conn.execute("SELECT * FROM nutsty_users WHERE id = ? AND secret_key = ?", (user_id, secret_key)).fetchone()
            if not caller:
                return {"success": False, "error": "Unauthorized"}
            u1 = min(user_id, from_user_id)
            u2 = max(user_id, from_user_id)
            rel = conn.execute("SELECT * FROM nutsty_friendships WHERE user_id_1 = ? AND user_id_2 = ?", (u1, u2)).fetchone()
            if not rel:
                return {"success": False, "error": "No friendship relation found"}
            if action == "accept":
                conn.execute("UPDATE nutsty_friendships SET status = 'accepted', updated_at = ? WHERE id = ?", (now, rel["id"]))
                evt_id = f"evt_{uuid.uuid4().hex[:16]}"
                conn.execute(
                    "INSERT INTO nutsty_events (id, to_user_id, from_user_id, event_type, payload, consumed, created_at) VALUES (?, ?, ?, 'friend_accepted', ?, 0, ?)",
                    (evt_id, from_user_id, user_id, json.dumps({"id": caller["id"], "username": caller["username"], "tag": caller["tag"], "avatar_url": caller["avatar_url"]}), now)
                )
                return {"success": True, "status": "accepted"}
            else:
                conn.execute("DELETE FROM nutsty_friendships WHERE id = ?", (rel["id"],))
                return {"success": True, "status": "rejected"}

    def friend_remove(self, user_id, secret_key, target_user_id):
        now = int(time.time() * 1000)
        with self._get_conn() as conn:
            caller = conn.execute("SELECT * FROM nutsty_users WHERE id = ? AND secret_key = ?", (user_id, secret_key)).fetchone()
            if not caller:
                return {"success": False, "error": "Unauthorized"}
            u1 = min(user_id, target_user_id)
            u2 = max(user_id, target_user_id)
            conn.execute("DELETE FROM nutsty_friendships WHERE user_id_1 = ? AND user_id_2 = ?", (u1, u2))
            evt_id = f"evt_{uuid.uuid4().hex[:16]}"
            conn.execute(
                "INSERT INTO nutsty_events (id, to_user_id, from_user_id, event_type, payload, consumed, created_at) VALUES (?, ?, ?, 'friend_removed', ?, 0, ?)",
                (evt_id, target_user_id, user_id, json.dumps({"user_id": user_id}), now)
            )
            return {"success": True, "message": "Friend removed"}

    def get_friends(self, user_id, secret_key):
        with self._get_conn() as conn:
            caller = conn.execute("SELECT * FROM nutsty_users WHERE id = ? AND secret_key = ?", (user_id, secret_key)).fetchone()
            if not caller:
                return {"success": False, "error": "Unauthorized"}
            friends_rows = conn.execute("""
                SELECT u.id, u.username, u.discriminator, u.tag, u.avatar_url, u.now_playing, u.last_active_at, f.created_at as friendship_created_at
                FROM nutsty_friendships f
                JOIN nutsty_users u ON u.id = CASE WHEN f.user_id_1 = ? THEN f.user_id_2 ELSE f.user_id_1 END
                WHERE (f.user_id_1 = ? OR f.user_id_2 = ?) AND f.status = 'accepted'
                ORDER BY u.last_active_at DESC
            """, (user_id, user_id, user_id)).fetchall()

            reqs_rows = conn.execute("""
                SELECT u.id, u.username, u.discriminator, u.tag, u.avatar_url, f.created_at as requested_at
                FROM nutsty_friendships f
                JOIN nutsty_users u ON u.id = f.initiated_by
                WHERE (f.user_id_1 = ? OR f.user_id_2 = ?) AND f.status = 'pending' AND f.initiated_by != ?
                ORDER BY f.created_at DESC
            """, (user_id, user_id, user_id)).fetchall()

            now_ms = int(time.time() * 1000)
            friends_list = []
            for r in friends_rows:
                d = dict(r)
                is_online = (now_ms - (d.get("last_active_at") or 0)) < 25000
                d["is_online"] = is_online
                if not is_online:
                    d["now_playing"] = ""
                friends_list.append(d)

            return {
                "success": True,
                "friends": friends_list,
                "incoming_requests": [dict(r) for r in reqs_rows]
            }

    def get_events(self, user_id, secret_key):
        with self._get_conn() as conn:
            caller = conn.execute("SELECT * FROM nutsty_users WHERE id = ? AND secret_key = ?", (user_id, secret_key)).fetchone()
            if not caller:
                return {"success": False, "error": "Unauthorized"}
            rows = conn.execute(
                "SELECT id, to_user_id, from_user_id, event_type, payload, created_at FROM nutsty_events WHERE to_user_id = ? AND consumed = 0 ORDER BY created_at ASC",
                (user_id,)
            ).fetchall()
            if rows:
                conn.execute("UPDATE nutsty_events SET consumed = 1 WHERE to_user_id = ? AND consumed = 0", (user_id,))
            events = []
            for r in rows:
                d = dict(r)
                try:
                    d["payload"] = json.loads(d["payload"])
                except Exception:
                    pass
                events.append(d)
            return {"success": True, "events": events}

    def update_presence(self, user_id, secret_key, now_playing):
        now = int(time.time() * 1000)
        np_str = json.dumps(now_playing) if isinstance(now_playing, (dict, list)) else str(now_playing or "")
        with self._get_conn() as conn:
            caller = conn.execute("SELECT id FROM nutsty_users WHERE id = ? AND secret_key = ?", (user_id, secret_key)).fetchone()
            if not caller:
                return {"success": False, "error": "Unauthorized"}
            conn.execute("UPDATE nutsty_users SET now_playing = ?, last_active_at = ? WHERE id = ?", (np_str, now, user_id))
            return {"success": True}

    def set_offline(self, user_id, secret_key=None):
        with self._get_conn() as conn:
            if secret_key:
                caller = conn.execute("SELECT id FROM nutsty_users WHERE id = ? AND secret_key = ?", (user_id, secret_key)).fetchone()
                if not caller:
                    return {"success": False, "error": "Unauthorized"}
            conn.execute("UPDATE nutsty_users SET now_playing = '', last_active_at = 0 WHERE id = ?", (user_id,))
            return {"success": True}


def invalidate_cloud_identity_by_user_id(user_id):
    if not user_id:
        return
    d = get_nutsty_config_dir()
    for p in glob.glob(os.path.join(d, "nutsty_cloud_identity*.json")):
        try:
            with open(p, "r", encoding="utf-8") as f:
                data = json.load(f)
            if data.get("user_id") == user_id:
                os.remove(p)
                sys.stderr.write(f"[CloudRelayClient] Removed invalid/unauthorized cloud identity: {p}\n")
        except Exception:
            pass


class CloudRelayClient:
    """Client bridge: forwards to Cloudflare Worker if configured, else uses CloudRelayEngine."""
    def __init__(self, relay_url=None):
        self.relay_url = relay_url or os.getenv("NUTSTY_CLOUD_RELAY_URL", "").strip()
        if not self.relay_url:
            try:
                settings_p = os.path.join(get_nutsty_config_dir(), "nutsty_settings.json")
                if os.path.exists(settings_p):
                    with open(settings_p, "r", encoding="utf-8") as sf:
                        sdata = json.load(sf)
                        self.relay_url = (sdata.get("cloud_relay_url") or sdata.get("relay_url") or "").strip()
            except Exception:
                pass
        if not self.relay_url:
            self.relay_url = "https://nutsty-global-relay.nutsty-global-relay.workers.dev"
        self.local_engine = CloudRelayEngine()

    def is_external(self):
        return self.relay_url.startswith("http://") or self.relay_url.startswith("https://")

    def _http_request(self, method, endpoint, data=None, params=None):
        if not self.is_external():
            return None
        url = self.relay_url.rstrip("/") + endpoint
        if params:
            url += "?" + urllib.parse.urlencode(params)

        # Priority 1: Use requests library with auto-retry and SSL tolerance
        try:
            import requests
            headers = {
                "Content-Type": "application/json",
                "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36 NutstyClient/1.0"
            }
            try:
                r = requests.request(method, url, json=data, params=params, headers=headers, timeout=5.0)
                if r.status_code == 401:
                    uid = (data or {}).get("user_id") or (params or {}).get("user_id") or (data or {}).get("from_user_id")
                    if uid:
                        invalidate_cloud_identity_by_user_id(uid)
                    return {"success": False, "error": "Unauthorized", "unauthorized": True}
                if r.status_code < 500:
                    return r.json()
            except Exception as req_err:
                if "CERTIFICATE_VERIFY_FAILED" in str(req_err) or "SSLError" in type(req_err).__name__:
                    try:
                        import urllib3
                        urllib3.disable_warnings()
                        r = requests.request(method, url, json=data, params=params, headers=headers, timeout=5.0, verify=False)
                        if r.status_code == 401:
                            uid = (data or {}).get("user_id") or (params or {}).get("user_id") or (data or {}).get("from_user_id")
                            if uid:
                                invalidate_cloud_identity_by_user_id(uid)
                            return {"success": False, "error": "Unauthorized", "unauthorized": True}
                        if r.status_code < 500:
                            return r.json()
                    except Exception:
                        pass
        except Exception:
            pass

        # Priority 2: urllib.request with unverified SSL fallback
        req = urllib.request.Request(url, method=method)
        req.add_header("Content-Type", "application/json")
        req.add_header("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36 NutstyClient/1.0")
        body = json.dumps(data).encode("utf-8") if data is not None else None
        ctx = None
        try:
            import certifi
            ctx = ssl.create_default_context(cafile=certifi.where())
        except Exception:
            try:
                ctx = ssl.create_default_context()
            except Exception:
                ctx = None

        try:
            with urllib.request.urlopen(req, data=body, timeout=5.0, context=ctx) as resp:
                return json.loads(resp.read().decode("utf-8"))
        except urllib.error.HTTPError as he:
            if he.code == 401:
                uid = (data or {}).get("user_id") or (params or {}).get("user_id") or (data or {}).get("from_user_id")
                if uid:
                    invalidate_cloud_identity_by_user_id(uid)
                return {"success": False, "error": "Unauthorized", "unauthorized": True}
            sys.stderr.write(f"[CloudRelayClient request failed]: {he}\n")
            return None
        except Exception as e:
            if "CERTIFICATE_VERIFY_FAILED" in str(e) or "SSL" in type(e).__name__:
                try:
                    unverified_ctx = ssl._create_unverified_context()
                    req_retry = urllib.request.Request(url, method=method)
                    req_retry.add_header("Content-Type", "application/json")
                    req_retry.add_header("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) NutstyClient/1.0")
                    with urllib.request.urlopen(req_retry, data=body, timeout=5.0, context=unverified_ctx) as resp:
                        return json.loads(resp.read().decode("utf-8"))
                except urllib.error.HTTPError as he2:
                    if he2.code == 401:
                        uid = (data or {}).get("user_id") or (params or {}).get("user_id") or (data or {}).get("from_user_id")
                        if uid:
                            invalidate_cloud_identity_by_user_id(uid)
                        return {"success": False, "error": "Unauthorized", "unauthorized": True}
                    sys.stderr.write(f"[CloudRelayClient request failed]: {he2}\n")
                    return None
                except Exception as e2:
                    sys.stderr.write(f"[CloudRelayClient request failed]: {e2}\n")
                    return None
            if "401" in str(e):
                uid = (data or {}).get("user_id") or (params or {}).get("user_id") or (data or {}).get("from_user_id")
                if uid:
                    invalidate_cloud_identity_by_user_id(uid)
                return {"success": False, "error": "Unauthorized", "unauthorized": True}
            sys.stderr.write(f"[CloudRelayClient request failed]: {e}\n")
            return None

    def register(self, username, avatar_url="", client_secret=None, user_id=None, preferred_discriminator=None):
        if self.is_external():
            res = self._http_request("POST", "/api/users/register", data={
                "username": username,
                "avatar_url": avatar_url,
                "client_secret": client_secret,
                "user_id": user_id,
                "preferred_discriminator": preferred_discriminator
            })
            if res and res.get("success"):
                return res
        return {"success": False, "error": "Cloud relay unreachable"}

    def update_profile(self, user_id, secret_key, new_username=None, new_discriminator=None, avatar_url=None):
        if self.is_external():
            res = self._http_request("POST", "/api/users/update_profile", data={
                "user_id": user_id,
                "secret_key": secret_key,
                "new_username": new_username,
                "new_discriminator": new_discriminator,
                "avatar_url": avatar_url
            })
            if res:
                return res
        return {"success": False, "error": "Cloud relay unreachable"}

    def search(self, q, caller_user_id=None):
        if self.is_external():
            res = self._http_request("GET", "/api/users/search", params={"q": q, "user_id": caller_user_id or ""})
            if res and "results" in res:
                return res
        return {"success": False, "results": []}

    def friend_request(self, from_user_id, secret_key, target_user_id):
        if self.is_external():
            res = self._http_request("POST", "/api/friends/request", data={
                "from_user_id": from_user_id,
                "secret_key": secret_key,
                "target_user_id": target_user_id
            })
            if res and res.get("success"):
                return res
        return {"success": False, "error": "Cloud relay unreachable"}

    def friend_respond(self, user_id, secret_key, from_user_id, action):
        if self.is_external():
            res = self._http_request("POST", "/api/friends/respond", data={
                "user_id": user_id,
                "secret_key": secret_key,
                "from_user_id": from_user_id,
                "action": action
            })
            if res and res.get("success"):
                return res
        return {"success": False, "error": "Cloud relay unreachable"}

    def friend_remove(self, user_id, secret_key, target_user_id):
        if self.is_external():
            res = self._http_request("POST", "/api/friends/remove", data={
                "user_id": user_id,
                "secret_key": secret_key,
                "target_user_id": target_user_id
            })
            if res and res.get("success"):
                return res
        return {"success": False, "error": "Cloud relay unreachable"}

    def get_friends(self, user_id, secret_key):
        if self.is_external():
            res = self._http_request("GET", "/api/friends", params={"user_id": user_id, "secret_key": secret_key})
            if res and res.get("success"):
                return res
        return {"success": False, "friends": [], "incoming_requests": []}

    def get_events(self, user_id, secret_key):
        if self.is_external():
            res = self._http_request("GET", "/api/events", params={"user_id": user_id, "secret_key": secret_key})
            if res and res.get("success"):
                return res
        return {"success": False, "events": []}

    def update_presence(self, user_id, secret_key, now_playing):
        if self.is_external():
            res = self._http_request("POST", "/api/users/presence", data={
                "user_id": user_id,
                "secret_key": secret_key,
                "now_playing": now_playing
            })
            if res and res.get("success"):
                return res
        return {"success": False, "error": "Cloud relay unreachable"}

    def set_offline(self, user_id, secret_key):
        if self.is_external():
            res = self._http_request("POST", "/api/users/offline", data={
                "user_id": user_id,
                "secret_key": secret_key
            })
            if res and res.get("success"):
                return res
        return {"success": False, "error": "Cloud relay unreachable"}

    def publish_note(self, user_id, secret_key, note_text, track=None, now_playing=None):
        if self.is_external():
            res = self._http_request("POST", "/api/notes", data={
                "user_id": user_id,
                "secret_key": secret_key,
                "note_text": note_text,
                "track": track,
                "now_playing": now_playing
            })
            if res and res.get("success"):
                return res
        return None

    def get_notes(self, user_id, secret_key):
        if self.is_external():
            res = self._http_request("GET", "/api/notes", params={
                "user_id": user_id,
                "secret_key": secret_key
            })
            if res and res.get("success"):
                return res
        return None

    def delete_note(self, user_id, secret_key):
        if self.is_external():
            res = self._http_request("POST", "/api/notes/delete", data={
                "user_id": user_id,
                "secret_key": secret_key
            })
            if res and res.get("success"):
                return res
        return None

    def send_note_event(self, user_id, secret_key, to_user_id=None, to_tag=None, event="chat_bubble", data=None):
        if self.is_external():
            res = self._http_request("POST", "/api/notes/events", data={
                "user_id": user_id,
                "secret_key": secret_key,
                "to_user_id": to_user_id,
                "to_tag": to_tag,
                "event": event,
                "data": data
            })
            if res and res.get("success"):
                return res
        return None


GLOBAL_RELAY_CLIENT = CloudRelayClient()
_cloud_notes_cache = {"ts": 0.0, "data": [], "my_note": None}


def resolve_profile_suffix(profile=None, user_email=None):
    return pc.get_profile_suffix(profile, user_email)


def get_cloud_identity_path(profile_suffix=""):
    return str(pc.get_cloud_identity_file(profile_suffix))


def load_cloud_identity(profile_suffix=""):
    p = get_cloud_identity_path(profile_suffix)
    if os.path.exists(p):
        try:
            with open(p, "r", encoding="utf-8") as f:
                data = json.load(f)
                if isinstance(data, dict) and data.get("user_id") and data.get("secret_key"):
                    return data
        except Exception:
            pass
    return None


def save_cloud_identity(data, profile_suffix=""):
    p = get_cloud_identity_path(profile_suffix)
    try:
        with open(p, "w", encoding="utf-8") as f:
            json.dump(data, f, indent=2, ensure_ascii=False)
        os.chmod(p, 0o600)
    except Exception:
        pass


def ensure_cloud_identity(profile_suffix="", fallback_name=None, fallback_avatar=None, force_recreate=False):
    if force_recreate:
        p = get_cloud_identity_path(profile_suffix)
        if os.path.exists(p):
            try:
                os.remove(p)
            except Exception:
                pass
        ident = None
    else:
        ident = load_cloud_identity(profile_suffix)

    d = get_nutsty_config_dir()
    cache_path = os.path.join(d, f"nutsty_user_cache{profile_suffix}.json")
    user_name = fallback_name
    avatar_url = fallback_avatar or ""

    if os.path.exists(cache_path):
        try:
            with open(cache_path, "r", encoding="utf-8") as f:
                cdata = json.load(f)
                if not user_name:
                    user_name = cdata.get("name") or (cdata.get("email", "").split("@")[0] if "@" in cdata.get("email", "") else "")
                if not avatar_url:
                    avatar_url = cdata.get("avatar", "")
        except Exception:
            pass

    # If identity exists, sync username (if placeholder) and sync avatar (if available and changed)
    if ident and ident.get("user_id") and ident.get("secret_key"):
        cur_uname = (ident.get("username") or "").strip()
        is_placeholder = cur_uname in ("", "User", "Nutsty User", "Khách", "Guest")
        target_name = None
        if not ident.get("custom_username") and is_placeholder and user_name and user_name not in ("User", "Nutsty User", "Shiraori", "Khách", "Guest"):
            target_name = user_name

        current_avatar = (ident.get("avatar_url") or "").strip()
        target_avatar = (avatar_url or "").strip()

        needs_avatar_sync = bool(target_avatar and target_avatar != current_avatar)
        needs_name_sync = bool(target_name and target_name != cur_uname)

        if needs_avatar_sync or needs_name_sync:
            try:
                up_res = GLOBAL_RELAY_CLIENT.update_profile(
                    user_id=ident["user_id"],
                    secret_key=ident["secret_key"],
                    new_username=target_name if needs_name_sync else None,
                    avatar_url=target_avatar if needs_avatar_sync else (current_avatar or None)
                )
                if up_res and up_res.get("success") and up_res.get("user"):
                    u = up_res["user"]
                    ident["username"] = u["username"]
                    ident["tag"] = u["tag"]
                    ident["discriminator"] = u["discriminator"]
                    if "avatar_url" in u:
                        ident["avatar_url"] = u.get("avatar_url") or ""
                    save_cloud_identity(ident, profile_suffix)
                elif up_res and up_res.get("unauthorized"):
                    sys.stderr.write(f"[CloudRelay] Cloud identity unauthorized for {ident.get('user_id')}. Re-registering as {user_name}...\n")
            except Exception as e:
                sys.stderr.write(f"[CloudRelay] Sync profile error: {e}\n")
        return ident

    if not user_name:
        if profile_suffix == "_user2":
            user_name = "Hiếu Trần"
        else:
            user_name = "Nutsty User"

    reg_res = GLOBAL_RELAY_CLIENT.register(
        username=user_name,
        avatar_url=avatar_url
    )
    if reg_res and reg_res.get("success") and reg_res.get("user"):
        u = reg_res["user"]
        ident = {
            "user_id": u["id"],
            "secret_key": reg_res["secret_key"],
            "username": u["username"],
            "discriminator": u["discriminator"],
            "tag": u["tag"],
            "avatar_url": u.get("avatar_url", "")
        }
        save_cloud_identity(ident, profile_suffix)
        return ident

    return {
        "user_id": f"usr_local{profile_suffix}",
        "secret_key": "local_secret",
        "username": user_name,
        "discriminator": "0001",
        "tag": f"{user_name}#0001",
        "avatar_url": avatar_url
    }


def get_canonical_user(profile_suffix=""):
    """SSOT helper returning canonical identity dict for current profile."""
    ident = ensure_cloud_identity(profile_suffix)
    return {
        "user_id": ident.get("user_id", ""),
        "secret_key": ident.get("secret_key", ""),
        "username": ident.get("username", "Nutsty User"),
        "name": ident.get("username", "Nutsty User"),
        "discriminator": ident.get("discriminator", "0001"),
        "tag": ident.get("tag", "Nutsty User#0001"),
        "email": (ident.get("tag") or "Nutsty User#0001").lower(),
        "avatar": ident.get("avatar_url", "") or "",
        "avatar_url": ident.get("avatar_url", "") or ""
    }


def get_notes_vault_path():
    return str(pc.get_notes_vault_file())


def load_notes_vault():
    p = get_notes_vault_path()
    if os.path.exists(p):
        try:
            with open(p, "r", encoding="utf-8") as f:
                return json.load(f)
        except Exception:
            pass
    return {}


def save_notes_vault(data):
    p = get_notes_vault_path()
    try:
        with open(p, "w", encoding="utf-8") as f:
            json.dump(data, f, indent=2, ensure_ascii=False)
    except Exception:
        pass


def get_events_vault_path():
    return str(pc.get_events_vault_file())


def load_events_vault():
    p = get_events_vault_path()
    if os.path.exists(p):
        try:
            with open(p, "r", encoding="utf-8") as f:
                return json.load(f)
        except Exception:
            pass
    return []


def save_events_vault(data):
    p = get_events_vault_path()
    try:
        with open(p, "w", encoding="utf-8") as f:
            json.dump(data, f, indent=2, ensure_ascii=False)
    except Exception:
        pass


def get_friends_vault_path():
    return str(pc.get_friends_vault_file())


def load_friends_vault():
    p = get_friends_vault_path()
    if os.path.exists(p):
        try:
            with open(p, "r", encoding="utf-8") as f:
                data = json.load(f)
                if isinstance(data, dict):
                    return data
        except Exception:
            pass
    return {}


def save_friends_vault(data):
    p = get_friends_vault_path()
    try:
        with open(p, "w", encoding="utf-8") as f:
            json.dump(data, f, indent=2, ensure_ascii=False)
    except Exception:
        pass


def get_friend_requests_vault_path():
    return str(pc.get_friend_requests_vault_file())


def load_friend_requests_vault():
    p = get_friend_requests_vault_path()
    if os.path.exists(p):
        try:
            with open(p, "r", encoding="utf-8") as f:
                data = json.load(f)
                if isinstance(data, list):
                    for r in data:
                        if isinstance(r, dict):
                            if "to_email" in r:
                                r["to_email"] = resolve_canonical_user_email(r["to_email"])
                            if "from_email" in r:
                                r["from_email"] = resolve_canonical_user_email(r["from_email"])
                    return data
        except Exception:
            pass
    return []


def save_friend_requests_vault(data):
    p = get_friend_requests_vault_path()
    try:
        with open(p, "w", encoding="utf-8") as f:
            json.dump(data, f, indent=2, ensure_ascii=False)
    except Exception:
        pass


def normalize_user_email(email):
    return (email or "").strip().lower()


def resolve_canonical_user_email(ident):
    if not ident:
        return ""
    s = str(ident).strip().lower()
    try:
        vault = load_profiles_vault()
        for em_key, prof in vault.items():
            em = prof.get("email", em_key).lower()
            tag = (prof.get("nutsty_tag") or "").lower()
            pin = str(prof.get("pin_code") or "")
            if s == em or (tag and s == tag) or (pin and s == pin):
                return em
    except Exception:
        pass
    try:
        known = get_all_known_users()
        for k, u in known.items():
            u_em = (u.get("email") or k).lower()
            u_tag = (u.get("nutsty_tag") or "").lower()
            u_pin = str(u.get("pin_code") or "")
            u_handle = (u.get("handle") or "").lower()
            if s == k.lower() or s == u_em or (u_tag and s == u_tag) or (u_pin and s == u_pin) or (u_handle and s == u_handle):
                return u_em
    except Exception:
        pass
    return normalize_user_email(s)


def get_user_all_identifiers(ident):
    if not ident:
        return set()
    s = str(ident).strip().lower()
    canonical = resolve_canonical_user_email(s)
    ids = set()
    if s:
        ids.add(s)
    if canonical:
        ids.add(canonical)
    try:
        vault = load_profiles_vault()
        for em_key, prof in vault.items():
            if prof.get("email", em_key).lower() == canonical:
                ids.add(em_key.lower())
                if prof.get("nutsty_tag"):
                    ids.add(prof["nutsty_tag"].lower())
                if prof.get("pin_code"):
                    ids.add(str(prof["pin_code"]))
    except Exception:
        pass
    try:
        known = get_all_known_users()
        for k, u in known.items():
            if (u.get("email") or k).lower() == canonical:
                ids.add(k.lower())
                if u.get("handle"):
                    ids.add(u["handle"].lower())
                if u.get("nutsty_tag"):
                    ids.add(u["nutsty_tag"].lower())
                if u.get("pin_code"):
                    ids.add(str(u["pin_code"]))
    except Exception:
        pass
    return ids


def get_profiles_vault_path():
    return str(pc.get_profiles_vault_file())


def load_profiles_vault():
    p = get_profiles_vault_path()
    if os.path.exists(p):
        try:
            with open(p, "r", encoding="utf-8") as f:
                data = json.load(f)
                if isinstance(data, dict):
                    return data
        except Exception:
            pass
    return {}


def save_profiles_vault(data):
    p = get_profiles_vault_path()
    try:
        with open(p, "w", encoding="utf-8") as f:
            json.dump(data, f, indent=2, ensure_ascii=False)
    except Exception:
        pass


def ensure_user_profile(email):
    norm = normalize_user_email(email)
    vault = load_profiles_vault()
    known = get_all_known_users()
    u_info = known.get(norm, {})

    if norm not in vault:
        pin = str(random.randint(100000, 999999))
        base_name = u_info.get("name") or (norm.split("@")[0] if "@" in norm else norm)
        tag = f"{base_name}#{random.randint(1000, 9999)}"
        vault[norm] = {
            "email": norm,
            "name": u_info.get("name") or base_name,
            "avatar": u_info.get("avatar") or "",
            "pin_code": pin,
            "nutsty_tag": tag
        }
        save_profiles_vault(vault)

    prof = vault[norm]
    if not prof.get("pin_code"):
        prof["pin_code"] = str(random.randint(100000, 999999))
        save_profiles_vault(vault)
    if not prof.get("nutsty_tag"):
        base = prof.get("name") or norm.split("@")[0]
        prof["nutsty_tag"] = f"{base}#{random.randint(1000, 9999)}"
        save_profiles_vault(vault)
    return prof


def regenerate_user_pin(email):
    norm = normalize_user_email(email)
    ensure_user_profile(norm)
    vault = load_profiles_vault()
    new_pin = str(random.randint(100000, 999999))
    if norm in vault:
        vault[norm]["pin_code"] = new_pin
        save_profiles_vault(vault)
    return new_pin


def get_all_known_users():
    d = get_nutsty_config_dir()
    users = {}
    for p in glob.glob(os.path.join(d, "nutsty_user_cache*.json")):
        try:
            with open(p, "r", encoding="utf-8") as f:
                u = json.load(f)
                email = (u.get("email") or "").strip().lower()
                name = u.get("name") or email.split("@")[0]
                avatar = u.get("avatar", "")
                handle = (u.get("handle") or "").strip().lower()
                if email:
                    users[email] = {
                        "email": email,
                        "name": name,
                        "avatar": avatar,
                        "handle": handle
                    }
                if handle:
                    users[handle] = {
                        "email": email,
                        "name": name,
                        "avatar": avatar,
                        "handle": handle
                    }
        except Exception:
            pass

    vault = load_notes_vault()
    for k, item in vault.items():
        iem = (item.get("user_email") or "").strip().lower()
        if iem:
            existing = users.get(iem, {})
            users[iem] = {
                "email": item.get("user_email", ""),
                "name": item.get("user_name") or existing.get("name") or iem.split("@")[0],
                "avatar": item.get("avatar_url") or existing.get("avatar", ""),
                "handle": existing.get("handle", ""),
                "pin_code": existing.get("pin_code", ""),
                "nutsty_tag": existing.get("nutsty_tag", "")
            }

    prof_vault = load_profiles_vault()
    for pem, pinfo in prof_vault.items():
        if pem in users:
            users[pem].update(pinfo)
        else:
            users[pem] = pinfo
    return users


def sync_local_friends_files(user_email, friends_list):
    d = get_nutsty_config_dir()
    u_norm = user_email.strip().lower()
    for p in glob.glob(os.path.join(d, "nutsty_user_cache*.json")):
        try:
            with open(p, "r", encoding="utf-8") as f:
                uc = json.load(f)
                if (uc.get("email") or "").strip().lower() == u_norm:
                    base = os.path.basename(p)
                    suffix = base.replace("nutsty_user_cache", "").replace(".json", "")
                    target_file = os.path.join(d, f"nutsty_friends{suffix}.json")
                    with open(target_file, "w", encoding="utf-8") as tf:
                        json.dump(friends_list, tf, indent=2, ensure_ascii=False)
        except Exception:
            pass
