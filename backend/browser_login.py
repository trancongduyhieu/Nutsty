#!/usr/bin/env python3
"""
Nutsty - Native Google / YouTube Music Login Assistant
Launches an isolated browser window for official Google login
and automatically captures auth cookies via Chrome DevTools Protocol (CDP).
Zero extension required, zero manual copy-pasting.
Includes deep forensic logging for instant diagnosis.
"""
import os
import sys
import json
import time
import shutil
import asyncio
import datetime
import traceback
import subprocess
import urllib.request
import urllib.error

BACKEND_DIR = os.path.dirname(os.path.abspath(__file__))
if BACKEND_DIR not in sys.path:
    sys.path.insert(0, BACKEND_DIR)

import ytmusic_helper

try:
    from . import platform_compat as pc
except (ImportError, ValueError):
    import platform_compat as pc

PROFILE_NAME = os.getenv("NUTSTY_PROFILE", "").strip().lower()
PROFILE_SUFFIX = f"_{PROFILE_NAME}" if PROFILE_NAME else ""

CDP_PORT = 19222 if not PROFILE_NAME else (19222 + (abs(hash(PROFILE_NAME)) % 100) + 1)
PROFILE_DIR = os.path.join(pc.get_config_dir(), f"browser_auth{PROFILE_SUFFIX}")

LOGIN_URL = (
    "https://accounts.google.com/ServiceLogin?"
    "ltmpl=music&service=youtube&uilel=3&passive=true&"
    "continue=https%3A%2F%2Fwww.youtube.com%2Fsignin%3Faction_handle_signin%3Dtrue%26app%3Ddesktop%26hl%3Den%26next%3Dhttps%253A%252F%252Fmusic.youtube.com%252F%26feature%3D__FEATURE__&hl=en"
)

SPOTIFY_LOGIN_URL = "https://accounts.spotify.com/en/login?continue=https%3A%2F%2Fopen.spotify.com%2F"
SPOTIFY_PROFILE_DIR = os.path.join(pc.get_config_dir(), f"browser_spotify{PROFILE_SUFFIX}")


# Forensic Logger Targets
LOG_FILE_PRIMARY = os.path.join(pc.get_config_dir(), "browser_login.log")
LOG_FILE_TEMP = os.path.join(pc.get_temp_dir(), "browser_login.log")

def emit_status(payload):
    """Emit JSON status line to stdout for real-time UI progress feedback."""
    try:
        sys.stdout.write(json.dumps(payload, ensure_ascii=False) + "\n")
        sys.stdout.flush()
    except Exception:
        pass

def log(msg, level="INFO"):
    """Thread-safe forensic logger with millisecond timestamps and dual-path sync."""
    now_str = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S.%f")[:-3]
    entry = f"[{now_str}] [{level}] {msg}"
    
    # Print to stderr for immediate console / IPC inspection
    try:
        sys.stderr.write(f"[BrowserLogin] {entry}\n")
        sys.stderr.flush()
    except Exception:
        pass

    # Persist to disk
    for path in (LOG_FILE_PRIMARY, LOG_FILE_TEMP):
        try:
            os.makedirs(os.path.dirname(path), exist_ok=True)
            with open(path, "a", encoding="utf-8", errors="replace") as f:
                f.write(entry + "\n")
        except Exception:
            pass

def find_system_browser():
    log("Scanning system for Chromium-based browsers...")
    # 1. On Windows: Check default browser in Registry, then standard paths
    if sys.platform == "win32" or os.name == "nt":
        # Check default browser registered for HTTPS
        try:
            import winreg
            import re
            with winreg.OpenKey(winreg.HKEY_CURRENT_USER, r"Software\Microsoft\Windows\Shell\Associations\UrlAssociations\https\UserChoice") as key:
                prog_id, _ = winreg.QueryValueEx(key, "ProgId")
            if prog_id:
                with winreg.OpenKey(winreg.HKEY_CLASSES_ROOT, rf"{prog_id}\shell\open\command") as cmd_key:
                    cmd_val, _ = winreg.QueryValueEx(cmd_key, "")
                    m = re.search(r'"([^"]+\.exe)"', cmd_val, re.IGNORECASE) or re.search(r'([^\s]+\.exe)', cmd_val, re.IGNORECASE)
                    if m:
                        exe_path = m.group(1)
                        if os.path.isfile(exe_path):
                            exe_lower = exe_path.lower()
                            if any(x in exe_lower for x in ("chrome", "msedge", "edge", "brave", "vivaldi", "opera", "arc", "thorium", "chromium", "yandex")):
                                log(f"Found Windows default browser: {exe_path}")
                                return exe_path
        except Exception as re_err:
            log(f"Registry default browser check error: {re_err}", "DEBUG")

        win_candidates = []
        p_files_x86 = os.environ.get("ProgramFiles(x86)", r"C:\Program Files (x86)")
        p_files = os.environ.get("ProgramFiles", r"C:\Program Files")
        local_appdata = os.environ.get("LOCALAPPDATA", "")

        # Microsoft Edge (Standard & Per-User installs)
        win_candidates.extend([
            os.path.join(p_files_x86, "Microsoft", "Edge", "Application", "msedge.exe"),
            os.path.join(p_files, "Microsoft", "Edge", "Application", "msedge.exe"),
            os.path.join(local_appdata, "Microsoft", "Edge", "Application", "msedge.exe") if local_appdata else "",
            shutil.which("msedge") or "",
        ])
        # Google Chrome
        win_candidates.extend([
            os.path.join(p_files, "Google", "Chrome", "Application", "chrome.exe"),
            os.path.join(p_files_x86, "Google", "Chrome", "Application", "chrome.exe"),
            os.path.join(local_appdata, "Google", "Chrome", "Application", "chrome.exe") if local_appdata else "",
            shutil.which("chrome") or "",
        ])
        # Brave
        win_candidates.extend([
            os.path.join(p_files, "BraveSoftware", "Brave-Browser", "Application", "brave.exe"),
            os.path.join(p_files_x86, "BraveSoftware", "Brave-Browser", "Application", "brave.exe"),
            os.path.join(local_appdata, "BraveSoftware", "Brave-Browser", "Application", "brave.exe") if local_appdata else "",
            shutil.which("brave") or "",
        ])
        # Arc Browser
        if local_appdata:
            win_candidates.append(os.path.join(local_appdata, "Programs", "Arc", "Arc.exe"))
        # Vivaldi & Opera GX & Opera
        if local_appdata:
            win_candidates.extend([
                os.path.join(local_appdata, "Vivaldi", "Application", "vivaldi.exe"),
                os.path.join(local_appdata, "Programs", "Opera GX", "opera.exe"),
                os.path.join(local_appdata, "Programs", "Opera", "opera.exe"),
                os.path.join(local_appdata, "Thorium", "Application", "thorium.exe"),
                os.path.join(local_appdata, "Yandex", "YandexBrowser", "Application", "browser.exe"),
                os.path.join(local_appdata, "Chromium", "Application", "chrome.exe"),
            ])
        win_candidates.extend([
            os.path.join(p_files, "Vivaldi", "Application", "vivaldi.exe"),
            os.path.join(p_files, "Opera", "launcher.exe"),
            os.path.join(p_files, "Chromium", "Application", "chrome.exe"),
            shutil.which("vivaldi") or "",
            shutil.which("opera") or "",
        ])

        for p in win_candidates:
            if p and os.path.exists(p) and os.path.isfile(p):
                log(f"Found Windows browser executable: {p}")
                return p

    # 2. On Linux: Check typical desktop Chromium binaries
    candidates = [
        "brave",
        "brave-browser",
        "/usr/bin/brave",
        "google-chrome",
        "google-chrome-stable",
        "/usr/bin/google-chrome",
        "chromium",
        "chromium-browser",
        "/usr/bin/chromium",
        "microsoft-edge",
        "microsoft-edge-stable",
        "msedge",
        "vivaldi",
        "opera"
    ]
    for c in candidates:
        bin_path = shutil.which(c)
        if bin_path and os.path.isfile(bin_path):
            log(f"Found Linux browser executable via PATH: {bin_path}")
            return bin_path
        if os.path.isfile(c):
            log(f"Found Linux browser executable directly: {c}")
            return c

    log("No compatible Chromium-based browser found on this system.", "ERROR")
    return None

def kill_browser_proc(proc):
    if not proc:
        return
    log(f"Terminating browser process (PID {proc.pid})...")
    try:
        if sys.platform == "win32" or os.name == "nt":
            CREATE_NO_WINDOW = 0x08000000
            subprocess.run(["taskkill", "/F", "/T", "/PID", str(proc.pid)], capture_output=True, timeout=3, creationflags=CREATE_NO_WINDOW)
        else:
            os.killpg(os.getpgid(proc.pid), 15)
    except Exception as e:
        log(f"Taskkill error (fallback to proc.kill): {e}", "WARN")
        try:
            proc.kill()
        except Exception:
            pass

async def query_browser_profile(cdp_port):
    """Query logged-in user profile from active tabs via CDP Runtime.evaluate."""
    import websockets
    try:
        with urllib.request.urlopen(f"http://127.0.0.1:{cdp_port}/json/list", timeout=1.0) as r:
            pages = json.loads(r.read().decode("utf-8"))

        # Sort candidate tabs: music.youtube.com first, then youtube.com, then accounts.google.com, then others
        def tab_score(p):
            u = p.get("url", "").lower()
            if "music.youtube.com" in u: return 0
            if "youtube.com" in u: return 1
            if "myaccount.google.com" in u: return 2
            if "accounts.google.com" in u: return 3
            return 4

        candidate_tabs = [p for p in pages if p.get("type") == "page" and p.get("webSocketDebuggerUrl")]
        candidate_tabs.sort(key=tab_score)

        js = r"""
        (() => {
            let name = "";
            let email = "";
            let thumb = "";
            try {
                // 1. InnerTube context (YouTube Music / YouTube)
                if (window.ytcfg) {
                    const d = window.ytcfg.data_ || {};
                    name = window.ytcfg.get("USER_NAME") || (d.INNERTUBE_CONTEXT && d.INNERTUBE_CONTEXT.user && d.INNERTUBE_CONTEXT.user.name) || "";
                    email = window.ytcfg.get("USER_EMAIL") || (d.INNERTUBE_CONTEXT && d.INNERTUBE_CONTEXT.user && d.INNERTUBE_CONTEXT.user.email) || "";
                    thumb = window.ytcfg.get("USER_AVATAR") || "";
                }
                // 2. YouTube DOM Elements
                if (!name || !email) {
                    const acc = document.querySelector("ytd-active-account-header-renderer, ytmusic-active-account-header-renderer, #avatar-btn");
                    if (acc) {
                        const nEl = acc.querySelector("#account-name, #channel-title, #name");
                        if (nEl && !name) name = nEl.textContent.trim();
                        const eEl = acc.querySelector("#email, #byline");
                        if (eEl && !email) email = eEl.textContent.trim();
                        const img = acc.querySelector("img#img, #account-photo img");
                        if (img && !thumb && img.src) thumb = img.src;
                    }
                }
                // 3. Google Accounts / MyAccount DOM Attributes & Elements
                if (!email) {
                    const emailEl = document.querySelector("[data-email], [data-identifier], [data-profile-identifier]");
                    if (emailEl) {
                        email = emailEl.getAttribute("data-email") || emailEl.getAttribute("data-identifier") || emailEl.getAttribute("data-profile-identifier") || "";
                    }
                }
                if (!name) {
                    const nameEl = document.querySelector("[data-name], [data-profile-name]");
                    if (nameEl) {
                        name = nameEl.getAttribute("data-name") || nameEl.getAttribute("data-profile-name") || "";
                    }
                }
                // 4. Regex fallback on document body text
                if (!email && document.body) {
                    const text = document.body.innerText || "";
                    const matches = text.match(/[a-zA-Z0-9_.+-]+@[a-zA-Z0-9-]+\.[a-zA-Z0-9-.]+/g);
                    if (matches) {
                        const valid = matches.filter(e => !e.endsWith("@google.com") && !e.endsWith("@youtube.com"));
                        if (valid.length > 0) email = valid[0];
                    }
                }
                if (!thumb) {
                    const img = document.querySelector("img[src*='googleusercontent.com']");
                    if (img && img.src) thumb = img.src;
                }
            } catch(e) {}
            return { name: name, email: email, thumb: thumb };
        })()
        """

        best_profile = {"name": "", "email": "", "thumb": ""}
        for tab in candidate_tabs:
            tab_ws = tab["webSocketDebuggerUrl"].replace("localhost", "127.0.0.1")
            try:
                async with websockets.connect(tab_ws, ping_interval=None) as p_sock:
                    await p_sock.send(json.dumps({
                        "id": 9999,
                        "method": "Runtime.evaluate",
                        "params": {"expression": js, "returnByValue": True}
                    }))
                    resp_raw = await asyncio.wait_for(p_sock.recv(), timeout=1.5)
                    parsed = json.loads(resp_raw)
                    val = parsed.get("result", {}).get("result", {}).get("value", {})
                    if isinstance(val, dict):
                        if val.get("name") and not best_profile["name"]:
                            best_profile["name"] = val["name"]
                        if val.get("email") and not best_profile["email"]:
                            best_profile["email"] = val["email"]
                        if val.get("thumb") and not best_profile["thumb"]:
                            best_profile["thumb"] = val["thumb"]
                        if best_profile["name"] and best_profile["email"]:
                            return best_profile
            except Exception:
                continue

        if best_profile["name"] or best_profile["email"]:
            return best_profile
    except Exception as e:
        log(f"query_browser_profile debug: {e}", "DEBUG")
    return None

async def capture_cookies_via_cdp(ws_url, cdp_port, proc, service="youtube", max_timeout=300):
    import websockets

    # Guarantee IPv4 loopback to avoid Windows IPv6 [WinError 10061]
    ws_url = ws_url.replace("localhost", "127.0.0.1")
    log(f"Initiating CDP connection to Browser Target: {ws_url} (service={service})")

    start_time = time.time()
    google_signed_in_time = None
    last_cookie_summary_time = 0
    last_pending_log = 0
    msg_id = 1

    try:
        async with websockets.connect(ws_url, ping_interval=None) as ws:
            log("WebSocket connection to Browser Target established successfully.")
            while time.time() - start_time < max_timeout:
                if proc and proc.poll() is not None and proc.poll() != 0:
                    log(f"Browser process crashed with code {proc.poll()}.", "WARN")
                    return {"success": False, "error": f"Browser process crashed with code {proc.poll()}."}

                cookies = []
                msg_id += 1

                # 1. Primary Query: Storage.getCookies on Browser Target (CDP standard for Chrome 120+, Edge, Brave)
                storage_cmd = {
                    "id": msg_id,
                    "method": "Storage.getCookies"
                }
                await ws.send(json.dumps(storage_cmd))

                # Drain response
                drain_start = time.time()
                while time.time() - drain_start < 1.5:
                    try:
                        resp_text = await asyncio.wait_for(ws.recv(), timeout=0.8)
                        parsed = json.loads(resp_text)
                        
                        # Handle potential error code
                        if "error" in parsed:
                            err_code = parsed["error"].get("code")
                            err_msg = parsed["error"].get("message")
                            log(f"CDP Browser Target returned error: code={err_code}, msg='{err_msg}'", "WARN")
                            
                            # Fallback if Storage.getCookies is not supported: try Network.getAllCookies
                            if err_code == -32601 and parsed.get("id") == msg_id:
                                msg_id += 1
                                await ws.send(json.dumps({"id": msg_id, "method": "Network.getAllCookies"}))
                                continue

                        if "cookies" in parsed.get("result", {}):
                            cookies.extend(parsed["result"]["cookies"])
                            break
                    except asyncio.TimeoutError:
                        break
                    except Exception as e:
                        log(f"Error draining Browser Target WebSocket: {e}", "DEBUG")
                        break

                # 2. Dual-Layer Fallback: Query all active page targets in /json/list (NO early break!)
                try:
                    with urllib.request.urlopen(f"http://127.0.0.1:{cdp_port}/json/list", timeout=1.0) as r:
                        pages = json.loads(r.read().decode("utf-8"))

                    target_urls = [
                        "https://open.spotify.com",
                        "https://accounts.spotify.com",
                        "https://spotify.com"
                    ] if service == "spotify" else [
                        "https://music.youtube.com",
                        "https://youtube.com",
                        "https://www.youtube.com",
                        "https://accounts.google.com"
                    ]

                    for p in pages:
                        p_ws = p.get("webSocketDebuggerUrl")
                        p_url = p.get("url", "")
                        p_type = p.get("type")

                        if p_ws and p_type == "page":
                            p_ws = p_ws.replace("localhost", "127.0.0.1")
                            try:
                                async with websockets.connect(p_ws, ping_interval=None) as p_sock:
                                    await p_sock.send(json.dumps({
                                        "id": 777,
                                        "method": "Network.getCookies",
                                        "params": {
                                            "urls": target_urls
                                        }
                                    }))
                                    for _ in range(6):
                                        p_resp = await asyncio.wait_for(p_sock.recv(), timeout=0.6)
                                        p_parsed = json.loads(p_resp)
                                        if p_parsed.get("id") == 777:
                                            p_cks = p_parsed.get("result", {}).get("cookies", [])
                                            if p_cks:
                                                cookies.extend(p_cks)
                                            break
                            except Exception as pe:
                                log(f"Page query error for target [{p_url}]: {pe}", "DEBUG")
                except Exception as le:
                    log(f"Error reading /json/list: {le}", "DEBUG")

                # 3. Analyze accumulated cookies
                if cookies and service == "spotify":
                    spdc_val = ""
                    for c in cookies:
                        if c.get("name") == "sp_dc" and c.get("value"):
                            spdc_val = c.get("value").strip()
                            break

                    if spdc_val:
                        log(f"Detected Spotify sp_dc cookie: {spdc_val[:10]}... (length={len(spdc_val)}). Verifying...")
                        try:
                            import lyrics_helper
                            tok = lyrics_helper.get_spotify_access_token(spdc_val)
                            if tok:
                                settings_path = os.path.join(pc.get_config_dir(), f"nutsty_settings{PROFILE_SUFFIX}.json")
                                if not os.path.exists(settings_path):
                                    settings_path = os.path.join(pc.get_config_dir(), "nutsty_settings.json")
                                sdata = {}
                                if os.path.exists(settings_path):
                                    try:
                                        with open(settings_path, "r", encoding="utf-8") as sf:
                                            sdata = json.load(sf)
                                    except Exception:
                                        pass
                                sdata["spotifySpdc"] = spdc_val
                                with open(settings_path, "w", encoding="utf-8") as sf:
                                    json.dump(sdata, sf, indent=2, ensure_ascii=False)

                                sess_info = lyrics_helper.get_spotify_session_info(spdc_val)
                                log(f"Spotify authentication verified successfully! Session: {sess_info}")
                                emit_status({"status": "verified", "service": "spotify", "spdc": spdc_val, "message": "Connected to Spotify!"})
                                await asyncio.sleep(0.5)
                                return {"success": True, "service": "spotify", "spdc": spdc_val, "session": sess_info}
                            else:
                                if time.time() - last_pending_log > 3.0:
                                    last_pending_log = time.time()
                                    log("Found sp_dc cookie but token validation pending. Waiting for complete login...", "INFO")
                        except Exception as se:
                            log(f"Spotify verify exception: {se}", "WARN")

                elif cookies and service != "spotify":

                    yt_cookies = {}
                    google_cookies = {}
                    has_login_info = False
                    has_sapisid = False

                    for c in cookies:
                        name = c.get("name", "")
                        val = c.get("value", "")
                        domain = c.get("domain", "")
                        if not name or not val:
                            continue

                        if name == "LOGIN_INFO":
                            has_login_info = True

                        if name in ("SAPISID", "__Secure-3PAPISID"):
                            has_sapisid = True

                        if "youtube" in domain:
                            yt_cookies[name] = val
                        elif "google" in domain:
                            google_cookies[name] = val

                    # YouTube session requires LOGIN_INFO or YouTube-specific session credentials
                    has_yt_session = (
                        has_login_info or 
                        (len(yt_cookies) > 0 and any(k in ("LOGIN_INFO", "SID", "__Secure-3PSID", "__Secure-1PSID", "SSID") for k in yt_cookies))
                    )

                    has_session = (
                        has_yt_session or 
                        any(k in ("SID", "__Secure-3PSID", "__Secure-1PSID", "SSID") for k in google_cookies)
                    )

                    # Periodic diagnostic log (every 3 seconds)
                    if time.time() - last_cookie_summary_time > 3.0:
                        last_cookie_summary_time = time.time()
                        log(
                            f"Cookie scan summary: total={len(cookies)}, "
                            f"yt_cookies={len(yt_cookies)}, google_cookies={len(google_cookies)}, "
                            f"has_sapisid={has_sapisid}, has_login_info={has_login_info}, has_yt_session={has_yt_session}"
                        )

                    # Note when Google Accounts credentials have arrived
                    if has_sapisid and not google_signed_in_time:
                        google_signed_in_time = time.time()
                        log("Google authentication detected (SAPISID found). Awaiting YouTube Music redirect...")

                    # Auto-navigate to music.youtube.com if Google signed in but no YouTube session yet (>1.5s)
                    if has_sapisid and not has_yt_session and google_signed_in_time and (time.time() - google_signed_in_time > 1.5):
                        log("Google session active, navigating to music.youtube.com to complete YouTube auth...", "INFO")
                        try:
                            with urllib.request.urlopen(f"http://127.0.0.1:{cdp_port}/json/list", timeout=1.0) as r:
                                pages = json.loads(r.read().decode("utf-8"))
                            for p in pages:
                                p_url = p.get("url", "")
                                if p.get("type") == "page" and "music.youtube.com" not in p_url:
                                    p_ws = p.get("webSocketDebuggerUrl")
                                    if p_ws:
                                        p_ws = p_ws.replace("localhost", "127.0.0.1")
                                        async with websockets.connect(p_ws, ping_interval=None) as page_ws:
                                            await page_ws.send(json.dumps({
                                                "id": 999,
                                                "method": "Page.navigate",
                                                "params": {"url": "https://music.youtube.com/"}
                                            }))
                                            log("Dispatched Page.navigate to https://music.youtube.com/")
                                            break
                        except Exception as ne:
                            log(f"Page navigation helper error: {ne}", "WARN")

                    # Crucial condition: must have auth (SAPISID) AND YouTube session
                    if has_sapisid and has_yt_session:
                        log("Candidate credentials complete! Merging and verifying...")
                        merged = dict(google_cookies)
                        merged.update(yt_cookies)

                        # Defensive: ensure __Secure-3PAPISID exists if SAPISID does
                        if "SAPISID" in merged and "__Secure-3PAPISID" not in merged:
                            merged["__Secure-3PAPISID"] = merged["SAPISID"]
                        elif "__Secure-3PAPISID" in merged and "SAPISID" not in merged:
                            merged["SAPISID"] = merged["__Secure-3PAPISID"]

                        full_cookie_str = "; ".join(f"{k}={v}" for k, v in merged.items())

                        profile_hint = None
                        try:
                            profile_hint = await query_browser_profile(cdp_port)
                            if profile_hint and (profile_hint.get("name") or profile_hint.get("email")):
                                log(f"Extracted profile hint from browser: {profile_hint.get('name')} ({profile_hint.get('email')})")
                        except Exception as pe:
                            log(f"Profile hint extraction error: {pe}", "DEBUG")

                        # Verify auth using ytmusic_helper
                        try:
                            res = ytmusic_helper.save_auth(full_cookie_str, profile_hint=profile_hint)
                            if res.get("success"):
                                acc_name = res.get("name", "Google User")
                                acc_email = res.get("email", "")

                                # Verify authentic user account (MUST NOT be generic "Google User" with empty email)
                                is_genuine_user = (
                                    acc_name and acc_name != "Google User" and
                                    acc_email and "@" in acc_email and not acc_email.startswith("googleuser@")
                                )

                                if not is_genuine_user:
                                    if time.time() - last_pending_log > 3.0:
                                        last_pending_log = time.time()
                                        log("Waiting for user to complete sign-in and redirect to YouTube Music...", "INFO")
                                    await asyncio.sleep(1.0)
                                    continue

                                log(f"Authentication verified successfully! Account: {acc_name} ({acc_email})")
                                emit_status({"status": "verified", "name": acc_name, "email": acc_email, "message": f"Connected as {acc_name}!"})
                                await asyncio.sleep(0.5)
                                return res
                            else:
                                log(f"save_auth pending/failed: {res.get('error')}", "WARN")
                        except Exception as se:
                            log(f"save_auth exception: {se}\n{traceback.format_exc()}", "ERROR")

                await asyncio.sleep(1.0)
    except websockets.exceptions.ConnectionClosed:
        log("CDP WebSocket connection was closed prematurely.", "WARN")
        return {"success": False, "error": "Login window was closed."}
    except Exception as e:
        log(f"CDP capture error: {e}\n{traceback.format_exc()}", "ERROR")
        return {"success": False, "error": str(e)}

    log("Login timed out after 5 minutes.", "WARN")
    return {"success": False, "error": "Login timed out after 5 minutes."}

def start_login(service="youtube"):
    session_profile_dir = SPOTIFY_PROFILE_DIR if service == "spotify" else PROFILE_DIR
    login_url = SPOTIFY_LOGIN_URL if service == "spotify" else LOGIN_URL
    os.makedirs(session_profile_dir, exist_ok=True)

    log("=" * 60)
    log(f"Nutsty Browser Login Session Started (Service: {service})")
    log(f"Platform: {sys.platform} ({os.name}), Python: {sys.version.split()[0]}")
    log(f"Profile: '{PROFILE_NAME}', CDP Port: {CDP_PORT}")
    log(f"Session Profile Dir: {session_profile_dir}")
    log(f"Logs: {LOG_FILE_PRIMARY}")
    log("=" * 60)

    prompt_msg = "Starting native Spotify login assistant..." if service == "spotify" else "Starting native browser login assistant..."
    emit_status({"status": "starting", "service": service, "message": prompt_msg})

    browser_bin = find_system_browser()
    if not browser_bin:
        err = {"success": False, "error": "No Chromium-based browser (Edge, Chrome, Brave) found."}
        log(f"Aborting: {err['error']}", "ERROR")
        emit_status(err)
        return err

    cmd = [
        browser_bin,
        "--new-window",
        login_url,
        f"--remote-debugging-port={CDP_PORT}",
        "--remote-debugging-address=127.0.0.1",
        f"--user-data-dir={session_profile_dir}",
        "--no-first-run",
        "--no-default-browser-check",
        "--disable-background-mode",
        "--disable-features=msEdgeStartupBoost,Translate,OptimizationHints,MediaRouter",
        "--window-size=680,780"
    ]

    log(f"Launching browser command: {' '.join(cmd)}")
    sign_in_hint = "Please sign in to Spotify..." if service == "spotify" else "Please sign in with Google..."
    emit_status({"status": "browser_launched", "service": service, "browser": os.path.basename(browser_bin), "message": f"Browser opened. {sign_in_hint}"})

    kwargs = {}
    if sys.platform == "win32" or os.name == "nt":
        kwargs["creationflags"] = subprocess.CREATE_NEW_PROCESS_GROUP
    else:
        kwargs["preexec_fn"] = os.setsid

    proc = None
    try:
        proc = subprocess.Popen(
            cmd,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            **kwargs
        )
        log(f"Browser spawned with PID: {proc.pid}")
    except Exception as e:
        err = {"success": False, "error": f"Failed to spawn browser process: {e}"}
        log(f"Spawn error: {e}\n{traceback.format_exc()}", "ERROR")
        emit_status(err)
        return err

    ws_url = None
    log(f"Polling CDP endpoint at http://127.0.0.1:{CDP_PORT}/json/version...")
    for attempt in range(40):
        time.sleep(0.5)
        if proc.poll() is not None:
            if proc.poll() != 0:
                log(f"Browser process crashed with code {proc.poll()}.", "WARN")
                err = {"success": False, "error": f"Browser process crashed with code {proc.poll()}."}
                emit_status(err)
                return err
            elif attempt == 0:
                log("Browser launcher delegated to background process (code 0). Continuing CDP port discovery...")

        try:
            with urllib.request.urlopen(f"http://127.0.0.1:{CDP_PORT}/json/version", timeout=1.0) as r:
                ver_info = json.loads(r.read().decode("utf-8"))
                ws_url = ver_info.get("webSocketDebuggerUrl")
                if ws_url:
                    # Enforce IPv4 loopback
                    ws_url = ws_url.replace("localhost", "127.0.0.1")
                    log(f"CDP endpoint ready at attempt #{attempt + 1}: {ws_url}")
                    break
        except Exception as pe:
            if attempt % 10 == 0:
                log(f"CDP polling attempt #{attempt + 1}: {pe}", "DEBUG")
            continue

    if not ws_url:
        kill_browser_proc(proc)
        err = {"success": False, "error": "Failed to establish DevTools connection with browser window."}
        log(f"CDP connection timeout: {err['error']}", "ERROR")
        emit_status(err)
        return err

    result = {"success": False, "error": "Unknown error"}
    try:
        result = asyncio.run(capture_cookies_via_cdp(ws_url, CDP_PORT, proc, service=service))
    except Exception as e:
        result = {"success": False, "error": str(e)}
        log(f"CDP capture exception: {e}\n{traceback.format_exc()}", "ERROR")
    finally:
        kill_browser_proc(proc)

    log(f"Browser Login Session Finished. Result: success={result.get('success')}, error={result.get('error')}")
    emit_status(result)
    return result

def handle_cli(args=None):
    """Thread-safe CLI dispatcher entry point for launcher_win.py in-process runner."""
    svc = "youtube"
    if args:
        for i, a in enumerate(args):
            if a == "--service" and i + 1 < len(args):
                svc = args[i + 1]
    return start_login(service=svc)

def main():
    import argparse
    parser = argparse.ArgumentParser(description="Nutsty Native Browser Login Assistant")
    parser.add_argument("--service", choices=["youtube", "spotify"], default="youtube", help="Service to authenticate")
    args, _ = parser.parse_known_args()
    start_login(service=args.service)

if __name__ == "__main__":
    main()

