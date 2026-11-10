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

## 5. Apple Music Character Sweep & Rolling Wave Engine (`components/AppleMusicWordFlow.qml`)
- **Tệp**: `components/AppleMusicWordFlow.qml`, `components/YTMusicNowPlayingView.qml`, `docs/adr/0006-apple-music-character-sweep-and-rolling-wave-engine.md`.
- **Character Sweep & Progressive Illumination**: Tách từng glyph qua `split("")`, tính `charProgress` quét mượt trái sang phải (alpha $0.38 \to 1.0$ pure white).
- **Persistent Rolling Wave Lift ($-2.5\text{px}$)**: Nội suy Hermite $w^2(3-2w)$ qua `BezierSpline [0.4, 0.0, 0.2, 1.0]` (750ms). Khi quét tới, nhấc $-2.5\text{px}$ và giữ nguyên độ cao (rolling wave), không sụt về baseline.
- **Hardware MultiEffect Gaussian Phosphor Bloom & Comet Tail**: Volumetric glow (`shadowBlur: 0.95`, `opacity: 0.92`, `scale: 1.12`). Đầu đọc trễ `bloomProg` (240ms) đi sau `smoothProg` (120ms) tạo vệt đuôi sao chổi (`bloomLagDelta`). Chỉ mount `Loader` trên duy nhất từ đang hát (`isSinging`) để triệt tiêu tải GPU FBO (đạt chuẩn 60/120 FPS).
- **Held-Note Elastic Easing**: Nhận diện nốt ngân `wDur >= 0.85\text{s}` hoặc `isHeld: true`, áp dụng co giãn đàn hồi vi mô $1.045\times$ qua Bezier `empEasing`.
- **Mochy-Music Cartesian Alignment**: Căn lề tĩnh Right/Center/Left theo tọa độ Cartesian `x`, không neo `anchors` động; chia dòng qua `partitionedLines`.
- **Footgun #1 (Compounded Alpha / 3 Câu Đen Kịt)**: Trong `YTMusicNowPlayingView.qml`, `appleMusicFlowLoader` chỉ được active và visible trên duy nhất câu đang hát (`lyricRow.isCurrent`). Nếu nạp trên câu tương lai ($dist \le 3$), alpha $0.38$ bị nhân với `restingAlpha` ($0.30$) thành $0.114$ (đen kịt so với text tĩnh thuần trắng $0.30$).
- **Footgun #2 (Bảo toàn vị trí dòng)**: Dùng `Row` lồng trong `Column` với phân vùng dòng cố định `partitionedLines` thay vì `Flow` thả nổi tự do.

---

## 6. Tối Ưu Hóa Bộ Nhớ Desktop Lyrics (Memory & Render Footprint)
- **Loại Bỏ Hoàn Toàn TaskbarLyrics (.NET 8)**: Đã loại bỏ companion `TaskbarLyrics.exe` và WebSocket bridge; tiết kiệm trực tiếp 135–180MB RAM và 180MB dung lượng bộ cài.
- **Bilinear Optical Haze (`AmberolDetailView.qml`)**: Đặt `sourceSize: Qt.size(160, 90)` cho ảnh nền artwork bokeh kết hợp `blurMax: 64`. Cắt giảm kích thước texture từ 20MB+ xuống 57KB, triệt tiêu tải VRAM và RAM bộ đệm đa tầng.
- **Win32 Working Set Auto-Trimming (`EmptyWorkingSet`)**: Tự động xả các trang bộ nhớ ảo không còn sử dụng sau khởi động (6s), khi ẩn/thu nhỏ (minimize) hoặc định kỳ mỗi 90s, duy trì mức RAM ổn định ở ~100–130MB thay vì bị Windows om giữ 450MB+.
