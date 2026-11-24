---
name: position-on-every-transport-command
description: Mỗi lệnh transport Nghe Cùng (play, pause, seek, join, resync) đều mang vị trí, bên nhận chỉ seek khi độ lệch vượt một ngưỡng duy nhất DRIFT_TOLERANCE_SEC, và pause cũng chốt vị trí. Dùng khi sau nhiều lần pause/play host và khách lệch dần, khi khách giật liên tục vì seek theo từng nhịp poll, hoặc khi các ngưỡng drift ở nhiều nơi khác nhau.
---

# Vị trí đi cùng lệnh, không đi theo đồng hồ hẹn giờ

Mỗi máy tự resolve stream của mình, nên "phát" tới mỗi máy ở thời điểm khác nhau. Có thể giữ cả
phòng thẳng hàng mà không bắt ai chờ, nếu có đủ ba thứ:

1. lệnh mang vị trí của host (`listenSyncData(win, position)`);
2. vị trí đó được cộng thêm thời gian bản tin nằm trên đường, chỉ khi host đang phát
   (`peer-clock-offset-min-filter`);
3. bên nhận chỉ seek khi `|local - expected| > DRIFT_TOLERANCE_SEC`.

```js
// adapted: components/social_engine.js, receiver
} else if (ev.event === "pause") {
    var pPos = _eventPositionForMe(win, ev);   // đọc TRƯỚC khi pause xoá isLoadingAudio
    win.isPlaying = false; win.isLoadingAudio = false;
    Quickshell.execDetached([... "player_daemon.py", "pause"]);
    if (pPos >= 0 && Math.abs(win.currentTime - pPos) > 0.3) win.seekLocalOnly(pPos);
}
```

## Traps

**Pause không mang vị trí làm phòng lệch dần theo mỗi lần pause.** Host pause ở 61.2s, khách nhận
lệnh trễ 1.5s và dừng ở 62.7s. Resume sau đó thì cả hai cùng chạy, nhưng lệch 1.5s mãi mãi, và
mỗi lần pause/play cộng thêm một khoảng nữa. Chưa tới ngưỡng drift thì không ai sửa. Vì vậy khi
pause, khách seek về đúng điểm dừng của host (ngưỡng 0.3s, chặt hơn lúc đang phát vì đứng yên thì
seek không gây giật).

**Đọc vị trí trước khi đổi cờ.** Bản đầu tính `pPos` sau `isLoadingAudio = false`, nên
`_eventPositionForMe` coi bài như đã mở và seek vào một bài đang loading. Thứ tự đúng là đọc,
rồi đổi state, rồi hành động. Cùng họ với `assign-dependents-before-trigger-property`.

**Một hằng số cho ngưỡng drift, không phải ba.** Trước khi sửa, code có `3.5` ở drift correction,
`3.0` ở join và không có ngưỡng nào ở play. Ba ngưỡng khác nhau làm hành vi phụ thuộc vào đường
nào chạy trước. Bây giờ tất cả dùng `DRIFT_TOLERANCE_SEC = 2.0`. Giá trị 2.0 là mức chọn nằm giữa
hai giá trị cũ, CHƯA được đo trên hai máy thật. Ngưỡng quá nhỏ thì mỗi lần mpv seek trên stream
(phải rebuffer) lại tự tạo ra drift mới, và phòng seek qua seek lại. Nếu đổi số này, hãy ghi lại
cách đo vào đây.

**Ngưỡng áp dụng khác ngưỡng phát hiện seek.** Host không tự phát hiện seek bằng cách so vị trí:
event `seek` chỉ được gửi từ `seekAudio` khi người dùng tua (`lastSeekTimestamp` chỉ là cửa sổ
grace để bỏ qua `time_pos` cũ sau khi tua). Nếu sau này thêm phát hiện seek theo vị trí, ngưỡng đó
phải LỚN hơn `DRIFT_TOLERANCE_SEC`. Nếu không, mỗi lần khách sửa drift sẽ
trông như một lần seek và được gửi ngược lại. Bản Kotlin gọi đây là vòng lặp ping-pong
(`references/kotlin-footguns/skills/position-based-group-sync`).

**Không broadcast vị trí theo timer.** Giữa các lệnh, mỗi máy tự chạy cùng tốc độ nên không có gì
để sửa. `now_playing` có nhịp làm mới để báo trạng thái, nhưng drift correction chỉ seek khi vượt
ngưỡng, không seek mỗi nhịp.

**Vị trí 0 khi đổi bài phải đi thẳng, không qua cộng tuổi.** Bài mới bắt đầu từ 0. Cộng tuổi bản
tin của lệnh đổi bài thì khách bắt đầu bài ở giây thứ N, mất đoạn đầu. Đường đổi bài dùng
`pendingListenAlongSeekPosition`, và giá trị này chỉ được áp sau khi bài mở xong.

## Verifying it

```bash
grep -n "DRIFT_TOLERANCE_SEC\|> 3\.5\|> 3\.0" components/social_engine.js
grep -n 'ev.event === "\(play\|pause\|seek\)"' components/social_engine.js
node scripts/test_playback_race.cjs
```

Lệnh đầu chỉ được thấy định nghĩa hằng số và các chỗ dùng nó, không còn `3.5` hay `3.0` lẻ. Lệnh
thứ hai là danh sách receiver: mỗi receiver phải gọi `_eventIsForOtherTrack` hoặc
`_eventPositionForMe` trước khi chạm vào mpv. Kiểm thử thật cần 2 profile:
`scripts/run_dual_profile_test.sh`, host pause/play 10 lần liên tiếp, sau đó hai bên phải lệch
dưới 2s.
