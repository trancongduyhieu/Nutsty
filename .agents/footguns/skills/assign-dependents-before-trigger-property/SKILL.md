---
name: assign-dependents-before-trigger-property
description: Trong QML, handler onXChanged chạy ĐỒNG BỘ ngay tại dòng gán X. Mọi state mà listener của X đọc (duration, thời gian, cờ loading) phải được gán TRƯỚC X. Dùng khi lyric hoặc metadata được tra bằng dữ liệu của bài trước, khi một listener thấy giá trị "nửa cũ nửa mới", hoặc khi sắp xếp lại các dòng gán trong hàm đổi bài.
---

# Gán state phụ trước, property kích hoạt sau cùng

`win.currentTrack` là property kích hoạt: nhiều component nghe `onCurrentTrackChanged` (lyric
trong `YTMusicNowPlayingView`, palette trong `shell.qml`, cover, Discord/MPRIS). QML gọi các
handler đó ngay trong câu lệnh gán, trước khi dòng tiếp theo của hàm chạy. Vì vậy thứ tự gán là
một phần của hợp đồng:

```js
// adapted: components/playback_engine.js, playOnlineTrack
armStaleStatusGuard(win, win.currentTrack, trk);   // đọc bài TRƯỚC
win.currentTime = 0.0;
win.totalDuration = initDur > 0 ? initDur : 0.0;   // listener lyric đọc giá trị này
win.isLoadingAudio = !hasLocalFile;
win.currentTrack = trk;                            // handler chạy NGAY ĐÂY
win.isPlaying = true;
```

Lỗi gốc: `totalDuration` được gán sau `currentTrack`. `fetchLyrics` đọc `root.totalDuration` ra
260s (của bài A) và gửi cho `lyrics_helper.py` khi tra bài B dài 200s. Provider khớp lyric theo
độ dài, nên khi skip nhanh nó trả về sai bản hoặc không tìm thấy.

## Traps

**"Sau đó một dòng" vẫn là quá muộn.** Đây không phải race bất đồng bộ nên không có độ trễ nào
cứu được. Handler đã chạy xong từ trước khi dòng kế tiếp bắt đầu. Đọc code tuần tự rất dễ tưởng
là mọi thứ được gán "cùng lúc".

**Listener nên đọc dữ liệu từ chính đối tượng nó nhận, không từ state toàn cục.** Phòng thủ tầng
hai: `fetchLyrics(track)` dùng `PlaybackEngine.extractTrackDuration(track)` trước, chỉ fallback
sang `root.totalDuration` khi track không mang độ dài. Track là thứ đi cùng tín hiệu, còn state
toàn cục có thể vẫn của bài trước.

**Có hơn một đường đổi bài, và tất cả phải theo cùng thứ tự.** `playOnlineTrack`, `playTrack`
(local) và `triggerRapidTrackSwitch` (debounce skip nhanh) đều gán `currentTrack`. Sửa một chỗ
mà quên hai chỗ kia thì lỗi chỉ hiện ở một kiểu skip. Khi thêm đường mới, hãy copy đúng khối thứ
tự này.

**Ngược lại cũng có: state đọc bài TRƯỚC phải chạy trước khi ghi đè.** `armStaleStatusGuard` cần
`win.currentTrack` cũ, nên nó đứng trên cùng. Quy tắc chung: đọc cái cũ → ghi các phụ thuộc →
ghi property kích hoạt → ghi các cờ không ai nghe đồng bộ.

**Binding cũng là listener.** Một `Text { text: formatTime(win.totalDuration) }` cập nhật hai lần
(260 → 200) nếu thứ tự sai, gây chớp số. Không phải lỗi logic, nhưng là cùng một nguyên nhân.

## Verifying it

```bash
node scripts/test_playback_race.cjs   # dòng "lyrics lookup sees the new song's length"
grep -n "win.currentTrack = " components/playback_engine.js
```

Với mỗi dòng grep trả về, đọc khoảng 6 dòng phía trên: `totalDuration`, `currentTime` và
`isLoadingAudio` phải nằm TRÊN dòng gán `currentTrack`. Harness gắn một setter giả lên
`currentTrack` để ghi lại `totalDuration` tại thời điểm gán, đúng như cách QML gọi handler.
