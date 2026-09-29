# Design Spec: Spotify Import Cloudy Spiral Vortex & Flat Text Cancel Action

- **Tác giả**: Nutsty Engineering Team
- **Ngày lập**: 2026-09-30
- **Trạng thái**: Approved for Implementation
- **Tài liệu liên quan**: [ADR-0002](file:///home/apple/Applications/FrostifyLocal/docs/adr/0002-spotify-import-vortex-and-flat-cancel.md)
- **Cảm hứng thiết kế**: Thí nghiệm "Cloudy Spiral CSS animation" của Hakim El Hattab (CodePen `kawJWE`).

---

## 1. Mục Tiêu & Vấn Đề Cần Giải Quyết

1. **Bo tròn ảnh bìa playlist theo chuẩn Design System**:
   - Khắc phục lỗi góc vuông sắc cạnh trên thumbnail bìa playlist ở view `isImporting` bằng cách tái sử dụng component có sẵn `components/RoundedImage.qml` với radius 10px, viền hairline và mask mượt mà (tuân thủ nguyên tắc `codebase-design`).
2. **Nút "Hủy Quá Trình Chuyển Giao" dạng text phẳng**:
   - Loại bỏ nút con nhộng (pill button) với khung viền xám đen nặng nề.
   - Chuyển thành nút text phẳng căn giữa với màu hoa hồng dịu (Muted Rose `#f43f5e`, alpha 0.70), không viền, không nền, phản xạ hover R=8 siêu nhẹ, giảm tải phân tâm thị giác (tuân thủ `ui-layout-design-rules` và `color-expert`).
3. **Sân khấu hoạt họa xoắn ốc (Cloudy Spiral Vortex Stage)**:
   - Thay thế loading spinner tĩnh đơn điệu bằng sân khấu chuyển động 3D trung tâm.
   - Các bài hát đang được import sẽ bay lượn theo quỹ đạo xoắn ốc elip 3D thu nhỏ dần và hút sâu vào đĩa than bìa playlist ở tâm (Inward Convergence).

---

## 2. Kiến Trúc & Bố Cục Giao Diện (Layout & Hierarchy)

### 2.1. Phân Bổ Chiều Cao Modal
- Trạng thái nhập link: Chiều cao `230px` (hoặc `360px` khi có preview).
- Trạng thái đang chuyển giao (`root.isImporting`): Chiều cao nâng lên **`420px`** để dành không gian cho Vortex Stage.
- Trạng thái hoàn tất (`root.importCompleted`): Chiều cao `260px`.

### 2.2. Cấu Trúc Khối `isImporting` (Từ Trên Xuống Dưới)
1. **Header Tiêu Đề Playlist**:
   - Tiêu đề playlist to, đậm, căn giữa (`15px`, bold, white).
   - Dòng phụ: "Đang khớp nguồn âm thanh chất lượng cao..." (`12px`, textSecondary).
2. **Vortex 3D Stage (`height: 180px`)**:
   - **Tâm Vortex**:
     - Vòng tròn Aurora Glow khuếch tán với `root.accentColor`.
     - Đĩa than tròn bọc bìa playlist qua `RoundedImage` ($R=14\text{px}$, kích thước $54\times 54\text{px}$), xoay chậm vòng tròn (`RotationAnimation { duration: 12000; loops: Animation.Infinite }`).
   - **Các Vành Xoắn Ốc (Spiral Track Nodes)**:
     - 5–6 node bài hát di chuyển theo công thức tham số elip 3D:
       $$\theta_i(t) = \text{basePhase} + i \cdot \frac{2\pi}{N}$$
       $$r_i(t) = R_{\max} - \left((t + \text{offset}_i) \bmod 1.0\right) \cdot (R_{\max} - R_{\min})$$
       $$X_i = X_{\text{center}} + r_i \cdot \cos(\theta_i)$$
       $$Y_i = Y_{\text{center}} + r_i \cdot \sin(\theta_i) \cdot 0.40$$
     - Hiệu ứng DoF: Càng xa tâm kích thước càng nhỏ ($0.65\times$) và mờ ($0.35$), khi lướt qua phía trước thì phóng to ($1.05\times$) và sáng rõ ($0.95$), rồi thu nhỏ dần khi hút vào đĩa than.
     - Node bài hát hiện tại (`root.importCurrentTrack`) có vệt sáng phát quang (phosphor glow) theo màu accent.
3. **Thanh Tiến Độ (Progress Bar) & Bộ Đếm**:
   - Thanh tiến độ bo góc $R=4\text{px}$, chiều cao $6\text{px}$ với gradient ánh sáng theo `root.accentColor`.
   - Dòng thông số: Tên bài đang tải rút gọn + Bộ đếm `37/82` (12px bold white).
4. **Nút Hủy Dạng Text Phẳng (Flat Ghost Cancel Button)**:
   - Căn giữa, không viền, không nền.
   - Text "Hủy Quá Trình Chuyển Giao" kèm icon x (12px), màu `#f87171` (Muted Rose).
   - Hover effect: Màu chữ sáng lên `#fda4af`, nền mờ `Qt.rgba(244, 63, 94, 0.08)` bo góc R=8.

---

## 3. Kế Hoạch Kiểm Thử Tự Động Python (`tests/test_spotify_import_vortex.py`)

Viết bộ test script Python độc lập bao quát các ca kiểm thử:
- **Case 1 (RoundedImage Component Integration)**: Kiểm tra mã QML của `SpotifyImportModal.qml` đã loại bỏ hoàn toàn `Rectangle { clip: true; Image {} }` và thay bằng `RoundedImage` với `radius: 10` hoặc `radius: 14` cho cả preview và import stage.
- **Case 2 (Flat Cancel Button Structure)**: Kiểm tra nút hủy không còn thuộc tính `Layout.fillWidth` kiểu pill, không dùng border thô, sử dụng text link phẳng với color token Muted Rose `#f87171` / `#fda4af`.
- **Case 3 (Vortex Mathematical Model & Orbit Parameters)**: Kiểm tra công thức tọa độ elip tham số 3D, hệ số tilt $0.40 \pm 0.05$, biến thiên bán kính $R_{\max} \to R_{\min}$ theo đúng chu trình xoắn ốc Inward Convergence của Hakim El Hattab.
- **Case 4 (Modal Height Dynamics)**: Kiểm tra biểu thức tính chiều cao modal khi `isImporting` đạt $\ge 400\text{px}$ đảm bảo không gian hiển thị không bị chen chúc hay tràn layout.
- **Case 5 (Static QML Syntax & Contract)**: Chạy `python scripts/verify_codebase.py` pass 100%.
