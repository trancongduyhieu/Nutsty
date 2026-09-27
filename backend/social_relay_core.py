#!/usr/bin/env python3
"""
Nutsty SocialRelayCore — Deep Module for Friends, 24h Notes, and Co-Listening
Consolidates resident caching, canonical identity resolution (SSOT #2),
peer normalization (SSOT #3), and event distribution behind a clean seam.
Informed by ADR-0001 and CONTEXT.md.
"""

import os
import sys
import json
import time
import uuid
import threading
from pathlib import Path
from typing import Dict, Any, List, Optional, Tuple, Set

try:
    from . import platform_compat as pc
    from .cloud_relay_client import (
        GLOBAL_RELAY_CLIENT,
        ensure_cloud_identity,
        resolve_profile_suffix,
        get_user_all_identifiers,
        load_notes_vault,
        save_notes_vault,
        load_events_vault,
        save_events_vault,
    )
except (ImportError, ValueError):
    import platform_compat as pc
    from cloud_relay_client import (
        GLOBAL_RELAY_CLIENT,
        ensure_cloud_identity,
        resolve_profile_suffix,
        get_user_all_identifiers,
        load_notes_vault,
        save_notes_vault,
        load_events_vault,
        save_events_vault,
    )

pc.configure_windows_ssl()

NOTE_TTL_SECONDS = 86400  # 24 hours
PRESENCE_ONLINE_THRESHOLD = 25.0  # seconds


class SocialRelayCore:
    """
    Deep Module managing social state, 24h notes, and real-time co-listening.
    Hides cache eviction, multi-identifier normalization, and cloud relay polling.
    """

    def __init__(self, transport=None):
        self._lock = threading.RLock()
        self.transport = transport or GLOBAL_RELAY_CLIENT
        self._notes_cache: Dict[str, Dict[str, Any]] = {}
        self._my_note_cache: Optional[Dict[str, Any]] = None
        self._last_feed_sync: float = 0.0
        self._co_listeners: Dict[str, Dict[str, Any]] = {}
        self._chat_dedup_set: Set[str] = set()
        self._recent_chats: List[Dict[str, Any]] = []

    # -------------------------------------------------------------------------
    # Identity & Normalization Helpers (SSOT #2 & #3)
    # -------------------------------------------------------------------------

    def get_caller_identity(self, profile: str = "", user_email: str = "") -> Dict[str, Any]:
        """Resolves the active user identity (SSOT #2)."""
        suffix = resolve_profile_suffix(profile, user_email)
        return ensure_cloud_identity(suffix)

    def normalize_peer(self, raw: Dict[str, Any]) -> Dict[str, Any]:
        """
        Normalizes any peer dictionary strictly to SSOT #3 contract:
        { user_id, tag, email, name, avatar, is_online, last_active_at, now_playing }
        """
        uid = str(raw.get("user_id") or raw.get("id") or "").strip()
        tag = str(raw.get("tag") or raw.get("user_email") or "").strip()
        name = str(raw.get("user_name") or raw.get("name") or raw.get("username") or "Nutsty Friend").strip()
        avatar = str(raw.get("avatar_url") or raw.get("avatar") or "").strip()
        last_active = float(raw.get("last_active_at") or raw.get("last_active") or 0.0)
        
        # Normalize epoch timestamp (Cloudflare D1 stores ms while Python uses seconds)
        if last_active > 1e11:
            last_active = last_active / 1000.0

        # Calculate real-time presence
        now = time.time()
        if "is_online" in raw and raw["is_online"] is not None:
            is_online = bool(raw["is_online"])
        elif last_active > 0:
            diff = now - last_active
            is_online = 0 <= diff < PRESENCE_ONLINE_THRESHOLD
        else:
            is_online = False
        
        now_playing = raw.get("now_playing")
        if not is_online:
            now_playing = None

        return {
            "user_id": uid,
            "tag": tag,
            "email": tag,
            "name": name,
            "user_name": name,
            "avatar": avatar,
            "avatar_url": avatar,
            "is_online": is_online,
            "last_active_at": last_active,
            "now_playing": now_playing,
        }

    # -------------------------------------------------------------------------
    # 24h Notes & Friends Feed (Deepened Seam)
    # -------------------------------------------------------------------------

    def get_feed(self, profile: str = "", user_email: str = "") -> Dict[str, Any]:
        """
        Retrieves active 24h notes and friends list with unified deduplication.
        Encapsulates external cloud relay polling and offline fallback.
        """
        with self._lock:
            caller = self.get_caller_identity(profile, user_email)
            caller_uid = caller.get("user_id", "")
            caller_secret = caller.get("secret_key", "")
            now = time.time()

            # 1. External Cloud Relay Path
            if self.transport.is_external():
                res = self.transport.get_notes(caller_uid, caller_secret)
                if res and res.get("unauthorized"):
                    suffix = resolve_profile_suffix(profile, user_email)
                    caller = ensure_cloud_identity(suffix, force_recreate=True)
                    caller_uid = caller.get("user_id", "")
                    caller_secret = caller.get("secret_key", "")
                    res = self.transport.get_notes(caller_uid, caller_secret)

                if res and res.get("success"):
                    notes_raw = res.get("notes") or []
                    norm_notes = []
                    seen_uids = set()

                    for item in notes_raw:
                        if isinstance(item, dict):
                            norm = self.normalize_peer(item)
                            norm["note_text"] = item.get("note_text", "")
                            norm["track"] = item.get("track")
                            norm["created_at"] = item.get("created_at", 0)
                            norm["is_friend"] = True
                            if norm["user_id"]:
                                seen_uids.add(norm["user_id"].lower())
                            norm_notes.append(norm)

                    # Augment with any accepted friends who haven't posted a note
                    try:
                        fr_res = self.transport.get_friends(caller_uid, caller_secret)
                        for f in (fr_res.get("friends") or []):
                            f_norm = self.normalize_peer(f)
                            fid = f_norm["user_id"].lower()
                            if fid and fid not in seen_uids:
                                f_norm["note_text"] = ""
                                f_norm["track"] = None
                                f_norm["created_at"] = 0
                                f_norm["is_friend"] = True
                                norm_notes.append(f_norm)
                                seen_uids.add(fid)
                    except Exception:
                        pass

                    my_n = res.get("my_note")
                    if isinstance(my_n, dict):
                        my_n = self.normalize_peer(my_n)
                        my_n["note_text"] = res.get("my_note", {}).get("note_text", "")
                        my_n["track"] = res.get("my_note", {}).get("track")

                    self._notes_cache = {n["user_id"]: n for n in norm_notes if n.get("user_id")}
                    self._my_note_cache = my_n
                    self._last_feed_sync = now

                    return {
                        "success": True,
                        "notes": norm_notes,
                        "my_note": my_note_or_none(my_n),
                        "count": len(norm_notes),
                        "cached_at": now,
                    }

            # 2. Local Vault / In-Process Simulator Path
            vault = load_notes_vault()
            valid_notes = []
            cleaned_vault = {}
            my_note = None

            caller_all_ids = set(x.lower() for x in get_user_all_identifiers(caller_uid))

            for k, item in vault.items():
                if item.get("_expires_ts", 0) > now:
                    cleaned_vault[k] = item
                    i_norm = self.normalize_peer(item)
                    i_norm["note_text"] = item.get("note_text", "")
                    i_norm["track"] = item.get("track")
                    i_norm["created_at"] = item.get("created_at", 0)

                    # Determine if this item belongs to caller
                    item_ids = set(x.lower() for x in get_user_all_identifiers(i_norm["user_id"]))
                    if item_ids & caller_all_ids:
                        my_note = i_norm
                    else:
                        i_norm["is_friend"] = True
                        valid_notes.append(i_norm)

            if len(cleaned_vault) < len(vault):
                save_notes_vault(cleaned_vault)

            return {
                "success": True,
                "notes": valid_notes,
                "my_note": my_note,
                "count": len(valid_notes),
                "cached_at": now,
            }

    def publish_note(
        self,
        note_text: str,
        track: Optional[Dict[str, Any]] = None,
        profile: str = "",
        user_email: str = "",
    ) -> Dict[str, Any]:
        """
        Publishes a 24-hour note with automatic now-playing track extraction and caching.
        """
        with self._lock:
            caller = self.get_caller_identity(profile, user_email)
            caller_uid = caller.get("user_id", "")
            caller_secret = caller.get("secret_key", "")

            # 1. Harvest active track from local IPC if none explicitly supplied
            now_playing = None
            suffix = resolve_profile_suffix(profile, user_email)
            cur_track_file = Path(pc.get_temp_dir()) / f"nutsty_current_track{suffix}.json"
            if cur_track_file.exists():
                try:
                    with open(cur_track_file, "r", encoding="utf-8") as f:
                        meta = json.load(f)
                        if meta.get("title"):
                            now_playing = {
                                "title": meta.get("title", ""),
                                "artist": meta.get("artist", ""),
                                "cover": meta.get("artUrl") or meta.get("cover") or meta.get("image", ""),
                                "path": meta.get("path", ""),
                                "accent_color": meta.get("accent_color", ""),
                            }
                except Exception:
                    pass

            # 2. Delegate to Transport
            if self.transport.is_external():
                res = self.transport.publish_note(
                    user_id=caller_uid,
                    secret_key=caller_secret,
                    note_text=note_text[:120],
                    track=track,
                    now_playing=now_playing,
                )
                if res and res.get("success"):
                    self._my_note_cache = res.get("note")
                return res or {"success": False, "error": "Relay returned empty response"}

            # 3. Local Vault Persistence
            now = time.time()
            note_obj = {
                "user_id": caller_uid,
                "user_name": caller.get("username", "Nutsty User"),
                "tag": caller.get("tag", ""),
                "avatar_url": caller.get("avatar_url", ""),
                "note_text": note_text[:120],
                "track": track,
                "now_playing": now_playing,
                "created_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(now)),
                "_expires_ts": now + NOTE_TTL_SECONDS,
            }

            vault = load_notes_vault()
            vault[caller_uid] = note_obj
            save_notes_vault(vault)
            self._my_note_cache = note_obj

            return {"success": True, "note": note_obj}

    def delete_note(self, profile: str = "", user_email: str = "") -> Dict[str, Any]:
        """Deletes caller's active note from cache and transport."""
        with self._lock:
            caller = self.get_caller_identity(profile, user_email)
            caller_uid = caller.get("user_id", "")
            caller_secret = caller.get("secret_key", "")

            self._my_note_cache = None

            if self.transport.is_external():
                return self.transport.delete_note(caller_uid, caller_secret) or {"success": True}

            vault = load_notes_vault()
            if caller_uid in vault:
                del vault[caller_uid]
                save_notes_vault(vault)

            return {"success": True}

    # -------------------------------------------------------------------------
    # Friends Management Seam
    # -------------------------------------------------------------------------

    def get_friends(self, profile: str = "", user_email: str = "") -> Dict[str, Any]:
        """Fetches friends list normalized to SSOT #3."""
        with self._lock:
            caller = self.get_caller_identity(profile, user_email)
            res = self.transport.get_friends(caller.get("user_id", ""), caller.get("secret_key", ""))
            friends = [self.normalize_peer(f) for f in (res.get("friends") or [])]
            pending = [self.normalize_peer(p) for p in (res.get("pending_requests") or [])]
            return {"success": True, "friends": friends, "pending_requests": pending}

    def add_friend(self, target_identifier: str, profile: str = "", user_email: str = "") -> Dict[str, Any]:
        """Sends a friend request by target username#pin or user_id."""
        with self._lock:
            caller = self.get_caller_identity(profile, user_email)
            return self.transport.friend_request(caller.get("user_id", ""), caller.get("secret_key", ""), target_identifier)

    def remove_friend(self, target_identifier: str, profile: str = "", user_email: str = "") -> Dict[str, Any]:
        """Removes a friend relationship."""
        with self._lock:
            caller = self.get_caller_identity(profile, user_email)
            return self.transport.friend_remove(caller.get("user_id", ""), caller.get("secret_key", ""), target_identifier)

    # -------------------------------------------------------------------------
    # Co-Listening & Chat Engine (Real-Time Bidirectional RPC)
    # -------------------------------------------------------------------------

    def get_co_listeners(self) -> List[Dict[str, Any]]:
        """Returns list of active co-listeners in memory."""
        with self._lock:
            now = time.time()
            active = []
            for uid, info in list(self._co_listeners.items()):
                if now - info.get("last_seen", 0) < PRESENCE_ONLINE_THRESHOLD:
                    active.append(info)
                else:
                    self._co_listeners.pop(uid, None)
            return active

    def register_co_listener(self, peer: Dict[str, Any]) -> None:
        """Registers or refreshes a co-listener heartbeat."""
        with self._lock:
            norm = self.normalize_peer(peer)
            norm["last_seen"] = time.time()
            if norm["user_id"]:
                self._co_listeners[norm["user_id"]] = norm

    def unregister_co_listener(self, user_id: str) -> None:
        """Removes a co-listener who left."""
        with self._lock:
            self._co_listeners.pop(user_id, None)

    def broadcast_chat(
        self,
        text: str,
        sender: Dict[str, Any],
        recipient_id: Optional[str] = None,
    ) -> Tuple[bool, Dict[str, Any]]:
        """
        Deduplicates and registers a floating chat message.
        Prevents chat bubble echo loops.
        """
        with self._lock:
            sender_norm = self.normalize_peer(sender)
            msg_id = str(uuid.uuid4())[:8]
            timestamp = time.time()
            clean_text = text.strip()[:140]

            dedup_key = f"{sender_norm['user_id']}:{clean_text}:{int(timestamp / 2)}"
            if dedup_key in self._chat_dedup_set:
                return False, {"error": "Duplicate chat message suppressed"}

            self._chat_dedup_set.add(dedup_key)
            if len(self._chat_dedup_set) > 200:
                self._chat_dedup_set.clear()

            msg_payload = {
                "id": msg_id,
                "text": clean_text,
                "from_user_id": sender_norm["user_id"],
                "from_name": sender_norm["name"],
                "from_avatar": sender_norm["avatar"],
                "to_user_id": recipient_id,
                "timestamp": timestamp,
            }

            self._recent_chats.append(msg_payload)
            if len(self._recent_chats) > 50:
                self._recent_chats.pop(0)

            return True, msg_payload

    # -------------------------------------------------------------------------
    # Presence & Event Distribution Seam
    # -------------------------------------------------------------------------

    def update_presence(
        self,
        now_playing_data: Optional[Dict[str, Any]] = None,
        profile: str = "",
        user_email: str = "",
    ) -> Dict[str, Any]:
        """Updates user presence and now-playing state across memory and transport."""
        with self._lock:
            caller = self.get_caller_identity(profile, user_email)
            caller_uid = caller.get("user_id", "")
            caller_secret = caller.get("secret_key", "")

            # If now_playing_data is None, attempt read from local IPC file
            if now_playing_data is None:
                suffix = resolve_profile_suffix(profile, user_email)
                cur_track_file = Path(pc.get_temp_dir()) / f"nutsty_current_track{suffix}.json"
                if cur_track_file.exists():
                    try:
                        with open(cur_track_file, "r", encoding="utf-8") as f:
                            meta = json.load(f)
                            if meta.get("title"):
                                vid = meta.get("path", "")
                                if vid.startswith("ytdl://"):
                                    vid = vid.replace("ytdl://", "")
                                now_playing_data = {
                                    "title": meta.get("title", ""),
                                    "artist": meta.get("artist", ""),
                                    "cover": meta.get("artUrl", ""),
                                    "path": meta.get("path", ""),
                                    "id": vid,
                                    "videoId": vid,
                                    "is_playing": True,
                                    "timestamp": time.time(),
                                }
                    except Exception:
                        pass

            # Update transport
            res = self.transport.update_presence(caller_uid, caller_secret, now_playing_data)
            
            # Update local vault if not external
            if not self.transport.is_external():
                vault = load_notes_vault()
                now = time.time()
                key = f"note:{caller_uid}"
                if key in vault:
                    vault[key]["now_playing"] = now_playing_data
                    vault[key]["last_active_ts"] = now
                    save_notes_vault(vault)

            return res or {"success": True}

    def set_offline(self, profile: str = "", user_email: str = "") -> Dict[str, Any]:
        """Notifies transport that user went offline and purges active presence."""
        with self._lock:
            caller = self.get_caller_identity(profile, user_email)
            caller_uid = caller.get("user_id", "")
            caller_secret = caller.get("secret_key", "")

            self.unregister_co_listener(caller_uid)
            res = self.transport.set_offline(caller_uid, caller_secret)

            if not self.transport.is_external():
                vault = load_notes_vault()
                key = f"note:{caller_uid}"
                if key in vault:
                    vault[key]["last_active_ts"] = 0
                    vault[key]["now_playing"] = ""
                    save_notes_vault(vault)

            return res or {"success": True}

    def send_event(
        self,
        event_type: str,
        to_identifier: str,
        extra_data: Optional[Dict[str, Any]] = None,
        profile: str = "",
        user_email: str = "",
    ) -> Dict[str, Any]:
        """Dispatches a bidirectional co-listen/note event to target user."""
        with self._lock:
            caller = self.get_caller_identity(profile, user_email)
            caller_uid = caller.get("user_id", "")
            caller_secret = caller.get("secret_key", "")

            target_uid = to_identifier if to_identifier.startswith("usr_") else None
            target_tag = to_identifier if "#" in to_identifier else None

            # Fast lookup from in-memory cache if target is username/tag
            if not target_uid and not target_tag:
                target_clean = to_identifier.strip().lower()
                for fn in self._notes_cache.values():
                    if target_clean in (fn["user_id"].lower(), fn["tag"].lower(), fn["name"].lower()):
                        target_uid = fn["user_id"]
                        target_tag = fn["tag"]
                        break

            if self.transport.is_external():
                return self.transport.send_note_event(
                    user_id=caller_uid,
                    secret_key=caller_secret,
                    to_tag=target_tag,
                    to_user_id=target_uid or (to_identifier if not target_tag else None),
                    event=event_type,
                    data=extra_data,
                ) or {"success": False}

            # In-memory / local vault dispatch
            events = load_events_vault()
            ev = {
                "id": f"ev_{int(time.time() * 1000)}",
                "event": event_type,
                "from_email": caller.get("tag", ""),
                "from_name": caller.get("username", "Nutsty User"),
                "from_avatar": caller.get("avatar_url", ""),
                "to_email": to_identifier,
                "data": extra_data,
                "timestamp": time.time(),
                "created_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
            }
            events.append(ev)
            save_events_vault(events)
            return {"success": True, "event": ev}

    def get_events(self, profile: str = "", user_email: str = "") -> List[Dict[str, Any]]:
        """Retrieves and clears unread events for the caller."""
        with self._lock:
            caller = self.get_caller_identity(profile, user_email)
            caller_uid = caller.get("user_id", "")
            caller_secret = caller.get("secret_key", "")

            if self.transport.is_external():
                relay_evts = self.transport.get_events(caller_uid, caller_secret)
                events = []
                for revt in relay_evts.get("events", []):
                    raw_pl = revt.get("payload")
                    if isinstance(raw_pl, str):
                        try:
                            raw_pl = json.loads(raw_pl)
                        except Exception:
                            raw_pl = {}
                    elif not isinstance(raw_pl, dict):
                        raw_pl = {}

                    inner_data = raw_pl.get("data") if "data" in raw_pl else raw_pl
                    events.append({
                        "id": revt.get("id", ""),
                        "event": revt.get("event_type", ""),
                        "from_id": raw_pl.get("from_id") or revt.get("from_user_id", ""),
                        "from_email": (raw_pl.get("from_tag") or raw_pl.get("tag") or revt.get("from_user_id", "")).strip(),
                        "from_name": raw_pl.get("from_name") or raw_pl.get("name") or "Friend",
                        "from_avatar": raw_pl.get("from_avatar") or raw_pl.get("avatar") or "",
                        "to_email": caller.get("tag", ""),
                        "data": inner_data,
                        "timestamp": revt.get("created_at") or time.time(),
                        "created_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
                    })
                return events

            events = load_events_vault()
            caller_all_ids = set(x.lower() for x in get_user_all_identifiers(caller_uid))
            my_events = []
            remaining = []

            for ev in events:
                to_target = (ev.get("to_email") or "").strip().lower()
                if to_target and to_target in caller_all_ids:
                    my_events.append(ev)
                else:
                    remaining.append(ev)

            if len(my_events) > 0:
                save_events_vault(remaining)

            return my_events


def my_note_or_none(note_dict: Optional[Dict[str, Any]]) -> Optional[Dict[str, Any]]:
    if isinstance(note_dict, dict) and note_dict.get("note_text"):
        return note_dict
    return None


# Global Singleton Instance for resident daemon
SOCIAL_RELAY_CORE = SocialRelayCore()
