//! Signing in to Discord in the browser, for when the Discord app is not on this computer.
//!
//! OAuth2 with PKCE, no client secret (the "Nutsty" app is a public client). Discord sends the
//! browser back to a page this helper serves on 127.0.0.1 for a moment; the token it gets is
//! kept in the Nutsty config folder (owner-only on Linux) and renewed before it runs out.
//! Tokens are never printed or logged.

use base64::Engine;
use serde_json::{json, Value};
use sha2::{Digest, Sha256};
use std::fs;
use std::io::{self, BufRead, BufReader, Write};
use std::net::{TcpListener, TcpStream};
use std::path::PathBuf;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, OnceLock};
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

const API: &str = "https://discord.com/api/v10";
const SCOPES: &str = "openid identify sdk.social_layer_presence";
/// The redirect registered in the Developer Portal; a fixed port, so it can be registered exactly.
pub const REDIRECT_PORT: u16 = 47823;
/// How long the browser has to come back before the sign-in gives up.
const LOGIN_WAIT: Duration = Duration::from_secs(5 * 60);
/// A token is renewed this long before it would run out.
const RENEW_EARLY_MS: i64 = 10 * 60_000;

pub fn redirect_uri() -> String {
    format!("http://127.0.0.1:{REDIRECT_PORT}/callback")
}

fn now_ms() -> i64 {
    SystemTime::now().duration_since(UNIX_EPOCH).map(|d| d.as_millis() as i64).unwrap_or(0)
}

#[derive(Clone, Debug, PartialEq)]
pub struct Token {
    pub access: String,
    pub refresh: String,
    pub expires_at_ms: i64,
    pub user_name: String,
    /// the account's picture on Discord's CDN (or the default one Discord gives), may be empty
    pub avatar_url: String,
}

#[derive(Debug, PartialEq)]
pub enum Fail {
    /// Discord no longer accepts this sign-in (revoked, or the user took the app off)
    SignedOut,
    /// no answer, or an answer that says nothing about the sign-in itself
    Network,
    /// the token endpoint said no to a new sign-in, with Discord's reason
    Refused(String),
}

// ---------------------------------------------------------------------------------------------
// Where the token lives
// ---------------------------------------------------------------------------------------------

fn config_dir() -> PathBuf {
    let base = std::env::var_os("XDG_CONFIG_HOME")
        .filter(|v| !v.is_empty())
        .map(PathBuf::from)
        .or_else(|| std::env::var_os("HOME").or_else(|| std::env::var_os("USERPROFILE")).map(|h| PathBuf::from(h).join(".config")))
        .unwrap_or_else(|| PathBuf::from(".config"));
    base.join("noctalia")
}

/// Same rule as platform_compat.get_profile_suffix for NUTSTY_PROFILE.
fn profile_suffix() -> String {
    let p = std::env::var("NUTSTY_PROFILE").unwrap_or_default().trim().to_lowercase();
    match p.as_str() {
        "default" | "main" | "" => String::new(),
        _ if p.starts_with('_') => p,
        _ => format!("_{p}"),
    }
}

fn auth_file() -> PathBuf {
    config_dir().join(format!("nutsty_discord_auth{}.json", profile_suffix()))
}

impl Token {
    fn from_json(v: &Value) -> Option<Token> {
        Some(Token {
            access: v.get("access_token")?.as_str()?.to_string(),
            refresh: v.get("refresh_token")?.as_str()?.to_string(),
            expires_at_ms: v.get("expires_at_ms")?.as_i64()?,
            user_name: v.get("user_name").and_then(Value::as_str).unwrap_or("").to_string(),
            avatar_url: v.get("avatar_url").and_then(Value::as_str).unwrap_or("").to_string(),
        })
    }

    fn to_json(&self) -> Value {
        json!({
            "access_token": self.access, "refresh_token": self.refresh,
            "expires_at_ms": self.expires_at_ms, "user_name": self.user_name,
            "avatar_url": self.avatar_url,
        })
    }

    /// From the token endpoint's answer, read at `now`.
    fn from_reply(v: &Value, now: i64, old: Option<&Token>) -> Option<Token> {
        Some(Token {
            access: v.get("access_token")?.as_str()?.to_string(),
            refresh: v.get("refresh_token")?.as_str()?.to_string(),
            expires_at_ms: now + v.get("expires_in").and_then(Value::as_i64).unwrap_or(604_800) * 1000,
            user_name: old.map(|t| t.user_name.clone()).unwrap_or_default(),
            avatar_url: old.map(|t| t.avatar_url.clone()).unwrap_or_default(),
        })
    }

    pub fn needs_renewal(&self, now: i64) -> bool {
        now >= self.expires_at_ms - RENEW_EARLY_MS
    }
}

pub fn load() -> Option<Token> {
    let text = fs::read_to_string(auth_file()).ok()?;
    Token::from_json(&serde_json::from_str(&text).ok()?)
}

pub fn save(token: &Token) -> io::Result<()> {
    let path = auth_file();
    if let Some(dir) = path.parent() {
        fs::create_dir_all(dir)?;
    }
    let tmp = path.with_extension("json.tmp");
    {
        let mut opts = fs::OpenOptions::new();
        opts.write(true).create(true).truncate(true);
        #[cfg(unix)]
        {
            use std::os::unix::fs::OpenOptionsExt;
            opts.mode(0o600);
        }
        let mut f = opts.open(&tmp)?;
        f.write_all(token.to_json().to_string().as_bytes())?;
    }
    fs::rename(&tmp, &path)
}

pub fn forget() {
    let _ = fs::remove_file(auth_file());
}

// ---------------------------------------------------------------------------------------------
// HTTP
// ---------------------------------------------------------------------------------------------

pub fn agent() -> &'static ureq::Agent {
    static AGENT: OnceLock<ureq::Agent> = OnceLock::new();
    AGENT.get_or_init(|| {
        ureq::Agent::config_builder()
            .timeout_global(Some(Duration::from_secs(15)))
            .http_status_as_error(false)
            .user_agent("Nutsty (https://github.com/trancongduyhieu/Nutsty, 2)")
            .build()
            .into()
    })
}

/// (status, body) of a form POST to Discord's API.
fn post_form(path: &str, fields: &[(&str, &str)]) -> Result<(u16, Value), Fail> {
    let mut resp = agent().post(format!("{API}{path}")).send_form(fields.iter().copied()).map_err(|_| Fail::Network)?;
    let status = resp.status().as_u16();
    let body = resp.body_mut().read_to_string().unwrap_or_default();
    Ok((status, serde_json::from_str(&body).unwrap_or(Value::Null)))
}

/// The name and picture Discord shows for this account, best effort: None when Discord says no.
pub fn profile(access: &str) -> Option<(String, String)> {
    let mut resp = agent().get(format!("{API}/users/@me")).header("Authorization", format!("Bearer {access}")).call().ok()?;
    if resp.status().as_u16() != 200 {
        return None;
    }
    let v: Value = serde_json::from_str(&resp.body_mut().read_to_string().ok()?).ok()?;
    let text = |k: &str| v.get(k).and_then(Value::as_str).filter(|s| !s.is_empty()).map(str::to_string);
    let id = text("id")?;
    let name = text("global_name").or_else(|| text("username")).unwrap_or_default();
    let avatar = match text("avatar") {
        Some(hash) => format!("https://cdn.discordapp.com/avatars/{id}/{hash}.png?size=128"),
        // accounts without a picture get one of Discord's six coloured defaults
        None => format!("https://cdn.discordapp.com/embed/avatars/{}.png", (id.parse::<u64>().unwrap_or(0) >> 22) % 6),
    };
    Some((name, avatar))
}

/// The saved sign-in with its name and picture read again from Discord, saved when they changed.
pub fn refresh_profile() -> Option<Token> {
    let mut token = load()?;
    let (name, avatar) = profile(&token.access)?;
    if token.user_name != name || token.avatar_url != avatar {
        token.user_name = name;
        token.avatar_url = avatar;
        let _ = save(&token);
    }
    Some(token)
}

fn exchange(client_id: &str, code: &str, verifier: &str) -> Result<Token, Fail> {
    let redirect = redirect_uri();
    let (status, v) = post_form("/oauth2/token", &[
        ("client_id", client_id),
        ("grant_type", "authorization_code"),
        ("code", code),
        ("redirect_uri", &redirect),
        ("code_verifier", verifier),
    ])?;
    if status != 200 {
        let why = format!(
            "token HTTP {status} {} {}",
            v.get("error").and_then(Value::as_str).unwrap_or(""),
            v.get("error_description").and_then(Value::as_str).unwrap_or("")
        );
        eprintln!("[nutsty-discord] sign-in turned down: {why}");
        return Err(Fail::Refused(why.trim().to_string()));
    }
    let mut token = Token::from_reply(&v, now_ms(), None).ok_or(Fail::Network)?;
    if let Some((name, avatar)) = profile(&token.access) {
        token.user_name = name;
        token.avatar_url = avatar;
    }
    Ok(token)
}

pub fn renew(client_id: &str, old: &Token) -> Result<Token, Fail> {
    let (status, v) = post_form("/oauth2/token", &[
        ("client_id", client_id),
        ("grant_type", "refresh_token"),
        ("refresh_token", &old.refresh),
    ])?;
    match status {
        200 => Token::from_reply(&v, now_ms(), Some(old)).ok_or(Fail::Network),
        400 | 401 => Err(Fail::SignedOut),
        _ => Err(Fail::Network),
    }
}

/// The saved token, renewed first when it is close to running out. Signed out: the file goes.
pub fn usable(client_id: &str) -> Result<Token, Fail> {
    let token = load().ok_or(Fail::SignedOut)?;
    if !token.needs_renewal(now_ms()) {
        return Ok(token);
    }
    match renew(client_id, &token) {
        Ok(fresh) => {
            let _ = save(&fresh);
            Ok(fresh)
        }
        Err(Fail::SignedOut) => {
            forget();
            Err(Fail::SignedOut)
        }
        Err(e) => Err(e),
    }
}

/// Takes the sign-in back on Discord's side too, then forgets it here.
pub fn sign_out(client_id: &str) {
    if let Some(token) = load() {
        for (value, hint) in [(&token.refresh, "refresh_token"), (&token.access, "access_token")] {
            let _ = post_form("/oauth2/token/revoke", &[("client_id", client_id), ("token", value), ("token_type_hint", hint)]);
        }
    }
    forget();
}

// ---------------------------------------------------------------------------------------------
// The browser round trip
// ---------------------------------------------------------------------------------------------

fn b64url(bytes: &[u8]) -> String {
    base64::engine::general_purpose::URL_SAFE_NO_PAD.encode(bytes)
}

fn random_text(len: usize) -> String {
    let mut bytes = vec![0u8; len];
    getrandom::fill(&mut bytes).expect("no randomness on this system");
    b64url(&bytes)
}

/// (verifier, challenge) for PKCE S256.
fn pkce() -> (String, String) {
    let verifier = random_text(48);
    let challenge = b64url(&Sha256::digest(verifier.as_bytes()));
    (verifier, challenge)
}

fn encode(s: &str) -> String {
    let mut out = String::new();
    for b in s.bytes() {
        match b {
            b'A'..=b'Z' | b'a'..=b'z' | b'0'..=b'9' | b'-' | b'_' | b'.' | b'~' => out.push(b as char),
            _ => out.push_str(&format!("%{b:02X}")),
        }
    }
    out
}

fn decode(s: &str) -> String {
    let bytes = s.as_bytes();
    let mut out = Vec::with_capacity(bytes.len());
    let mut i = 0;
    while i < bytes.len() {
        match bytes[i] {
            b'+' => out.push(b' '),
            b'%' if i + 2 < bytes.len() => {
                let hex = std::str::from_utf8(&bytes[i + 1..i + 3]).unwrap_or("");
                match u8::from_str_radix(hex, 16) {
                    Ok(b) => {
                        out.push(b);
                        i += 2;
                    }
                    Err(_) => out.push(b'%'),
                }
            }
            b => out.push(b),
        }
        i += 1;
    }
    String::from_utf8_lossy(&out).into_owned()
}

pub fn authorize_url(client_id: &str, state: &str, challenge: &str) -> String {
    format!(
        "https://discord.com/oauth2/authorize?client_id={}&response_type=code&redirect_uri={}&scope={}&state={}&code_challenge={}&code_challenge_method=S256&prompt=consent",
        encode(client_id), encode(&redirect_uri()), encode(SCOPES), encode(state), encode(challenge)
    )
}

/// What came back in the redirect's query: Ok(code) or Err(error name).
fn read_callback(target: &str, state: &str) -> Option<Result<String, String>> {
    let query = target.strip_prefix("/callback?")?;
    let mut code = None;
    let mut error = None;
    let mut got_state = None;
    for pair in query.split('&') {
        let (k, v) = pair.split_once('=').unwrap_or((pair, ""));
        match k {
            "code" => code = Some(decode(v)),
            "error" => error = Some(decode(v)),
            "state" => got_state = Some(decode(v)),
            _ => {}
        }
    }
    // a redirect that doesn't carry our state is someone else's: not ours to act on
    if got_state.as_deref() != Some(state) {
        return Some(Err("state".into()));
    }
    Some(match (code, error) {
        (Some(c), _) if !c.is_empty() => Ok(c),
        (_, Some(e)) => Err(e),
        _ => Err("no_code".into()),
    })
}

fn page(vi: bool, ok: bool) -> String {
    let (title, body) = match (vi, ok) {
        (true, true) => ("Đã đăng nhập Discord", "Bạn có thể đóng trang này và quay lại Nutsty."),
        (true, false) => ("Chưa đăng nhập được", "Hãy quay lại Nutsty và thử lại."),
        (false, true) => ("Signed in to Discord", "You can close this page and go back to Nutsty."),
        (false, false) => ("Couldn't sign in", "Go back to Nutsty and try again."),
    };
    format!(
        "<!doctype html><html lang=\"{}\"><meta charset=\"utf-8\"><title>Nutsty</title>\
<body style=\"margin:0;height:100vh;display:grid;place-items:center;background:#121214;color:#f4f4f5;font-family:system-ui,sans-serif\">\
<div style=\"text-align:center\"><h1 style=\"font-weight:600;font-size:22px\">{title}</h1>\
<p style=\"color:#a1a1aa\">{body}</p></div></body></html>",
        if vi { "vi" } else { "en" }
    )
}

fn answer(stream: &mut TcpStream, status: &str, html: &str) {
    let _ = write!(
        stream,
        "HTTP/1.1 {status}\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: {}\r\nConnection: close\r\nCache-Control: no-store\r\n\r\n{html}",
        html.len()
    );
    let _ = stream.flush();
}

pub enum LoginError {
    /// the port for the redirect is taken by something else
    Port,
    /// the user said no in the browser, or Discord refused; Discord's reason (never a token)
    Denied(String),
    Timeout,
    Cancelled,
    Network,
}

/// Opens the redirect page, hands the sign-in URL to `open`, and waits for the browser to come
/// back. The token is saved before this returns Ok.
pub fn login(client_id: &str, vi: bool, cancel: Arc<AtomicBool>, open: impl FnOnce(&str)) -> Result<Token, LoginError> {
    let listener = TcpListener::bind(("127.0.0.1", REDIRECT_PORT)).map_err(|_| LoginError::Port)?;
    listener.set_nonblocking(true).map_err(|_| LoginError::Port)?;
    let (verifier, challenge) = pkce();
    let state = random_text(24);
    open(&authorize_url(client_id, &state, &challenge));
    let deadline = Instant::now() + LOGIN_WAIT;
    loop {
        if cancel.load(Ordering::Relaxed) {
            return Err(LoginError::Cancelled);
        }
        if Instant::now() >= deadline {
            return Err(LoginError::Timeout);
        }
        let mut stream = match listener.accept() {
            Ok((s, _)) => s,
            Err(e) if e.kind() == io::ErrorKind::WouldBlock => {
                std::thread::sleep(Duration::from_millis(150));
                continue;
            }
            Err(_) => continue,
        };
        let _ = stream.set_nonblocking(false);
        let _ = stream.set_read_timeout(Some(Duration::from_secs(5)));
        let mut first = String::new();
        if BufReader::new(&stream).read_line(&mut first).is_err() {
            continue;
        }
        let target = first.split_whitespace().nth(1).unwrap_or("");
        let Some(result) = read_callback(target, &state) else {
            // the browser asking for a favicon and the like
            answer(&mut stream, "404 Not Found", "");
            continue;
        };
        let outcome = match result {
            Ok(code) => exchange(client_id, &code, &verifier).map_err(|e| match e {
                Fail::SignedOut => LoginError::Denied(String::new()),
                Fail::Refused(why) => LoginError::Denied(why),
                Fail::Network => LoginError::Network,
            }),
            Err(e) => Err(LoginError::Denied(format!("authorize {e}"))),
        };
        let outcome = outcome.and_then(|t| save(&t).map(|_| t).map_err(|_| LoginError::Network));
        answer(&mut stream, "200 OK", &page(vi, outcome.is_ok()));
        return outcome;
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn pkce_challenge_is_the_hash_of_the_verifier() {
        let (v, c) = pkce();
        assert!(v.len() >= 43 && v.len() <= 128);
        assert_eq!(c, b64url(&Sha256::digest(v.as_bytes())));
        assert!(!c.contains('=') && !c.contains('+') && !c.contains('/'));
    }

    #[test]
    fn authorize_url_carries_scope_and_redirect() {
        let u = authorize_url("123", "st", "ch");
        assert!(u.contains("scope=openid%20identify%20sdk.social_layer_presence"));
        assert!(u.contains("redirect_uri=http%3A%2F%2F127.0.0.1%3A47823%2Fcallback"));
        assert!(u.contains("code_challenge_method=S256"));
    }

    #[test]
    fn callback_needs_our_state() {
        assert_eq!(read_callback("/callback?code=abc&state=st", "st"), Some(Ok("abc".into())));
        assert_eq!(read_callback("/callback?code=abc&state=xx", "st"), Some(Err("state".into())));
        assert_eq!(read_callback("/callback?error=access_denied&state=st", "st"), Some(Err("access_denied".into())));
        assert_eq!(read_callback("/favicon.ico", "st"), None);
        assert_eq!(decode("a%2Fb+c"), "a/b c");
    }

    #[test]
    fn token_round_trips_and_renews_early() {
        let t = Token::from_reply(&json!({"access_token":"a","refresh_token":"r","expires_in":604800}), 0, None).unwrap();
        assert_eq!(Token::from_json(&t.to_json()), Some(t.clone()));
        assert!(!t.needs_renewal(0));
        assert!(t.needs_renewal(604_800_000 - 5 * 60_000));
    }
}
