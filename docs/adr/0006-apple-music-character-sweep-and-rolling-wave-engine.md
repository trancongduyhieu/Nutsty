# ADR 0006: Apple Music Character Sweep, Persistent Rolling Wave & Phosphor Bloom Engine

- **Status**: Accepted
- **Date**: 2026-11-03 (Updated 2026-11-10)
- **Deciders**: User, Antigravity AI Assistant
- **Replaces**: [ADR 0004: Apple Music Phrase-Level Spatial Traveling Wave Engine](file:///home/apple/Applications/FrostifyLocal/docs/adr/0004-apple-music-phrase-spatial-wave.md)

---

## 1. Context & Motivation

Trong các bản phát hành trước, engine lời bài hát kiểu Apple Music đã trải qua nhiều thế hệ thử nghiệm:
1. **Thế hệ SimpMusic (Discrete Word Pops)**: Mỗi từ nảy độc lập theo thời gian riêng, gây hiện tượng từ nhảy giật cục (jumping islands) và trôi vị trí.
2. **Thế hệ ADR 0004 (Phrase Spatial Traveling Wave)**: Nhóm từ theo vế câu (trước dấu phẩy) và nâng đỉnh sóng $-1.6\text{px}$ rồi hạ về $0.0\text{px}$. Dù đã giải quyết độ mượt, chuyển động nâng-rồi-hạ vẫn chưa phản ánh đúng linh hồn của Apple Music trên iOS 17+ và macOS, nơi sóng ánh sáng quét qua từ và **giữ nguyên độ cao** (persistent rolling wave) tạo thành một dải lụa đã được thắp sáng.
3. **Hiện tượng đục/tối màu (Compounded Alpha Footgun)**: Việc nạp component `AppleMusicWordFlow` lên cả các câu tương lai gần ($dist \le 3$) dẫn tới việc độ mờ $0.38$ của từ chưa hát bị nhân đôi với `restingAlpha: 0.30` của dòng, làm 3 câu kế tiếp bị đen kịt ($0.114$).

---

## 2. Decision & Architecture Overview

Nutsty triển khai bộ engine lời bài hát Apple Music độc bản kết hợp các chuẩn mực tốt nhất từ **AMLL (Apple Music Like Lyrics)** và **Mochy-Music**:

### 2.1. 1-by-1 Character Sweep & Progressive Glyphs Illumination
- Thay vì sáng đồng loạt cả từ, mỗi từ được tách thành các ký tự độc lập: `(wData.text || "").split("")`.
- Từng glyph tự tính toán tỉ lệ quét `charProgress`:
  $$\text{charProgress} = \text{clamp}\left(\frac{\text{smoothProg} - \text{charFrom}}{\text{charTo} - \text{charFrom}}, 0.0, 1.0\right)$$
- Dải màu chuyển tiếp từ mờ dịu sang trắng tinh khiết:
  $$\text{Alpha}(\text{glyph}) = 0.38 + (1.0 - 0.38) \times \text{charProgress}$$

### 2.2. Persistent Rolling Wave Lift ($-2.5\text{px}$)
- Không hạ về baseline sau khi hát: Khi con trỏ chạm tới ký tự (`charProgress > 0.0 || isPast`), độ cao được nâng lên $-2.5\text{px}$ và **duy trì cố định** trong suốt thời gian câu hát còn hiệu lực.
- Chuyển động nâng sử dụng đường cong Hermite $w^2(3 - 2w)$ kết hợp bộ nội suy mượt mà `BezierSpline [0.4, 0.0, 0.2, 1.0]` (thời lượng 750ms), tạo cảm giác sóng cuộn nhẹ nhàng và tự nhiên.

### 2.3. Volumetric Gaussian MultiEffect Phosphor Bloom & Comet Tail
- **Lagged Phosphor Bloom Head**: Đầu đọc lân tinh `bloomProg` (thời lượng 240ms) trôi chậm phía sau đầu đọc chính `smoothProg` (thời lượng 120ms).
- Sự chênh lệch $\Delta_{\text{lag}} = \text{smoothProg} - \text{bloomProg}$ điều khiển trực tiếp độ lệch ngang của quầng sáng (`shadowHorizontalOffset: -\Delta_{\text{lag}} \times \text{width} \times 0.45`), tạo nên vệt đuôi sao chổi (comet tail) lướt theo từng âm tiết.
- **Zero FBO Thrashing**: `MultiEffect` chỉ được nạp qua `Loader` động trên DUY NHẤT từ đang hát (`wordRoot.isSinging`), đảm bảo hiệu năng tuyệt đối 60/120 FPS trên Wayland và Windows mà không gây tốn VRAM.

### 2.4. Held-Note Elastic Easing (Nốt Ngân Dài)
- Các từ có thời lượng $\ge 0.85\text{s}$ hoặc gắn cờ `isHeld: true` được kích hoạt đường cong thở đàn hồi `empEasing` (Cubic Bezier $S$-curve), co giãn vi mô $1.0 \to 1.045\times$, giữ cho chữ có nhịp thở sống động trong suốt nốt ngân.

### 2.5. Mochy-Music Monotonic Reading Head & Cartesian Alignment
- **Monotonic Reading**: Chỉ số `activeWordIndex` duyệt tuần tự đơn điệu theo thời gian thực tế `effectiveTime = currentTime + 0.06s` (bù trễ bộ đệm âm thanh 60ms). Một từ không bao giờ bị coi là đã hát nếu con trỏ chưa đi qua nó.
- **Cartesian Coordinate Layout**: Căn lề tĩnh Right/Center/Left dựa trên `parent.width - width` thay vì dùng hệ thống neo `anchors` của Qt Quick, loại bỏ hoàn toàn độ trễ giải quyết neo và chống deadlock vị trí.
- **Partitioned Line Wrapping**: Tự động tính toán ngắt dòng qua `wordMetrics.width` trước khi render (`partitionedLines`), đảm bảo bố cục chuẩn xác và không bị nhảy chữ đột ngột khi mở rộng cửa sổ.

---

## 3. Single Active Loader SSOT & Khắc Phục Lỗi Màu

- **Đơn nhất hóa Loader (`YTMusicNowPlayingView.qml`)**:
  - `appleMusicFlowLoader` chỉ được `active` và `visible` cho câu đang hát (`lyricRow.isCurrent`).
  - Toàn bộ các câu tương lai và quá khứ hiển thị qua `staticLineTxt` thuần trắng (`color: "#ffffff"`) kết hợp hiệu ứng quang học làm mờ phân tầng DoF (`restingAlpha: 0.30 - 0.50`).
  - Triệt tiêu hoàn toàn lỗi 3 câu đen kịt do xung đột nhân đôi alpha ($0.38 \times 0.30 = 0.114$).

---

## 4. Consequences & Verification

- **Ưu điểm**:
  - Tái hiện 100% linh hồn của Apple Music lyrics: ký tự quét mượt, sóng nâng giữ nguyên, quầng sáng lân tinh kéo đuôi sao chổi sang trọng.
  - Tối ưu GPU tối đa: Không lạm dụng MultiEffect trên toàn bộ văn bản; chỉ kích hoạt cục bộ tại đúng 1 từ đang phát âm.
  - Phân tầng quang học hoàn hảo: Câu đang hát nổi bật rực rỡ, các câu kế tiếp mờ dần đều đặn, không có đốm tối bất thường.
- **Tệp liên quan**:
  - `components/AppleMusicWordFlow.qml`
  - `components/AppleMusicDesktopLyrics.qml`
  - `components/YTMusicNowPlayingView.qml`
  - `.agents/rules/03-desktop-lyrics-engine.md`
