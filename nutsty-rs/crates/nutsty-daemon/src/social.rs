//! Native fast path for the social routes the UI polls every few seconds
//! (`GET /api/notes/events`, `GET /api/notes`, `GET /api/friends`, `POST /api/now_playing`).
//!
//! Serving them here means a Python worker no longer has to stay alive just to forward these
//! polls to the Cloudflare relay. The output mirrors `backend/social_routes.py` and
//! `backend/social_relay_core.py`. Anything outside the common case (no saved cloud identity, a
//! profile name/avatar that still has to be synced, a 401 that needs re-registration, local
//! same-machine events waiting in the vault, a non-HTTP relay, the relay being unreachable for the
//! notes feed) returns `None`, and the caller forwards the request to Python unchanged.

use serde_json::{json, Map, Value};
use std::env;
use std::fs;
use std::path::PathBuf;
use std::sync::{Mutex, OnceLock};
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

const DEFAULT_RELAY_URL: &str = "https://nutsty-global-relay.nutsty-global-relay.workers.dev";
const USER_AGENT: &str = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36 NutstyClient/1.0";
const PRESENCE_ONLINE_THRESHOLD: f64 = 25.0;
const PLACEHOLDER_NAMES: [&str; 5] = ["", "User", "Nutsty User", "Khách", "Guest"];
const INVALID_FALLBACK_NAMES: [&str; 5] = ["User", "Nutsty User", "Shiraori", "Khách", "Guest"];

/// Feed notes from the last successful `/api/notes` call, read by `/api/friends`.
static NOTES_CACHE: Mutex<Vec<Value>> = Mutex::new(Vec::new());
/// (consecutive failures, cooldown end): three failures pause relay calls for 25 s like Python.
static RELAY_HEALTH: Mutex<(u32, Option<Instant>)> = Mutex::new((0, None));

enum Relay {
    Ok(Value),
    Unauthorized,
    Failed,
}

struct Identity {
    user_id: String,
    secret_key: String,
}

pub fn try_handle(method: &str, path: &str, url: &url::Url, body: &str) -> Option<String> {
    let query = |key: &str| -> String {
        url.query_pairs()
            .find(|(k, _)| k == key)
            .map(|(_, v)| v.trim().to_string())
            .unwrap_or_default()
    };
    let out = match (method, path) {
        ("GET", "/api/notes/events") => note_events(&query("profile"), &query("user_email"))?,
        ("GET", "/api/notes") => notes_feed(&query("profile"), &query("user_email"))?,
        ("GET", "/api/friends") => friends(&query("profile"), &query("user_email"), &query("name"))?,
        ("POST", "/api/now_playing") => now_playing(body)?,
        _ => return None,
    };
    Some(out.to_string())
}

// ---------------------------------------------------------------------------------------------
// Routes
// ---------------------------------------------------------------------------------------------

fn note_events(profile: &str, user_email: &str) -> Option<Value> {
    let ident = fast_identity(profile, user_email, "")?;
    // Same-machine events (two local profiles) need Python's alias resolution: leave them to it.
    if local_events_pending() {
        return None;
    }
    let res = match relay_get("/api/events", &ident) {
        Relay::Unauthorized => return None,
        Relay::Ok(v) if truthy(v.get("success")) => v,
        _ => json!({}),
    };
    let now_ms = now_secs() * 1000.0;
    let mut events = Vec::new();
    for revt in res.get("events").and_then(Value::as_array).into_iter().flatten() {
        let payload = match revt.get("payload") {
            Some(Value::String(s)) => match serde_json::from_str::<Value>(s) {
                Ok(v @ Value::Object(_)) => v,
                _ => json!({}),
            },
            Some(v @ Value::Object(_)) => v.clone(),
            _ => json!({}),
        };
        let inner = match payload.get("data") {
            Some(d) => d.clone(),
            None => payload.clone(),
        };
        let from_user_id = revt.get("from_user_id").cloned().unwrap_or_else(|| json!(""));
        let created = revt.get("created_at").and_then(as_f64).unwrap_or(now_ms);
        events.push(json!({
            "id": revt.get("id").cloned().unwrap_or_else(|| json!("")),
            "event": revt.get("event_type").cloned().unwrap_or_else(|| json!("")),
            "from_id": first_truthy(&[payload.get("from_id"), Some(&from_user_id)]),
            "from_email": strip(first_truthy(&[payload.get("from_tag"), payload.get("tag"), Some(&from_user_id)])),
            "from_name": strip(first_truthy(&[payload.get("from_name"), payload.get("username"), Some(&json!("User"))])),
            "from_avatar": strip(first_truthy(&[payload.get("from_avatar"), payload.get("avatar_url"), Some(&json!(""))])),
            "timestamp": created / 1000.0,
            "data": inner,
        }));
    }
    Some(json!({"count": events.len(), "events": events}))
}

fn notes_feed(profile: &str, user_email: &str) -> Option<Value> {
    let ident = fast_identity(profile, user_email, "")?;
    // Unreachable relay or rejected identity: Python serves the local vault or re-registers.
    let res = match relay_get("/api/notes", &ident) {
        Relay::Ok(v) if truthy(v.get("success")) => v,
        _ => return None,
    };
    let mut notes = Vec::new();
    let mut seen = std::collections::HashSet::new();
    for item in res.get("notes").and_then(Value::as_array).into_iter().flatten() {
        if !item.is_object() {
            continue;
        }
        let mut norm = normalize_peer(item);
        norm.insert("note_text".into(), item.get("note_text").cloned().unwrap_or_else(|| json!("")));
        norm.insert("track".into(), item.get("track").cloned().unwrap_or(Value::Null));
        norm.insert("created_at".into(), item.get("created_at").cloned().unwrap_or_else(|| json!(0)));
        norm.insert("is_friend".into(), json!(true));
        let uid = norm_str(&norm, "user_id").to_lowercase();
        if !uid.is_empty() && !seen.insert(uid) {
            continue;
        }
        notes.push(Value::Object(norm));
    }
    // The relay's GET /api/notes already lists every accepted friend (LEFT JOIN on notes), note or
    // not, so no second GET /api/friends is needed to fill in friends without a note.
    let my_note = match res.get("my_note") {
        Some(raw @ Value::Object(_)) => {
            let mut norm = normalize_peer(raw);
            norm.insert("note_text".into(), raw.get("note_text").cloned().unwrap_or_else(|| json!("")));
            norm.insert("track".into(), raw.get("track").cloned().unwrap_or(Value::Null));
            if truthy(norm.get("note_text")) { Value::Object(norm) } else { Value::Null }
        }
        _ => Value::Null,
    };
    *NOTES_CACHE.lock().unwrap() = notes
        .iter()
        .filter(|n| n.get("user_id").and_then(Value::as_str).is_some_and(|s| !s.is_empty()))
        .cloned()
        .collect();
    Some(json!({
        "success": true,
        "count": notes.len(),
        "notes": notes,
        "my_note": my_note,
        "cached_at": now_secs(),
    }))
}

fn friends(profile: &str, user_email: &str, preferred_name: &str) -> Option<Value> {
    let ident = fast_identity(profile, user_email, preferred_name)?;
    let res = match relay_get("/api/friends", &ident) {
        Relay::Unauthorized => return None,
        Relay::Ok(v) if truthy(v.get("success")) => v,
        _ => json!({}),
    };
    let cache = NOTES_CACHE.lock().unwrap().clone();
    let field = |v: &Value, k: &str| v.get(k).cloned().unwrap_or(Value::Null);
    let mut friends = Vec::new();
    for f in res.get("friends").and_then(Value::as_array).into_iter().flatten() {
        let f_id = f.get("id").and_then(Value::as_str).unwrap_or("");
        let f_tag = f.get("tag").and_then(Value::as_str).unwrap_or("");
        let mut note = cache.iter().find(|n| n.get("user_id").and_then(Value::as_str) == Some(f_id) && !f_id.is_empty());
        if note.is_none() && !f_tag.is_empty() {
            note = cache.iter().find(|n| {
                n.get("tag").and_then(Value::as_str) == Some(f_tag) || n.get("email").and_then(Value::as_str) == Some(f_tag)
            });
        }
        friends.push(json!({
            "id": field(f, "id"),
            "user_id": field(f, "id"),
            "email": field(f, "tag"),
            "name": field(f, "username"),
            "avatar": f.get("avatar_url").cloned().unwrap_or_else(|| json!("")),
            "nutsty_tag": field(f, "tag"),
            "tag": field(f, "tag"),
            "discriminator": field(f, "discriminator"),
            "now_playing": f.get("now_playing").cloned().unwrap_or_else(|| json!("")),
            "note": note.cloned().unwrap_or(Value::Null),
        }));
    }
    let mut incoming = Vec::new();
    for r in res.get("incoming_requests").and_then(Value::as_array).into_iter().flatten() {
        let rid = match r.get("id") {
            Some(Value::String(s)) => s.clone(),
            Some(v) => v.to_string(),
            None => String::new(),
        };
        incoming.push(json!({
            "id": format!("req_{rid}"),
            "from_id": field(r, "id"),
            "from_email": field(r, "tag"),
            "from_name": field(r, "username"),
            "from_avatar": r.get("avatar_url").cloned().unwrap_or_else(|| json!("")),
            "from_tag": field(r, "tag"),
            "created_at": r.get("requested_at").cloned().unwrap_or_else(|| json!(0)),
            "status": "pending",
        }));
    }
    Some(json!({
        "unread_count": incoming.len(),
        "friends": friends,
        "incoming_requests": incoming,
        "outgoing_requests": [],
    }))
}

fn now_playing(body: &str) -> Option<Value> {
    let req: Value = serde_json::from_str(body).unwrap_or_else(|_| json!({}));
    let profile = req.get("profile").and_then(Value::as_str).unwrap_or("");
    let user_email = req.get("user_email").and_then(Value::as_str).unwrap_or("").trim();
    let np = req.get("now_playing");
    let payload_from = |src: &Value, cover_keys: (&str, &str), id_keys: (&str, &str)| {
        json!({
            "title": get_or(src, "title", json!("")),
            "artist": get_or(src, "artist", json!("")),
            "cover": get_or(src, cover_keys.0, get_or(src, cover_keys.1, json!(""))),
            "videoId": get_or(src, id_keys.0, get_or(src, id_keys.1, json!(""))),
            "accent_color": get_or(src, "accent_color", json!("")),
        })
    };
    let mut payload = match (np, req.get("track")) {
        (Some(v @ Value::Object(_)), _) => Some(v.clone()),
        (_, Some(t @ Value::Object(_))) => Some(payload_from(t, ("cover", "image"), ("videoId", "id"))),
        (Some(Value::String(s)), _) if s.trim().starts_with('{') => serde_json::from_str::<Value>(s).ok(),
        _ => None,
    };
    if payload.is_none() && truthy(req.get("title")) {
        payload = Some(payload_from(&req, ("image", "cover"), ("videoId", "id")));
    }
    let presence = match payload {
        Some(p) if truthy(Some(&p)) => p,
        _ => match np {
            Some(v) if !v.is_null() => v.clone(),
            _ => json!(""),
        },
    };

    let ident = fast_identity(profile, user_email, "")?;
    if presence_unchanged(&ident.user_id, &presence) {
        return Some(json!({"success": true, "res": {"success": true, "skipped": true}}));
    }
    let data = json!({"user_id": ident.user_id, "secret_key": ident.secret_key, "now_playing": presence});
    let res = match relay_request("POST", "/api/users/presence", &[], Some(&data)) {
        Relay::Unauthorized => return None,
        Relay::Ok(v) if truthy(v.get("success")) => v,
        _ => json!({"success": false, "error": "Cloud relay unreachable"}),
    };
    if truthy(res.get("success")) {
        remember_presence(&ident.user_id, &presence);
    }
    Some(json!({"success": true, "res": res}))
}

// ---------------------------------------------------------------------------------------------
// Presence write skipping
// ---------------------------------------------------------------------------------------------

/// The relay counts a user as online for 25 s after their last presence write, so an unchanged
/// presence is still re-sent once this much time has passed.
const PRESENCE_HEARTBEAT: Duration = Duration::from_secs(15);
/// Listeners extrapolate the host's position from `position + (now - timestamp)`, so a write is
/// only needed when the reported position drifts from that by more than this (a seek).
const PRESENCE_DRIFT_SECS: f64 = 2.0;

struct SentPresence {
    at: Instant,
    value: Value,
}

/// Last presence the relay accepted, per cloud user id (several profile windows share one daemon).
static LAST_PRESENCE: Mutex<Vec<(String, SentPresence)>> = Mutex::new(Vec::new());

/// The fields a listener reacts to; position and timestamp are compared separately.
fn presence_key(v: &Value) -> Value {
    if !v.is_object() {
        return v.clone();
    }
    let mut m = v.as_object().cloned().unwrap_or_default();
    m.remove("position");
    m.remove("timestamp");
    Value::Object(m)
}

fn presence_unchanged(user_id: &str, presence: &Value) -> bool {
    let guard = LAST_PRESENCE.lock().unwrap();
    let Some((_, last)) = guard.iter().find(|(uid, _)| uid == user_id) else {
        return false;
    };
    if last.at.elapsed() >= PRESENCE_HEARTBEAT || presence_key(&last.value) != presence_key(presence) {
        return false;
    }
    let num = |v: &Value, k: &str| v.get(k).and_then(as_f64);
    match (num(&last.value, "position"), num(presence, "position")) {
        (None, None) => true,
        (Some(old_pos), Some(new_pos)) => {
            let playing = last.value.get("is_playing").and_then(Value::as_bool).unwrap_or(false);
            let elapsed = match (num(&last.value, "timestamp"), num(presence, "timestamp")) {
                (Some(t0), Some(t1)) if playing => {
                    let ms = |t: f64| if t > 1e11 { t / 1000.0 } else { t };
                    (ms(t1) - ms(t0)).max(0.0)
                }
                _ => 0.0,
            };
            (new_pos - (old_pos + elapsed)).abs() <= PRESENCE_DRIFT_SECS
        }
        _ => false,
    }
}

fn remember_presence(user_id: &str, presence: &Value) {
    let mut guard = LAST_PRESENCE.lock().unwrap();
    let sent = SentPresence { at: Instant::now(), value: presence.clone() };
    match guard.iter_mut().find(|(uid, _)| uid == user_id) {
        Some(slot) => slot.1 = sent,
        None => guard.push((user_id.to_string(), sent)),
    }
}

// ---------------------------------------------------------------------------------------------
// Identity (read-only mirror of ensure_cloud_identity's "already registered" branch)
// ---------------------------------------------------------------------------------------------

fn config_dir() -> PathBuf {
    let base = env::var_os("XDG_CONFIG_HOME")
        .filter(|v| !v.is_empty())
        .map(PathBuf::from)
        .or_else(|| env::var_os("HOME").or_else(|| env::var_os("USERPROFILE")).map(|h| PathBuf::from(h).join(".config")))
        .unwrap_or_else(|| PathBuf::from(".config"));
    base.join("noctalia")
}

fn read_json(path: &PathBuf) -> Option<Value> {
    serde_json::from_str(&fs::read_to_string(path).ok()?).ok()
}

fn normalize_profile(p: &str) -> String {
    let p = p.trim().to_lowercase();
    match p.as_str() {
        "user1" | "_user1" => "_user1".into(),
        "default" | "main" | "" => String::new(),
        _ if p.starts_with('_') => p,
        _ => format!("_{p}"),
    }
}

/// Mirror of platform_compat.get_profile_suffix
fn profile_suffix(profile: &str, user_email: &str) -> String {
    if !profile.is_empty() {
        return normalize_profile(profile);
    }
    let em = user_email.trim().to_lowercase();
    if !em.is_empty() {
        if em.contains("user1") {
            return "_user1".into();
        } else if em.contains("user2") {
            return "_user2".into();
        } else if em.contains("friend") {
            return "_friend".into();
        }
        if let Ok(entries) = fs::read_dir(config_dir()) {
            for entry in entries.flatten() {
                let name = entry.file_name().to_string_lossy().to_string();
                let Some(suffix) = name.strip_prefix("nutsty_user_cache").and_then(|s| s.strip_suffix(".json")) else {
                    continue;
                };
                if let Some(c) = read_json(&entry.path()) {
                    let matches = |k: &str| c.get(k).and_then(Value::as_str).is_some_and(|v| v.trim().to_lowercase() == em);
                    if matches("email") || matches("handle") {
                        return suffix.to_string();
                    }
                }
            }
        }
    }
    normalize_profile(&env::var("NUTSTY_PROFILE").unwrap_or_default())
}

/// The saved identity when it is ready to use as-is, else None so Python can register or sync it.
fn fast_identity(profile: &str, user_email: &str, fallback_name: &str) -> Option<Identity> {
    if !relay_url().starts_with("http://") && !relay_url().starts_with("https://") {
        return None;
    }
    let suffix = profile_suffix(profile, user_email);
    let id_suffix = match suffix.as_str() {
        "" => String::new(),
        "user1" => "_user1".into(),
        s if s.starts_with('_') => s.to_string(),
        s => format!("_{s}"),
    };
    let dir = config_dir();
    let ident = read_json(&dir.join(format!("nutsty_cloud_identity{id_suffix}.json")))?;
    let user_id = ident.get("user_id").and_then(Value::as_str).filter(|s| !s.is_empty())?.to_string();
    let secret_key = ident.get("secret_key").and_then(Value::as_str).filter(|s| !s.is_empty())?.to_string();

    // ensure_cloud_identity pushes a new name/avatar to the relay first: let Python do that
    let cache = read_json(&dir.join(format!("nutsty_user_cache{suffix}.json"))).unwrap_or_else(|| json!({}));
    let cache_str = |k: &str| cache.get(k).and_then(Value::as_str).unwrap_or("").to_string();
    let user_name = if !fallback_name.is_empty() {
        fallback_name.to_string()
    } else {
        let name = cache_str("name");
        let email = cache_str("email");
        if !name.is_empty() {
            name
        } else if email.contains('@') {
            email.split('@').next().unwrap_or("").to_string()
        } else {
            String::new()
        }
    };
    let target_avatar = cache_str("avatar").trim().to_string();
    let cur_uname = ident.get("username").and_then(Value::as_str).unwrap_or("").trim();
    let cur_avatar = ident.get("avatar_url").and_then(Value::as_str).unwrap_or("").trim();
    let wants_name = !truthy(ident.get("custom_username"))
        && PLACEHOLDER_NAMES.contains(&cur_uname)
        && !user_name.is_empty()
        && !INVALID_FALLBACK_NAMES.contains(&user_name.as_str())
        && user_name != cur_uname;
    let wants_avatar = !target_avatar.is_empty() && target_avatar != cur_avatar;
    if wants_name || wants_avatar {
        return None;
    }
    Some(Identity { user_id, secret_key })
}

fn local_events_pending() -> bool {
    let path = config_dir().join("nutsty_notes_events.json");
    match read_json(&path) {
        Some(Value::Array(a)) => !a.is_empty(),
        Some(Value::Null) | None => false,
        Some(_) => true,
    }
}

// ---------------------------------------------------------------------------------------------
// Relay transport
// ---------------------------------------------------------------------------------------------

fn relay_url() -> &'static str {
    static URL: OnceLock<String> = OnceLock::new();
    URL.get_or_init(|| {
        let from_env = env::var("NUTSTY_CLOUD_RELAY_URL").unwrap_or_default().trim().to_string();
        if !from_env.is_empty() {
            return from_env;
        }
        if let Some(s) = read_json(&config_dir().join("nutsty_settings.json")) {
            for key in ["cloud_relay_url", "relay_url"] {
                let v = s.get(key).and_then(Value::as_str).unwrap_or("").trim();
                if !v.is_empty() {
                    return v.to_string();
                }
            }
        }
        DEFAULT_RELAY_URL.to_string()
    })
}

fn agent() -> &'static ureq::Agent {
    static AGENT: OnceLock<ureq::Agent> = OnceLock::new();
    AGENT.get_or_init(|| {
        ureq::Agent::config_builder()
            .timeout_global(Some(Duration::from_secs(5)))
            .http_status_as_error(false)
            .user_agent(USER_AGENT)
            .build()
            .into()
    })
}

fn relay_get(endpoint: &str, ident: &Identity) -> Relay {
    relay_request("GET", endpoint, &[("user_id", &ident.user_id), ("secret_key", &ident.secret_key)], None)
}

fn relay_request(method: &str, endpoint: &str, params: &[(&str, &str)], data: Option<&Value>) -> Relay {
    {
        let health = RELAY_HEALTH.lock().unwrap();
        if health.1.is_some_and(|until| Instant::now() < until) {
            return Relay::Failed;
        }
    }
    let url = format!("{}{}", relay_url().trim_end_matches('/'), endpoint);
    let result = if method == "POST" {
        let body = data.map(Value::to_string).unwrap_or_else(|| "null".into());
        agent().post(&url).header("Content-Type", "application/json").send(&body)
    } else {
        let mut req = agent().get(&url).header("Content-Type", "application/json");
        for (k, v) in params {
            req = req.query(*k, *v);
        }
        req.call()
    };
    let outcome = match result {
        Ok(mut resp) => {
            let status = resp.status().as_u16();
            if status == 401 {
                return Relay::Unauthorized;
            }
            match resp.body_mut().read_to_string() {
                Ok(text) if status < 500 => serde_json::from_str::<Value>(&text).map(Relay::Ok).unwrap_or(Relay::Failed),
                _ => Relay::Failed,
            }
        }
        Err(e) => {
            eprintln!("[nutsty-daemon social] relay {endpoint}: {e}");
            Relay::Failed
        }
    };
    let mut health = RELAY_HEALTH.lock().unwrap();
    if matches!(outcome, Relay::Failed) {
        health.0 += 1;
        if health.0 >= 3 {
            health.1 = Some(Instant::now() + Duration::from_secs(25));
        }
    } else {
        *health = (0, None);
    }
    outcome
}

// ---------------------------------------------------------------------------------------------
// Value helpers (Python truthiness and dict.get semantics)
// ---------------------------------------------------------------------------------------------

fn now_secs() -> f64 {
    SystemTime::now().duration_since(UNIX_EPOCH).map(|d| d.as_secs_f64()).unwrap_or(0.0)
}

fn truthy(v: Option<&Value>) -> bool {
    match v {
        None | Some(Value::Null) => false,
        Some(Value::Bool(b)) => *b,
        Some(Value::Number(n)) => n.as_f64().is_some_and(|f| f != 0.0),
        Some(Value::String(s)) => !s.is_empty(),
        Some(Value::Array(a)) => !a.is_empty(),
        Some(Value::Object(o)) => !o.is_empty(),
    }
}

/// Python `a or b or c`: first truthy value, else the last one
fn first_truthy(vals: &[Option<&Value>]) -> Value {
    for v in vals {
        if truthy(*v) {
            return v.cloned().unwrap_or(Value::Null);
        }
    }
    vals.last().copied().flatten().cloned().unwrap_or(Value::Null)
}

fn strip(v: Value) -> Value {
    match v {
        Value::String(s) => Value::String(s.trim().to_string()),
        other => other,
    }
}

/// Python `d.get(key, default)`: a present key wins even when its value is null
fn get_or(src: &Value, key: &str, default: Value) -> Value {
    src.get(key).cloned().unwrap_or(default)
}

fn as_f64(v: &Value) -> Option<f64> {
    match v {
        Value::Number(n) => n.as_f64(),
        Value::String(s) => s.trim().parse().ok(),
        Value::Bool(b) => Some(if *b { 1.0 } else { 0.0 }),
        _ => None,
    }
}

fn py_str(v: Option<&Value>) -> String {
    match v {
        Some(Value::String(s)) => s.clone(),
        Some(Value::Null) | None => String::new(),
        Some(other) => other.to_string(),
    }
}

fn norm_str<'a>(m: &'a Map<String, Value>, k: &str) -> &'a str {
    m.get(k).and_then(Value::as_str).unwrap_or("")
}

/// Mirror of SocialRelayCore.normalize_peer
fn normalize_peer(raw: &Value) -> Map<String, Value> {
    let pick = |keys: &[&str], default: &str| -> String {
        let vals: Vec<Option<&Value>> = keys.iter().map(|k| raw.get(*k)).collect();
        let v = first_truthy(&vals);
        if truthy(Some(&v)) { py_str(Some(&v)).trim().to_string() } else { default.to_string() }
    };
    let uid = pick(&["user_id", "id"], "");
    let tag = pick(&["tag", "user_email"], "");
    let name = pick(&["user_name", "name", "username"], "Nutsty Friend");
    let avatar = pick(&["avatar_url", "avatar"], "");
    let mut last_active = first_truthy(&[raw.get("last_active_at"), raw.get("last_active")]);
    if !truthy(Some(&last_active)) {
        last_active = json!(0.0);
    }
    let mut last_active = as_f64(&last_active).unwrap_or(0.0);
    if last_active > 1e11 {
        last_active /= 1000.0;
    }
    let is_online = match raw.get("is_online") {
        Some(v) if !v.is_null() => truthy(Some(v)),
        _ if last_active > 0.0 => {
            let diff = now_secs() - last_active;
            (0.0..PRESENCE_ONLINE_THRESHOLD).contains(&diff)
        }
        _ => false,
    };
    let now_playing = if is_online { raw.get("now_playing").cloned().unwrap_or(Value::Null) } else { Value::Null };
    let mut m = Map::new();
    m.insert("user_id".into(), json!(uid));
    m.insert("tag".into(), json!(tag));
    m.insert("email".into(), json!(tag));
    m.insert("name".into(), json!(name));
    m.insert("user_name".into(), json!(name));
    m.insert("avatar".into(), json!(avatar));
    m.insert("avatar_url".into(), json!(avatar));
    m.insert("is_online".into(), json!(is_online));
    m.insert("last_active_at".into(), json!(last_active));
    m.insert("now_playing".into(), now_playing);
    m
}

#[cfg(test)]
mod tests {
    use super::*;

    fn np(vid: &str, pos: f64, ts: f64, playing: bool) -> Value {
        json!({"videoId": vid, "position": pos, "timestamp": ts, "is_playing": playing, "allow_control": true})
    }

    #[test]
    fn presence_skips_only_steady_playback() {
        let uid = "usr_test_presence";
        assert!(!presence_unchanged(uid, &np("a", 10.0, 1000.0, true)), "first write always goes out");
        remember_presence(uid, &np("a", 10.0, 1000.0, true));
        assert!(presence_unchanged(uid, &np("a", 14.0, 1004.0, true)), "position advancing with the clock");
        assert!(!presence_unchanged(uid, &np("a", 60.0, 1004.0, true)), "a seek is sent");
        assert!(!presence_unchanged(uid, &np("b", 0.0, 1004.0, true)), "a new track is sent");
        assert!(!presence_unchanged(uid, &np("a", 14.0, 1004.0, false)), "pause is sent");
        remember_presence(uid, &np("a", 14.0, 1004.0, false));
        assert!(presence_unchanged(uid, &np("a", 14.0, 1030.0, false)), "paused position holds still");
        assert!(!presence_unchanged(uid, &json!("")), "going idle is sent");
    }
}
