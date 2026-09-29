<div align="center">

# Nutsty

**The Dual-Platform Desktop Music & Streaming Player for Linux Wayland & Windows**

[![Platform](https://img.shields.io/badge/Platform-Linux%20Wayland%20%7C%20Windows-blue?style=flat-square)](#)
[![UI](https://img.shields.io/badge/UI-Qt%206%20%2F%20Quickshell-41CD52?style=flat-square&logo=qt)](#)
[![Engine](https://img.shields.io/badge/Audio-mpv%20IPC%20Daemon-9b59b6?style=flat-square)](#)
[![Cloud](https://img.shields.io/badge/Cloud%20Relay-Cloudflare%20Workers%20%2B%20D1-F38020?style=flat-square&logo=cloudflare)](#)
[![License](https://img.shields.io/badge/License-MIT-green?style=flat-square)](#)
[![Version](https://img.shields.io/badge/Release-v1.0.0-gold?style=flat-square)](#)

*Nutsty là trình phát nhạc máy tính để bàn hiện đại, kết hợp hoàn hảo giữa thẩm mỹ kính lỏng Liquid Glass thích ứng màu sắc và bộ máy âm thanh bit-perfect độ trễ thấp.*

---

</div>

## Tính Năng Nổi Bật (Key Highlights)

### 1. Bộ Máy Lời Bài Hát Desktop Điện Ảnh (Desktop Lyrics Engine)
Tích hợp hiển thị lời bài hát trực tiếp lên màn hình desktop (Wayland Layer-Shell native trên Linux và Frameless Overlay trên Windows) với 4 phong cách nghệ thuật:
- **Mẫu 1: Điện ảnh Serif (`Cinematic Serif`)**: 1 dòng typography *Instrument Serif* nghiêng, chuyển nhịp so le mượt mà và đổ bóng điện ảnh sâu đa tầng (*Universal Cinematic Shadows*).
- **Mẫu 2: Apple Music (`Apple Music DoF`)**: Hiển thị 5 dòng kèm chiều sâu quang học (Optical Depth-of-Field), làm mờ mềm mại và đồng bộ karaoke từng âm tiết (*Syllable-level Karaoke Sync*).
- **Mẫu 3: Tối giản lướt (`Minimal Glide`)**: 2 dòng tối giản với hiệu ứng chuyển động trượt mượt mà kèm vệt mờ (*Motion Blur*).
- **Mẫu 4: Đồ họa Chuyển động (`Motion Typography`)**: Khung Bento với các chuyển động đồ họa động lực học hiện đại.

---

### 2. Bộ Máy Phát Nhạc Độ Trễ Thấp (Audiophile Audio Pipeline)
- Trình điều khiển nền resident daemon giao tiếp với **`mpv`** qua **Unix Domain Socket** (`/tmp/nutsty_mpv.sock` trên Linux) hoặc **Named Pipe** (`\\.\pipe\nutsty_mpv` trên Windows).
- Phát trực tuyến tức thì không trễ (gapless streaming, zero-rebuffer seek).
- Chống chặn luồng âm thanh YouTube Music với kiến trúc **Android Client Session Resolver** tự động.

---

### 3. Chuyển Giao Danh Sách Phát Spotify (Spotify Transfer Stage)
- Hỗ trợ dán link mọi playlist Spotify (công khai hoặc chia sẻ cá nhân) để nhập về Nutsty.
- **Sân khấu Chuyển giao Đĩa xoay (Arc Gunshot Stage)**: Đĩa than xoay chuyển vị trí mềm mại, các bài hát xếp theo đường cong hình cánh cung và bắn thẳng vào tâm đĩa khi nạp xong.
- Tự động đối soát và khớp luồng âm thanh chất lượng cao 256kbps hoàn toàn miễn phí.

---

### 4. Nghe Cùng và Mạng Xã Hội Cloudflare Edge (Global Social Sync)
- Kiến trúc Serverless Edge toàn cầu chạy trên **Cloudflare Workers** kết hợp cơ sở dữ liệu phân tán **Cloudflare D1**.
- **Nghe Cùng (Listen Along 1:1)**: Đồng bộ bài hát, trạng thái phát và tiến trình thời gian thực giữa hai máy tính dù ở Linux hay Windows.
- **Ghi chú 24h (Stories & Daily Notes)**: Chia sẻ bài hát yêu thích kèm suy nghĩ trong 24 giờ.
- **Bong bóng chat Danmaku**: Gửi tin nhắn tức thì bay qua màn hình khi đang nghe cùng bạn bè.

---

### 5. Kính Lỏng Liquid Glass và Phối Màu Thích Ứng (Chromatic Salience)
- **Thuật toán OKLAB / OKLCH**: Tự động trích xuất các mảng màu điểm nhấn từ hình nền máy tính và ảnh bìa album để biến đổi giao diện thích ứng hài hòa theo thời gian thực.
- **Nguyên lý Bo góc Đồng tâm**: $R_{\text{trong}} = R_{\text{ngoài}} - \text{Khoảng cách}$ kết hợp viền bán trong suốt hairline 1px sang trọng.
- **Thiết kế Thuần biểu tượng (100% SVG)**: Tuyệt đối không dùng ký tự emoji trên toàn bộ giao diện, tôn trọng ngôn ngữ đồ họa tối giản và chuyên nghiệp.
- **Đa ngôn ngữ Chuẩn mực (Strict Bimodal Localization)**: Hỗ trợ hoàn hảo 100% Tiếng Việt thuần túy và Tiếng Anh chuẩn mực.

---

## Cài Đặt và Khởi Chạy (Quick Start)

### Trên Linux (Wayland / Niri / Hyprland / KDE Wayland)
Yêu cầu hệ thống: `python3 (>= 3.10)`, `quickshell`, `mpv`, `ffmpeg`.

```bash
# Clone repository
git clone https://github.com/nutsty/nutsty.git
cd nutsty

# Cấp quyền thực thi và khởi chạy 1-chạm (tự động tạo venv và cài phụ thuộc)
chmod +x ./run.sh
./run.sh
```

---

### Trên Windows (Windows 10 / 11)
Yêu cầu hệ thống: `Python >= 3.10`, `mpv`.

```bat
:: Khởi chạy 1-chạm qua batch script
start.bat
```

Hoặc đóng gói thành file cài đặt độc lập `.exe`:
```bat
build_exe.bat
```

---

## Phím Tắt Tiện Dụng (Shortcuts)

| Phím tắt | Chức năng |
| :--- | :--- |
| <kbd>Space</kbd> | Phát / Tạm dừng bài hát |
| <kbd>Ctrl</kbd> + <kbd>→</kbd> | Chuyển sang bài tiếp theo |
| <kbd>Ctrl</kbd> + <kbd>←</kbd> | Quay lại bài trước |
| <kbd>M</kbd> | Bật / Tắt lời bài hát Desktop nổi |
| <kbd>Ctrl</kbd> + <kbd>Q</kbd> | Thoát ứng dụng hoàn toàn |

---

## Kiến Trúc Mã Nguồn (System Architecture)

```
Nutsty/
├── shell.qml                       # Cửa sổ chính & Floating Window QML
├── launcher_win.py                 # PySide6 + System Tray Host trên Windows
├── run.sh / start.bat              # Script khởi chạy 1-chạm đa nền tảng
├── backend/
│   ├── player_daemon.py            # Trình điều khiển nền mpv qua IPC Socket
│   ├── stream_resolver.py          # Bộ phân giải stream YouTube Music Android
│   ├── spotify_importer.py         # Trình chuyển giao playlist Spotify & Arc Stage
│   ├── social_relay_core.py        # SSOT quản lý danh tính & kết nối bạn bè
│   ├── catalog_engine.py           # Bộ máy nạp gợi ý bài hát & kệ nhạc
│   └── palette_extractor.py        # OKLAB Chromatic Salience phân tích màu sắc
├── cloud_relay/                    # Cloudflare Worker & D1 Database bindings
└── components/
    ├── DesktopLyricsWidget.qml     # Universal Desktop Lyrics Harness (Wayland/Win32)
    ├── SpotifyImportModal.qml      # Sân khấu chuyển giao Spotify Arc Gunshot
    ├── ShuffleButton.qml           # Nút trộn bài hát thiết kế Liquid Glass
    ├── SettingsModal.qml           # Cài đặt hệ thống, tài khoản & mẫu lời bài hát
    └── I18n.qml                    # Singleton bản địa hóa song ngữ nghiêm ngặt
```

---

## Bản Quyền (License)

Dự án được phân phối dưới giấy phép mã nguồn mở **MIT License**.
Mọi đóng góp (Pull Request, Issue báo lỗi, Ý tưởng thiết kế) đều được hoan nghênh nồng nhiệt!
