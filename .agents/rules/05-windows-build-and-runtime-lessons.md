# 05 - Bài Học Build & Runtime Trên Windows (Đã Kiểm Chứng)

> Chỉ ghi những gì đã chạy thật và xác nhận. Mỗi mục: Triệu chứng, Nguyên nhân gốc, Cách sửa, Bẫy lỗi (Footgun).

---

## 1. Exe trong `dist\` chạy lỗi âm thầm do nhãn Low Integrity (Mandatory Label)
- **Triệu chứng**: `Nutsty.exe` / `TaskbarLyrics.exe` build xong chạy "như bình thường" nhưng taskbar lyrics không hiện, `%LOCALAPPDATA%\TaskbarLyrics\log.txt` không có dòng mới, cổng `9012` đóng, `Nutsty.exe` báo `Permission denied` khi ghi cache `%LOCALAPPDATA%\Nutsty`. Chép đúng file exe đó sang `%TEMP%` thì chạy bình thường (cùng hash).
- **Nguyên nhân gốc**: Thư mục dự án có nhãn `Mandatory Label\Low` (do sandbox của AI-agent đặt lên workspace) và file tạo sau đó thừa kế. Windows chạy một exe mang nhãn Low ở quyền Low: không ghi được vùng Medium (AppData) và không đăng ký được `HttpListener` trên `localhost:9012`. Lỗi bị nuốt vì `Log.Write` bắt mọi exception.
- **Cách chẩn đoán**: `icacls <exe>` có dòng `Mandatory Label\Low Mandatory Level`. So sánh cùng exe chạy từ `%TEMP%`.
- **Cách sửa**: `icacls dist\Nutsty /setintegritylevel "(OI)(CI)M" /T /C`. Lệnh này đã được gắn vào cuối `build_exe.bat` (sau PyInstaller).
- **Footgun**: Mỗi lần build lại trong workspace, file mới lại bị gắn Low. Luôn build qua `build_exe.bat`, không gọi `pyinstaller` trần. Thư mục `bin\` của repo cũng cần nhãn Medium nếu chạy từ source.

## 2. `Nutsty.exe` ngoài Desktop là bản build cũ
- Shortcut `Nutsty Player.lnk` trỏ tới `Desktop\Nutsty\dist\Nutsty\Nutsty.exe`; `Desktop\Nutsty` là junction vào thư mục repo. Sửa code Python/QML KHÔNG có tác dụng với exe cho tới khi chạy `build_exe.bat`.
- Trước khi build phải tắt `Nutsty.exe`, `mpv.exe`, `TaskbarLyrics.exe` (khoá file trong `dist`). PyInstaller `--clean` xoá cả `dist\Nutsty`.

## 3. Chuột xuyên cửa sổ toàn màn hình trên Windows
- **Nguyên nhân**: `HTTRANSPARENT` trong `WM_NCHITTEST` chỉ chuyển chuột cho cửa sổ cùng thread. Cửa sổ trong suốt toàn màn hình sẽ chặn thao tác kéo icon Explorer.
- **Cách sửa**: `DesktopMusicWidget` trên Windows là cửa sổ đúng 216x216 (không neo 4 cạnh), `NativeHitTestFilter` bỏ qua cửa sổ nhỏ (<= 300 px). Cửa sổ lyrics toàn màn hình dùng `SetWindowRgn` bó vào hộp chữ (toạ độ DIP nhân DPI), vùng rỗng khi ẩn.
- **Footgun**: `mask: null` trên widget nhỏ + đăng ký vào `_panel_hwnds` làm cả widget click-through, không bấm/kéo được.

## 4. Taskbar Lyrics: vòng đời tiến trình companion
- `TaskbarLyricsService.ensure_process()`: nếu cổng 9012 mở thì thôi; nếu tiến trình do chính app bật còn sống thì KHÔNG giết (tránh vòng lặp giết-bật lại mỗi 2 giây); chỉ dọn `TaskbarLyrics.exe` mồ côi (cổng không phản hồi) một lần khi khởi động, có khoảng chờ 30 giây.
- Kiểm tra cổng bằng `localhost` (IPv4 và IPv6), URI WebSocket giữ `ws://localhost:9012/`.
- Desktop lyrics (`DesktopLyricsWidget`) và Taskbar lyrics là hai công tắc riêng trong `SettingsModal.qml`; trên Windows cả hai đều hoạt động (không còn bị ép tắt).

## 5. Quy trình kiểm tra exe sau build
1. `python scripts/verify_codebase.py`.
2. `build_exe.bat` (đã tự reset nhãn Medium).
3. Mở shortcut, kiểm tra `log.txt` có `bridge: listening on localhost:9012`, lyrics hiện trên desktop và taskbar, thu về widget rồi kéo icon desktop.
