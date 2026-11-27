# Nền ảnh bìa đập theo nhịp bass

## Mục đích

Nền ảnh bìa mờ phía sau cả cửa sổ Nutsty (trang chủ lẫn màn Đang phát, cùng là `components/LiquidWarpBackdrop.qml`)
phồng lên và uốn nhanh hơn trong chốc lát mỗi khi có cú bass, giống "Pulse to the beat" của SimpMusic
(`references/SimpMusic`, `LyricsFlowBackground.kt` và `core/.../player/BassEnvelope.kt`).

## Mục tiêu / Không làm / Không được xảy ra

- Mục tiêu: đập đúng nhịp bass thật của bài đang phát, ở cả Linux (Niri) lẫn Windows.
- Mục tiêu: bài kế tiếp đã được đo sẵn trước khi tới lượt, nên đổi bài là đập ngay.
- Không làm: đập theo giọng hát hay hi-hat; hình sóng nhạc hay thanh phổ.
- Không được xảy ra: làm chậm hay giật giao diện; chen vào chuỗi âm thanh (chế độ "Nguyên bản tuyệt đối" phải
  giữ nguyên); đập lệch nhịp; vẫn đập khi đã tạm dừng.

## Các cách đã cân nhắc

- **A. Đo trước cả bài (đã chọn)**: tiến trình mpv riêng giải mã cả bài ra 8 kHz mono, lưu dãy mức bass vào cache,
  giao diện tra theo vị trí đang phát. Đúng nhịp, nhẹ, giống nhau trên hai hệ điều hành; lần đầu nghe một bài thì
  vài giây đầu chưa đập.
- B. Đo trực tiếp bằng bộ lọc trong mpv: đập ngay từ đầu nhưng đi trước tiếng thật vài trăm ms, phải hỏi qua
  socket 30 lần/giây và chen bộ lọc vào âm thanh.
- C. Chỉ đoán BPM: không theo bass thật, đoạn lặng vẫn đập.

## Thiết kế

**Đo (backend, mới `backend/bass_envelope.py`)**: bê nguyên thuật toán `BassEnvelope` của SimpMusic:
hai bộ lọc thông thấp một cực ở 150 Hz, RMS mỗi 25 ms (40 ô/giây), mức đập
`(mức / mạnh_nhất_trong_±2s − 0.5) / 0.5`, kẹp 0..1, mốc so không dưới 0.15 lần phân vị 95% của cả bài.
Giải mã dùng lại cách của AutoMix (`crossfade_engine.decode_levels`: mpv `--ao=pcm`, 8 kHz, mono, có sẵn trên Windows,
không cần ffmpeg), nhưng cho cả bài và đọc PCM theo từng khúc để không giữ cả bài trong RAM.
Kiểm thử bằng các ca của `BassEnvelopeTest`: cú 60 Hz đập hết cỡ, im lặng sau đó 0, tiếng 2 kHz to ngang
bass 0, kick verse nhỏ bằng 1/4 drop vẫn đập rõ.

**Cache**: `<cache>/bass/<khoá bài>.bass`, mỗi ô một byte (0..255 so với ô mạnh nhất), file rỗng nghĩa là
"đã đo, không dùng được". Giữ tối đa khoảng 500 file, xoá file cũ nhất theo thời gian sửa.

**Khi nào đo**:
- Bài hiện tại: ngay khi bắt đầu phát, nếu chưa có trong cache.
- Bài kế tiếp: khi bài hiện tại phát tới **50%** (theo mẫu `maybePrefetchNextCover` đang làm ở 80%; đo cần
  thời gian hơn tải ảnh). Sửa hàng đợi sau mốc đó thì đo bài kế tiếp mới. Lấy link phát qua `_resolve_for_crossfade`.
- Tối đa một lần đo chạy cùng lúc; bài hiện tại được ưu tiên hơn bài kế tiếp.

**Gửi lên giao diện**: một API local trả dãy byte của bài (khoảng 10 KB cho bài 4 phút). QML giữ dãy đó cho bài
đang phát và tự tra theo vị trí, không hỏi backend mỗi khung hình. Vị trí được nội suy từ `win.currentTime`
cộng thời gian trôi qua kể từ lần cập nhật cuối, khi đang phát.

**Hiển thị (`LiquidWarpBackdrop.qml`)**: thêm `pulse` (0..1). Mỗi khung (tối đa 30 lần/giây):
`pulse = max(mức_tại_vị_trí, pulse · e^(−Δt / 0.14 s))`. Nền phóng to thêm tối đa 7% (`scale`), và thời gian
của sóng uốn chạy nhanh hơn `1 + 3·pulse` lần (đổi `NumberAnimation` của `animTime` sang cập nhật theo khung).

**Cài đặt**: công tắc "Đập theo nhịp bass" / "Pulse to the bass" (qua `I18n.tr`), mặc định tắt, lưu cùng các cài đặt
khác. Tắt thì không đo gì cả.

## Quyết định của mình (mày sửa được)

- Mốc đo trước bài kế tiếp: 50%.
- Không đập (và không đo) khi bật Lite mode, khi tạm dừng, khi cửa sổ bị ẩn, khi Nghe Cùng vẫn đập bình thường.
- **Bài Tidal lossless không đo**: đo phải tải lại cả file FLAC (30–50 MB mỗi bài), gấp đôi dữ liệu. Nền đứng yên
  với những bài này. Bài YouTube và bài trong máy đo bình thường (bài online tải thêm khoảng 3–5 MB).
- Phồng tối đa 7%, tắt dần 140 ms, xoay nhanh tối đa 4 lần: lấy theo số SimpMusic đã thử với người dùng.

## Để người làm tự quyết

Tên API, chỗ đặt hàm tra trong QML, cách đọc PCM theo khúc, tên file kiểm thử.
