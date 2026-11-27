# Khung viền + tai thỏ khi phóng to (học theo liner)

## Ý định
Ở mọi kích cỡ cửa sổ (ban đầu chỉ khi phóng to; người dùng xem bản đầu rồi yêu cầu áp dụng cả cửa sổ thường), app trông giống liner: một dải kính tối mảnh chạy quanh toàn bộ app, các "tai thỏ" (notch kiểu MacBook) mọc ra từ mép trên chứa nút điều khiển.

## Mục tiêu
- Dải khung 6px quanh 4 cạnh, nội dung lùi vào; góc trong bo 12px khi phóng to, 18px (= 24 − 6, đồng tâm với góc cửa sổ) khi ở cửa sổ thường.
- Nút ◻ đổi qua lại phóng to / khôi phục dựa trên `win.maximized` (Quickshell trên Linux không có `visibility`/`showNormal`).
- Tai giữa: cụm icon điều hướng (avatar, trang chủ, tìm kiếm, thư viện, tải xuống, công cụ, chuông).
- Tai phải: nút phóng to/khôi phục và đóng.
- Tai trái: nút mũi tên thu gọn, chỉ ở màn Đang phát.
- Hairline 1px chạy liền mạch dọc mép trong, ôm quanh từng tai.
- Dải trên ngoài các tai: kéo để di chuyển, nhấp đôi để khôi phục.

## Không làm
- Không đưa cụm chuyển chế độ Đang phát (ảnh bìa/lời/tiếp theo/hẹn giờ) vào tai; nó chỉ nhích lên theo nội dung.
- Không thêm nút thu nhỏ (─).
- Không đụng `LiquidWarpBackdrop.qml`.

## Ràng buộc
AGENTS.md: chuỗi qua `I18n.tr`, không emoji, icon qua `AppIcon`, nút hover dùng `accentColor` (✕ dùng Muted Rose), chạy trên cả Niri và Windows (`QtQuick.Shapes` đã dùng trong repo nên có sẵn qua PySide6).

## Các cách đã cân nhắc
1. **Một `Shape` liền khối (đã chọn).** Đường ngoài = chữ nhật cả cửa sổ; đường trong = chữ nhật bo góc có 3 tai thụt xuống; `OddEvenFill` tô phần giữa bằng kính tối; một `ShapePath` thứ hai vẽ hairline theo đường trong. Hairline liền mạch, không chồng màu ở chỗ nối.
2. **Ghép mảnh như liner** (4 dải + 3 tai riêng). Dễ hơn nhưng hairline đứt và chỗ chồng bị đậm màu.
Người dùng chọn cách 1.

## Thiết kế
- Component mới `components/WindowFrameNotches.qml`: nhận độ rộng ba tai (trái có thể 0), dựng path SVG theo số đo liner (tai cao 30, loe 8, bo dưới 15; dải 6). Màu tô `Qt.rgba(0,0,0,0.35)`, hairline `Qt.rgba(1,1,1,0.10)`.
- `shell.qml`: luôn bật notchMode, ẩn dòng header 64px (cột layout thu chiều cao về 0), nội dung chừa lề 6px; đặt frame + nội dung ba tai lên trên cùng.
- Các nút trong tai: kích cỡ 26px như liner, hover nền `accentColor` 0.16.
- `YTMusicNowPlayingView`: ẩn nút thu gọn của chính nó khi phóng to (nút sống trong tai trái); cụm chế độ nhích lên theo.

## Để người dựng tự quyết
Cách tách icon điều hướng ra khỏi `TopHeaderBar` (tái dùng hay tạo hàng icon riêng), chi tiết animation chuyển trạng thái.
