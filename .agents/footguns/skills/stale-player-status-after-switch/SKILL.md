---
name: stale-player-status-after-switch
description: Khi đổi bài, mpv vẫn giữ file cũ (đang pause) trong lúc yt-dlp resolve bài mới, nên mọi status poll trong khoảng đó mô tả bài CŨ. Nhớ path cũ và bỏ qua status mang path đó cho tới khi mpv báo file khác. Dùng khi skip nhanh làm thanh thời gian hiện vị trí bài trước, bài cũ tự phát lại sau khi bấm Next, một lần Next nhảy hai bài, hoặc khách Nghe Cùng bị seek sai chỗ ngay đầu bài.
---

# Status của bài trước đội lốt bài mới

`player_daemon.py play` không thay file ngay. Nó ghi state `"loading"`, pause mpv, gọi yt-dlp
(0.5–3 giây), rồi mới `loadfile`. Trong suốt khoảng đó `/api/player/status` vẫn trả về path,
`time_pos` và `duration` của bài cũ. Tệ hơn, bridge Rust (`nutsty-bridge/src/lib.rs`, hàm đọc
status) sẽ tự hạ state `"loading"` thành `"playing"` hễ thấy mpv có path, không idle và
`time_pos > 0.2`. Bài cũ thoả cả ba điều kiện đó nên cờ loading biến mất trước khi bài mới mở.

Cách chặn: lúc phát lệnh đổi bài thì nhớ path mpv đang giữ, rồi bỏ mọi status mang path đó:

```js
// adapted: components/playback_engine.js
function armStaleStatusGuard(win, prevTrk, nextTrk) {
    if (win.crossfadeArmed) return;                          // crossfade có handover riêng
    if (prevTrk && win.isSameTrack(prevTrk, nextTrk)) return; // phát lại chính bài đó
    var oldPath = win.lastMpvPath || "";
    if (!oldPath || win.lastMpvPathKey === trackKeyOf(nextTrk)) { win.staleStatusPath = ""; return; }
    win.staleStatusPath = oldPath;
}
// trong handlePlayerStatus, trước mọi xử lý khác:
if (win.staleStatusPath) {
    if (s.path === win.staleStatusPath) { /* chỉ còn timeout 25s */ return; }
    if (s.path) win.staleStatusPath = "";
}
if (s.path) { win.lastMpvPath = s.path; win.lastMpvPathKey = trackKeyOf(win.currentTrack); }
```

## Traps

**Một status cũ kéo theo bốn lỗi khác nhau.** Đã chứng minh bằng harness (`test_playback_race.cjs`):
(1) thanh thời gian hiện `120s / 260s` của bài A dưới tiêu đề bài B; (2) cửa sổ post-load grace
thấy `is_paused` mà `isPlaying` đang là true, nên gửi `resume` và bài A lại kêu; (3) nếu skip ở
gần cuối bài A, A chạy tới hết bài và auto-advance bỏ qua luôn B, tức một lần Next nhảy hai bài;
(4) `syncNowPlaying` công bố B ở vị trí 120s cho khách Nghe Cùng. Đừng vá riêng từng triệu chứng:
gốc của cả bốn là một và phải chặn ở cửa vào `handlePlayerStatus`.

**Path, không phải title hay videoId, là danh tính đáng tin của status.** Status của mpv không
có videoId. `filename` của stream YouTube luôn là `videoplayback`, nên không dùng để so được.
Chỉ `path` (URL googlevideo có `id=`, hoặc đường dẫn file local) mới thay đổi khi file đổi. Vì
vậy guard so sánh path, và nhớ thêm path đó thuộc track key nào (`lastMpvPathKey`).

**Quay lại đúng bài mpv đang giữ thì KHÔNG được chặn.** Ví dụ A → B (B chưa mở) → Back về A:
status của A lúc này là status đúng. Nếu guard vẫn bật, UI kẹt ở trạng thái loading mãi. Vì vậy
`lastMpvPathKey === trackKeyOf(nextTrk)` sẽ xoá guard. Bài test "going back to the song mpv
still holds" giữ nhánh này.

**Guard không được nuốt mất timeout "bài không bao giờ mở".** Khi yt-dlp fail, mpv giữ path cũ
mãi mãi và guard không tự nhả. Nhánh return sớm vẫn phải kiểm tra
`Date.now() - trackChangeTimestamp > 25000` để tắt loading. Thiếu kiểm tra đó, một bài lỗi làm
player treo ở spinner vô hạn.

**Crossfade là ngoại lệ có chủ đích.** Khi AutoMix đã nạp bài kế bằng `loadfile append`, path cũ
vẫn là bài đang kêu thật, và `crossfadeHandoverPath` đã lo chuyện bàn giao. Nếu bật cả hai guard
cùng lúc, đồng hồ blend bị chặn và thời gian đứng im.

**Chặn ở cả hai tầng: bridge sửa gốc, JS là lưới an toàn.** Khi gửi request online,
`player_daemon.py play` ghi `prev_mpv_path` (path mpv đang giữ) vào state file. Lúc mpv vẫn báo
đúng path đó, `nutsty_bridge::loading_verdict` giữ `"loading"`, tối đa
`STALE_FILE_LOADING_LIMIT_SEC = 25s`, thay vì nhả sau 5s như trước. Ngay sau `loadfile`, daemon
xoá `prev_mpv_path` (chỉ khi `epoch` trong state file vẫn là của request này). Lý do: stream URL
được cache, nên quay lại đúng bài cũ có thể nạp lại CÙNG một URL, và nếu không xoá thì loading
treo tới 25s. Guard JS vẫn giữ lại vì nó bắt được cả daemon bản cũ (không ghi `prev_mpv_path`)
lẫn khoảng vài ms giữa lúc gửi `loadfile` và lúc mpv thật sự đổi file.

**CLI và daemon phải dùng chung một hàm quyết định.** Trước đây `nutsty-bridge/src/main.rs` có
một bản sao riêng của toàn bộ logic status, trùng với `lib.rs` (mà `nutsty-daemon` dùng). Sửa một
bản thì bản kia vẫn lỗi. Bây giờ `handle_status` của CLI gọi
`nutsty_bridge::get_player_status_output()`. Đừng chép logic ngược trở lại vào `main.rs`.

**Sửa Rust thì phải build lại cả hai nền tảng.** Chạy `cargo build --release -p nutsty-daemon -p
nutsty-bridge`, sau đó build thêm với `--target x86_64-pc-windows-gnu`. Chép vào `bin/` bằng
`cp --remove-destination` (daemon đang chạy sẽ báo "Text file busy"), rồi khởi động lại
`bin/nutsty-daemon`.

**Gán guard TRƯỚC `win.currentTrack = trk`.** `armStaleStatusGuard` đọc `win.currentTrack` làm
bài trước. Gán sau thì bài trước chính là bài mới, `isSameTrack` trả true và guard không bao giờ
bật. Xem `assign-dependents-before-trigger-property`.

## Verifying it

```bash
node scripts/test_playback_race.cjs
(cd nutsty-rs && cargo test -p nutsty-bridge loading_tests)
grep -n "armStaleStatusGuard(win" components/playback_engine.js
grep -n "staleStatusPath" components/playback_engine.js shell.qml
```

Lệnh đầu phải in đủ 4 dòng: "previous song's status is ignored", "one press of Next...",
"going back to the song mpv still holds" và "a song that never opens still times out". Lệnh thứ
hai phải ra đúng 3 chỗ gọi (`playOnlineTrack`, `playTrack`, `triggerRapidTrackSwitch`). Thêm
một đường đổi bài mới (vd. phát từ notification) mà không gọi guard là tái tạo lại lỗi. Lệnh thứ
ba phải thấy property khai báo trong `shell.qml` cùng `lastMpvPathKey`. `loading_tests` (6 test)
giữ phía bridge: file cũ thì vẫn loading (kể cả sau 5s), file mới thì xong, timeout 25s, và state
file của daemon bản cũ (không có `prev_mpv_path`) vẫn chạy như trước.

Kiểm thử với mpv thật mà không đụng tới phiên đang nghe: chạy một mpv riêng với
`--input-ipc-server=$TMP/nutsty_mpv_xtest.sock`, sau đó
`NUTSTY_PROFILE=xtest python3 backend/player_daemon.py play ytdl://<id>`, và poll
`NUTSTY_PROFILE=xtest bin/nutsty-bridge status`. Kết quả đúng là `is_loading: true` khi path vẫn
là file cũ, rồi chuyển sang false đúng lúc path đổi sang URL googlevideo.
