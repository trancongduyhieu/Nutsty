# Desktop Lyrics Engine & Kinetic Typography Specification

Tài liệu đặc tả chuyên sâu về hệ thống lời bài hát hiển thị trên Desktop (Desktop Lyrics), các hiệu ứng kinetic typography, đổ bóng điện ảnh và thuật toán đồng bộ từng âm tiết (Syllable-level Karaoke) của dự án Nutsty.

---

## 1. Universal Lyrics Harness (`components/DesktopLyricsWidget.qml`)
- **Kiến trúc Host**: Chạy trên nền native Wayland Layer-Shell thông qua Quickshell, neo trực tiếp lên không gian desktop mà không tạo khung cửa sổ XWayland truyền thống.
- **Dynamic Input Mask**: Khai báo `Region { id: lyricsRegion; item: containerBox }` và `mask: (pressed || drag.active) ? null : lyricsRegion` giúp desktop/ứng dụng bên dưới nhận chuột 100% khi idle.
- **Cử chỉ chuột & Bảo vệ kéo thả**: Double-click gọi `playPauseRequested()`, lăn chuột (wheel) tăng/giảm âm lượng $\pm 3\%$, drag threshold 8px (hoặc giữ phím `Super`) ngăn trôi vị trí khi click.
- **Per-Wallpaper Smart Anchor**: Lưu tọa độ theo tên file hình nền vào `desktopLyricsWallpaperPositions` (`nutsty_settings.json`); tự động đổi vị trí tương ứng khi chuyển hình nền.
- **Tọa độ trực quan**: Hiển thị nổi lên hình nền desktop tại vùng hạ tiêu cự / tà váy nhân vật, tự động đồng bộ màu theo `nutsty_palette.json`.

---

## 2. Các Bộ Mẫu Hiển Thị (Lyrics Engine Presets)

### Preset 1: Điện ảnh Serif (`Cinematic Serif`)
- **Font chữ**: *Instrument Serif* cổ điển nghệ thuật.
- **Hiệu ứng**:
  - Pop chữ nhịp điệu khi bắt đầu câu mới (scale nảy nhẹ kèm chuyển động baseline so le - staggered baselines).
  - Đổ bóng điện ảnh đa tầng Universal Cinematic Shadows (`#a6020305` và `#66000000`) giúp chữ luôn sắc nét và đọc rõ trên mọi loại hình nền sáng/tối.
  - > [!CAUTION]
    > **Tuyệt đối không dùng viền trắng (White Halo)** quanh chữ lyric vì gây thô ráp và phá hủy thẩm mỹ điện ảnh.

### Preset 2: Apple Music Parametric Multi-Line Engine (`AppleMusicDesktopLyrics.qml`)
- **Bố cục**: Hiển thị đồng thời 5 dòng lời parametric (Slot 0..4 + buffer) với rolling glide animation 450ms OutCubic.
- **Engine cốt lõi**: Tích hợp trực tiếp `AppleMusicWordFlow.qml` cho dòng active (Slot 1), tận dụng trọn vẹn syllable timing, wave lift và phosphor bloom tự nhiên.
- **Hiệu ứng quang học**:
  - Độ sâu trường ảnh quang học (Optical Depth-of-Field - DoF): Dòng hiện tại sắc nét nhất (Slot 1), các dòng trước (Slot 0) và sau (Slot 2..4) mờ dần theo gradient Gaussian blur thực tế (blur $0.35 \to 0.85$, opacity $0.58 \to 0.14$).

### Preset 3: Minimalist Word-by-Word Motion Blur Engine
- Hiển thị tối giản, làm nhòe chuyển động (motion blur) theo từng từ khi ca sĩ phát âm.

### Preset 4: Đồ họa Chuyển động (`Motion Typography`)
- Hiển thị theo phong cách Motion Graphics hiện đại trong khung Bento (chữ trượt, chuyển cảnh typographic nhịp điệu).

---

## 3. Đồng Bộ Từng Âm Tiết & Elastic Scaling (Syllable-Level Karaoke)
- **Kế thừa kiến trúc**: Tham chiếu từ SimpMusic Footgun #217 & AMLL (Apple Music Like Lyrics).
- **Nguyên lý hoạt động**:
  - Phân tích cú pháp lời bài hát nâng cao (enhanced LRC / TTML / syllable timestamps).
  - Với các nốt ngân dài (held notes), áp dụng hoạt ảnh co giãn đàn hồi (elastic scaling) cho từ đang hát thay vì dịch chuyển đột ngột.
  - Đảm bảo chuyển động mượt mà ở 60/120 FPS trên Wayland bằng cách sử dụng các thuộc tính nội suy GPU của Qt Quick.

---

## 4. Cơ Chế Tìm Lời Bài Hát Tự Động (Online Synced Lyrics Fetcher)
- **Tệp**: `backend/lyrics_helper.py`.
- **Thứ tự ưu tiên nạp lời**:
  1. File `.lrc` cục bộ có sẵn cùng thư mục với file nhạc.
  2. Fallback trực tuyến tự động qua thư viện `syncedlyrics` theo tuần tự:
     $$\text{LRCLIB} \longrightarrow \text{NetEase Cloud Music} \longrightarrow \text{Musixmatch}$$
- **Bộ nhớ đệm (Cache)**: Tự động lưu cache file lời bài hát tìm được để tái sử dụng tức thì trong các lần phát sau mà không tốn băng thông mạng.

---

## 5. Apple Music Phrase Traveling Wave (`components/AppleMusicWordFlow.qml`)
- **Tệp**: `components/AppleMusicWordFlow.qml`, `backend/lyrics_helper.py`, `docs/adr/0004-apple-music-phrase-spatial-wave.md`.
- **Phrase-Level Spatial Traveling Wave**: Tự động gom cụm từ (phrase) trước dấu câu (`,`, `.`, `!`, `?`, `;`, `—`) hoặc nhịp thở ca sĩ ($> 0.35\text{s}$). Con sóng quét liên tục dọc theo vế câu qua `waveProgressTotal`: từ kế tiếp nhấc nhẹ đón đầu sóng ($T_{\text{lead}} = 160\text{ms}$), đạt đỉnh crest và hạ êm về baseline ($0.0\text{px}$).
- **Unified Baseline & Spring-Damped SmoothedAnimation**: Toàn bộ từ (chưa hát, đang hát, đã hát) nằm chung baseline $0.0\text{px}$ (xóa bỏ triệt để hố sâu $1.8\text{px}$). Đỉnh sóng nâng $y_{\text{lift}} = -1.6\text{px}$ (biên độ $1.6\text{px} \le 2.0\text{px}$), scale $1.01\times$. Bọc `Translate.y` và `scale` trong `SmoothedAnimation { duration: 150; reversingMode: SmoothedAnimation.Immediate }` đảm bảo $C^1$ velocity continuity, triệt tiêu hoàn toàn giật cục.
- **Phosphor Bloom Glow**: Tỏa hào quang lân tinh qua `MultiEffect` (blur $0.55$, opacity $0.51$, max $24$) trên nền layer mượt.
- **Footgun #1**: **TUYỆT ĐỐI CẤM** gán trực tiếp `x, y` trên con trực tiếp của QML `Flow` (làm vỡ positioner và văng chữ lên dòng trên). Bắt buộc bọc qua `transform: Translate { y: waveY }` trên item con bên trong.
