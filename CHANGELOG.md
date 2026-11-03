# Changelog

Định dạng theo [Keep a Changelog](https://keepachangelog.com/). Phiên bản theo `APP_VERSION` trong `backend/platform_compat.py`.

## [1.0.6] - 2026-11-03

### Thêm mới / Added
- **Lời bài hát trên Desktop (Windows)**: Bật lại lyric nổi trên màn hình desktop cho Windows, có công tắc riêng trong Cài đặt. Trước đây bị ép tắt trên Windows.
  *Desktop lyrics are available again on Windows with their own toggle in Settings.*
- **Lời bài hát trên và trong Taskbar (Windows)**: Dải lyric karaoke theo âm tiết trên thanh tác vụ (vị trí "above" / "taskbar"), công tắc riêng tách khỏi Desktop lyrics.
  *Syllable-level karaoke lyrics above and inside the Windows taskbar, with a separate toggle.*
- `CHANGELOG.md` và bài học build Windows `.agents/rules/05-windows-build-and-runtime-lessons.md`.

### Sửa lỗi / Fixed
- Thu Nutsty về widget không còn chặn chuột trên desktop: widget Windows là cửa sổ 216x216, kéo thả và bấm đúp hoạt động; cửa sổ lyrics toàn màn hình chỉ nhận chuột trong khung chữ (`SetWindowRgn`).
  *Minimising to the widget no longer blocks the desktop mouse; the widget is draggable and double-click opens the app.*
- Taskbar lyrics không hiện vì `TaskbarLyrics.exe` mồ côi/treo: app kiểm tra cổng `9012`, dọn tiến trình treo một lần khi khởi động và không còn giết-bật lại tiến trình của chính nó.
  *Fixed stale/hung companion process handling for taskbar lyrics.*
- Exe build trong `dist\` chạy ở quyền Low Integrity (do nhãn thừa kế từ workspace sandbox) nên không ghi được `%LOCALAPPDATA%` và không mở được cổng `9012`. `build_exe.bat` nay tự đặt lại nhãn Medium sau khi đóng gói.
  *`build_exe.bat` now resets the integrity label to Medium so the packaged app can write AppData and bind localhost:9012.*
- Kẹt tiến trình chuyển bài (Next / Prev / Dislike) khi bài đang phát lệch khỏi hàng đợi: trong `components/playback_engine.js`, `playNext()` và `playPrev()` nay tự động chuyển sang bài đầu tiên của hàng đợi thay vì hủy lệnh khi `curIdx === -1`; nút Dislike lập tức dừng bài bị ghét và chuyển bài kế tiếp.
  *Fixed playback freeze on Next, Prev, and Dislike when the playing track is not found in the active queue: `playNext` and `playPrev` now fallback to the queue's first track instead of silently aborting, and Dislike immediately advances playback.*

### Ghi chú / Notes
- Linux (Niri / CachyOS): hành vi Desktop lyrics (layer-shell) giữ nguyên, các thay đổi Windows nằm sau nhánh `Qt.platform.os === "windows"` hoặc trong `launcher_win.py`.
- Chưa tăng số phiên bản trong mã (`APP_VERSION`, README, updater); sẽ tăng khi phát hành bản 1.0.6.

## [1.0.5]
- Lyrics Romanization, Obsidian LiquidGlass & MediaCoverSurface.
