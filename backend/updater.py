#!/usr/bin/env python3
"""
Nutsty Update Checker
Queries GitHub Releases API, performs semantic version comparison,
caches results (TTL 6 hours) to prevent GitHub rate-limiting,
and returns structured update info with direct download assets.
"""
import os
import sys
import json
import time
import re
import urllib.request
import urllib.error
import zipfile
import shutil
import subprocess
import threading

try:
    from . import platform_compat as pc
except (ImportError, ValueError):
    import platform_compat as pc

CONFIG_DIR = pc.get_config_dir()
CACHE_FILE = os.path.join(CONFIG_DIR, "nutsty_update_cache.json")
CACHE_TTL = 6 * 3600  # 6 hours TTL

def parse_semver(v_str):
    """Parse version string like 'v1.0.11' or '1.0.0-beta.1' into comparable tuple."""
    if not v_str:
        return (0, 0, 0)
    cleaned = re.sub(r"^[vV]", "", str(v_str).strip())
    match = re.match(r"^(\d+)\.(\d+)(?:\.(\d+))?", cleaned)
    if match:
        major = int(match.group(1))
        minor = int(match.group(2))
        patch = int(match.group(3)) if match.group(3) else 0
        return (major, minor, patch)
    return (0, 0, 0)

def is_newer_version(latest_tag, current_ver):
    """Return True if latest_tag > current_ver."""
    v_latest = parse_semver(latest_tag)
    v_current = parse_semver(current_ver)
    return v_latest > v_current

def load_cached_update():
    """Load cached update info if still valid within TTL."""
    if not os.path.exists(CACHE_FILE):
        return None
    try:
        with open(CACHE_FILE, "r", encoding="utf-8") as f:
            data = json.load(f)
            checked_at = data.get("checked_at", 0)
            if time.time() - checked_at < CACHE_TTL:
                return data
    except Exception:
        pass
    return None

def save_cached_update(data):
    """Save update info to cache file."""
    try:
        os.makedirs(CONFIG_DIR, exist_ok=True)
        with open(CACHE_FILE, "w", encoding="utf-8") as f:
            json.dump(data, f, ensure_ascii=False, indent=2)
    except Exception as e:
        sys.stderr.write(f"save_cached_update error: {e}\n")

def check_for_updates(force=False, mock=False):
    """
    Check GitHub Releases API for Nutsty updates.
    Returns dictionary with update status, versions, changelog, and download link.
    """
    current_ver = getattr(pc, "APP_VERSION", "1.0.0")

    if mock:
        return {
            "has_update": True,
            "current_version": current_ver,
            "latest_version": "v1.0.2",
            "release_name": "Nutsty v1.0.2 (Windows Hotfixes & Stability)",
            "changelog": "- Khắc phục lỗi lệch bài hát / desync metadata\n- Sửa lỗi trỏ chuột đồng hồ cát và mở duplicate cửa sổ\n- Sửa lỗi nền trắng và giật rung ở Desktop Lyrics Widget\n- Tối ưu hóa CPU, loại bỏ rò rỉ luồng và chống nóng máy\n- Khắc phục lỗi không phát nhạc sau khi khởi động lại máy",
            "release_url": "https://github.com/trancongduyhieu/FrostifyLocal/releases",
            "download_url": "https://github.com/trancongduyhieu/FrostifyLocal/releases/download/v1.0.2/Nutsty_Windows_Portable.zip",
            "checked_at": int(time.time())
        }

    if not force:
        cached = load_cached_update()
        if cached:
            cached["current_version"] = current_ver
            cached["has_update"] = is_newer_version(cached.get("latest_version", ""), current_ver)
            return cached

    repos = ["trancongduyhieu/FrostifyLocal", "trancongduyhieu/Nutsty"]
    release_data = None
    last_err = ""

    for repo in repos:
        api_url = f"https://api.github.com/repos/{repo}/releases"
        try:
            req = urllib.request.Request(
                api_url,
                headers={
                    "User-Agent": "Nutsty-Desktop-App/1.0",
                    "Accept": "application/vnd.github.v3+json"
                }
            )
            with urllib.request.urlopen(req, timeout=4.0) as resp:
                if resp.status == 200:
                    releases = json.loads(resp.read().decode("utf-8"))
                    if isinstance(releases, list) and len(releases) > 0:
                        # Find first non-prerelease or the latest release
                        non_pre = [r for r in releases if not r.get("prerelease", False)]
                        release_data = non_pre[0] if non_pre else releases[0]
                        break
        except Exception as e:
            last_err = str(e)
            continue

    if not release_data:
        # Fallback to releases.atom (HTML-based RSS feed, not subject to 60 req/hr REST API rate limits)
        import xml.etree.ElementTree as ET
        for repo in repos:
            atom_url = f"https://github.com/{repo}/releases.atom"
            try:
                req = urllib.request.Request(
                    atom_url,
                    headers={"User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64)"}
                )
                with urllib.request.urlopen(req, timeout=5.0) as resp:
                    if resp.status == 200:
                        root = ET.fromstring(resp.read())
                        ns = {'atom': 'http://www.w3.org/2005/Atom'}
                        entry = root.find('atom:entry', ns)
                        if entry is not None:
                            title_elem = entry.find('atom:title', ns)
                            if title_elem is not None and title_elem.text:
                                tag = title_elem.text.strip()
                                link_elem = entry.find('atom:link', ns)
                                atom_html = link_elem.attrib.get('href') if link_elem is not None else f"https://github.com/{repo}/releases/tag/{tag}"
                                content_elem = entry.find('atom:content', ns)
                                atom_body = ""
                                if content_elem is not None and content_elem.text:
                                    atom_body = re.sub(r'<[^>]+>', '', content_elem.text).strip()
                                
                                asset_name = "Nutsty_Windows_Portable.zip" if getattr(pc, "IS_WINDOWS", False) else "Nutsty_Linux.zip"
                                atom_download = f"https://github.com/{repo}/releases/download/{tag}/{asset_name}"
                                release_data = {
                                    "tag_name": tag,
                                    "name": tag,
                                    "body": atom_body,
                                    "html_url": atom_html,
                                    "assets": [{"name": asset_name, "browser_download_url": atom_download}]
                                }
                                break
            except Exception as e:
                last_err = str(e)
                continue

    if not release_data:
        # Offline or GitHub rate limit
        res = {
            "has_update": False,
            "current_version": current_ver,
            "latest_version": current_ver,
            "release_name": "",
            "changelog": "",
            "release_url": "https://github.com/trancongduyhieu/Nutsty/releases",
            "download_url": "",
            "checked_at": int(time.time()),
            "error": last_err
        }
        return res

    latest_tag = release_data.get("tag_name", "")
    release_name = release_data.get("name") or latest_tag
    body = (release_data.get("body") or "").strip()
    html_url = release_data.get("html_url", "https://github.com/trancongduyhieu/Nutsty/releases")

    # Find download asset
    download_url = ""
    assets = release_data.get("assets", [])
    if isinstance(assets, list):
        if pc.IS_WINDOWS:
            for a in assets:
                name = a.get("name", "").lower()
                if "portable.zip" in name or ".zip" in name or ".exe" in name:
                    download_url = a.get("browser_download_url", "")
                    break
        else:
            for a in assets:
                name = a.get("name", "").lower()
                if ".tar.gz" in name or ".zip" in name:
                    download_url = a.get("browser_download_url", "")
                    break
        if not download_url and assets:
            download_url = assets[0].get("browser_download_url", "")

    if not download_url:
        download_url = html_url

    has_update = is_newer_version(latest_tag, current_ver)

    res = {
        "has_update": has_update,
        "current_version": current_ver,
        "latest_version": latest_tag,
        "release_name": release_name,
        "changelog": body,
        "release_url": html_url,
        "download_url": download_url,
        "checked_at": int(time.time())
    }

    save_cached_update(res)
    return res


class DirectUpdateManager:
    def __init__(self):
        self._lock = threading.Lock()
        self.active = False
        self.status = "idle"  # idle, downloading, extracting, ready, error
        self.progress = 0.0
        self.percent = 0
        self.message = ""
        self.error = None
        self.target_version = ""
        self.staged_dir = None

    def get_status(self):
        with self._lock:
            return {
                "active": self.active,
                "status": self.status,
                "progress": self.progress,
                "percent": self.percent,
                "message": self.message,
                "error": self.error,
                "target_version": self.target_version
            }

    def start_download_update(self, download_url=None, target_version=None):
        with self._lock:
            if self.active:
                return {"success": False, "error": "Đang có tiến trình cập nhật đang chạy."}
            self.active = True
            self.status = "downloading"
            self.progress = 0.0
            self.percent = 0
            self.message = "Đang kết nối tới máy chủ cập nhật..."
            self.error = None

        thread = threading.Thread(target=self._worker_download, args=(download_url, target_version), daemon=True)
        thread.start()
        return {"success": True, "message": "Bắt đầu tải bản cập nhật."}

    def _worker_download(self, download_url, target_version):
        try:
            if not download_url:
                info = check_for_updates(force=True)
                download_url = info.get("download_url")
                target_version = info.get("latest_version")

            if not download_url or not str(download_url).startswith("http"):
                raise ValueError("Không tìm thấy tệp cập nhật hợp lệ.")

            with self._lock:
                self.target_version = target_version or "latest"
                self.message = "Đang tải bản cập nhật..."

            update_root = os.path.join(CONFIG_DIR, "updates")
            os.makedirs(update_root, exist_ok=True)
            zip_dest = os.path.join(update_root, "update.zip")
            staged_dest = os.path.join(update_root, "staged")

            if os.path.exists(zip_dest):
                try:
                    os.remove(zip_dest)
                except Exception:
                    pass
            if os.path.exists(staged_dest):
                try:
                    shutil.rmtree(staged_dest, ignore_errors=True)
                except Exception:
                    pass

            req = urllib.request.Request(
                download_url,
                headers={"User-Agent": "Nutsty-Desktop-App/1.0"}
            )

            with urllib.request.urlopen(req, timeout=60.0) as resp:
                total_size = int(resp.headers.get("Content-Length", 0))
                downloaded = 0
                chunk_size = 65536
                with open(zip_dest, "wb") as f_out:
                    while True:
                        chunk = resp.read(chunk_size)
                        if not chunk:
                            break
                        f_out.write(chunk)
                        downloaded += len(chunk)
                        if total_size > 0:
                            pct = min(100, int((downloaded / total_size) * 100))
                            prog = min(1.0, downloaded / float(total_size))
                            with self._lock:
                                self.progress = prog
                                self.percent = pct
                                self.message = f"Đang tải bản cập nhật ({pct}%)..."

            with self._lock:
                self.status = "extracting"
                self.message = "Đang giải nén bản cập nhật..."

            os.makedirs(staged_dest, exist_ok=True)
            with zipfile.ZipFile(zip_dest, "r") as zf:
                zf.extractall(staged_dest)

            entries = os.listdir(staged_dest)
            final_stage = staged_dest
            if len(entries) == 1 and os.path.isdir(os.path.join(staged_dest, entries[0])):
                final_stage = os.path.join(staged_dest, entries[0])

            with self._lock:
                self.active = False
                self.status = "ready"
                self.staged_dir = final_stage
                self.progress = 1.0
                self.percent = 100
                self.message = "Bản cập nhật đã tải xong! Bấm để áp dụng và khởi động lại."
        except Exception as e:
            with self._lock:
                self.active = False
                self.status = "error"
                self.error = str(e)
                self.message = f"Lỗi tải cập nhật: {str(e)}"

    def apply_update_and_restart(self, target_dir=None):
        with self._lock:
            staged = self.staged_dir
        if not staged or not os.path.exists(staged):
            default_staged = os.path.join(CONFIG_DIR, "updates", "staged")
            if os.path.exists(default_staged):
                entries = os.listdir(default_staged)
                if len(entries) == 1 and os.path.isdir(os.path.join(default_staged, entries[0])):
                    staged = os.path.join(default_staged, entries[0])
                else:
                    staged = default_staged
            else:
                return {"success": False, "error": "Chưa có bản cập nhật được giải nén sẵn sàng."}

        if target_dir and os.path.exists(target_dir):
            app_dir = os.path.abspath(target_dir)
            exe_name = "Nutsty.exe"
        elif getattr(sys, "frozen", False):
            app_dir = os.path.dirname(os.path.abspath(sys.executable))
            exe_name = os.path.basename(sys.executable)
        else:
            app_dir = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
            exe_name = "Nutsty.exe"

        staged = os.path.normpath(staged)
        app_dir = os.path.normpath(app_dir)

        if pc.IS_WINDOWS:
            bat_path = os.path.normpath(os.path.join(CONFIG_DIR, "updates", "apply_update.bat"))
            os.makedirs(os.path.dirname(bat_path), exist_ok=True)
            script_content = f"""@echo off
chcp 65001 >nul
title Nutsty Updater
cls
echo ========================================================
echo    Nutsty - Dang cap nhat len phien ban moi...
echo ========================================================
echo.
ping 127.0.0.1 -n 2 >nul

echo [*] Dang dong tien trinh cu / Terminating old processes...
taskkill /f /im Nutsty.exe >nul 2>&1
taskkill /f /im mpv.exe >nul 2>&1
ping 127.0.0.1 -n 2 >nul

echo [*] Dang ghi de tep cap nhat / Applying update files...
robocopy "{staged}" "{app_dir}" /E /IS /IT /NP /R:2 /W:1 >nul

echo [*] Hoan tat! Dang khoi dong lai Nutsty / Launching new version...
ping 127.0.0.1 -n 2 >nul
if exist "{app_dir}\\{exe_name}" (
    start "" "{app_dir}\\{exe_name}"
) else if exist "{app_dir}\\start.bat" (
    start "" "{app_dir}\\start.bat"
)
exit
"""
            with open(bat_path, "w", encoding="utf-8") as f:
                f.write(script_content)

            CREATE_NEW_CONSOLE = 0x00000010
            CREATE_NEW_PROCESS_GROUP = 0x00000200
            flags = CREATE_NEW_CONSOLE | CREATE_NEW_PROCESS_GROUP
            subprocess.Popen(["cmd.exe", "/c", bat_path], creationflags=flags, close_fds=True)
            return {"success": True, "message": "Đang khởi động lại ứng dụng..."}
        else:
            sh_path = os.path.join(CONFIG_DIR, "updates", "apply_update.sh")
            os.makedirs(os.path.dirname(sh_path), exist_ok=True)
            sh_content = f"""#!/bin/sh
sleep 1
cp -rf "{staged}"/* "{app_dir}"/
if [ -f "{app_dir}/run.sh" ]; then
    sh "{app_dir}/run.sh" &
fi
"""
            with open(sh_path, "w", encoding="utf-8") as f:
                f.write(sh_content)
            os.chmod(sh_path, 0o755)
            subprocess.Popen(["/bin/sh", sh_path], start_new_session=True)
            return {"success": True, "message": "Đang khởi động lại ứng dụng..."}

direct_updater = DirectUpdateManager()

if __name__ == "__main__":
    force_check = "--force" in sys.argv
    info = check_for_updates(force=force_check)
    print(json.dumps(info, ensure_ascii=False, indent=2))
