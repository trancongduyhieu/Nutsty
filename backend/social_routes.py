#!/usr/bin/env python3
"""
Nutsty Social, Friends, 24h Notes, and Co-Listening HTTP Route Handlers
Extracted from auth_server.py for clean modularity and CodeGraph AST function indexing.
"""
import os
import json
import time
from datetime import datetime

try:
    from .social_relay_core import SOCIAL_RELAY_CORE
    from .cloud_relay_client import (
        GLOBAL_RELAY_CLIENT,
        _cloud_notes_cache,
        get_nutsty_config_dir,
        resolve_profile_suffix,
        ensure_cloud_identity,
        save_cloud_identity,
        load_notes_vault,
        save_notes_vault,
        load_events_vault,
        save_events_vault,
        get_user_all_identifiers,
    )
except (ImportError, ValueError):
    from social_relay_core import SOCIAL_RELAY_CORE
    from cloud_relay_client import (
        GLOBAL_RELAY_CLIENT,
        _cloud_notes_cache,
        get_nutsty_config_dir,
        resolve_profile_suffix,
        ensure_cloud_identity,
        save_cloud_identity,
        load_notes_vault,
        save_notes_vault,
        load_events_vault,
        save_events_vault,
        get_user_all_identifiers,
    )


def handle_get_notes(handler, query):
    profile = query.get("profile", [""])[0].strip()
    user_email = query.get("user_email", [""])[0].strip()
    feed_data = SOCIAL_RELAY_CORE.get_feed(profile, user_email)
    handler._send_json(feed_data, 200)


def handle_get_friends(handler, query):
    profile = query.get("profile", [""])[0].strip()
    user_email = query.get("user_email", [""])[0].strip()
    preferred_name = query.get("name", [""])[0].strip()
    suffix = resolve_profile_suffix(profile, user_email)
    caller_ident = ensure_cloud_identity(suffix, fallback_name=preferred_name or None)

    relay_res = GLOBAL_RELAY_CLIENT.get_friends(caller_ident["user_id"], caller_ident["secret_key"])
    if relay_res and relay_res.get("unauthorized"):
        caller_ident = ensure_cloud_identity(suffix, fallback_name=preferred_name or None, force_recreate=True)
        relay_res = GLOBAL_RELAY_CLIENT.get_friends(caller_ident["user_id"], caller_ident["secret_key"])
    friends_data = []
    feed_notes = SOCIAL_RELAY_CORE._notes_cache or {}

    for f in (relay_res or {}).get("friends", []):
        f_id = f.get("id") or ""
        f_tag = f.get("tag") or ""
        note_item = feed_notes.get(f_id)
        if not note_item and f_tag:
            note_item = next((n for n in feed_notes.values() if n.get("tag") == f_tag or n.get("email") == f_tag), None)
        friends_data.append({
            "id": f["id"],
            "user_id": f["id"],
            "email": f["tag"],
            "name": f["username"],
            "avatar": f.get("avatar_url", ""),
            "nutsty_tag": f["tag"],
            "tag": f["tag"],
            "discriminator": f["discriminator"],
            "now_playing": f.get("now_playing", ""),
            "note": note_item
        })

    incoming = []
    for r in (relay_res or {}).get("incoming_requests", []):
        incoming.append({
            "id": f"req_{r['id']}",
            "from_id": r["id"],
            "from_email": r["tag"],
            "from_name": r["username"],
            "from_avatar": r.get("avatar_url", ""),
            "from_tag": r["tag"],
            "created_at": r.get("requested_at", 0),
            "status": "pending"
        })

    data = {
        "friends": friends_data,
        "incoming_requests": incoming,
        "outgoing_requests": [],
        "unread_count": len(incoming)
    }
    handler._send_json(data, 200)


def handle_get_user_me(handler, query):
    profile = query.get("profile", [""])[0].strip()
    user_email = query.get("user_email", [""])[0].strip()
    preferred_name = query.get("name", [""])[0].strip()
    suffix = resolve_profile_suffix(profile, user_email)
    ident = ensure_cloud_identity(suffix, fallback_name=preferred_name or None)
    cur_uname = (ident.get("username") or "").strip()
    if cur_uname and cur_uname not in ("User", "Nutsty User", "Khách", "Guest"):
        display_name = cur_uname
        display_tag = ident.get("tag") or f"{display_name}#{ident.get('discriminator', '0001')}"
    else:
        display_name = preferred_name if (preferred_name and preferred_name not in ("User", "Nutsty User", "Shiraori", "Khách", "Guest")) else (cur_uname or "Nutsty User")
        display_tag = f"{display_name}#{ident.get('discriminator', '0001')}"
    handler._send_json({
        "success": True,
        "profile": {
            "id": ident["user_id"],
            "user_id": ident["user_id"],
            "name": display_name,
            "username": display_name,
            "discriminator": ident["discriminator"],
            "pin_code": ident["discriminator"],
            "tag": display_tag,
            "nutsty_tag": display_tag,
            "avatar": ident.get("avatar_url", ""),
            "avatar_url": ident.get("avatar_url", "")
        }
    }, 200)


def handle_search_users(handler, query):
    raw_q = query.get("q", [""])[0].strip()
    profile = query.get("profile", [""])[0].strip()
    user_email = query.get("user_email", [""])[0].strip()
    suffix = resolve_profile_suffix(profile, user_email)
    caller_ident = ensure_cloud_identity(suffix)

    res = GLOBAL_RELAY_CLIENT.search(raw_q, caller_user_id=caller_ident.get("user_id"))
    raw_results = res.get("results", [])

    # Deduplicate multiple stale IDs that have the EXACT SAME username (e.g. Shiraori#4444, #3333, #1168 -> keep newest Shiraori#4444)
    # Never merge across avatar_url alone so two devices sharing a Google account with different names (e.g. Shiraori vs nick) stay distinct!
    deduped_map = {}
    ordered_keys = []
    q_clean = raw_q.strip().lower()
    exact_disc_query = q_clean.split("#")[-1].strip() if "#" in q_clean else (q_clean if q_clean.isdigit() else "")
    caller_uid = (caller_ident.get("user_id") or "").strip()

    for r in raw_results:
        if caller_uid and r.get("id") == caller_uid:
            continue
        uname_key = (r.get("username") or "").strip().lower()
        r_disc = str(r.get("discriminator") or "").strip()
        if exact_disc_query and r_disc == exact_disc_query.zfill(4):
            person_key = f"disc:{r.get('id', '')}"
        elif uname_key and uname_key not in ("user", "nutsty user", "khách", "guest"):
            person_key = f"u:{uname_key}"
        else:
            person_key = f"id:{r.get('id', '')}"

        item_obj = {
            "id": r["id"],
            "user_id": r["id"],
            "email": r["tag"],
            "name": r["username"],
            "nutsty_tag": r["tag"],
            "tag": r["tag"],
            "pin_code": r["discriminator"],
            "discriminator": r["discriminator"],
            "avatar": r.get("avatar_url", "") or "",
            "avatar_url": r.get("avatar_url", "") or "",
            "now_playing": r.get("now_playing", ""),
            "last_active_at": r.get("last_active_at", 0) or 0,
            "is_self": False,
            "is_friend": r.get("is_friend", False),
            "has_outgoing_request": r.get("has_outgoing_request", False),
            "has_incoming_request": r.get("has_incoming_request", False)
        }

        if person_key not in deduped_map:
            deduped_map[person_key] = item_obj
            ordered_keys.append(person_key)
        else:
            existing = deduped_map[person_key]
            cand_tag_low = (r.get("tag") or "").strip().lower()
            if (q_clean and cand_tag_low == q_clean) or \
               (item_obj["last_active_at"] > existing["last_active_at"]) or \
               (item_obj["is_friend"] and not existing["is_friend"]):
                if existing["is_friend"]:
                    item_obj["is_friend"] = True
                deduped_map[person_key] = item_obj
            else:
                if item_obj["is_friend"]:
                    existing["is_friend"] = True

    results = [deduped_map[k] for k in ordered_keys]
    handler._send_json({"results": results}, 200)


def handle_get_note_events(handler, query):
    profile = query.get("profile", [""])[0].strip()
    user_email = query.get("user_email", [""])[0].strip()
    suffix = resolve_profile_suffix(profile, user_email)
    caller_ident = ensure_cloud_identity(suffix)

    relay_evts = GLOBAL_RELAY_CLIENT.get_events(caller_ident["user_id"], caller_ident["secret_key"])
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
            "from_name": (raw_pl.get("from_name") or raw_pl.get("username") or "User").strip(),
            "from_avatar": (raw_pl.get("from_avatar") or raw_pl.get("avatar_url") or "").strip(),
            "timestamp": revt.get("created_at", time.time() * 1000) / 1000.0,
            "data": inner_data
        })

    user_aliases = set(get_user_all_identifiers(user_email))
    if caller_ident.get("tag"):
        user_aliases.add(caller_ident["tag"].strip().lower())
    if caller_ident.get("user_id"):
        user_aliases.add(caller_ident["user_id"].strip().lower())
    local_evts = load_events_vault()
    my_local = [e for e in local_evts if e.get("to_email", "").strip().lower() in user_aliases]
    rem_local = [e for e in local_evts if e.get("to_email", "").strip().lower() not in user_aliases]
    if my_local:
        save_events_vault(rem_local)
        events.extend(my_local)

    handler._send_json({"count": len(events), "events": events}, 200)


def handle_post_update_profile(handler, req_data):
    profile = req_data.get("profile", "")
    user_email = req_data.get("user_email", "")
    suffix = resolve_profile_suffix(profile, user_email)
    ident = ensure_cloud_identity(suffix)

    new_username = req_data.get("new_username")
    new_discriminator = req_data.get("new_discriminator")
    avatar_url = req_data.get("avatar_url")

    res = GLOBAL_RELAY_CLIENT.update_profile(
        user_id=ident["user_id"],
        secret_key=ident["secret_key"],
        new_username=new_username,
        new_discriminator=new_discriminator,
        avatar_url=avatar_url
    )

    if res.get("success") and res.get("user"):
        u = res["user"]
        ident["username"] = u["username"]
        ident["discriminator"] = u["discriminator"]
        ident["tag"] = u["tag"]
        ident["custom_username"] = True
        if "avatar_url" in u:
            ident["avatar_url"] = u["avatar_url"]
        save_cloud_identity(ident, suffix)

        d = get_nutsty_config_dir()
        uc_path = os.path.join(d, f"nutsty_user_cache{suffix}.json")
        if os.path.exists(uc_path):
            try:
                with open(uc_path, "r", encoding="utf-8") as f:
                    uc_data = json.load(f)
                uc_data["name"] = u["username"]
                with open(uc_path, "w", encoding="utf-8") as f:
                    json.dump(uc_data, f, indent=2, ensure_ascii=False)
            except Exception:
                pass

        handler._send_json({"success": True, "user": u, "profile": ident}, 200)
    else:
        handler._send_json(res, 409 if res.get("suggested_discriminator") else 400)


def handle_post_regenerate_pin(handler, req_data):
    profile = req_data.get("profile", "")
    user_email = req_data.get("user_email", "")
    suffix = resolve_profile_suffix(profile, user_email)
    ident = ensure_cloud_identity(suffix)

    new_disc = GLOBAL_RELAY_CLIENT.local_engine.find_available_discriminator(ident["username"])
    res = GLOBAL_RELAY_CLIENT.update_profile(
        user_id=ident["user_id"],
        secret_key=ident["secret_key"],
        new_username=ident["username"],
        new_discriminator=new_disc
    )
    if res.get("success") and res.get("user"):
        u = res["user"]
        ident["discriminator"] = u["discriminator"]
        ident["tag"] = u["tag"]
        save_cloud_identity(ident, suffix)
        handler._send_json({"success": True, "pin_code": u["discriminator"], "nutsty_tag": u["tag"], "tag": u["tag"]}, 200)
    else:
        handler._send_json({"success": False, "error": "Failed to generate new tag"}, 500)


def handle_post_user_offline(handler, req_data):
    profile = req_data.get("profile", "")
    user_email = req_data.get("user_email", "")
    suffix = resolve_profile_suffix(profile, user_email)
    ident = ensure_cloud_identity(suffix)

    email = user_email.lower() if user_email else ident.get("tag", "").lower()
    try:
        GLOBAL_RELAY_CLIENT.set_offline(ident["user_id"], ident["secret_key"])
    except Exception as e:
        print(f"[auth_server offline error] {e}")

    handler._send_json({"success": True, "message": "User is offline"}, 200)


def handle_post_publish_note(handler, req_data):
    profile = req_data.get("profile", "").strip().lower()
    email = req_data.get("user_email", "").strip().lower()
    note_text = req_data.get("note_text", "").strip()
    track = req_data.get("track")
    if isinstance(track, dict) and not track.get("title") and not track.get("name") and not track.get("id"):
        track = None

    if not note_text and not track:
        handler._send_json({"success": False, "error": "Missing required fields (either text or track required)"}, 400)
        return

    res = SOCIAL_RELAY_CORE.publish_note(note_text, track, profile, email)
    handler._send_json(res, 200 if res.get("success") else 400)


def handle_post_delete_note(handler, req_data):
    profile = req_data.get("profile", "").strip().lower()
    email = req_data.get("user_email", "").strip().lower()
    res = SOCIAL_RELAY_CORE.delete_note(profile, email)
    handler._send_json(res, 200 if res.get("success") else 400)


def handle_post_note_event(handler, req_data):
    ev_type = req_data.get("event", "leave")
    from_email = req_data.get("from_email", "").strip()
    from_name = req_data.get("from_name", "").strip()
    from_avatar = req_data.get("from_avatar", "").strip()
    to_email = req_data.get("to_email", "").strip()
    profile = req_data.get("profile", "").strip().lower()
    suffix = resolve_profile_suffix(profile, from_email)
    caller_ident = ensure_cloud_identity(suffix)

    to_user_id = req_data.get("to_user_id", "").strip()
    if not to_email and not to_user_id:
        handler._send_json({"success": False, "error": "Missing to_email or to_user_id"}, 400)
        return

    if GLOBAL_RELAY_CLIENT.is_external():
        resolved_uid = to_user_id if to_user_id.startswith("usr_") else None
        resolved_tag = to_email if "#" in to_email else None
        target_lower = (to_email or to_user_id or "").lower()

        # Fast 0ms lookup from in-memory _cloud_notes_cache first
        if not resolved_uid and target_lower:
            for fn in (_cloud_notes_cache.get("data") or []):
                fn_uid = (fn.get("user_id") or "").strip()
                fn_tag = (fn.get("tag") or "").strip()
                fn_email = (fn.get("user_email") or "").strip()
                fn_name = (fn.get("user_name") or "").strip()
                if target_lower in (fn_uid.lower(), fn_tag.lower(), fn_email.lower(), fn_name.lower()):
                    if fn_uid:
                        resolved_uid = fn_uid
                    if fn_tag:
                        resolved_tag = fn_tag
                    break

        # Fallback to friends API if not in cache
        if not resolved_uid and target_lower:
            try:
                f_res = GLOBAL_RELAY_CLIENT.get_friends(caller_ident["user_id"], caller_ident["secret_key"])
                for fr in (f_res or {}).get("friends", []):
                    fr_tag = (fr.get("tag") or "").strip()
                    fr_name = (fr.get("username") or "").strip()
                    fr_id = (fr.get("id") or "").strip()
                    if fr_id.lower() == target_lower or fr_tag.lower() == target_lower or fr_name.lower() == target_lower:
                        resolved_uid = fr_id
                        resolved_tag = fr_tag
                        break
            except Exception:
                pass

        cloud_res = GLOBAL_RELAY_CLIENT.send_note_event(
            caller_ident["user_id"],
            caller_ident["secret_key"],
            to_tag=resolved_tag,
            to_user_id=resolved_uid or (to_email if not resolved_tag else None),
            event=ev_type,
            data=req_data.get("data")
        )
        if cloud_res and cloud_res.get("success"):
            handler._send_json(cloud_res, 200)
            return

    events = load_events_vault()
    ev = {
        "id": f"ev_{int(time.time()*1000)}",
        "event": ev_type,
        "from_email": from_email,
        "from_name": from_name,
        "from_avatar": from_avatar,
        "to_email": to_email,
        "data": req_data.get("data"),
        "timestamp": time.time(),
        "created_at": datetime.now().isoformat()
    }
    events.append(ev)
    save_events_vault(events)
    handler._send_json({"success": True, "event": ev}, 200)


def handle_post_now_playing(handler, req_data):
    profile = req_data.get("profile", "")
    user_email = req_data.get("user_email", "").strip()
    now_playing = req_data.get("now_playing")
    track_meta = req_data.get("track")
    np_payload = None

    if isinstance(now_playing, dict):
        np_payload = now_playing
    elif isinstance(track_meta, dict):
        np_payload = {
            "title": track_meta.get("title", ""),
            "artist": track_meta.get("artist", ""),
            "cover": track_meta.get("cover", track_meta.get("image", "")),
            "videoId": track_meta.get("videoId", track_meta.get("id", "")),
            "accent_color": track_meta.get("accent_color", "")
        }
    elif isinstance(now_playing, str) and now_playing.strip().startswith("{"):
        try:
            np_payload = json.loads(now_playing)
        except Exception:
            pass

    if np_payload is None and req_data.get("title"):
        np_payload = {
            "title": req_data.get("title", ""),
            "artist": req_data.get("artist", ""),
            "cover": req_data.get("image", req_data.get("cover", "")),
            "videoId": req_data.get("videoId", req_data.get("id", "")),
            "accent_color": req_data.get("accent_color", "")
        }

    presence_val = np_payload if np_payload else (now_playing if now_playing is not None else "")
    res = SOCIAL_RELAY_CORE.update_presence(presence_val, profile, user_email)
    handler._send_json({"success": True, "res": res}, 200)


def handle_post_friend_request(handler, req_data):
    profile = req_data.get("profile", "")
    from_email = req_data.get("from_email", "")
    suffix = resolve_profile_suffix(profile, from_email)
    caller_ident = ensure_cloud_identity(suffix)

    target_user_id = (req_data.get("target_user_id") or req_data.get("target_id") or "").strip()
    to_email = (req_data.get("to_email") or req_data.get("target_email") or "").strip()

    if not target_user_id and to_email:
        search_res = GLOBAL_RELAY_CLIENT.search(to_email, caller_user_id=caller_ident["user_id"])
        for cand in search_res.get("results", []):
            if cand["tag"].lower() == to_email.lower() or cand["id"] == to_email or cand["username"].lower() == to_email.lower():
                target_user_id = cand["id"]
                break
        if not target_user_id and search_res.get("results"):
            target_user_id = search_res["results"][0]["id"]

    if not target_user_id:
        handler._send_json({"success": False, "error": "Target user not found"}, 404)
        return

    res = GLOBAL_RELAY_CLIENT.friend_request(caller_ident["user_id"], caller_ident["secret_key"], target_user_id)
    handler._send_json(res, 200 if res.get("success") else 400)


def handle_post_friend_respond(handler, req_data):
    profile = req_data.get("profile", "")
    user_email = req_data.get("user_email", "")
    suffix = resolve_profile_suffix(profile, user_email)
    caller_ident = ensure_cloud_identity(suffix)

    from_user_id = (req_data.get("from_user_id") or req_data.get("from_id") or req_data.get("target_id") or "").strip()
    from_email = req_data.get("from_email", "").strip()
    request_id = req_data.get("request_id", "").strip()
    action = req_data.get("action", "").strip().lower()

    if not from_user_id:
        if request_id:
            from_user_id = request_id.replace("req_", "")
        elif from_email:
            search_res = GLOBAL_RELAY_CLIENT.search(from_email, caller_user_id=caller_ident["user_id"])
            if search_res.get("results"):
                from_user_id = search_res["results"][0]["id"]

    if not from_user_id:
        handler._send_json({"success": False, "error": "Requester not found"}, 404)
        return

    res = GLOBAL_RELAY_CLIENT.friend_respond(caller_ident["user_id"], caller_ident["secret_key"], from_user_id, action)
    handler._send_json(res, 200 if res.get("success") else 400)


def handle_post_friend_remove(handler, req_data):
    profile = req_data.get("profile", "")
    user_email = req_data.get("user_email", "")
    suffix = resolve_profile_suffix(profile, user_email)
    caller_ident = ensure_cloud_identity(suffix)

    target_user_id = (req_data.get("target_user_id") or req_data.get("target_id") or "").strip()
    target_email = req_data.get("target_email", "").strip()
    if not target_user_id and target_email:
        search_res = GLOBAL_RELAY_CLIENT.search(target_email, caller_user_id=caller_ident["user_id"])
        for cand in search_res.get("results", []):
            if cand["tag"].lower() == target_email.lower() or cand["id"] == target_email:
                target_user_id = cand["id"]
                break

    if not target_user_id:
        handler._send_json({"success": False, "error": "Target user not found"}, 404)
        return

    res = GLOBAL_RELAY_CLIENT.friend_remove(caller_ident["user_id"], caller_ident["secret_key"], target_user_id)
    handler._send_json(res, 200 if res.get("success") else 400)
