# Audio Backend, IPC & Queue Lifecycle Specification

Daemon phát nhạc, IPC mpv, YouTube Music engine và vòng đời hàng đợi.

## 1. Backend Daemon & Giao Thức IPC MPV
- **Tiến trình**: `backend/player_daemon.py` quản lý một instance `mpv` thường trú.
- **Giao tiếp**: Unix Domain Socket tại `/tmp/nutsty_mpv.sock`.
- **Tính năng âm thanh**:
  - Gapless, giải mã phần cứng.
  - Hook `yt-dlp` (`--ytdl-format="bestaudio"`) stream YouTube Music trực tiếp.
  - **Tránh HTTP 403 CDN & Autoplay tức thì**: `resolve_stream_url()` dùng `player_client: ["android"]` (không ép cookie web vào direct googlevideo URL). MPV thêm `--referrer=https://www.youtube.com/`, `--audio-buffer=0.4` để mở stream ~1 s.
- **Quy tắc**: mọi lệnh tới mpv đi qua socket IPC JSON, không dùng stdin/stdout.

## 2. YouTube Music Streaming (4 module + facade `ytmusic_helper.py`)
- `stream_resolver.py` (stream android, chặn 403), `catalog_engine.py` (shelves + continuation cho >10 mood), `song_enrichment.py` (metadata, lyrics, related), `ytmusic_auth.py` (OAuth/cookie).
## 3. Phân Lập Luồng Duyệt (Browsing) & Hàng Đợi Phát Nhạc (Playback Queue)
- **Hai thuộc tính độc lập tại `shell.qml`**:
  - `win.browsingTracks`: Danh sách bài hát đang hiển thị trên giao diện duyệt (kết quả tìm kiếm, tab Downloads, danh sách bài của album/nghệ sĩ).
  - `win.currentTracks`: Hàng đợi phát nhạc thực sự (Queue).
- **Nguyên tắc**: duyệt playlist, tìm kiếm, mở tab Tải xuống **không ghi đè** `win.currentTracks`; chỉ bấm phát bài mới đổi.

## 4. Tách Bạch Browsing Title & Playing Source Title
- **Ràng buộc cốt lõi**:
  - `win.mainSectionTitle`: Tiêu đề phục vụ giao diện duyệt (browsing UI).
  - `win.playingSourceTitle`: Nguồn gốc thực tế của bài hát đang phát (album, playlist, artist hoặc queue).
- **Mục đích**: nghe Album A mà mở xem Album B không làm đổi nguồn; `playingSourceTitle` chỉ gán khi thực sự phát nguồn mới.

## 5. Cơ Chế Snapshot & Reset Queue An Toàn Khi Chuyển Mood Chips
- **Tệp**: `shell.qml`, `components/YTMusicNowPlayingView.qml`. Bài/album mới (`!isAlreadyInQueue` hoặc `playingPlaylistTitle` đổi) reset `originalAlbumQueue = []`, `selectedMoodIndex = 0`; ở tab "Tất cả" nó bám theo `queueTracks`.
- **Đổi mood**: `loadQueueForChipIndex` snapshot danh sách mood 0 vào `originalAlbumQueue` trước khi nạp radio; quay lại index 0 thì khôi phục vào `win.currentTracks` + `queueUpdated`, không gọi API. `moodChipsProc` không tự gọi khi đang phát album/playlist.

## 6. Download Manager Daemon
- `backend/download_manager.py` thường trú, socket `/tmp/nutsty_download.sock`, trạng thái atomic JSON `/tmp/frostify_download_status.json`. Tải 192k AAC/M4A qua `yt-dlp`, nhúng tag + bìa, kèm `.lrc` vào `~/Music/Downloads_Phone`.
- UI: `DownloadManager.qml` (`FileView` + timer 250ms), `DownloadQueuePopover.qml`.
## 7. Kiến Trúc Modular Social & Music Engine (3 SSOT Chuẩn Hóa)
- **Backend Modular**: `backend/auth_server.py` điều phối sang `backend/music_routes.py` và `backend/social_routes.py`. Toàn bộ logic mạng xã hội tập trung tại Deep Module `backend/social_relay_core.py` (caching, danh tính SSOT #2, phân phối event).
- **Frontend Engines**: `components/social_engine.js` (Listen Along, bạn bè, Danmaku) và `components/playback_engine.js` (toàn bộ vòng đời phát nhạc, mutate queue, reconcile MPV status).
- **3 Single Sources of Truth (SSOT)**:
  1. **SSOT #1 (Config Path)**: `platform_compat.get_config_dir()` trả về `~/.config/noctalia` đồng nhất trên Linux & Windows.
  2. **SSOT #2 (Canonical Identity)**: `social_relay_core.get_caller_identity()` lấy định danh chuẩn từ `nutsty_cloud_identity.json`.
  3. **SSOT #3 (Peer Normalization)**: `SocialEngine.normalizePeer(raw)` chuẩn hóa mọi peer về `{ user_id, tag, email, name, avatar, is_online }`.

## 8. Friends 24h Notes, Listen Along & PlaybackEngine Consolidate
- **PlaybackEngine (`components/playback_engine.js`)**: Tập trung toàn bộ logic `playOnlineTrack`, `playTrack`, `togglePlay`, `playNext`, `seekAudio`, `handlePlayerStatus` (bù trôi, sleep timer, auto-advance). `shell.qml` chỉ giữ 1-line delegates.
- **Đồng bộ 2 chiều**: FIFO `/api/notes/events` (`join`, `leave`, `play`, `pause`, `seek`, `chat_message`) < 50ms. Drift: `expectedPos = np.position + elapsed`, nắn khi lệch > 2.0s.
- **Bẫy lỗi**: Host khi pause vẫn phải gửi `now_playing` kèm `is_playing: false` thay vì `null`. Cờ `isSyncingFromFriend` chặn loop phản hồi ngược. **Sự kiện kèm bài**: `play`/`pause`/`seek` gửi `listenSyncData` = `{videoId, position}`; khách bỏ qua sự kiện của bài khác (`_eventIsForOtherTrack`), pause dừng đúng vị trí host. Giờ host lệch giờ khách: `hostStampAgeSec` trừ độ lệch nhỏ nhất của 20 mẫu gần nhất (lọc min kiểu NTP).
- **Footgun đổi bài**: mpv còn giữ bài cũ (đang pause) suốt lúc yt-dlp resolve bài mới, daemon ghi `prev_mpv_path`, bridge (`loading_verdict`) giữ loading tới khi path đổi; JS `armStaleStatusGuard` ghi `staleStatusPath`, `handlePlayerStatus` bỏ qua status của đường dẫn đó cho tới khi mpv mở file khác. Gán `totalDuration` **trước** `currentTrack` (lyric đọc đồng bộ). Test: `node scripts/test_playback_race.cjs`, `cargo test -p nutsty-bridge loading_tests`. Chi tiết: `.agents/footguns/`.

## 9. Lưu Trữ Cài Đặt (`nutsty_settings.json`) & Hiện Diện Thời Gian Thực (Presence)
- **Cài đặt (`~/.config/noctalia/nutsty_settings.json`)**: `shell.qml` nạp qua `FileView` + timer `delayedSettingsRead` (100ms). Nút Shuffle/Repeat chỉ phát signal `toggleShuffle()` / `toggleRepeat()` để `shell.qml` xử lý và gọi `saveSettings()`.
- **Presence & Liveness**: Cloudflare Edge Worker & local daemon áp dụng ngưỡng 25s (`ONLINE_THRESHOLD_MS = 25000`). Khi thoát app, `shell.qml` gọi `sendOfflineSignal()` tới `/api/users/offline` để xóa `now_playing` và đặt `last_active_at = 0` tức thì.

## 10. Spotify Embed Importer & 0-Friction Session Cache
- **Embed không cần Token**: `backend/spotify_importer.py` đọc JSON `__NEXT_DATA__` từ `open.spotify.com/embed/playlist/{id}`, không dính 429, <0.5s. Auto-sync kiểm session trong `nutsty_settings.json` / `ytmusic_auth.json` trước khi mở browser.

## 11. Warm Python Worker Pool (`nutsty-daemon` → `route_dispatcher.py --serve`)
- **Tệp**: `nutsty-rs/crates/nutsty-daemon/src/main.rs` (`WorkerPool`), `backend/route_dispatcher.py` (`serve`). Daemon xử lý mỗi request trên 1 thread, giữ 2 worker Python sống (1 dòng JSON vào / 1 dòng ra); cache hit ~1 ms thay vì ~0,8 s spawn + import `ytmusicapi`.
- **Vòng đời**: worker 0 prewarm lúc daemon bật; tự thoát khi rảnh 10 phút, sau 500 request, hoặc khi có `backend/*.py` mới hơn lúc nạp (sửa code / updater) → spawn lại lười. Cả 2 bận > 400 ms → fallback one-shot cũ.
- **Footgun**: `/api/update*`, `/api/check_update`, `/api/spotify*` giữ tiến trình trong RAM nên **luôn pin worker 0**. Cache trong module phải chịu được nhiều tiến trình (auth status theo mtime `AUTH_FILE`, `online_tracks` reload theo mtime + merge khi ghi). Handler `print()` đi stderr; stdout là kênh trả lời.
- **Social fast path** (`social.rs`, `ureq`): notes, events, friends, now_playing gọi thẳng relay, không giữ worker Python.
- **Footgun**: `try_handle` trả `None` → Python xử lý (chưa có identity, cần sync tên/avatar, 401, events cục bộ, `/api/notes` lỗi mạng). Sửa route/identity ở Python phải sửa cả `social.rs`.

## 12. Cập Nhật Delta (`backend/update_delta.py`, `updater.py`, `components/UpdateModal.qml`)
- **Cơ chế**: Windows đọc central directory của zip release qua HTTP Range (CRC32 + size = manifest), chỉ tải tệp khác bản đang cài, kiểm CRC, tệp staged đúng thì bỏ qua (resume). Không có Range thì tải nguyên zip.
- **Delta**: chỉ Windows (~40 MB thay vì ~381 MB); Linux tải nguyên gói. MB chỉ hiện khi đã biết (`sizeKnown`), chưa biết thì Odometer quay.
- **API**: `/api/update/plan` (`planning`→`planned`), `/start`, `/cancel`, `/status`. UI: `UpdateModal.qml`, state ở `shell.qml` `updateState`.
- **UI**: `UpdateModal.qml` không bật/tắt đột ngột: opacity + Behavior (OutExpo), `FadeText`, thời lượng nhân `root.motion`. Demo: `open_settings?mock=1`.
- **Footgun**: CI phải ghim mpv (mpv đổi = ~97 MB mỗi bản). Suffix Range `bytes=-N` bị CDN GitHub từ chối (501), luôn dùng khoảng tuyệt đối. `.source`/`*.part` bị loại khi robocopy. Chạy `scripts/test_update_delta.py`.

## 13. Tidal Lossless (`backend/tidal_source.py`, `audio_output.py`, `lossless_logic.js`)
- **Resolve** (`resolve_media_path`): file đã tải > Tidal (bật, đã đăng nhập, không tạm tắt) > YouTube. Tidal lỗi/None/quá 4s → YouTube; epoch cũ bỏ kết quả. Nguồn thật ghi ở `now_source.json`.
- **Nghe Cùng**: `lossless_suspend 1` tạo cờ, đang phát Tidal thì nạp YouTube đúng vị trí; `0` chỉ xóa cờ. Chỉ tài khoản của chính người dùng, không log token, session chmod 600.
- **Nhãn**: `build_audio_specs` (Python) = `nutsty-bridge/src/audio_specs.rs`; không biết thì để trống, cấm bịa mặc định.
- **DAC**: không cần Tidal; lưu thiếu `dacModeStandalone` chỉ tính khi lossless bật. `exclusive` (Windows) restart mpv giữ vị trí, khóa AutoMix + âm lượng 100, ao lỗi → `shared` + toast. `rate_match` (Linux) chỉ ghi `90-nutsty-rates.conf` khi người dùng đồng ý, không đè `allowed-rates` có sẵn.
- **Footgun**: link FLAC/MPD hết hạn giữa bài → `stream_failed <pos>` nạp YouTube đúng vị trí, bỏ Tidal bài đó một lúc (`TIDAL_SKIP_FILE`). Test: `scripts/test_lossless_resolve.py`.
