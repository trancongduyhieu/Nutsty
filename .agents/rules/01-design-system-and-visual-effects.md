# Design System, Liquid Glass & Visual Effects Specification

Tài liệu đặc tả chuyên sâu về hệ thống đồ họa, ngôn ngữ thiết kế Dark Glass, hiệu ứng quang học và quy chuẩn hình học thị giác của dự án Nutsty.

---

## 1. Thuật Toán Kính Lỏng Liquid Glass & Keo 502 Trong Suốt
- **Tệp cốt lõi**: `components/LiquidGlassContainer.qml`, `assets/shaders/liquid_glass.frag` (chuẩn GLSL 440 Qt 6 RHI).
- **Kiến trúc đệm nền 3 tầng (Triple-Tier Backdrop)**:
  - Container ngầm `glassCompositeBackdrop` bắt buộc đặt `visible: true, opacity: 0.001, z: -999`. Tuyệt đối không dùng `visible: false` vì Scene Graph sẽ bỏ qua không vẽ vào GPU FBO, khiến shader lấy mẫu pixel rỗng `(0,0,0,0)` thành đen xì.
  - Hòa trộn 3 tầng: Đáy (hình nền desktop) $\to$ Giữa (ảnh bìa fade in/out 900ms khi play/pause) $\to$ Đỉnh (card bài hát cuộn).
- **Giải thuật GLSL Shader quang học**:
  - *Inigo Quilez SDF Rounded Box* `sdRoundedBox` kết hợp gradient giải tích `gradSdRoundedRect` chống răng cưa góc bo.
  - *Khúc xạ thấu kính Circle Map*: $\text{circleMap}(x) = 1.0 - \sqrt{\max(0.0, 1.0 - x^2)}$ bẻ cong tọa độ UV theo độ vồng giọt nước.
  - *Quang sai tán sắc (Chromatic Aberration)*: Tách 3 kênh RGB lệch pha khi ánh sáng khúc xạ qua rìa mép kính.
  - *Phản quang bề mặt cong (`rimSheen` & `topReflect`)*: Mô phỏng độ bóng dẻo keo 502 trong suốt, triệt tiêu màng sữa đục trắng (`Vibrancy 1.6x`).
- **Quy tắc tuyệt đối**: Tuyệt đối không thay thế Liquid Glass bằng các khối `Rectangle` đơn giản mang màu đục `rgba(255,255,255,0.1)`.

---

## 2. Định Lý Bo Góc Đồng Tâm & Hairline Borders
- **Công thức hình học**:
  $$\large R_{\text{con}} = R_{\text{mẹ}} - \text{Padding}$$
  - *Ví dụ mẫu*: Với thẻ cha có $R_{\text{mẹ}} = 12\text{px}$ và `padding: 6px`, ảnh hoặc phần tử con bên trong bắt buộc phải có $R_{\text{ảnh}} = 12 - 6 = 6\text{px}$.
- **Hairline Border 1px**:
  - Toàn bộ card, hàng đợi (Queue Track Items) và Mood Chips bắt buộc phải có viền siêu mảnh 1px:
    - *Tĩnh (Idle)*: `Qt.rgba(1, 1, 1, 0.07)`
    - *Rê chuột (Hover)*: `Qt.rgba(1, 1, 1, 0.18)`
    - *Bài đang phát (Active)*: `Qt.rgba(accent.r, accent.g, accent.b, 0.45)`
  - Có viền hairline 1px trực tiếp trên mép ảnh bìa; tuyệt đối không để các thành phần trôi nổi không viền.

---

## 3. Quy Chuẩn Màu Sắc Nút Bấm & Popover (Cấm Tuyệt Đối Nút Xám Đen)
- **Cấm tiệt**: Không sử dụng màu xám đen chết (`rgba(255, 255, 255, 0.06)`, `0.08`, `#18181b`, `#27272a`) cho bất kỳ nút tương tác, pill button, selector hay popover nào.
- **Chuẩn hóa Interactive Controls (Dynamic Chromatic Salience)**:
  - Hấp thụ màu sắc động `accentColor` từ hình nền desktop hoặc ảnh bìa bài hát (`root.accentColor` từ `nutsty_palette.json`).
  - *Trạng thái tĩnh*: Nền `Qt.rgba(accent.r, accent.g, accent.b, 0.12)`, viền hairline 1px `Qt.rgba(accent.r, accent.g, accent.b, 0.25)`, text trắng sáng `#ffffff`, icon mang sắc thái `accent`.
  - *Trạng thái hover*: Nền `Qt.rgba(accent.r, accent.g, accent.b, 0.22)`, viền `Qt.rgba(accent.r, accent.g, accent.b, 0.45)`.
- **Hộp thoại Popover Menu / Dropdown List**:
  - Nền kính sẫm hữu cơ: `Qt.rgba(0.06 + accent.r * 0.08, 0.06 + accent.g * 0.08, 0.08 + accent.b * 0.12, 0.96)`, viền `Qt.rgba(accent.r, accent.g, accent.b, 0.35)`.
  - *Mục đang chọn*: Nền `Qt.rgba(accent.r, accent.g, accent.b, 0.26)`, viền `Qt.rgba(accent.r, accent.g, accent.b, 0.45)`, text trắng kèm icon checkmark `emblem-ok-symbolic.svg` màu `accent`.
  - *Mục hover*: Nền `Qt.rgba(accent.r, accent.g, accent.b, 0.14)`, viền `Qt.rgba(accent.r, accent.g, accent.b, 0.25)`.
- **Nút hành động nhạy cảm / Đăng xuất / Xóa (Destructive Muted Rose)**:
  - *Trạng thái tĩnh*: Nền đỏ hoa hồng `Qt.rgba(244, 63, 94, 0.12)`, viền `Qt.rgba(244, 63, 94, 0.26)`, text hồng đào `#fda4af`.
  - *Trạng thái hover*: Nền đỏ ấm `Qt.rgba(239, 68, 68, 0.24)`, viền `Qt.rgba(239, 68, 68, 0.48)`, text trắng hồng `#ffe4e6`.

---

## 4. Cơ Chế Xuyên Thấu Khi Pause & Hòa Sắc Khi Play (Footgun #1)
- **Tệp**: `shell.qml` và `components/MainTrackGrid.qml`.
- **Ràng buộc cốt lõi**:
  - `effectiveAccentColor`: `(win.currentTrack && win.isPlaying) ? win.songAccentColor : win.wallpaperAccentColor`
  - `playingBackdropCover.opacity`: `(win.currentTrack && win.isPlaying) ? 1.0 : 0.0` (với `duration: 400`, `Easing.InOutQuad`)
  - `fallbackPlayingImg.opacity`: `(win.currentTrack && win.isPlaying) ? 1.0 : 0.0`
  - `nutstySurfaceArtwork.opacity`: `(win.currentTrack && win.isPlaying) ? 0.70 : 0.0`
- **Hành vi trực quan**:
  - *Khi phát nhạc (`isPlaying === true`)*: Backdrop tối `#0a0b0e` mờ dần hiện lên (opacity 1.0) che hình nền desktop, bung tỏa hiệu ứng velvet aurora blur từ bìa bài hát và hòa sắc toàn hệ thống theo `win.songAccentColor`.
  - *Khi tạm dừng (`isPlaying === false`)*: Toàn bộ backdrop mờ dần về `0.0` trong 400ms, đưa cửa sổ về kính mờ acrylic 58% (`Qt.rgba(0.04, 0.04, 0.06, 0.58)`), nhìn xuyên thấu 100% hình nền desktop; accent chuyển mượt mà về `win.wallpaperAccentColor`.
- > [!CAUTION]
  > **Bẫy lỗi tối thượng**: Tuyệt đối không thay `win.isPlaying` bằng `win.currentTrack ? ... : ...`. Làm như vậy sẽ khóa chết ứng dụng ở trạng thái màn hình đen đục và mất tính năng xuyên thấu hình nền khi pause.

---

## 5. Chuẩn Hóa Hình Ảnh Bo Góc (`components/RoundedImage.qml`)
- **Quy định nghiêm ngặt**: Mọi hình ảnh cần bo góc trong toàn bộ dự án BẮT BUỘC dùng `RoundedImage.qml` với thuộc tính `radius`. TUYỆT ĐỐI KHÔNG tự sinh thêm cụm `Rectangle mask + MultiEffect` thủ công gây phình mã nguồn và rò rỉ VRAM FBO.
- **Tối ưu RAM/VRAM tự động**:
  - Tự động downscale HiDPI: `sourceSize: Qt.size(width * 2, height * 2)` (giảm 99% RAM giải nén bitmap).
  - Tiêu tốn 0 byte VRAM khi ảnh chưa tải hoặc `radius === 0` (`layer.enabled` chỉ bật khi `Image.Ready && radius > 0`).
  - Tích hợp sẵn placeholder nền và fallback `AppIcon` khi rỗng hoặc tải lỗi.
- Ảnh đại diện/bìa phải lấp đầy 100% thẻ (`fillMode: Image.PreserveAspectCrop`), không để đệm trống mép đen.
- Viền hairline 1px áp dụng trực tiếp qua `borderColor` và `borderWidth` theo công thức bo góc đồng tâm.

---

## 6. Nút Điều Hướng Chuẩn Hóa (`components/NavArrowButton.qml`)
- Mọi nút lướt ngang carousel `<` và `>` bắt buộc dùng `NavArrowButton.qml`.
- Tự động liên kết `accentColor`, hiệu ứng hover scale 1.06x và tự động làm mờ (`opacity: 0.28`, `enabled: false`) khi chạm giới hạn cuộn (`canScroll`).
- Không dùng nút `< >` tại `CategorizedSearchView.qml` để giữ giao diện tối giản, người dùng lọc danh mục trực tiếp qua Filter Chips.

---

## 7. Cấm Tự Tiện Dùng Hình Con Nhộng (Anti-Capsule Mandate) & Bố Cục Đồng Phẳng
- **Tuyệt đối cấm hình con nhộng (Pill / Capsule)**: Không dùng `radius = height / 2` trên nút bấm, thẻ, khung hay badge trừ khi được người dùng yêu cầu rõ ràng (như Mood Chips).
- **Chuẩn hóa nút bấm & badge**: Nút bấm dùng $R = 8\text{px}$ (`rounded-lg`), badge $R = 4\text{px}$/6px (`rounded-md`).
- **Bố cục đồng phẳng (Planar Purity)**: Không lồng các khối hộp nổi viền dày chồng chéo (box-in-a-box). Phân vùng bằng khoảng trắng hệ 8pt/16pt và đường kẻ viền siêu mảnh hairline 1px `Qt.rgba(1, 1, 1, 0.08)`.
