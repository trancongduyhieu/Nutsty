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
from concurrent.futures import ThreadPoolExecutor

try:
    from . import platform_compat as pc
except (ImportError, ValueError):
    import platform_compat as pc
try:
    from . import update_delta as ud
except (ImportError, ValueError):
    import update_delta as ud

CONFIG_DIR = pc.get_config_dir()
CACHE_FILE = os.path.join(CONFIG_DIR, "nutsty_update_cache.json")
CACHE_TTL = 6 * 3600  # 6 hours TTL

def parse_semver(v_str):
    """Parse version string like 'v1.0.11', '1.0.5' or '1.0.0-beta.1' into comparable 4-element tuple."""
    if not v_str:
        return (0, 0, 0, 0)
    cleaned = re.sub(r"^[vV]", "", str(v_str).strip())
    base_ver = cleaned.split("-")[0]
    nums = [int(x) for x in re.findall(r"\d+", base_ver)]
    while len(nums) < 4:
        nums.append(0)
    return tuple(nums[:4])

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
            "latest_version": "v2.2.0",
            "release_name": "Nutsty v2.2.0",
            "changelog": "- Thanh phát nhạc kính lỏng viên nhộng: Thiết kế thanh điều khiển nổi dạng viên nhộng trong suốt hiện đại, làm mờ êm ái hình ảnh bên dưới giúp tên bài hát và ca sĩ luôn nổi bật, dễ nhìn.\n- Quầng sáng tỏa lan khi giữ chuột: Khi bạn nhấn giữ vào thanh phát nhạc, thanh sẽ phóng to nhẹ nhàng và tỏa ra vầng sáng nam châm mềm mại bám theo con trỏ chuột.\n- Thanh trượt âm lượng dạng dọc: Bấm vào biểu tượng loa để mở thanh điều chỉnh âm lượng dọc nhỏ gọn, hỗ trợ bấm chọn mức âm lượng tức thì hoặc lăn con lăn chuột cực kỳ thuận tiện.\n- Hàng đợi bài hát tiếp theo: Bấm biểu tượng danh sách cạnh nút Thích để mở nhanh danh sách các bài hát chuẩn bị phát.\n- Nút Thích và Đóng tiện lợi: Trái tim đổi sang màu đỏ rực rỡ khi bạn yêu thích bài hát; nút [✕] giúp dừng phát và làm gọn thanh phát nhạc khi cần.",
            "release_url": "https://github.com/trancongduyhieu/Nutsty/releases",
            "download_url": "https://github.com/trancongduyhieu/Nutsty/releases/download/v2.2.0/Nutsty_Windows_Portable.zip",
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
    all_releases = []
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
                        all_releases = non_pre
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
                                
                                assets = []
                                if getattr(pc, "IS_WINDOWS", False):
                                    asset_name = "Nutsty_Windows_Portable.zip"
                                    assets.append({"name": asset_name, "browser_download_url": f"https://github.com/{repo}/releases/download/{tag}/{asset_name}"})
                                release_data = {
                                    "tag_name": tag,
                                    "name": tag,
                                    "body": atom_body,
                                    "html_url": atom_html,
                                    "assets": assets
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
    # Skipping versions (2.1.0 -> 2.3.1): show what every release in between added, newest first
    skipped = [r for r in all_releases
               if is_newer_version(r.get("tag_name", ""), current_ver) and (r.get("body") or "").strip()]
    if len(skipped) > 1:
        body = "\n".join(f"## {r.get('tag_name', '')}\n{(r.get('body') or '').strip()}" for r in skipped)
    html_url = release_data.get("html_url", "https://github.com/trancongduyhieu/Nutsty/releases")

    # Find download asset
    download_url = ""
    download_size = 0
    assets = release_data.get("assets", [])
    if isinstance(assets, list):
        if pc.IS_WINDOWS:
            for a in assets:
                name = a.get("name", "").lower()
                if "portable.zip" in name or ".zip" in name or ".exe" in name:
                    download_url = a.get("browser_download_url", "")
                    download_size = int(a.get("size") or 0)
                    break
        else:
            for a in assets:
                name = a.get("name", "").lower()
                # Do NOT download Windows packages on Linux
                if any(w in name for w in ["win", "windows", "portable", ".exe"]):
                    continue
                if "linux" in name or ".tar.gz" in name:
                    download_url = a.get("browser_download_url", "")
                    break
        if not download_url and assets and pc.IS_WINDOWS:
            download_url = assets[0].get("browser_download_url", "")

    # Releases only ship a Windows build; Linux runs from source, so fall back to the tag's source archive
    if not download_url and not pc.IS_WINDOWS and latest_tag:
        download_url = source_archive_url(latest_tag)

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
        "download_size": download_size,
        "checked_at": int(time.time())
    }

    save_cached_update(res)
    return res


def source_archive_url(tag):
    return f"https://github.com/trancongduyhieu/Nutsty/archive/refs/tags/{tag}.zip"


def baseline_url(url, current_ver=None):
    """The same release asset for the version that is installed now, or "" when it cannot be derived."""
    ver = (current_ver or getattr(pc, "APP_VERSION", "")).strip().lstrip("vV")
    m = re.search(r"/releases/download/([^/]+)/", str(url))
    if not ver or not m:
        return ""
    tag = "v" + ver
    if m.group(1) == tag:
        return ""
    return url[:m.start(1)] + tag + url[m.end(1):]


def source_app_dir():
    return os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))


def is_git_checkout(path):
    return os.path.exists(os.path.join(path, ".git")) and shutil.which("git") is not None


# Files the running app rewrites inside its own folder; a source update must not replace them
LOCAL_STATE_FILES = ("library.json", os.path.join("assets", "nutsty_palette.json"))


def find_app_root_in_staged(stage_path):
    """Ensure we find the folder containing Nutsty.exe, shell.qml, or start.bat, never a subfolder like _internal."""
    if not stage_path or not os.path.exists(stage_path):
        return stage_path
    if os.path.exists(os.path.join(stage_path, "Nutsty.exe")) or os.path.exists(os.path.join(stage_path, "start.bat")) or os.path.exists(os.path.join(stage_path, "shell.qml")):
        return stage_path
    for root, dirs, files in os.walk(stage_path):
        if "Nutsty.exe" in files or "start.bat" in files or "shell.qml" in files:
            if os.path.basename(root) != "_internal":
                return root
    return stage_path

def _install_dir():
    if getattr(sys, "frozen", False):
        return os.path.dirname(os.path.abspath(sys.executable))
    return source_app_dir()


class _Cancelled(Exception):
    pass


class DirectUpdateManager:
    def __init__(self):
        self._lock = threading.Lock()
        self.active = False
        self.status = "idle"  # idle, planning, planned, downloading, extracting, ready, error
        self.progress = 0.0
        self.percent = 0
        self.message = ""
        self.error = None
        self.target_version = ""
        self.staged_dir = None
        self.mode = ""  # "delta" (only changed files) or "full" (whole zip)
        self.plan_info = None  # {"download_bytes","full_bytes","changed","total"}
        self.bytes_done = 0
        self.bytes_total = 0
        self.speed = 0.0
        self._meter = None
        self._cancel = False
        self._plan = None  # (url, entries, todo, stage_dir) kept between plan and download

    def get_status(self):
        with self._lock:
            speed = self._meter.rate() if self._meter else 0.0
            left = max(0, self.bytes_total - self.bytes_done)
            return {
                "active": self.active,
                "status": self.status,
                "progress": self.progress,
                "percent": self.percent,
                "message": self.message,
                "error": self.error,
                "target_version": self.target_version,
                "mode": self.mode,
                "plan": self.plan_info,
                "bytes_done": self.bytes_done,
                "bytes_total": self.bytes_total,
                "speed": speed,
                "eta": int(left / speed) if speed > 1 else -1,
            }

    def cancel(self):
        with self._lock:
            if not self.active:
                return {"success": False, "error": "Không có tiến trình nào để hủy."}
            self._cancel = True
        return {"success": True}

    def _is_cancelled(self):
        return self._cancel

    def _reset(self, status, message):
        self.active = True
        self.status = status
        self.progress = 0.0
        self.percent = 0
        self.message = message
        self.error = None
        self.bytes_done = 0
        self.bytes_total = 0
        self._meter = None
        self._cancel = False

    def _stage_dir(self):
        return os.path.join(CONFIG_DIR, "updates", "staged")

    def _delta_possible(self, url):
        return bool(pc.IS_WINDOWS and str(url).lower().endswith(".zip"))

    def start_plan(self, download_url=None, target_version=None):
        """Work out how much would be downloaded (changed files only) without downloading yet."""
        with self._lock:
            if self.active:
                return {"success": False, "error": "Đang có tiến trình cập nhật đang chạy."}
            self._reset("planning", "Đang so sánh với bản đang cài...")
            self.plan_info = None
            self.target_version = target_version or ""
        threading.Thread(target=self._worker_plan, args=(download_url, target_version), daemon=True).start()
        return {"success": True}

    def _resolve_url(self, download_url, target_version):
        if not download_url:
            info = check_for_updates(force=True)
            download_url = info.get("download_url")
            target_version = info.get("latest_version")
        if not download_url or not str(download_url).startswith("http"):
            raise ValueError("Không tìm thấy tệp cập nhật hợp lệ.")
        return download_url, target_version

    def _worker_plan(self, download_url, target_version):
        try:
            download_url, target_version = self._resolve_url(download_url, target_version)
            self._compute_plan(download_url)
            with self._lock:
                self.active = False
                self.status = "planned"
                self.target_version = target_version or "latest"
                self.message = ""
        except _Cancelled:
            with self._lock:
                self.active = False
                self.status = "idle"
                self.message = ""
        except Exception as e:
            with self._lock:
                self.active = False
                self.status = "error"
                self.error = str(e)
                self.message = f"Lỗi so sánh bản cập nhật: {str(e)}"

    def _compute_plan(self, url):
        """Fill plan_info. Leaves mode 'delta' when only part of the zip is needed, else 'full'."""
        if not self._delta_possible(url):
            with self._lock:
                self.mode = "full"
                self.plan_info = None
            return
        try:
            base_url = baseline_url(url)
            with ThreadPoolExecutor(max_workers=2) as pool:
                new_job = pool.submit(ud.read_directory, url)
                base_job = pool.submit(ud.read_directory, base_url) if base_url else None
                entries, full_size = new_job.result()
                try:
                    base_entries = base_job.result()[0] if base_job else None
                except Exception:
                    base_entries = None  # this version has no release zip (dev build): hash the folder instead
            app_dir = _install_dir()
            stage = self._stage_dir()
            marker = os.path.join(stage, ".source")
            if os.path.exists(stage) and (not os.path.exists(marker) or open(marker, encoding="utf-8").read() != url):
                shutil.rmtree(stage, ignore_errors=True)
            if base_entries:
                todo = ud.plan_from_baseline(entries, base_entries, app_dir, stage,
                                             skip=LOCAL_STATE_FILES, cancelled=self._is_cancelled)
            else:
                todo, _same = ud.plan(entries, app_dir, stage, skip=LOCAL_STATE_FILES, cancelled=self._is_cancelled)
        except Exception:
            if self._cancel:
                raise _Cancelled()
            # Range or zip layout unsupported: whole-zip download still works
            with self._lock:
                self.mode = "full"
                self.plan_info = None
            return
        files = [e for e in entries if not e.name.endswith("/")]
        info = {
            "download_bytes": sum(e.csize for e in todo),
            "full_bytes": full_size,
            "changed": len(todo),
            "total": len(files),
        }
        with self._lock:
            self.mode = "delta"
            self.plan_info = info
            self._plan = (url, entries, todo, stage)

    def start_download_update(self, download_url=None, target_version=None):
        with self._lock:
            if self.active:
                return {"success": False, "error": "Đang có tiến trình cập nhật đang chạy."}
            self._reset("downloading", "Đang kết nối tới máy chủ cập nhật...")
        threading.Thread(target=self._worker_download, args=(download_url, target_version), daemon=True).start()
        return {"success": True, "message": "Bắt đầu tải bản cập nhật."}

    def _worker_download(self, download_url, target_version):
        try:
            download_url, target_version = self._resolve_url(download_url, target_version)
            with self._lock:
                self.target_version = target_version or "latest"

            if not pc.IS_WINDOWS:
                app_dir = source_app_dir()
                if is_git_checkout(app_dir):
                    self._git_pull(app_dir)
                    return
                if not str(download_url).lower().endswith(".zip") and target_version:
                    download_url = source_archive_url(target_version)

            with self._lock:
                plan = self._plan if (self._plan and self._plan[0] == download_url) else None
            if plan is None and self._delta_possible(download_url):
                self._compute_plan(download_url)
                with self._lock:
                    plan = self._plan if (self._plan and self._plan[0] == download_url) else None
            if plan is not None and self.mode == "delta":
                self._download_delta(plan)
            else:
                self._download_full(download_url)
        except _Cancelled:
            self._finish_cancel()
        except Exception as e:
            if self._cancel:
                self._finish_cancel()
                return
            with self._lock:
                self.active = False
                self.status = "error"
                self.error = str(e)
                self.message = f"Lỗi tải cập nhật: {str(e)}"

    def _finish_cancel(self):
        with self._lock:
            self.active = False
            self.status = "idle"
            self.message = ""
            self.progress = 0.0
            self.percent = 0
            self.bytes_done = 0

    def _on_bytes(self, n):
        if self._cancel:
            raise _Cancelled()
        self._meter.add(n)
        with self._lock:
            self.bytes_done = self._meter.done
            if self.bytes_total > 0:
                self.progress = min(1.0, self.bytes_done / float(self.bytes_total))
                self.percent = int(self.progress * 100)
                self.message = f"Đang tải bản cập nhật ({self.percent}%)..."

    def _download_delta(self, plan):
        url, _entries, todo, stage = plan
        os.makedirs(stage, exist_ok=True)
        with open(os.path.join(stage, ".source"), "w", encoding="utf-8") as f:
            f.write(url)
        total = sum(e.csize for e in todo)
        with self._lock:
            self.bytes_total = total
            self.bytes_done = 0
            self._meter = ud.SpeedMeter()
            self.status = "downloading"
        if todo:
            ud.download(url, todo, stage, self._on_bytes, cancelled=self._is_cancelled)
        with self._lock:
            self.active = False
            self.status = "ready"
            self.staged_dir = stage
            self.progress = 1.0
            self.percent = 100
            self.bytes_done = total
            self.message = "Bản cập nhật đã tải xong! Bấm để áp dụng và khởi động lại."

    def _download_full(self, download_url):
        with self._lock:
            self.mode = "full"
        update_root = os.path.join(CONFIG_DIR, "updates")
        os.makedirs(update_root, exist_ok=True)
        zip_dest = os.path.join(update_root, "update.zip")
        staged_dest = self._stage_dir()

        if os.path.exists(zip_dest):
            try:
                os.remove(zip_dest)
            except Exception:
                pass
        if os.path.exists(staged_dest):
            shutil.rmtree(staged_dest, ignore_errors=True)

        req = urllib.request.Request(download_url, headers={"User-Agent": "Nutsty-Desktop-App/1.0"})
        with urllib.request.urlopen(req, timeout=60.0) as resp:
            total_size = int(resp.headers.get("Content-Length", 0))
            with self._lock:
                self.bytes_total = total_size
                self._meter = ud.SpeedMeter()
            with open(zip_dest, "wb") as f_out:
                while True:
                    chunk = resp.read(65536)
                    if not chunk:
                        break
                    f_out.write(chunk)
                    self._on_bytes(len(chunk))

        with self._lock:
            self.status = "extracting"
            self.message = "Đang giải nén bản cập nhật..."

        os.makedirs(staged_dest, exist_ok=True)
        with zipfile.ZipFile(zip_dest, "r") as zf:
            zf.extractall(staged_dest)
        try:
            os.remove(zip_dest)
        except OSError:
            pass

        final_stage = find_app_root_in_staged(staged_dest)
        if not pc.IS_WINDOWS:
            for rel in LOCAL_STATE_FILES:
                try:
                    os.remove(os.path.join(final_stage, rel))
                except OSError:
                    pass

        with self._lock:
            self.active = False
            self.status = "ready"
            self.staged_dir = final_stage
            self.progress = 1.0
            self.percent = 100
            self.message = "Bản cập nhật đã tải xong! Bấm để áp dụng và khởi động lại."

    def _git_pull(self, app_dir):
        """Linux git checkout: fast-forward to the latest commit instead of copying an archive over it."""
        env = dict(os.environ, GIT_TERMINAL_PROMPT="0")
        res = subprocess.run(
            ["git", "-C", app_dir, "pull", "--ff-only", "--autostash"],
            capture_output=True, text=True, timeout=300, env=env
        )
        if res.returncode != 0:
            detail = (res.stderr or res.stdout or "").strip().splitlines()
            raise RuntimeError("git pull: " + (detail[-1] if detail else f"exit {res.returncode}"))
        with self._lock:
            self.active = False
            self.status = "ready"
            self.staged_dir = None
            self.progress = 1.0
            self.percent = 100
            self.message = "Bản cập nhật đã tải xong! Bấm để áp dụng và khởi động lại."

    def _restart_linux(self, app_dir, copy_from=None):
        sh_path = os.path.join(CONFIG_DIR, "updates", "apply_update.sh")
        os.makedirs(os.path.dirname(sh_path), exist_ok=True)
        copy_line = f'cp -rf "{copy_from}"/. "{app_dir}"/\n' if copy_from else ""
        sh_content = f"""#!/bin/sh
sleep 1
{copy_line}if [ -f "{app_dir}/run.sh" ]; then
    bash "{app_dir}/run.sh" --restart &
fi
"""
        with open(sh_path, "w", encoding="utf-8") as f:
            f.write(sh_content)
        os.chmod(sh_path, 0o755)
        subprocess.Popen(["/bin/sh", sh_path], start_new_session=True)
        return {"success": True, "message": "Đang khởi động lại ứng dụng..."}

    def apply_update_and_restart(self, target_dir=None):
        with self._lock:
            staged = self.staged_dir
        if not pc.IS_WINDOWS and not staged and is_git_checkout(source_app_dir()):
            # Already pulled by _git_pull; only the restart is left
            return self._restart_linux(source_app_dir())
        if not staged or not os.path.exists(staged):
            default_staged = os.path.join(CONFIG_DIR, "updates", "staged")
            if os.path.exists(default_staged):
                staged = find_app_root_in_staged(default_staged)
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
for %%P in (nutsty-daemon nutsty-bridge nutsty-library nutsty-tray) do taskkill /f /im %%P.exe >nul 2>&1
ping 127.0.0.1 -n 2 >nul

echo [*] Dang ghi de tep cap nhat / Applying update files...
robocopy "{staged}" "{app_dir}" /E /IS /IT /NP /R:2 /W:1 /XF .source *.part >nul
rd /s /q "{staged}" >nul 2>&1

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
            return self._restart_linux(app_dir, copy_from=staged)

direct_updater = DirectUpdateManager()

if __name__ == "__main__":
    force_check = "--force" in sys.argv
    info = check_for_updates(force=force_check)
    print(json.dumps(info, ensure_ascii=False, indent=2))
