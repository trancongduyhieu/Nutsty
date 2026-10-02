#!/usr/bin/env python3
"""
Nutsty Platform Compatibility Layer
Handles cross-platform paths, process lifecycle, IPC socket targets, and binary resolution
between Linux (Wayland / Niri) and Windows (PySide6 / Win32).
"""
import os
import sys
import platform
import tempfile
import socket
import shutil
import subprocess
import time
from pathlib import Path

IS_WINDOWS = platform.system() == "Windows"
IS_LINUX = platform.system() == "Linux"
IS_MACOS = platform.system() == "Darwin"

APP_ROOT = os.getenv("NUTSTY_APP_DIR") or os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

_bin_dir = os.path.join(APP_ROOT, "bin")
if os.path.exists(_bin_dir) and _bin_dir not in os.environ.get("PATH", ""):
    os.environ["PATH"] = _bin_dir + os.pathsep + os.environ.get("PATH", "")

def configure_windows_utf8():
    """Ensure standard input/output/error streams use UTF-8 on Windows."""
    if IS_WINDOWS:
        os.environ["PYTHONIOENCODING"] = "utf-8"
        os.environ["PYTHONUTF8"] = "1"
        try:
            if hasattr(sys.stdout, "reconfigure"):
                sys.stdout.reconfigure(encoding="utf-8", errors="replace")
            if hasattr(sys.stderr, "reconfigure"):
                sys.stderr.reconfigure(encoding="utf-8", errors="replace")
        except Exception:
            pass

configure_windows_utf8()

_CONFIG_MIGRATED = False

def get_config_dir() -> str:
    """
    Single Source of Truth (SSOT) configuration directory across Linux and Windows.
    Always resolves to ~/.config/noctalia (matching QML FileView & Quickshell paths)
    and migrates any legacy %APPDATA%/Nutsty files on Windows seamlessly.
    """
    global _CONFIG_MIGRATED
    xdg = os.getenv("XDG_CONFIG_HOME") or os.path.expanduser("~/.config")
    base = os.path.join(xdg, "noctalia")
    os.makedirs(base, exist_ok=True)

    if IS_WINDOWS and not _CONFIG_MIGRATED:
        _CONFIG_MIGRATED = True
        appdata = os.getenv("APPDATA")
        if appdata:
            legacy_win_dir = os.path.join(appdata, "Nutsty")
            if os.path.isdir(legacy_win_dir):
                try:
                    for item in os.listdir(legacy_win_dir):
                        src = os.path.join(legacy_win_dir, item)
                        dst = os.path.join(base, item)
                        if not os.path.exists(dst):
                            if os.path.isdir(src):
                                shutil.copytree(src, dst, dirs_exist_ok=True)
                            else:
                                shutil.copy2(src, dst)
                except Exception:
                    pass
    return base

def get_config_path() -> Path:
    """Return SSOT configuration directory as a pathlib.Path."""
    return Path(get_config_dir())

def get_profile_suffix(profile: str = None, user_email: str = None) -> str:
    """Resolve profile suffix (_user1, _user2, _friend, or '') from profile or email."""
    if profile:
        p = str(profile).strip().lower()
        if p in ("user1", "_user1"):
            return "_user1"
        elif p in ("default", "main", ""):
            return ""
        elif p.startswith("_"):
            return p
        else:
            return f"_{p}"
    if user_email:
        em = str(user_email).strip().lower()
        if "user1" in em:
            return "_user1"
        elif "user2" in em:
            return "_user2"
        elif "friend" in em:
            return "_friend"
        d = get_config_dir()
        import glob
        for cache_file in glob.glob(os.path.join(d, "nutsty_user_cache*.json")):
            try:
                import json
                with open(cache_file, "r", encoding="utf-8") as f:
                    cdata = json.load(f)
                    if (cdata.get("email") or "").strip().lower() == em or (cdata.get("handle") or "").strip().lower() == em:
                        base_name = os.path.basename(cache_file)
                        return base_name.replace("nutsty_user_cache", "").replace(".json", "")
            except Exception:
                pass
    env_p = os.getenv("NUTSTY_PROFILE", "").strip().lower()
    if env_p in ("user1", "_user1"):
        return "_user1"
    if env_p in ("default", "main", ""):
        return ""
    return env_p if env_p.startswith("_") else f"_{env_p}"

def get_cloud_identity_file(suffix: str = "") -> Path:
    if suffix in ("_user1", "user1"):
        norm_suffix = "_user1"
    elif suffix:
        norm_suffix = suffix if suffix.startswith("_") else f"_{suffix}"
    else:
        norm_suffix = ""
    return get_config_path() / f"nutsty_cloud_identity{norm_suffix}.json"

def get_notes_vault_file() -> Path:
    return get_config_path() / "nutsty_notes_vault.json"

def get_events_vault_file() -> Path:
    return get_config_path() / "nutsty_notes_events.json"

def get_friends_vault_file() -> Path:
    return get_config_path() / "nutsty_friends_vault.json"

def get_friend_requests_vault_file() -> Path:
    return get_config_path() / "nutsty_friend_requests_vault.json"

def get_profiles_vault_file() -> Path:
    return get_config_path() / "nutsty_profiles_vault.json"

def get_friends_file(suffix: str = "") -> Path:
    return get_config_path() / f"nutsty_friends{suffix}.json"

def get_notes_cache_file(suffix: str = "") -> Path:
    return get_config_path() / f"nutsty_notes_cache{suffix}.json"

def get_cache_dir() -> str:
    """Return platform-appropriate cache directory."""
    if IS_WINDOWS:
        local_appdata = os.getenv("LOCALAPPDATA")
        if local_appdata:
            base = os.path.join(local_appdata, "Nutsty", "cache")
        else:
            base = os.path.expanduser("~/.cache/nutsty")
    else:
        base = os.path.expanduser("~/.cache/nutsty")
    os.makedirs(base, exist_ok=True)
    return base

def get_temp_dir() -> str:
    """Return platform-appropriate temp directory."""
    if IS_WINDOWS:
        base = os.path.join(tempfile.gettempdir(), "nutsty")
        os.makedirs(base, exist_ok=True)
        return base
    return "/tmp"

def get_music_dir() -> str:
    """Return user's Music directory across platforms."""
    if IS_WINDOWS:
        userprofile = os.getenv("USERPROFILE")
        if userprofile:
            m = os.path.join(userprofile, "Music")
            if os.path.exists(m):
                return m
    return os.path.expanduser("~/Music")

APP_VERSION = "1.0.3"
GITHUB_REPO = "trancongduyhieu/FrostifyLocal"

if IS_WINDOWS:
    import ctypes
    from ctypes import wintypes

    kernel32 = ctypes.windll.kernel32
    kernel32.CreateFileW.argtypes = [wintypes.LPCWSTR, wintypes.DWORD, wintypes.DWORD, wintypes.LPVOID, wintypes.DWORD, wintypes.DWORD, wintypes.HANDLE]
    kernel32.CreateFileW.restype = wintypes.HANDLE
    kernel32.WaitNamedPipeW.argtypes = [wintypes.LPCWSTR, wintypes.DWORD]
    kernel32.WaitNamedPipeW.restype = wintypes.BOOL
    kernel32.WriteFile.argtypes = [wintypes.HANDLE, wintypes.LPCVOID, wintypes.DWORD, ctypes.POINTER(wintypes.DWORD), wintypes.LPVOID]
    kernel32.WriteFile.restype = wintypes.BOOL
    kernel32.ReadFile.argtypes = [wintypes.HANDLE, wintypes.LPVOID, wintypes.DWORD, ctypes.POINTER(wintypes.DWORD), wintypes.LPVOID]
    kernel32.ReadFile.restype = wintypes.BOOL
    kernel32.CloseHandle.argtypes = [wintypes.HANDLE]
    kernel32.CloseHandle.restype = wintypes.BOOL

    GENERIC_READ = 0x80000000
    GENERIC_WRITE = 0x40000000
    OPEN_EXISTING = 3
    INVALID_HANDLE_VALUE = wintypes.HANDLE(-1).value

    def is_invalid_handle(h):
        return h in (None, 0, -1, 0xFFFFFFFFFFFFFFFF, INVALID_HANDLE_VALUE)

    class WindowsNamedPipeClient:
        def __init__(self, pipe_name: str, timeout: float = 2.0):
            self.pipe_name = pipe_name
            self.timeout = float(timeout)
            timeout_ms = int(self.timeout * 1000)
            kernel32.WaitNamedPipeW(pipe_name, max(100, timeout_ms))
            self.handle = kernel32.CreateFileW(
                pipe_name,
                GENERIC_READ | GENERIC_WRITE,
                0,
                None,
                OPEN_EXISTING,
                0,
                None
            )
            if is_invalid_handle(self.handle):
                err = ctypes.GetLastError()
                raise OSError(f"Failed to open named pipe {pipe_name}, win32 error: {err}")

        def settimeout(self, timeout: float):
            self.timeout = max(0.1, float(timeout))

        def sendall(self, data: bytes):
            if is_invalid_handle(self.handle):
                raise OSError("Cannot write to invalid named pipe handle")
            bytes_written = ctypes.c_ulong()
            res = kernel32.WriteFile(self.handle, data, len(data), ctypes.byref(bytes_written), None)
            if not res:
                err = ctypes.GetLastError()
                raise OSError(f"WriteFile to named pipe failed, error: {err}")

        def recv(self, bufsize: int = 4096) -> bytes:
            if is_invalid_handle(self.handle):
                return b""

            buf = ctypes.create_string_buffer(bufsize)
            bytes_read = ctypes.c_ulong()
            avail = ctypes.c_ulong()

            deadline = time.time() + self.timeout
            while time.time() < deadline:
                res_peek = kernel32.PeekNamedPipe(self.handle, None, 0, None, ctypes.byref(avail), None)
                if not res_peek:
                    err = ctypes.GetLastError()
                    if err in (109, 233):  # ERROR_BROKEN_PIPE or ERROR_PIPE_NOT_CONNECTED
                        return b""
                    raise OSError(f"PeekNamedPipe failed, error: {err}")

                if avail.value > 0:
                    to_read = min(bufsize, avail.value)
                    res = kernel32.ReadFile(self.handle, buf, to_read, ctypes.byref(bytes_read), None)
                    if not res:
                        err = ctypes.GetLastError()
                        if err in (109, 233):
                            return b""
                        raise OSError(f"ReadFile from named pipe failed, error: {err}")
                    return buf.raw[:bytes_read.value]

                time.sleep(0.015)

            # Timeout elapsed without incoming data: return empty bytes gracefully
            return b""

        def close(self):
            if not is_invalid_handle(self.handle):
                kernel32.CloseHandle(self.handle)
                self.handle = INVALID_HANDLE_VALUE
else:
    class WindowsNamedPipeClient:
        pass

def get_mpv_ipc_target(profile_suffix: str = ""):
    r"""
    Return (ipc_type, address) for MPV IPC communication.
    On Linux: ('unix', '/tmp/nutsty_mpv<suffix>.sock')
    On Windows: ('pipe', r'\\.\pipe\nutsty_mpv<suffix>')
    """
    if IS_WINDOWS:
        pipe_path = rf"\\.\pipe\nutsty_mpv{profile_suffix}"
        return ("pipe", pipe_path)
    else:
        sock_path = f"/tmp/nutsty_mpv{profile_suffix}.sock"
        return ("unix", sock_path)

def get_mpv_ipc_arg(ipc_type: str, address) -> str:
    """Return the --input-ipc-server argument for MPV CLI."""
    return f"--input-ipc-server={address}"

def connect_mpv_socket(ipc_type: str, address, timeout: float = 2.0):
    """Open and return a connected socket or pipe client to MPV IPC server."""
    if ipc_type == "pipe":
        return WindowsNamedPipeClient(address, timeout=timeout)
    elif ipc_type == "tcp":
        s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        s.settimeout(timeout)
        s.connect(address)
        return s
    else:
        s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        s.settimeout(timeout)
        s.connect(address)
        return s

def is_process_running(name_or_title: str) -> bool:
    """Check if process with title or image name is currently active."""
    if IS_WINDOWS:
        try:
            CREATE_NO_WINDOW = 0x08000000
            exe_name = name_or_title if name_or_title.endswith(".exe") else f"{name_or_title}.exe"
            cmd = ["tasklist", "/fi", f"imagename eq {exe_name}"]
            res = subprocess.run(cmd, capture_output=True, text=True, timeout=2, creationflags=CREATE_NO_WINDOW)
            return exe_name.lower() in res.stdout.lower()
        except Exception:
            return False
    else:
        try:
            res = subprocess.run(["pgrep", "-f", f"title={name_or_title}"], capture_output=True, text=True, timeout=2)
            return res.returncode == 0 and bool(res.stdout.strip())
        except Exception:
            return False

def kill_process(name_or_title: str):
    """Force terminate process cleanly across platforms."""
    if IS_WINDOWS:
        try:
            CREATE_NO_WINDOW = 0x08000000
            exe_name = name_or_title if name_or_title.endswith(".exe") else f"{name_or_title}.exe"
            subprocess.run(["taskkill", "/f", "/im", exe_name], capture_output=True, timeout=3, creationflags=CREATE_NO_WINDOW)
        except Exception:
            pass
    else:
        try:
            subprocess.run(["pkill", "-9", "-f", f"title={name_or_title}"], capture_output=True, timeout=3)
        except Exception:
            pass

def get_binary_path(name: str) -> str:
    """Resolve executable path, checking local bin/ directory before system PATH."""
    bin_ext = ".exe" if IS_WINDOWS else ""
    local_bin = os.path.join(APP_ROOT, "bin", f"{name}{bin_ext}")
    if os.path.exists(local_bin) and os.path.isfile(local_bin):
        return local_bin
    
    found = shutil.which(name if not IS_WINDOWS else f"{name}{bin_ext}")
    if found:
        # On Windows, never use .com console wrapper if .exe exists
        if IS_WINDOWS and found.lower().endswith(".com"):
            exe_alt = found[:-4] + ".exe"
            if os.path.exists(exe_alt):
                return exe_alt
        return found
    return name

def get_daemon_popen_kwargs() -> dict:
    """Return platform-safe subprocess flags for detached background execution."""
    kwargs = {}
    if IS_WINDOWS:
        CREATE_NO_WINDOW = 0x08000000
        kwargs["creationflags"] = CREATE_NO_WINDOW
    else:
        kwargs["start_new_session"] = True
    return kwargs

def configure_windows_ssl():
    """Ensure SSL certificates work reliably across Windows PyInstaller bundles and requests/urllib."""
    try:
        import ssl
        try:
            import certifi
            ca_path = certifi.where()
            if os.path.exists(ca_path):
                orig_create_default = ssl.create_default_context
                ssl.create_default_context = lambda *args, **kwargs: orig_create_default(cafile=ca_path)
                ssl._create_default_https_context = lambda: orig_create_default(cafile=ca_path)
                os.environ["REQUESTS_CA_BUNDLE"] = ca_path
                os.environ["CURL_CA_BUNDLE"] = ca_path
                os.environ["SSL_CERT_FILE"] = ca_path
                return
        except Exception:
            pass
        # Fallback to unverified context to prevent hard crashes on Windows when root CAs are missing
        ssl._create_default_https_context = ssl._create_unverified_context
        try:
            import urllib3
            urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)
        except Exception:
            pass
    except Exception:
        pass

def get_ssl_context():
    """Returns an SSLContext configured with certifi or unverified fallback for Windows."""
    import ssl
    try:
        import certifi
        ca_path = certifi.where()
        if os.path.exists(ca_path):
            return ssl.create_default_context(cafile=ca_path)
    except Exception:
        pass
    try:
        return ssl._create_unverified_context()
    except Exception:
        return None

def patch_gettext_translation():
    """Ensure gettext.translation does not crash if locale files are missing (common in PyInstaller bundles)."""
    try:
        import gettext
        if getattr(gettext, "_nutsty_patched", False):
            return
        orig_translation = gettext.translation
        def _safe_translation(domain, localedir=None, languages=None, class_=None, fallback=False, codeset=None):
            try:
                return orig_translation(domain, localedir=localedir, languages=languages, class_=class_, fallback=fallback)
            except (FileNotFoundError, OSError):
                return gettext.NullTranslations()
        gettext.translation = _safe_translation
        gettext._nutsty_patched = True
    except Exception:
        pass

patch_gettext_translation()
