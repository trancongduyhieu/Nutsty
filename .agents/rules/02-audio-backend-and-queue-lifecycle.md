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
## 3. Duyệt ≠ Hàng Đợi, Tiêu Đề Duyệt ≠ Nguồn Phát (`shell.qml`)
- `win.browsingTracks` (đang xem) tách khỏi `win.currentTracks` (hàng đợi thật); `win.mainSectionTitle` (đang xem) tách khỏi `win.playingSourceTitle` (đang phát). Duyệt, tìm kiếm, mở tab Tải xuống không ghi đè hàng đợi hay nguồn; chỉ bấm phát mới đổi.

## 5. Cơ Chế Snapshot & Reset Queue An Toàn Khi Chuyển Mood Chips
- **Tệp**: `shell.qml`, `components/YTMusicNowPlayingView.qml`. Bài/album mới (`!isAlreadyInQueue` hoặc `playingPlaylistTitle` đổi) reset `originalAlbumQueue = []`, `selectedMoodIndex = 0`; ở tab "Tất cả" nó bám theo `queueTracks`.
- **Đổi mood**: `loadQueueForChipIndex` snapshot danh sách mood 0 vào `originalAlbumQueue` trước khi nạp radio; quay lại index 0 thì khôi phục vào `win.currentTracks` + `queueUpdated`, không gọi API. `moodChipsProc` không tự gọi khi đang phát album/playlist.

## 6. Download Manager Daemon
- `backend/download_manager.py` thường trú, socket `/tmp/nutsty_download.sock`, trạng thái atomic JSON `/tmp/frostify_download_status.json`. Tải 192k AAC/M4A qua `yt-dlp`, nhúng tag + bìa, kèm `.lrc` vào `~/Music/Downloads_Phone`.
- UI: `DownloadManager.qml` (`FileView` + timer 250ms), `DownloadQueuePopover.qml`.
## 7. Modular Social & Music Engine (3 SSOT)
- `auth_server.py` → `music_routes.py` / `social_routes.py`; logic xã hội ở Deep Module `social_relay_core.py`. Frontend: `social_engine.js` (Listen Along, bạn bè, Danmaku), `playback_engine.js` (vòng đời phát, queue, MPV status).
- **SSOT**: #1 `platform_compat.get_config_dir()` = `~/.config/noctalia` mọi OS; #2 `social_relay_core.get_caller_identity()` từ `nutsty_cloud_identity.json`; #3 `SocialEngine.normalizePeer(raw)` → `{ user_id, tag, email, name, avatar, is_online }`.

## 8. Friends 24h Notes, Listen Along & PlaybackEngine Consolidate
- **PlaybackEngine (`components/playback_engine.js`)**: Tập trung toàn bộ logic `playOnlineTrack`, `playTrack`, `togglePlay`, `playNext`, `seekAudio`, `handlePlayerStatus` (bù trôi, sleep timer, auto-advance). `shell.qml` chỉ giữ 1-line delegates.
- **Đồng bộ 2 chiều**: FIFO `/api/notes/events` (`join`, `leave`, `play`, `pause`, `seek`, `chat_message`) < 50ms. Drift: `expectedPos = np.position + elapsed`, nắn khi lệch > 2.0s.
- **Bẫy lỗi**: Host khi pause vẫn phải gửi `now_playing` kèm `is_playing: false` thay vì `null`. Cờ `isSyncingFromFriend` chặn loop phản hồi ngược. **Sự kiện kèm bài**: `play`/`pause`/`seek` gửi `listenSyncData` = `{videoId, position}`; khách bỏ qua sự kiện của bài khác (`_eventIsForOtherTrack`), pause dừng đúng vị trí host. Giờ host lệch giờ khách: `hostStampAgeSec` trừ độ lệch nhỏ nhất của 20 mẫu gần nhất (lọc min kiểu NTP).
- **Footgun đổi bài**: mpv còn giữ bài cũ (đang pause) suốt lúc yt-dlp resolve bài mới, daemon ghi `prev_mpv_path`, bridge (`loading_verdict`) giữ loading tới khi path đổi; JS `armStaleStatusGuard` ghi `staleStatusPath`, `handlePlayerStatus` bỏ qua status của đường dẫn đó cho tới khi mpv mở file khác. Gán `totalDuration` **trước** `currentTrack` (lyric đọc đồng bộ). Test: `node scripts/test_playback_race.cjs`, `cargo test -p nutsty-bridge loading_tests`. Chi tiết: `.agents/footguns/`.

## 9. Cài Đặt (`nutsty_settings.json`) & Presence
- `shell.qml` nạp qua `FileView` + timer `delayedSettingsRead` (100ms); Shuffle/Repeat chỉ phát signal để `shell.qml` gọi `saveSettings()`.
- Presence: ngưỡng online 25s (`ONLINE_THRESHOLD_MS`); thoát app gọi `/api/users/offline` xóa `now_playing`, `last_active_at = 0`.

## 10. Spotify: Import Embed & Đồng Bộ Hai Chiều (`spotify_importer.py`, `spotify_sync*.py`, `spotify_web.py`)
- **Import**: đọc `__NEXT_DATA__` của `open.spotify.com/embed/playlist/{id}`, không token, không 429.
- **Đồng bộ**: GraphQL web-player bằng cookie `sp_dc` của chính người dùng. Playlist liên kết id cố định `custom_pl_spotify_{pid}`, `spotifyLink.base` nằm trong bản ghi (đi theo account_sync); công tắc, `likedBase`, match cache theo máy + profile. Merge 3 chiều `spotify_sync_merge.three_way`.
- **Ghi ngược** (mặc định tắt): bật thì ghi mốc `localBaseline` + `writeBackAbsent`, chỉ thay đổi sau đó được đẩy. Ghi sau khi nhả khóa, đọc lại remote trước (xóa theo `uid`), 10 bài/lệnh, 3 s/lệnh, 30 bài/lượt; base chỉ nhận lệnh đã thành công. Backlog "đẩy bài thích cũ" giữ `_RUN_LOCK`, nghỉ 60 s mỗi 30 bài.
- **Footgun**: remote rỗng/thiếu **không** có nghĩa là xóa (`remote_is_valid`: complete + đủ `total`); xóa > nửa và > 3 bài bị chặn cả hai chiều tới khi bấm "Vẫn áp dụng". Biến GraphQL sai tên trả 400 `missing variable` (`addToPlaylist` cần `playlistItemUris`). Test: `scripts/test_spotify_sync.py`; smoke thật: `spotify_sync_smoke.py [--write <playlist nháp>]`.

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
- **UI**: opacity + Behavior (OutExpo), `FadeText`, thời lượng nhân `root.motion`. Demo: `open_settings?mock=1`.
- **Footgun**: CI phải ghim mpv (mpv đổi = ~97 MB mỗi bản). Suffix Range `bytes=-N` bị CDN GitHub từ chối (501), luôn dùng khoảng tuyệt đối. `.source`/`*.part` bị loại khi robocopy. Chạy `scripts/test_update_delta.py`.

## 13. Tidal Lossless (`backend/tidal_source.py`, `audio_output.py`, `lossless_logic.js`)
- **Resolve** (`resolve_media_path`): file đã tải > Tidal (bật, đã đăng nhập, không tạm tắt) > YouTube. Tidal lỗi/None/quá 4s → YouTube; epoch cũ bỏ kết quả. Nguồn thật ghi ở `now_source.json`.
- **Nghe Cùng**: `lossless_suspend 1` tạo cờ, đang phát Tidal thì nạp YouTube đúng vị trí; `0` chỉ xóa cờ. Chỉ tài khoản của chính người dùng, không log token, session chmod 600.
- **Nhãn**: `build_audio_specs` (Python) = `nutsty-bridge/src/audio_specs.rs`; không biết thì để trống, cấm bịa mặc định.
- **DAC**: không cần Tidal; lưu thiếu `dacModeStandalone` chỉ tính khi lossless bật. `exclusive` (Windows) restart mpv giữ vị trí, khóa AutoMix + âm lượng 100, ao lỗi → `shared` + toast. `rate_match` (Linux) chỉ ghi `90-nutsty-rates.conf` khi người dùng đồng ý, không đè `allowed-rates` có sẵn.
- **Footgun**: link FLAC/MPD hết hạn giữa bài → `stream_failed <pos>` nạp YouTube đúng vị trí, bỏ Tidal bài đó một lúc (`TIDAL_SKIP_FILE`). Test: `scripts/test_lossless_resolve.py`.

## 14. Discord Rich Presence (`nutsty-rs/crates/nutsty-discord`, `components/DiscordPresence.qml`)
- **Cơ chế**: IPC cục bộ của Discord (`discord-ipc-0..9`: Unix socket Linux gồm cả Flatpak/Snap/Vesktop, named pipe Windows), không token/đăng nhập. Client ID app "Nutsty" nằm trong `main.rs`. Activity type 2 (Listening), ảnh bìa là URL https, bài local dùng logo trên GitHub raw.
- **Vòng đời**: `bin/nutsty-discord` chạy suốt khi bật công tắc (`discordPresenceEnabled`, mặc định tắt), nhận một dòng JSON mỗi thay đổi qua stdin, trả `{"status":...}` qua stdout. Stdin đóng → xóa status rồi thoát; bị kill thì Discord tự xóa khi socket đóng. Windows: compat `Process` có `stdinEnabled` → `__NutstyBridge.startStream/writeStream/stopStream`.
- **Footgun**: giới hạn 5 lần/20 s (`SendBudget`), lệch < 2,5 s không gửi (`looks_like`). Windows: đọc chặn trên pipe đồng bộ chặn luôn ghi qua handle clone, nên reader `PeekNamedPipe` trước. Test: `cargo test -p nutsty-discord`.
