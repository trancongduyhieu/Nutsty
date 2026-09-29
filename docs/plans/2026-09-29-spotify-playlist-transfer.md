# Spotify Playlist Transfer Implementation Plan

> **For Antigravity:** REQUIRED WORKFLOW: Use `.agent/workflows/execute-plan.md` to execute this plan in single-flow mode.

**Goal:** Kích hoạt tính năng chuyển giao Playlist từ tài khoản Spotify (hoặc đường link công khai) sang Danh sách phát cá nhân của Nutsty (`custom_playlists.json`) thông qua cơ chế tìm kiếm và ghép nối âm thanh YouTube Music tự động.

**Architecture:** Tái sử dụng tối đa Single Source of Truth (SSOT): Tận dụng `backend/lyrics_helper.py` để lấy Spotify Access Token qua TOTP exchange, `backend/ytmusic_helper.py` để tra cứu video ID tương ứng theo thuật toán đối chiếu thời lượng $\pm 5$s của SpotDL, và `backend/playlist_manager.py` để lưu trữ dữ liệu bền vững. Giao diện QML được đóng gói thành `components/SpotifyImportModal.qml` theo chuẩn Liquid Glass bo góc đồng tâm, song ngữ bimodal 100% `I18n.tr`, không emoji và hiển thị tiến trình thời gian thực.

**Tech Stack:** Python 3 (urllib, threading, json), PySide6 / Quickshell QML, Spotify Web API, YouTube Music Internal API, `verify_codebase.py`.

---

### Task 1: Module Chuyển Giao Spotify Backend (`backend/spotify_importer.py`)

**Files:**
- Create: `backend/spotify_importer.py`
- Test: `tests/test_spotify_importer.py`

**Step 1: Write test case for Spotify Importer**

Tạo file `tests/test_spotify_importer.py`:
- Kiểm tra hàm trích xuất playlist ID từ Spotify URL (`extract_playlist_id`).
- Kiểm tra tính toán độ lệch thời lượng giữa bài hát Spotify và kết quả YouTube Music.
- Kiểm tra cấu trúc dữ liệu trả về của bài hát sau khi map.

**Step 2: Run test to verify it fails**

Run: `python -m unittest tests/test_spotify_importer.py`
Expected: FAIL with `ModuleNotFoundError: No module named 'backend.spotify_importer'`

**Step 3: Write minimal implementation in `backend/spotify_importer.py`**

Tận dụng `lyrics_helper.get_spotify_access_token`, `playlist_manager.save_playlists`, `ytmusic_helper.filter_search`:
- `extract_playlist_id(url_or_id)`: Trích xuất 22 ký tự Spotify Playlist ID từ link hoặc chuỗi.
- `fetch_user_spotify_playlists(spdc)`: Gọi `GET https://api.spotify.com/v1/me/playlists?limit=50`.
- `fetch_playlist_tracks(playlist_id, access_token)`: Gọi `GET https://api.spotify.com/v1/playlists/{playlist_id}/tracks` có phân trang (`offset`, `limit=100`).
- `match_track_to_ytmusic(title, artist, duration_ms)`: Tìm kiếm `f"{title} {artist}"` và chọn kết quả có $|\text{yt\_duration} - \text{sp\_duration}| \le 5\text{s}$.
- `class SpotifyImportManager`: Quản lý background thread, trạng thái tiến độ (`active`, `current`, `total`, `percent`, `current_track`, `completed`, `error`) và hủy luồng an toàn.

**Step 4: Run test to verify it passes**

Run: `python -m unittest tests/test_spotify_importer.py`
Expected: PASS

**Step 5: Commit**

```bash
git add -f backend/spotify_importer.py tests/test_spotify_importer.py
git commit -m "feat(backend): add spotify playlist importer and track matching engine"
```

---

### Task 2: Đăng Ký Route API Vào Backend Server (`backend/music_routes.py` & `backend/auth_server.py`)

**Files:**
- Modify: `backend/music_routes.py`
- Modify: `backend/auth_server.py`
- Test: `scripts/verify_codebase.py`

**Step 1: Write handler functions in `backend/music_routes.py`**
- `handle_get_spotify_playlists(handler, query)`: Trả về danh sách playlist của người dùng từ Spotify.
- `handle_post_spotify_import(handler)`: Nhận `playlist_id`, `playlist_title` và bắt đầu tiến trình import ngầm.
- `handle_get_spotify_import_status(handler)`: Trả về tiến độ import hiện tại (`%`, số bài, tên bài đang tìm).
- `handle_post_spotify_cancel_import(handler)`: Cho phép hủy import.

**Step 2: Map routes in `backend/auth_server.py`**
- Route GET `/api/spotify/playlists` -> `music_routes.handle_get_spotify_playlists`
- Route POST `/api/spotify/import_playlist` -> `music_routes.handle_post_spotify_import`
- Route GET `/api/spotify/import_status` -> `music_routes.handle_get_spotify_import_status`
- Route POST `/api/spotify/cancel_import` -> `music_routes.handle_post_spotify_cancel_import`

**Step 3: Run static verification**

Run: `python scripts/verify_codebase.py`
Expected: PASS (không có lỗi cú pháp hoặc scope biến)

**Step 4: Commit**

```bash
git add backend/music_routes.py backend/auth_server.py
git commit -m "feat(api): expose spotify playlist fetch and background import routes"
```

---

### Task 3: Xây Dựng Component Modal Nhập Playlist (`components/SpotifyImportModal.qml`)

**Files:**
- Create: `components/SpotifyImportModal.qml`
- Modify: `components/qmldir`
- Test: `python scripts/verify_codebase.py`

**Step 1: Implement `components/SpotifyImportModal.qml`**
- Tái sử dụng `components/Theme.qml`, `components/I18n.qml`, `components/AppIcon.qml`, `components/CircularSpinner.qml`, `components/RoundedImage.qml`.
- Bo góc đồng tâm $R_{\text{ngoài}} = 20\text{px}$, viền 1px `Theme.border`, nền Liquid Glass.
- Không sử dụng ký tự Emoji (sử dụng SVG icons).
- Song ngữ bimodal 100%: `I18n.tr(...)`.
- Các chế độ hiển thị:
  1. **Tab chọn playlist cá nhân**: Hiển thị danh sách playlist Spotify lấy từ API (ảnh bìa, tên, số bài, nút chọn).
  2. **Tab dán link trực tiếp**: Ô nhập `TextField` để dán link `https://open.spotify.com/playlist/...`.
  3. **Màn hình tiến độ (Progress View)**:
     - Hiển thị thanh tiến trình bo tròn mượt mà kèm con số `%` và số bài `(x/y)`.
     - Tên bài hát đang được xử lý `current_track`.
     - Nút "Hủy bỏ" (`Muted Rose`).
     - Tự động phát tín hiệu `playlistImported()` khi xong để reload danh sách phát trong Nutsty.

**Step 2: Register into `components/qmldir`**
- Thêm dòng: `SpotifyImportModal 1.0 SpotifyImportModal.qml`

**Step 3: Run verification**

Run: `python scripts/verify_codebase.py`
Expected: PASS

**Step 4: Commit**

```bash
git add components/SpotifyImportModal.qml components/qmldir
git commit -m "feat(ui): add liquid glass SpotifyImportModal with real-time progress"
```

---

### Task 4: Tích Hợp UI Triggers Vào `SettingsModal.qml` & `NavSidebar.qml`

**Files:**
- Modify: `components/SettingsModal.qml`
- Modify: `components/NavSidebar.qml`
- Modify: `shell.qml`
- Test: `python scripts/verify_codebase.py`

**Step 1: Add Spotify import trigger button in `components/SettingsModal.qml`**
- Trong khu vực liên kết Spotify (khi `spotifyConnected` là true), thêm nút:
  - Text: `I18n.tr("Nhập Playlist từ Spotify", "Import Playlists from Spotify")`
  - Style: Nền `Theme.accent` với độ trong suốt tinh tế, hover scale 1.02x, icon `assets/icons/share.svg`.
  - OnClicked: Mở `spotifyImportModal`.

**Step 2: Add quick import icon in `components/NavSidebar.qml`**
- Cạnh tiêu đề "Danh sách phát", thêm nút icon nhỏ mở nhanh modal chuyển giao Spotify.

**Step 3: Mount `SpotifyImportModal` in `shell.qml`**
- Khai báo instance `SpotifyImportModal` trong `shell.qml`.
- Khi import hoàn tất: gọi `loadCustomPlaylists()` để danh sách phát bên cột trái hiển thị ngay playlist vừa nhập.

**Step 4: Run verification**

Run: `python scripts/verify_codebase.py`
Expected: PASS

**Step 5: Commit**

```bash
git add components/SettingsModal.qml components/NavSidebar.qml shell.qml
git commit -m "feat(ui): integrate spotify import triggers into settings and sidebar"
```

---

### Task 5: Kiểm Thử Toàn Diện & Đánh Giá Trực Quan

**Files:**
- Verification only

**Step 1: Run comprehensive codebase check**
- Run: `python scripts/verify_codebase.py`
- Ensure all AST scopes, QML syntax, and imports pass cleanly.

**Step 2: Test Spotify API communication & track resolution**
- Kiểm tra gọi endpoint `/api/spotify/playlists` khi có `sp_dc`.
- Kiểm tra resolution đối chiếu bài hát.

**Step 3: Launch Nutsty on Windows desktop & Capture visual screenshot**
- Khởi động app: `powershell -ExecutionPolicy Bypass -File scripts/run_on_default_desktop.ps1`
- Mở modal nhập Spotify và chụp ảnh màn hình bằng `capture_screen.ps1`.
- Kiểm tra bằng `view_file` để thẩm định layout, bo góc đồng tâm và Liquid Glass.

**Step 4: Push to remote main**
- Run: `git push origin main`
