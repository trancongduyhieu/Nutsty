# GLOSSARY.md - Ngôn ngữ miền của Nutsty

Tên gọi chuẩn cho các khái niệm trong code, tài liệu và đánh giá kiến trúc. Khi đặt tên module, hàm hay
thẻ đề xuất, dùng đúng các từ dưới đây. Mục "Tránh" là các tên hay bị dùng lẫn nhưng không chính xác.
Từ vựng kiến trúc (module, interface, seam, adapter, depth...) theo skill `codebase-design`, không ghi lại ở đây.

## Nền tảng và chạy ứng dụng

- **Quickshell seam**: Interface QML mà `shell.qml` và `components/` dùng từ `import Quickshell`,
  `Quickshell.Io`, `Quickshell.Wayland`. Có hai adapter: Quickshell thật (Linux) và compat layer (Windows).
- **compat layer**: `compat/Quickshell/*` cùng NutstyBridge, đóng vai Quickshell trên Windows (PySide6).
  Mọi API Quickshell mà component dùng phải có ở đây, nếu không Windows crash lúc nạp `shell.qml`.
  _Tránh_: "shim Windows", "lớp giả lập".
- **seam contract test**: `scripts/verify_qml_compat.py`, nạp mọi file QML qua compat layer; là test surface
  của Quickshell seam. Thêm API Quickshell mới vào QML thì phải thêm vào compat cho tới khi test qua.
- **NutstyBridge** (`__NutstyBridge`): QObject Python mà `launcher_win.py` đưa vào QML trên Windows
  (env, readFile, runProcess, execDetached, mask cửa sổ). Chỉ tồn tại trên Windows.
- **BACKEND_MAP**: Bảng trong `launcher_win.py` ánh xạ tên script backend sang module Python chạy
  ngay trong tiến trình trên Windows, thay vì mở tiến trình con như Linux.
- **appDir**: `win.appDir`, thư mục cài Nutsty, dùng để ghép đường dẫn tới `backend/` và `bin/`.
- **config dir**: `~/.config/noctalia` (`platform_compat.get_config_dir`), nơi lưu cài đặt và dữ liệu người dùng
  trên cả hai nền tảng. Không nằm trong appDir nên còn nguyên khi cài lại ứng dụng.
- **profile suffix**: Hậu tố `_<NUTSTY_PROFILE>` gắn vào tên file cấu hình để nhiều hồ sơ chạy song song
  (ví dụ `custom_playlists_user1.json`). Rỗng với hồ sơ mặc định.
- **Lite mode** (Chế độ nhẹ): Công tắc tắt các hiệu ứng vẽ lại toàn cửa sổ khi máy không có GPU.

## Gọi backend

- **backend command**: Một lần QML gọi một script hoặc binary backend và nhận kết quả. Hiện có bốn đường:
  `Process`, `Quickshell.execDetached`, HTTP tới cổng 17890, và `bin/nutsty-bridge`.
  _Tránh_: "API call", "service call".
- **nutsty-bridge**: CLI Rust nói chuyện trực tiếp với mpv qua IPC (status, pause, seek, volume).
- **nutsty-daemon**: Router HTTP Rust ở `127.0.0.1:17890` trên Linux, chuyển yêu cầu cho các worker
  `route_dispatcher.py --serve`.
- **auth_server**: Server Python cùng cổng 17890, dùng trên Windows thay cho nutsty-daemon.
- **fire-and-forget write**: Lệnh ghi chạy bằng `execDetached`, không chờ kết quả, rồi đoán lúc xong bằng
  timer làm mới (xem refreshPlaylistsTimer).

## Danh sách phát

- **custom playlist**: Danh sách phát người dùng tự tạo hoặc nhập từ Spotify, lưu trong
  `custom_playlists{suffix}.json`, id dạng `custom_pl_<ms>`, có `isCustom`, `isLocal`, `type: "custom"`.
  _Tránh_: "local playlist" (dễ nhầm với thư mục nhạc local).
- **favorite playlist**: Danh sách phát (trực tuyến hoặc custom) được đánh dấu yêu thích, lưu trong
  `favorite_playlists{suffix}.json`, so khớp theo `id`, `playlistId` hoặc `browseId`.
- **Spotify import**: Custom playlist chuyển từ Spotify, có `source: "spotify_import"` và `spotifyId`.
- **playlist backup**: File JSON (`format: "nutsty-playlists"`) chứa custom playlist và favorite playlist,
  tạo bằng nút Xuất file / Nhập file trong Cài đặt. Nhập chỉ thêm, không xóa.
- **track key**: Khóa duy nhất của một bài trong danh sách phát (`get_track_unique_key`): `yt_<videoId>`
  cho bài trực tuyến, `local_<path>` cho file trên máy. Dùng để chống trùng.
- **optimistic patch**: Việc QML tự sửa bản sao danh sách phát trong bộ nhớ ngay khi người dùng thao tác,
  trước khi backend ghi xong.
- **refreshPlaylistsTimer**: Timer 300 ms trong `shell.qml` nạp lại danh sách phát sau mỗi lệnh ghi.

## Mạng xã hội và giao diện

- **Listen Along** (Nghe Cùng): Phiên nghe chung với bạn bè, đồng bộ qua Cloudflare Worker và D1.
- **note** (ghi chú 24h): Trạng thái ngắn kèm bài hát, tự hết hạn sau 24 giờ.
- **Mochy side panel**: Bảng bên phải gồm Lời bài hát, Bình luận và Phát tiếp theo.
- **Mood Island**: Thanh chọn thể loại cảm xúc thu gọn ở giữa thanh điều hướng trên cùng.
