# Design Spec: Adaptive Multi-Gear Polling with Active User Boost

- **Tác giả**: Nutsty Engineering Team
- **Ngày lập**: 2026-09-30
- **Trạng thái**: Approved for Implementation
- **Vấn đề giải quyết**: Cloudflare Worker Free Tier chạm trần 100k requests/ngày (ngày 26/09 đạt 94,458 reqs, ngày 29/09 đạt 82,870 reqs) do các timer polling mạng xã hội chạy quá dày trong `shell.qml`.

---

## 1. Mục Tiêu & Ràng Buộc Kỹ Thuật

### 1.1. Mục Tiêu (Goals)
1. **Cắt giảm tối thiểu 65% – 70% số lượng request** gửi lên Cloudflare Worker hàng ngày.
2. Giữ lượng request ở mức an toàn tuyệt đối ($\le 28,000\text{ reqs/ngày}$) ngay cả khi ứng dụng mở liên tục suốt 24/7.
3. **Không làm suy giảm trải nghiệm thời gian thực**: Lời mời nghe cùng, thông báo kết bạn và chat Danmaku vẫn phản hồi tức thì ($\le 1.0\text{s}$) khi người dùng đang tương tác với ứng dụng.
4. **Không phụ thuộc vào việc nâng cấp gói cước**: Chạy hoàn hảo trên Cloudflare Free Tier (Workers + D1).

### 1.2. Ràng Buộc (Constraints)
- Giữ nguyên hợp đồng IPC và API hiện tại giữa QML và Python daemon / Cloudflare Worker.
- Không gây giật lag luồng render QML; không tạo thêm độ trễ khi chuyển bài hát.
- Tuân thủ quy tắc quản lý timer của Qt/QML: tránh memory leak, không lồng timer vô hạn.

---

## 2. Kiến Trúc & Thiết Kế Giải Pháp

### 2.1. Phân Tầng Dữ Liệu (Tiered Polling Split)

Hệ thống phân tách rạch ròi 2 nhóm dữ liệu với đặc tính thời gian khác biệt:

1. **Nhóm Sự Kiện Thời Gian Thực (High-Priority Realtime Events)**:
   - Endpoint: `/api/notes/events` (hoặc `/api/events`).
   - Tải trọng: Nhẹ, chỉ kiểm tra xem có event mới trong bảng `nutsty_events` hay không.
   - Nội dung: Lời mời nghe cùng (`listen_along_invite`), phản hồi nghe cùng (`listen_along_accept`), lệnh đồng bộ (`play`, `pause`, `seek`), tin nhắn Danmaku, thông báo kết bạn.
   - Tần suất:
     - Đang trong phòng Nghe Cùng (`isCoListeningActive`): **`800ms`** (High Gear).
     - Đang có tương tác người dùng (`isUserActiveBoost`): **`1000ms`** (Active Boost).
     - Trạng thái bình thường không thao tác: **`2000ms`** (Steady State).

2. **Nhóm Dữ Liệu Tĩnh / Bán Tĩnh (Low-Priority State Queries)**:
   - Endpoint: `/api/notes` (ghi chú 24h & online status) và `/api/friends` (danh sách bạn bè).
   - Tải trọng: Trung bình (quét bảng `nutsty_notes` và `nutsty_friendships`).
   - Tần suất:
     - Đang trong phòng Nghe Cùng: **`2000ms`** (notes) và **`4000ms`** (friends).
     - Trạng thái bình thường: Giãn thành **`8000ms`** (notes + sync now_playing) và **`10000ms`** (friends).
     - Kích hoạt nạp tức thì một lần (Instant Fetch) khi người dùng mở `ManageFriendsModal` hoặc hover vào `FriendsPulseBar`.

---

### 2.2. Cơ Chế Active User Boost (Burst Polling)

```
[Sự kiện người dùng] ──► triggerUserActiveBoost() 
                            ├── Đặt win.isUserActiveBoost = true
                            ├── socialEventsFastTimer tự co về 1000ms
                            └── Khởi động activeBoostTimer (interval: 15,000ms, repeat: false)
                                  │
                                  ▼ (sau 15 giây không có tương tác mới)
                            Đặt win.isUserActiveBoost = false
                            socialEventsFastTimer tự dãn về 2000ms
```

**Các điểm kích hoạt `triggerUserActiveBoost()`**:
- Người dùng di chuột hoặc click trong cửa sổ chính `Nutsty`.
- Người dùng bấm phím media (Play/Pause, Next, Prev, Seek).
- Người dùng mở bất kỳ Modal nào liên quan đến tương tác: `ManageFriendsModal`, `FriendStoryModal`, `PostNoteModal`, `SettingsModal`, `SpotifyImportModal`.
- Khi vừa nhận được một event mới (nhận tin nhắn hoặc lời mời nghe cùng $\rightarrow$ duy trì boost để đàm thoại mượt mà).

---

## 3. Chi Tiết Thay Đổi Trong Mã Nguồn

### 3.1. Tệp `shell.qml`
1. Bổ sung thuộc tính và hàm điều phối:
   - `property bool isUserActiveBoost: false`
   - `function triggerUserActiveBoost()`: Bật cờ `isUserActiveBoost = true` và khởi động lại `activeBoostTimer`.
   - `Timer { id: activeBoostTimer; interval: 15000; repeat: false; onTriggered: win.isUserActiveBoost = false }`
2. Cập nhật `socialEventsFastTimer`:
   - `interval: win.isCoListeningActive ? 800 : (win.isUserActiveBoost ? 1000 : 2000)`
3. Cập nhật `friendsNotesTimer`:
   - `interval: win.isCoListeningActive ? 2000 : 8000`
4. Cập nhật `friendsSyncTimer`:
   - `interval: win.isCoListeningActive ? 4000 : 10000`
5. Tích hợp `triggerUserActiveBoost()` vào sự kiện hover/interaction của `nutstyAppSurface` và các callback thao tác chính.

---

## 4. Kế Hoạch Kiểm Thử & Nghiệm Thu (Verification Plan)

1. **Kiểm tra cú pháp & tính toàn vẹn**:
   - Chạy `python scripts/verify_codebase.py` để đảm bảo hợp đồng QML/JS và Python backend pass 100%.
2. **Kiểm tra thực tế trạng thái Timer**:
   - Mở Nutsty, theo dõi log debug của timer khi không thao tác $\rightarrow$ chu kỳ nhịp đập giãn về đúng 2000ms / 8000ms.
   - Thao tác di chuột/đổi bài $\rightarrow$ chu kỳ co về 1000ms (Active Boost) trong đúng 15 giây rồi tự trở lại 2000ms.
   - Kích hoạt chế độ Nghe Cùng $\rightarrow$ chu kỳ co về 800ms.
3. **Đo đạc lưu lượng thực nghiệm**:
   - Chạy `npx wrangler tail` trong 30 giây để đo đạc số lượng request thực tế gửi lên Cloudflare Worker, xác nhận tần suất đã giảm $\ge 65\%$.
