# Nutsty Footguns: Catalog

Mỗi dòng: `tên` — bẫy là gì — bằng chứng — triệu chứng người dùng thấy.
Đọc `README.md` để biết cách viết thêm.

---

## A · Đổi bài và trạng thái player (3)

1. `stale-player-status-after-switch` — mpv giữ file cũ trong lúc yt-dlp resolve bài mới; daemon
   ghi `prev_mpv_path`, bridge giữ "loading" tới khi path đổi, JS bỏ status mang path cũ —
   `loading_verdict` (bridge), `armStaleStatusGuard`, `test_playback_race.cjs`, `loading_tests` — thời gian sai sau skip, bài cũ tự phát lại,
   một lần Next nhảy hai bài.
2. `assign-dependents-before-trigger-property` — handler `onXChanged` chạy đồng bộ, nên state phụ
   phải gán trước `currentTrack` — `playOnlineTrack`, `playTrack`, `triggerRapidTrackSwitch` — lyric
   tra bằng độ dài của bài trước nên ra sai bản.
3. `drop-late-async-responses` — request theo bài hiện tại mang token, response lệch token thì bỏ;
   mỗi đường trả kết quả (XHR, Process) có token riêng — `shell.qml` (`paletteRequestUrl`,
   `songPaletteProc.forUrl`) — màu accent hoặc cover của bài trước đè lên bài sau.

## B · Nghe Cùng (Listen Along) (3)

4. `sync-events-carry-track-identity` — play/pause/seek mang videoId, event khác bài thì bỏ, event
   của bản cũ không có id vẫn nhận — `listenSyncData`, `_eventIsForOtherTrack` — khách bị seek hoặc
   pause sai ngay sau khi host đổi bài.
5. `position-on-every-transport-command` — mọi lệnh mang vị trí, pause chốt vị trí, một hằng số
   `DRIFT_TOLERANCE_SEC` — receiver trong `social_engine.js` — phòng lệch dần sau mỗi lần pause/play,
   khách giật vì seek liên tục.
6. `peer-clock-offset-min-filter` — relay lưu giờ của host, khách trừ offset bằng bộ lọc cực tiểu
   kiểu Cristian/NTP — `hostStampAgeSec`, test clock skew 7s — khách luôn lệch cố định vài giây
   giữa Linux và Windows.

## C · Kiểm thử và chứng minh (1)

7. `prove-races-with-fake-clock-harness` — nạp nguyên engine JS vào `node vm` với `Date.now` giả và
   status mpv thật; chứng minh trước, sửa sau — `scripts/test_playback_race.cjs` — lỗi kiểu "skip
   nhanh thì đôi khi sai" không tái hiện được bằng tay.

---

## Đối chiếu với SimpMusic (`references/kotlin-footguns/skills/`)

| Nutsty | SimpMusic tương ứng | Khác biệt |
| :--- | :--- | :--- |
| `peer-clock-offset-min-filter` | `monotonic-clock-offset-sync` | SimpMusic có ping/pong nên trừ được thời gian xử lý của peer; Nutsty chỉ có stamp một chiều qua relay HTTP. |
| `position-on-every-transport-command` | `position-based-group-sync` | Cùng ba thành phần; Nutsty thêm việc pause chốt vị trí. |
| `sync-events-carry-track-identity` | `sync-room-bridge-echo-guard` | SimpMusic chặn tiếng vọng (echo); Nutsty chặn lệnh áp nhầm bài. |
| `stale-player-status-after-switch` | `queue-rebuild-state-machine` | Cùng ý: state trung gian lúc đổi item phải tường minh. |

## Ứng viên chưa viết (cần chứng minh trước)

- Cover art race khi `currentResolvedCover` về muộn (chưa có harness).
- `lyricsProc`: dòng stdout đã nằm trong buffer có còn được giao sau `running = false` không.
