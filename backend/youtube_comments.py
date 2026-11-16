"""YouTube Music comments for the track playing, read from the watch page's Comments tab.

Reading works signed out. Signed in (ytmusic_auth file), the first page also carries the comment
box params, and each comment its reply params, which create_comment / create_reply send back.
"""
import sys

try:
    from . import ytmusic_auth
except ImportError:
    import ytmusic_auth


def _client():
    return ytmusic_auth.get_ytmusic_client()


def _runs(obj):
    if not isinstance(obj, dict):
        return ""
    if "simpleText" in obj:
        return obj.get("simpleText") or ""
    return "".join(r.get("text", "") for r in obj.get("runs", []) if isinstance(r, dict))


def _find(obj, key):
    """First value stored under key at any depth."""
    if isinstance(obj, dict):
        if key in obj:
            return obj[key]
        for v in obj.values():
            found = _find(v, key)
            if found is not None:
                return found
    elif isinstance(obj, list):
        for v in obj:
            found = _find(v, key)
            if found is not None:
                return found
    return None


def _entities(resp):
    muts = (((resp.get("frameworkUpdates") or {}).get("entityBatchUpdate") or {}).get("mutations")) or []
    return {m["entityKey"]: m.get("payload") or {} for m in muts if m.get("entityKey")}


def _comment(vm, ents, replies_label="", replies_token=None):
    entity = (ents.get(vm.get("commentKey")) or {}).get("commentEntityPayload")
    if not entity:
        return None
    props = entity.get("properties") or {}
    author = entity.get("author") or {}
    toolbar = entity.get("toolbar") or {}
    surface = (ents.get(vm.get("toolbarSurfaceKey")) or {}).get("engagementToolbarSurfaceEntityPayload") or {}
    state = (ents.get(vm.get("toolbarStateKey")) or {}).get("engagementToolbarStateEntityPayload") or {}
    reply_cmd = surface.get("replyCommand")
    return {
        "id": vm.get("commentId") or props.get("commentId") or "",
        "author": author.get("displayName") or "",
        "avatar": author.get("avatarThumbnailUrl") or "",
        "isCreator": bool(author.get("isCreator")),
        "isVerified": bool(author.get("isVerified")),
        "text": (props.get("content") or {}).get("content") or "",
        "published": props.get("publishedTime") or "",
        "likes": (toolbar.get("likeCountNotliked") or "").strip(),
        "likesLiked": (toolbar.get("likeCountLiked") or "").strip(),
        "liked": state.get("likeState") == "TOOLBAR_LIKE_STATE_LIKED",
        # Signed in only: opaque tokens for comment/perform_comment_action
        "likeAction": _find(surface.get("likeCommand"), "action") or "",
        "unlikeAction": _find(surface.get("unlikeCommand"), "action") or "",
        "isHearted": state.get("heartState") == "TOOLBAR_HEART_STATE_HEARTED",
        "isPinned": vm.get("pinnedText") is not None,
        "repliesLabel": replies_label or "",
        "repliesToken": replies_token or "",
        "replyParams": _find(reply_cmd, "createReplyParams") or "",
    }


def _token(item):
    return _find(item.get("continuationEndpoint"), "token") or _find(item.get("button"), "token")


def _parse(resp):
    ents = _entities(resp)
    out = {"header": None, "comments": [], "next": "", "nextLabel": ""}
    seen = set()
    for ep in resp.get("onResponseReceivedEndpoints") or []:
        cmd = ep.get("reloadContinuationItemsCommand") or ep.get("appendContinuationItemsAction") or {}
        for item in cmd.get("continuationItems") or []:
            if "commentsHeaderRenderer" in item:
                h = item["commentsHeaderRenderer"]
                box = ((h.get("createRenderer") or {}).get("commentSimpleboxRenderer")) or {}
                thumbs = ((box.get("authorThumbnail") or {}).get("thumbnails")) or []
                out["header"] = {
                    "count": _runs(h.get("countText")),
                    "createParams": _find(box.get("submitButton"), "createCommentParams") or "",
                    "placeholder": _runs(box.get("placeholderText")),
                    "userAvatar": thumbs[-1].get("url", "") if thumbs else "",
                }
            thread = item.get("commentThreadRenderer")
            vm = None
            label, rtoken = "", None
            if thread:
                vm = (thread.get("commentViewModel") or {}).get("commentViewModel")
                replies = ((thread.get("replies") or {}).get("commentRepliesRenderer")) or {}
                label = _runs(_find(replies.get("viewReplies"), "text"))
                for sub in (replies.get("subThreads") or []) + (replies.get("contents") or []):
                    if "continuationItemRenderer" in sub:
                        rtoken = _token(sub["continuationItemRenderer"])
                        break
            elif "commentViewModel" in item:
                vm = item["commentViewModel"]
            if vm:
                c = _comment(vm, ents, label, rtoken)
                # YouTube repeats comments across pages; a repeated id would duplicate rows
                if c and c["id"] not in seen:
                    seen.add(c["id"])
                    out["comments"].append(c)
            if "continuationItemRenderer" in item:
                cont = item["continuationItemRenderer"]
                out["next"] = _token(cont) or ""
                out["nextLabel"] = _runs(_find(cont.get("button"), "text"))
    return out


def get_comments(video_id):
    """First page plus header, or {"disabled": True} when the track has no Comments tab."""
    yt = _client()
    resp = yt._send_request("next", {"videoId": video_id})
    tabs = (((resp.get("contents") or {}).get("singleColumnMusicWatchNextResultsRenderer") or {})
            .get("tabbedRenderer") or {}).get("watchNextTabbedResultsRenderer", {}).get("tabs") or []
    token = None
    # The Comments tab is the only one whose section list reloads from a continuation; its title is translated
    for tab in tabs:
        section = ((tab.get("tabRenderer") or {}).get("content") or {}).get("sectionListRenderer") or {}
        for c in section.get("continuations") or []:
            token = (c.get("reloadContinuationData") or {}).get("continuation") or token
        if token:
            break
    if not token:
        return {"disabled": True, "comments": [], "header": None, "next": ""}
    page = _parse(yt._send_request("next", {"continuation": token}))
    page["signedIn"] = bool(page["header"] and page["header"]["createParams"])
    page["disabled"] = not page["comments"] and page["header"] is None
    return page


def get_page(token):
    """Next page of comments, or a thread's replies."""
    return _parse(_client()._send_request("next", {"continuation": token}))


def _created(resp):
    ents = _entities(resp)
    keys = _find(resp.get("actions"), "commentKey")
    if keys:
        holder = None

        def walk(o):
            nonlocal holder
            if holder is not None:
                return
            if isinstance(o, dict):
                if "commentKey" in o:
                    holder = o
                    return
                for v in o.values():
                    walk(v)
            elif isinstance(o, list):
                for v in o:
                    walk(v)
        walk(resp.get("actions"))
        if holder:
            c = _comment(holder, ents)
            if c:
                return c
    for key, payload in ents.items():
        if "commentEntityPayload" in payload:
            return _comment({"commentKey": key}, ents)
    return None


def perform_action(action):
    """Like or unlike, using a token from the comment's toolbar."""
    resp = _client()._send_request("comment/perform_comment_action", {"actions": [action]})
    status = _find(resp.get("actionResults"), "status") or ""
    return {"success": status != "STATUS_FAILED", "status": status}


def create_comment(params, text):
    resp = _client()._send_request("comment/create_comment", {"createCommentParams": params, "commentText": text})
    return {"success": True, "comment": _created(resp)}


def create_reply(params, text):
    resp = _client()._send_request("comment/create_comment_reply", {"createReplyParams": params, "commentText": text})
    return {"success": True, "comment": _created(resp)}


if __name__ == "__main__":
    import json
    vid = sys.argv[1] if len(sys.argv) > 1 else "Y6LKBtUsfSE"
    print(json.dumps(get_comments(vid), ensure_ascii=False)[:1500])
