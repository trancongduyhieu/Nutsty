---
name: peer-clock-offset-min-filter
description: Ước lượng độ lệch đồng hồ giữa host và khách bằng bộ lọc cực tiểu kiểu Cristian/NTP trên các mẫu (giờ khách - stamp của host), rồi dùng nó để tính tuổi thật của now_playing. Dùng khi khách Nghe Cùng luôn lệch cố định vài giây so với host, khi drift correction seek liên tục dù mạng ổn, hoặc khi relay lưu timestamp của client thay vì giờ server.
---

# Giờ của host không phải giờ của khách

Cloudflare D1 relay lưu nguyên `timestamp` mà host tự đóng dấu bằng `Date.now()` của máy host.
Khách tính tuổi bản tin bằng `Date.now() - np.timestamp`, rồi cộng tuổi đó vào `position` để đoán
host đang ở đâu. Hai máy (Linux và Windows, hai cách đồng bộ NTP khác nhau) lệch nhau 2–5 giây là
bình thường. Lệch +3s thì khách luôn đi trước 3s; lệch âm thì tuổi âm, bị kẹp về 0, nên khách luôn
đi sau.

Mỗi mẫu `raw = guest_now - stamp` bằng `offset + delay`, trong đó delay ≥ 0 và biến thiên. Mẫu
nhỏ nhất gần với `offset + delay_min` nhất, nên trừ nó đi sẽ loại được offset:

```js
// adapted: components/social_engine.js
var _hostClock = { key: "", lastStamp: 0, samples: [] };
function hostStampAgeSec(hostKey, stamp, maxSec) {
    var stampMs = Number(stamp) > 1e12 ? Number(stamp) : Number(stamp) * 1000.0;
    if (!(stampMs > 0)) return 0;                          // 0 = không biết, không phải epoch
    var raw = Date.now() - stampMs;
    if (_hostClock.key !== hostKey) _hostClock = { key: hostKey, lastStamp: 0, samples: [] };
    if (stampMs !== _hostClock.lastStamp) {                // một stamp chỉ là MỘT mẫu
        _hostClock.lastStamp = stampMs;
        _hostClock.samples.push(raw);
        if (_hostClock.samples.length > 20) _hostClock.samples.shift();
    }
    var age = raw;
    if (_hostClock.samples.length >= 3) age = raw - Math.min.apply(null, _hostClock.samples);
    var limit = (maxSec > 0 ? maxSec : 600) * 1000;
    return (age > 0 && age < limit) ? age / 1000.0 : 0;
}
```

## Traps

**Poll lại cùng một stamp không phải mẫu mới.** Khách poll mỗi khoảng 1s, còn host chỉ đóng dấu
lại khi có thay đổi (hoặc theo nhịp `syncNowPlaying`). Đọc lại cùng một bản tin 5 lần thì `raw`
tăng dần chỉ vì thời gian trôi. Nếu đẩy cả 5 vào mẫu, giá trị nhỏ nhất bị neo ở lần đọc đầu, mà đó
lại là kết quả đúng. Nhưng mảng 20 mẫu sẽ đầy toàn bản sao của một stamp, và khi stamp đó rời cửa
sổ thì ước lượng nhảy. `lastStamp` đảm bảo mỗi stamp chỉ được đếm một lần.

**Ít mẫu thì đừng tin bộ lọc.** Một mẫu duy nhất cho `age = 0` ngay lập tức, tức là "bản tin vừa
tới", sai bằng đúng delay thật. Dưới 3 mẫu thì dùng `raw` (hành vi cũ), từ 3 mẫu trở lên mới trừ
cực tiểu. Thà lệch một chút ở giây đầu còn hơn seek sai.

**Reset khi đổi host.** Offset là đặc tính của một cặp máy. Chuyển sang nghe cùng một người bạn
khác mà giữ mẫu cũ thì offset của máy cũ áp lên máy mới. Khoá theo `hostKey` (userId, rồi email,
rồi tên) và đổi khoá là xoá sạch mẫu.

**Stamp có thể tính bằng giây hoặc mili-giây.** Python gửi `time.time()` (giây, có phần lẻ), JS
gửi `Date.now()` (ms). Ngưỡng `1e12` phân biệt được hai loại cho tới năm 33658. Trộn nhầm đơn vị
sẽ cho tuổi khoảng 1.7 tỷ giây, và nhánh `limit` kẹp về 0. Kết quả là drift sửa sai mà không có
lỗi nào báo.

**Tuổi chỉ được cộng khi host đang phát.** `if (np.is_playing === true) expectedPos += npAge`. Cộng
cả khi pause sẽ đẩy khách đi tới trong lúc cả phòng đang dừng. Xem
`position-on-every-transport-command`.

**Bộ lọc cực tiểu thua thiết kế có giờ server.** Cách gọn hơn là relay đóng dấu `Date.now()` của
Worker, cả hai bên so với giờ server. Cách đó cần sửa `cloud_relay/src/index.js`, deploy, và chịu
cả hai phiên bản client cùng tồn tại. Bộ lọc này là cách vá phía client không cần đổi giao thức.
Bản Kotlin tương ứng ở `references/kotlin-footguns/skills/monotonic-clock-offset-sync`, bản đó dùng
ping/pong và trọng số.

## Verifying it

```bash
node scripts/test_playback_race.cjs   # "host clock offset is removed from the position estimate"
grep -n "hostStampAgeSec(" components/social_engine.js
grep -n "Date.now() - .*timestamp" components/social_engine.js
```

Bài test cho đồng hồ host chạy trước 7s và delay 0.3–1.5s. Mẫu cuối tới sau stamp 0.9s, nên kỳ
vọng tuổi là 0.9 − 0.3 = 0.6s, chứ không phải khoảng 7.9s. Lệnh thứ hai phải thấy cả drift correction trong `fetchFriendsNotesFast` lẫn
`startListeningAlong`. Lệnh thứ ba phải KHÔNG còn chỗ nào tự tính tuổi bản tin bằng tay ngoài
`hostStampAgeSec`.
