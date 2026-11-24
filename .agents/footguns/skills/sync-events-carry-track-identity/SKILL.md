---
name: sync-events-carry-track-identity
description: Sự kiện Nghe Cùng (play, pause, seek) phải mang videoId của bài nó được gửi cho, và bên nhận bỏ qua sự kiện thuộc bài khác. Dùng khi khách bị seek hoặc pause ngay sau khi host đổi bài, khi vị trí seek của bài trước rơi vào bài mới, hoặc khi thêm một loại event điều khiển mới vào social_engine.js.
---

# Một lệnh không nói nó dành cho bài nào sẽ áp nhầm bài

Event Nghe Cùng đi qua relay HTTP (`/api/notes/events`) và được poll, nên tới khách trễ 1–3 giây
và không theo thứ tự với `now_playing`. Host seek bài A tới 95s rồi bấm Next sang B. Khách thường
nhận `now_playing` (B) trước, sau đó mới nhận `seek 95`, và áp lệnh đó vào B. Cách chữa là mỗi
event tự khai nó thuộc bài nào:

```js
// adapted: components/playback_engine.js (bên gửi)
function listenSyncData(win, position) {
    return { videoId: extractTrackVideoId(win.currentTrack) || "", position: Number(position) || 0 };
}
win.sendSocialEventFast("seek", target, listenSyncData(win, sec));

// adapted: components/social_engine.js (bên nhận)
function _eventIsForOtherTrack(win, ev) {
    var evVid = ev.data && ev.data.videoId ? String(ev.data.videoId).replace(/^yt_/, "") : "";
    var myVid = _vidOf(win.currentTrack);
    return Boolean(evVid && myVid && evVid !== myVid);
}
```

## Traps

**Bản cũ không gửi videoId thì vẫn phải được chấp nhận.** Chuỗi rỗng nghĩa là "không biết",
không phải "bài khác". `_eventIsForOtherTrack` chỉ trả true khi CẢ HAI bên đều có videoId và
chúng khác nhau. Nếu từ chối event không có id, người dùng bản cũ (nhất là bản Windows build từ
trước) mất toàn bộ điều khiển Nghe Cùng mà không có lỗi nào hiện ra.

**Có id nhưng vị trí vẫn chưa chắc dùng được.** `_eventPositionForMe` trả -1 (tức không seek) khi
event không có videoId (không xác minh được vị trí thuộc bài nào), khi thuộc bài khác, hoặc khi
khách đang `isLoadingAudio`. Seek vào một bài chưa mở thì mpv bỏ qua, hoặc tệ hơn là seek nhầm
file cũ (xem `stale-player-status-after-switch`). Khi đang loading, vị trí đi qua
`pendingListenAlongSeekPosition`.

**Chuẩn hoá id ở cả hai đầu.** Track online có id dạng `yt_XXXX`, `videoId` thô, hoặc
`path: ytdl://XXXX`. `_vidOf` gom cả ba và bỏ tiền tố `yt_`. So sánh id thô thì cùng một bài
cũng bị coi là "bài khác" và lệnh bị bỏ một cách âm thầm.

**Mọi nơi gửi event đều phải dùng helper.** Các điểm gửi gồm `togglePlay`, `seekAudio`, handler
join, `_forceResyncUnauthorizedGuest` và `hostFollowupSyncTimer` trong `shell.qml`. Một chỗ còn
gửi `null` thì chỗ đó lại thành lỗ hổng. Giữ một helper duy nhất mỗi engine; JS QML không import
chéo được nên hai bản nằm ở hai file, cùng một hình dạng `{videoId, position}`.

**Event khác bài thì bỏ, đừng "chuyển bài theo".** Việc chuyển bài là của `now_playing` (có đủ
title, artist, cover). Event play/pause/seek chỉ là chỉ thị transport. Để event tự đổi bài sẽ tạo
hai nguồn sự thật đua nhau.

## Verifying it

```bash
node scripts/test_playback_race.cjs   # dòng "Listen Along events name their song"
grep -n 'sendSocialEventFast("\(play\|pause\|seek\)' components/*.js shell.qml
grep -n 'sendSocialEventFast(win.isPlaying' components/*.js shell.qml
```

Mọi dòng grep phải truyền `listenSyncData(...)` làm đối số thứ ba. Một dòng truyền `null`, `{}`
hoặc thiếu đối số là một đường gửi chưa được vá. `togglePlay` gửi qua biến
(`sendSocialEventFast(evType, ..., evData)`) nên grep trên không bắt được; chạy thêm
`grep -n "evData" components/playback_engine.js` và kiểm tra `evData = listenSyncData(...)`.
