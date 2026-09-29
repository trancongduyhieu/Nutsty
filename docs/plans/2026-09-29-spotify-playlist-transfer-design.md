# Spotify Playlist Transfer to Nutsty Design Document

- **Date**: 2026-09-29
- **Author**: Antigravity & User Pair Programming
- **Topic**: Chuyển giao Playlist từ Spotify sang Nutsty (`custom_playlists.json`)

---

## 1. Mục Tiêu & Bối Cảnh (Context & Goals)
Người dùng muốn có tính năng khi đã có Cookie Spotify (`sp_dc`), trong Nutsty sẽ có nút kích hoạt chuyển giao Playlist cá nhân (hoặc link công khai) từ Spotify sang Nutsty để nghe trực tiếp, lưu trữ vĩnh viễn và không bị phụ thuộc vào DRM Spotify.

### Nguyên Tắc Tối Thượng (Core Principles)
- **Tái sử dụng tối đa thành phần sẵn có (SSOT & DRY)**:
  - Tận dụng `backend/lyrics_helper.py` để lấy Spotify Access Token qua TOTP exchange.
  - Tận dụng `backend/playlist_manager.py` để lưu và quản lý `custom_playlists.json`.
  - Tận dụng `backend/ytmusic_helper.py` để tìm kiếm và map bài hát YouTube Music.
  - Tái sử dụng Design System: `components/Theme.qml`, `components/I18n.qml`, `components/AppIcon.qml`, `components/CircularSpinner.qml`, `components/RoundedImage.qml`.
- **Tuyệt đối không dùng Emoji**: Dùng biểu tượng SVG vector chuẩn (`assets/icons/*.svg`).
- **Chuẩn hóa song ngữ nghiêm ngặt**: 100% sử dụng `I18n.tr("Tiếng Việt", "English")`.
- **Bo góc đồng tâm**: $R_{\text{trong}} = R_{\text{ngoài}} - \text{Khoảng cách}$, viền hairline 1px, liquid glass vibrancy.

---

## 2. Kiến Trúc Kỹ Thuật (Architecture & Data Flow)

### 2.1. Backend Endpoints (`backend/music_routes.py` / `backend/spotify_importer.py`)
1. **`GET /api/spotify/playlists`**:
   - Sử dụng `sp_dc` hiện có từ cấu hình Nutsty.
   - Gọi `get_spotify_access_token(spdc)` từ `backend/lyrics_helper.py`.
   - Gửi request đến `https://api.spotify.com/v1/me/playlists?limit=50`.
   - Trả về danh sách playlist: `id`, `name`, `description`, `images`, `trackCount`, `owner`.

2. **`POST /api/spotify/resolve_url`**:
   - Nhận `{ "url": "https://open.spotify.com/playlist/{id}..." }`.
   - Phân giải ID và lấy thông tin playlist công khai (kể cả khi không có cookie cá nhân).

3. **`POST /api/spotify/import_playlist`**:
   - Nhận payload `{ "playlist_id": "...", "title": "..." }`.
   - Kích hoạt tiến trình ngầm `SpotifyImportWorker` chạy trong background thread riêng biệt để không block HTTP server và QML UI.

4. **`GET /api/spotify/import_status`**:
   - Trả về tiến trình chuyển đổi theo thời gian thực:
     ```json
     {
       "active": true,
       "playlistId": "...",
       "playlistTitle": "V-Pop Hits",
       "current": 14,
       "total": 40,
       "currentTrack": "Lạ Lùng - Vũ",
       "percent": 35,
       "completed": false,
       "error": null
     }
     ```

### 2.2. Thuật Toán Khớp Bài Hát (SpotDL Matching Algorithm)
- Đối với từng bài hát trong Spotify Playlist:
  1. Trích xuất: Tên bài (`track.name`), Nghệ sĩ (`artists[0].name`), Thời lượng (`duration_ms`), Bìa album.
  2. Tìm kiếm trên YouTube Music qua `ytmusic_helper.filter_search(f"{title} {artist}", "songs", limit=5)`.
  3. Lọc bài hát phù hợp nhất:
     - So sánh độ lệch thời lượng: $|\text{yt\_duration} - \text{sp\_duration}| \le 5\text{s}$.
     - Nếu trùng khớp thời lượng, ưu tiên bài hát có tên khớp cao nhất.
  4. Nếu không tìm thấy trong danh mục "songs", fallback sang tìm kiếm tổng thể video.
  5. Đóng gói object track theo chuẩn Nutsty Custom Playlist:
     ```json
     {
       "title": "Lạ Lùng",
       "artist": "Vũ",
       "album": "Vũ",
       "duration": 262,
       "videoId": "abcxyz",
       "path": "ytdl://abcxyz",
       "image": "https://...",
       "source": "spotify_import"
     }
     ```
  6. Sau khi hoàn tất danh sách, gọi `playlist_manager.save_playlists(...)` để lưu vào `custom_playlists.json`.

---

## 3. Giao Diện Người Dùng (UI/UX Specification)

### 3.1. Các Điểm Kích Hoạt (Triggers)
- **Khu vực Cài đặt (`SettingsModal.qml`)**:
  - Dưới mục Spotify Cookie, khi tài khoản đã kết nối (`spotifyConnected === true`), hiển thị nút:
    - Text: `I18n.tr("Nhập Playlist từ Spotify", "Import Playlists from Spotify")`
    - Icon: `assets/icons/share.svg` hoặc playlist icon.
- **Thanh điều hướng Sidebar (`NavSidebar.qml`)**:
  - Bên cạnh tiêu đề "Danh sách phát", thêm nút icon nhỏ để mở nhanh modal.

### 3.2. Modal Nhập Playlist (`SpotifyImportModal.qml`)
- **Khung chứa Liquid Glass**:
  - $R_{\text{ngoài}} = 20\text{px}$, viền 1px `Theme.border`.
  - Tiêu đề song ngữ: `I18n.tr("Chuyển Giao Playlist Spotify", "Transfer Spotify Playlists")`.
- **Tab / Khu vực dán Link**:
  - TextField dán link playlist công khai kèm nút "Phân giải".
- **Khu vực danh sách Playlist tài khoản**:
  - Grid/List cuộn mượt các playlist của tài khoản Spotify.
  - Mỗi item gồm: Thumbnail bo góc $R=8\text{px}$, Tên playlist, Số bài, Nút "Chuyển sang Nutsty".
- **Giao diện tiến trình chuyển đổi**:
  - Khi bắt đầu chuyển: Hiển thị thanh tiến trình bo tròn mượt mà, tỷ lệ %, tên bài đang xử lý và nút "Hủy".
  - Hoàn tất: Tự động kích hoạt nạp lại danh sách playlist trong Nutsty và đóng modal kèm thông báo thành công.

---

## 4. Xử Lý Lỗi & Trường Hợp Biên (Edge Cases)
1. **Cookie hết hạn hoặc chưa đăng nhập**:
   - Hiển thị thông báo hướng dẫn người dùng dán link trực tiếp hoặc bấm "Đồng bộ cookie từ trình duyệt".
2. **Playlist quá dài (> 100 bài)**:
   - Sử dụng phân trang Spotify (`offset`, `limit`) để lấy trọn vẹn danh sách bài mà không bị cắt xén.
3. **Bài hát không tìm thấy trên YouTube Music**:
   - Ghi nhận vào log và bỏ qua hoặc tìm video thay thế gần nhất, không làm ngắt quãng toàn bộ quá trình import.
4. **Hủy tiến trình giữa chừng**:
   - Lưu lại những bài đã map thành công vào playlist để người dùng không bị mất dữ liệu.

---

## 5. Kế Hoạch Kiểm Thử (Verification Plan)
1. Kiểm tra AST & Syntax: `python scripts/verify_codebase.py`.
2. Kiểm tra tải danh sách playlist từ Spotify API với tài khoản mẫu.
3. Kiểm tra độ chính xác thuật toán matching bài hát (đối chiếu thời lượng $\pm 5$s).
4. Khởi chạy thực tế trên Windows Desktop và kiểm tra trực quan UI modal, thanh tiến trình và playlist sau khi nhập.
