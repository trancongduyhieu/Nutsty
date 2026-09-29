# ADR-0002: Spotify Import Cloudy Spiral Vortex & Flat Text Cancel Action

## Trạng Thái
Accepted

## Bối Cảnh
Modal "Chuyển Giao Playlist Spotify" (`components/SpotifyImportModal.qml`) đang gặp phải các vấn đề về giao diện và trải nghiệm thị giác:
1. **Lỗi góc vuông ảnh bìa**: Khung bìa playlist dùng `Rectangle { clip: true; Image {} }` dẫn tới ảnh không được bo góc 4 cạnh mà bị sắc nhọn lòi ra ngoài viền. Thay vì tạo mới, cần tận dụng deep component có sẵn `components/RoundedImage.qml` theo nguyên lý `codebase-design`.
2. **Nút Hủy quá thô**: Nút "Hủy Quá Trình Chuyển Giao" hiện là nút con nhộng (pill button) màu xám đen viền đỏ chiếm toàn bộ chiều ngang, tạo cảm giác nặng nề và chiếm diện tích thị giác không cần thiết.
3. **Trải nghiệm chờ đợi đơn điệu**: Quá trình khớp luồng âm thanh chỉ có một thanh tiến trình và con quay tròn nhỏ xíu, thiếu cảm xúc trực quan khi đang import danh sách hàng chục bài hát.

Ý tưởng mới: Lấy cảm hứng từ thí nghiệm hoạt họa 3D **"Cloudy Spiral CSS animation"** của Hakim El Hattab (CodePen `kawJWE`), biến giai đoạn loading thành một sân khấu Vortex không gian huyền ảo nơi các tên bài hát đang import xoáy theo quỹ đạo 3D elip và hút sâu vào đĩa than bìa playlist ở trung tâm.

## Quyết Định Thiết Kế
1. **Deep Component Reuse**:
   - Sử dụng `components/RoundedImage.qml` cho bìa playlist tại màn hình import để đảm bảo bo góc $R=10\text{px}$ – $14\text{px}$ chuẩn qua `MultiEffect` mask, loại bỏ hoàn toàn viền sắc góc vuông.
2. **Flat Ghost Text Cancel Action**:
   - Loại bỏ nút bấm con nhộng `Layout.fillWidth`.
   - Thay thế bằng text link phẳng căn giữa với màu đỏ Muted Rose (`#f43f5e`, alpha 0.70) và icon `window-close-symbolic.svg` nhỏ 12px.
   - Khi hover: Text sáng 100% (`#fda4af`) kèm nền phản xạ siêu mờ `Qt.rgba(244, 63, 94, 0.08)` bo góc R=8.
3. **Inward Cloudy Spiral Vortex Stage**:
   - Mở rộng chiều cao modal khi `isImporting` lên ~400px.
   - Bố trí một sân khấu hoạt họa trung tâm (`Item { height: 160 }`):
     - **Tâm Vortex**: Đĩa than tròn bọc bìa playlist (`RoundedImage` bo góc $R=14\text{px}$ hoặc hình tròn $R=32\text{px}$) xoay đĩa than vinyl nhẹ nhàng kèm hào quang `Aurora Glow` theo `accentColor`.
     - **Quỹ Đạo Xoắn Ốc Elip 3D (Hakim El Hattab Inward Convergence)**: 5–7 particle / text node đại diện cho các bài hát đang import chuyển động theo phương trình tham số:
       $$X(t) = X_0 + r(t) \cdot \cos(\theta(t))$$
       $$Y(t) = Y_0 + r(t) \cdot \sin(\theta(t)) \cdot 0.42$$
       với $r(t)$ xoắn ốc từ $140\text{px}$ thu nhỏ dần về $32\text{px}$, `scale` và `opacity` biến thiên tạo DoF chiều sâu quang học. Bài hát đang xử lý (`root.importCurrentTrack`) phát sáng rực rỡ ở tiền cảnh.

## Hệ Quả
- **Tích cực**:
  - Giao diện modal trở nên thanh thoát, tinh tế và mang tính nghệ thuật số (digital craftsmanship) cao cấp.
  - Loại bỏ hoàn toàn lỗi hiển thị ảnh bìa vuông vức.
  - Giảm tải phân tâm thị giác từ nút hủy, dồn 100% sự chú ý của người dùng vào sân khấu chuyển động kỳ ảo của các bài hát.
- **Tiêu cực**:
  - Tăng nhẹ số lượng tính toán tọa độ QML Animation (giải quyết bằng `NumberAnimation` nhẹ trên GPU và `FrameAnimation` tối ưu).
