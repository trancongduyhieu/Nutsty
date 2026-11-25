<div align="center">

# Nutsty

**Trình phát nhạc cho máy tính, chạy trên Linux Wayland và Windows**

*A desktop music player for Linux Wayland and Windows*

![Phiên bản](https://img.shields.io/badge/version-2.5.0-gold?style=flat-square)
![Nền tảng](https://img.shields.io/badge/platform-Linux%20Wayland%20%7C%20Windows-blue?style=flat-square)
![Giao diện](https://img.shields.io/badge/UI-Qt%206%20%2F%20Quickshell-41CD52?style=flat-square)

</div>

Nutsty phát nhạc trong thư mục Nhạc của máy bạn và nghe trực tuyến từ YouTube Music, không quảng cáo, không cần trả phí. Bạn có thể nghe cùng bạn bè ở máy khác (Linux với Windows vẫn được), đưa lời bài hát ra màn hình nền, đồng bộ danh sách phát giữa các máy, và nếu có gói Tidal nghe được lossless thì phát bản FLAC bằng chính tài khoản Tidal của bạn. Màu giao diện lấy theo hình nền và ảnh bìa bài đang phát. Giao diện có tiếng Việt và tiếng Anh.

Xem những gì mới ở từng bản trong [CHANGELOG.md](CHANGELOG.md).

---

## Tính năng

### Nghe nhạc trực tuyến (YouTube Music)
- Trang chủ có lời chào, hàng ghi chú của bạn bè, mục "Của bạn" (bài yêu thích, đã tải, danh sách phát) và các kệ nhạc theo thể loại.
- Tìm bài, nghệ sĩ, album. Đăng nhập tài khoản Google để có gợi ý riêng, lịch sử nghe và bình luận YouTube ngay trong app.
- Chọn chất lượng phát và chất lượng tải về. Tải bài về máy để nghe khi không có mạng.
- Chuyển bài mượt (bài cũ nhỏ dần, bài mới to dần) và Tự động hòa trộn (tự chọn lúc chuyển, bỏ đoạn im lặng đầu và cuối bài).
- Lặp lại ba chế độ, phát ngẫu nhiên không lặp bài, hẹn giờ ngủ có nhạc nhỏ dần trước khi tắt.
- Nhập danh sách phát từ Spotify bằng link.

### Thư viện trên máy
- Tự quét thư mục `~/Music` (Linux) hoặc thư mục Music trong tài khoản Windows.
- Danh sách phát tự tạo, có bảng sửa riêng, tự tạo ảnh bìa với tên danh sách.
- Xuất toàn bộ danh sách phát, bài yêu thích và bài đã tải ra một file để chuyển sang máy khác; nhập lại chỉ thêm vào, không xóa gì.
- Trang hồ sơ, thẻ người nghe, thống kê cả năm và tổng kết tháng. Số liệu chỉ nằm trên máy bạn.

### Lời bài hát
- Lời chạy theo từng từ trong bảng bên phải và màn hình Đang phát.
- Lời bài hát trên màn hình nền với 8 mẫu: Điện ảnh Serif, Apple Music, Tối giản lướt, Đồ họa chuyển động, Biểu cảm Mochy, Biến hóa chuyển động, Sân khấu chữ và Sân khấu chữ tối đa. Mỗi mẫu xem trước được ngay trên thẻ chọn.
- Chọn nguồn lời trong Cài đặt (có 9 nguồn, ví dụ Apple Music, SimpMusic, KuGou, Spotify, phụ đề YouTube).

### Nghe Cùng và bạn bè
- Nghe Cùng: hai máy phát cùng một bài, cùng một chỗ, dù một bên dùng Linux và một bên dùng Windows.
- Mời bạn nghe cùng, gửi bong bóng chat bay qua màn hình khi đang nghe.
- Ghi chú 24 giờ kèm một bài hát, xem bạn bè đang nghe gì.

### Đồng bộ giữa các máy
- Danh sách phát, bài đã thích và lịch sử nghe giống nhau trên mọi máy dùng chung một tài khoản Nutsty.
- Nối máy mới: Cài đặt, mục "Đồng bộ giữa các máy", bấm "Thêm máy" trên máy cũ để lấy mã 6 chữ, rồi "Nhập mã" trên máy mới. Mã dùng một lần, hết hạn sau 10 phút.
- Tắt đồng bộ trên một máy, hoặc tách máy ra thành tài khoản riêng bất cứ lúc nào.
- Mở app ở máy khác thì có thể nghe tiếp bài đang dở đúng chỗ đã dừng.

### Lossless qua Tidal (từ bản 2.5.0)
- Dùng **tài khoản Tidal của chính bạn**. Vào Cài đặt, tab Phát nhạc, mục "Lossless (Tidal)", đăng nhập rồi bật lên.
- Bài có trên Tidal phát bản FLAC (16-bit, hoặc Hi-Res nếu gói của bạn có). Bài không có trên Tidal vẫn phát bản YouTube như cũ.
- **Gói Tidal miễn phí không có lossless**, nên với gói này Nutsty vẫn phát YouTube bình thường.
- Mỗi bài lossless tốn khoảng 30-50 MB dữ liệu thay vì 3-5 MB. Khi Nghe Cùng, Nutsty tạm phát bản YouTube để hai bên khớp nhau.
- Thanh phát ghi đúng chất lượng của bản đang phát (ví dụ FLAC 24-bit 96 kHz hay AAC).

### Đưa âm thanh tới DAC (từ bản 2.5.0)
Cũng trong mục Lossless, chọn một trong các cách sau. Các chế độ này dùng được cả khi không bật Tidal, nên nhạc FLAC trong thư viện máy cũng được phát đúng chất lượng gốc.

| Chế độ | Có trên | Nghĩa là gì |
| :--- | :--- | :--- |
| Qua hệ thống | Linux, Windows | Âm thanh đi qua bộ trộn của máy như mọi app khác. Giữ đủ tính năng. |
| Đúng tần số gốc | Linux | DAC nhận đúng tần số của từng bài, vẫn giữ Tự động hòa trộn. Nutsty hỏi trước khi đổi cài đặt âm thanh của máy và không đè lên cài đặt bạn đã tự chỉnh. |
| Nguyên bản tuyệt đối | Windows | Âm thanh đi thẳng tới DAC không qua xử lý nào. Đổi lại: Tự động hòa trộn tắt, âm lượng trong app cố định 100%, app khác không phát tiếng qua DAC được. Nếu DAC không nhận, Nutsty tự quay về "Qua hệ thống" và báo cho bạn. |

### Giao diện
- Màu nhấn lấy từ hình nền và ảnh bìa (thuật toán OKLAB / OKLCH), đổi theo bài đang phát.
- Chế độ nhẹ cho máy không có card đồ họa: tắt bớt hiệu ứng để máy mát và mượt hơn.
- Khi đóng cửa sổ: chọn hiện trình phát nhỏ trên màn hình nền hoặc chỉ phát nhạc nền. Có biểu tượng ở khay hệ thống.
- Trung tâm thông báo xem lại các thông báo đã qua.
- Phím tắt: <kbd>Space</kbd> để phát / tạm dừng (khi không gõ chữ trong ô nhập).

---

## Cài đặt và chạy

### Linux (Wayland, thử chính trên Niri / CachyOS)

Cần có:
- `quickshell` (Nutsty chạy giao diện qua `/usr/bin/quickshell`)
- `python3` 3.10 trở lên và `pip`
- `mpv`
- `ffmpeg` (nên có, dùng khi tải nhạc về)
- `cargo` chỉ cần khi thư mục `bin/` thiếu các chương trình Rust dựng sẵn; `run.sh` sẽ tự dựng chúng

```bash
git clone https://github.com/trancongduyhieu/Nutsty.git
```

```bash
cd Nutsty
```

```bash
./run.sh
```

`run.sh` tự cài các gói Python còn thiếu, chạy dịch vụ nền, quét thư viện nhạc lần đầu rồi mở cửa sổ. Chạy lại khi Nutsty đang mở thì cửa sổ được đưa lên trước. Hai tùy chọn thêm:
- `./run.sh --restart`: tắt giao diện đang chạy rồi mở lại (ví dụ sau khi `git pull`; `run.sh` cũng tự làm vậy khi thấy mã nguồn đã đổi).
- `./run.sh --rescan`: quét lại thư viện nhạc.

Nếu vẫn thiếu gói Python, cài đủ bằng `pip install -r requirements.txt`.

### Windows 10 / 11

Cần có:
- Python 3.10 trở lên (khi cài nhớ tích "Add Python to PATH")
- `mpv`: đặt `mpv.exe` (kèm các DLL) vào thư mục `bin/`, hoặc cài để có trong PATH. Có thể đặt thêm `ffmpeg.exe`, `ffprobe.exe`, `yt-dlp.exe` vào `bin/`; Nutsty ưu tiên các file ở đây. Tải nhạc vẫn chạy khi không có `ffmpeg`.

Bấm đúp `start.bat`, hoặc chạy:

```bat
start.bat
```

Lần đầu, `start.bat` tạo môi trường Python riêng (`venv`) và cài các gói trong `requirements_win.txt`, rồi mở Nutsty qua `launcher_win.py`. Khi danh sách gói đổi, lần chạy sau tự cài lại.

Đóng gói thành bản chạy độc lập `Nutsty.exe` (dùng PyInstaller):

```bat
build_exe.bat
```

Bản Windows tự cập nhật trong app và chỉ tải những tệp thật sự thay đổi.

### Dữ liệu của bạn nằm ở đâu
Cài đặt và dữ liệu người dùng nằm trong thư mục cấu hình riêng (trên Linux là `~/.config/noctalia`), ngoài thư mục cài đặt, nên cài lại Nutsty không mất gì.

---

## Cấu trúc thư mục

```
Nutsty/
├── run.sh / start.bat       # Chạy trên Linux / Windows
├── launcher_win.py          # Điểm khởi động trên Windows (PySide6, khay hệ thống)
├── build_exe.bat            # Đóng gói Nutsty.exe cho Windows
├── shell.qml                # Cửa sổ chính (QML)
├── components/              # Các phần giao diện QML và logic JS
├── compat/Quickshell/       # Lớp thay thế Quickshell để chạy QML trên Windows
├── backend/                 # Python: phát nhạc (mpv), YouTube Music, Tidal, thư viện, lời, tải nhạc, đồng bộ
├── nutsty-rs/               # Rust: dịch vụ nền, quét thư viện, khay hệ thống
├── bin/                     # Chương trình dựng sẵn (và mpv/ffmpeg trên Windows nếu có)
├── cloud_relay/             # Máy chủ bạn bè và Nghe Cùng (Cloudflare Workers + D1)
├── scripts/                 # Kiểm tra và test
├── assets/                  # Font, biểu tượng SVG
└── docs/                    # Ghi chép thiết kế và quyết định kỹ thuật
```

Chi tiết kiến trúc và quy tắc viết code ở [AGENTS.md](AGENTS.md).

---

## Kiểm tra trước khi gửi thay đổi

```bash
python scripts/verify_codebase.py
```

```bash
python scripts/verify_qml_compat.py
```

- `verify_codebase.py` (dưới 1 giây): biên dịch thử mọi file Python, bắt tên biến chưa khai báo và kiểm tra các ràng buộc giữa QML và JS.
- `verify_qml_compat.py` (khoảng 2 giây): nạp toàn bộ QML qua lớp `compat/` để bắt những gì Quickshell có mà bản Windows còn thiếu.

Cả hai cũng chạy tự động trên GitHub mỗi lần đẩy code. Các test riêng cho từng phần nằm trong `scripts/test_*`.

---

## Báo lỗi và góp ý

Lỗi, ý tưởng và lộ trình được theo dõi ở [GitHub Issues](https://github.com/trancongduyhieu/Nutsty/issues).
