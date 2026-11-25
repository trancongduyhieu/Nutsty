# Tidal Lossless Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Khi người dùng bật lossless và đăng nhập Tidal của chính họ, Nutsty lặng lẽ thay luồng YouTube bằng luồng FLAC của Tidal, hiện nhãn chất lượng thật và cho chọn cách đưa âm thanh tới DAC.

**Architecture:** Một Deep Module mới `backend/tidal_source.py` (tidalapi) lo đăng nhập, khớp bài, lấy luồng. `resolve_media_path` trong `player_daemon.py` gọi nó trước bước YouTube và luôn quay về YouTube khi lỗi. Một module nhỏ `backend/audio_output.py` lo chế độ DAC (cờ mpv, file PipeWire, đọc tần số ALSA). QML chỉ thêm cài đặt, modal giải thích, toast Nghe Cùng và một hàm định dạng nhãn dùng chung.

**Tech Stack:** Python 3.11, `tidalapi==0.9.0`, mpv IPC, Quickshell/QML (Qt 6), PipeWire (Linux), WASAPI (Windows).

**Spec:** `docs/superpowers/specs/2026-11-25-tidal-lossless-design.md`

## Global Constraints

- Chỉ tài khoản Tidal của chính người dùng. Không pool, không tài khoản chung, không proxy bên thứ ba.
- Luồng `is_encrypted` thì bỏ, trả `None`.
- Token không bao giờ ra log hay stdout. File phiên chmod 600 trên Linux.
- Lỗi Tidal ở bất kỳ đâu: phát YouTube, không bao giờ im lặng.
- Không ghi nhãn "Lossless" cho Opus/AAC. Không bịa giá trị mặc định (AAC/192 kbps/48.0 kHz/44.1 kHz).
- Không ghi cấu hình PipeWire khi người dùng chưa bấm đồng ý. Không ghi đè `allowed-rates` có sẵn. Không tự khởi động lại PipeWire.
- Cài đặt mới trong `nutsty_settings{PROFILE_SUFFIX}.json`: `losslessEnabled` (mặc định `false`), `losslessQuality` (`"lossless"` | `"hires"`), `dacOutputMode` (`"shared"` mặc định | `"rate_match"` chỉ Linux | `"exclusive"`).
- AGENTS.md: không emoji trong UI, mọi chuỗi qua `I18n.tr("vi", "en")`, không hardcode đường dẫn (`platform_compat`, `Quickshell.env("HOME")`), nút dùng `accentColor`, nút nguy hiểm dùng Muted Rose `Qt.rgba(244, 63, 94, 0.12)`, chạy được trên Linux và Windows.
- Ghim `tidalapi==0.9.0` trong cả `requirements.txt` và `requirements_win.txt`.
- Test Python viết theo `unittest` (máy dev không có pytest), chạy bằng `python -m unittest`.
- Commit chỉ các file của task. Không đụng `backend/browser_login.py`, `backend/ytmusic_auth.py`, `run.sh` (người dùng đang sửa).

## Review Focus

1. Tidal trả bài nhưng luồng MPD hết hạn giữa bài (bài dài, tạm dừng lâu): mpv báo lỗi thì phải phát lại bản YouTube ở đúng vị trí, không nhảy bài. Test ở Task 3 (`test_tidal_stream_error_falls_back_at_position`).
2. Người dùng đổi bài liên tục khi Tidal chậm: kết quả Tidal về muộn không được phát đè bài mới. Test ở Task 3 (`test_superseded_epoch_ignores_tidal_result`).
3. Hai profile chạy song song (`run_dual_profile_test.sh`): phiên, cache khớp bài, file MPD và cờ tạm tắt phải tách theo `PROFILE_SUFFIX`. Test ở Task 2 (`test_paths_are_profile_scoped`) và Task 3.
4. Gói Tidal không có lossless hoặc chỉ có 16-bit mà setting là `hires`: không lỗi, phát mức cao nhất gói cho, nhãn ghi đúng mức thật. Test ở Task 2 (`test_hires_falls_back_to_lossless_quality`).
5. Tên bài YouTube kiểu "Artist - Title (Official MV) [Lyrics]" hoặc chỉ có tiếng Việt có dấu: làm sạch tên không được làm hỏng chữ có dấu, không khớp sang bài remix/live. Test ở Task 2 (`test_clean_title_*`, `test_rejects_live_and_remix`).

---

### Task 1: Spike (bỏ đi sau khi xong, cần tài khoản Tidal thật)

Không có test, không commit code spike. Chỉ commit bản ghi kết quả. Người dùng phải đăng nhập bằng tài khoản của họ, agent không nhập mật khẩu.

**Files:**
- Create (scratch, không commit): script trong thư mục scratchpad của phiên.
- Create: `docs/evidence/2026-11-25-tidal-spike.md`

- [ ] **Step 1:** Trong venv riêng, `pip install tidalapi==0.9.0`. Script gọi `session.login_oauth()`, in link để người dùng tự mở và xác nhận, rồi lưu phiên vào scratchpad.
- [ ] **Step 2:** Với `config.quality = Quality.hi_res_lossless`, gọi `get_stream()` cho 10 bài (có bài 24-bit). Ghi lại cho từng bài: `audio_quality`, `bit_depth`, `sample_rate`, kiểu manifest (BTS/MPD), `is_encrypted`.
- [ ] **Step 3:** Phát bằng mpv cả luồng BTS (URL trực tiếp) và MPD (`file://...mpd`). Ghi lại mpv có mở được không và thời gian tới khi có tiếng.
- [ ] **Step 4:** Đo `crossfade_engine.decode_levels` trên một URL FLAC (thời gian chạy).
- [ ] **Step 5:** Linux: phát bài 44,1 kHz và 96 kHz với `--audio-exclusive=yes`, đọc `/proc/asound/card*/pcm*p/sub0/hw_params`. Thử lại sau khi thêm drop-in `allowed-rates` vào scratchpad cấu hình tạm (chỉ khi người dùng đồng ý ghi vào `~/.config/pipewire/pipewire.conf.d/`). Windows: chạy mpv `--audio-exclusive=yes --msg-level=ao=v`, chép phần log ao.
- [ ] **Step 6:** Ghi kết quả vào `docs/evidence/2026-11-25-tidal-spike.md`, kết luận 4 câu hỏi: OAuth có ra HiRes không, mpv đọc MPD được không, `decode_levels` có kịp (< 3 giây) không, exclusive có đưa đúng tần số tới DAC không.
- [ ] **Step 7: Cổng quyết định.** Nếu OAuth không ra HiRes: hỏi người dùng chọn (a) bản đầu chỉ FLAC 16-bit, hay (b) thêm PKCE qua server localhost. Nếu mpv không đọc MPD: dừng, báo người dùng trước khi làm tiếp. Ghi quyết định vào file evidence.
- [ ] **Step 8: Commit**

```bash
git add docs/evidence/2026-11-25-tidal-spike.md
git commit -m "docs(evidence): Tidal spike results for lossless streaming"
```

---

### Task 2: `backend/tidal_source.py` và test offline

**Files:**
- Create: `backend/tidal_source.py`
- Create: `tests/test_tidal_source.py`
- Modify: `requirements.txt`, `requirements_win.txt` (thêm `tidalapi==0.9.0`)

**Interfaces:**
- Produces:
  - `login_start() -> dict` trả `{"url": str, "code": str, "expires_in": int}`
  - `login_poll() -> dict` trả `{"state": "pending"|"ok"|"expired"|"error", "account": str, "subscription": str}`
  - `logout() -> None` (xóa file phiên)
  - `status() -> dict` trả `{"logged_in": bool, "account": str, "can_hires": bool, "needs_relogin": bool}`
  - `resolve(video_id: str, title: str, artist: str, duration_s: float, quality: str, budget_s: float = 4.0) -> dict | None`. Dict là `TidalStream`: `{"url", "codec", "bit_depth", "sample_rate", "audio_quality", "tidal_id", "expires_at"}`
  - `clean_title(title: str) -> str`, `score_candidate(title, artist, duration_s, cand_title, cand_artists: list[str], cand_duration_s) -> float` (0..1)
  - `MATCH_THRESHOLD = 0.75`, `MISS_TTL_S = 7 * 86400`, `STREAM_TTL_S = 600`
  - `_session_factory` (biến module, test thay bằng session giả), `SESSION_FILE`, `MATCH_CACHE_FILE`, `MPD_DIR`: mọi đường dẫn lấy từ `platform_compat` và có `PROFILE_SUFFIX`.

- [ ] **Step 1: Viết test hỏng.** `tests/test_tidal_source.py` theo khuôn `tests/test_audio_quality_and_lyrics_source.py` (chèn `backend` vào `sys.path`). Đặt `NUTSTY_CONFIG_DIR`/cache dir vào `tempfile.mkdtemp()` trong `setUp`, gán `tidal_source._session_factory` thành session giả trả về các `Track` giả (có `name`, `artists[].name`, `duration`, `id`, `get_stream()`).

```python
def test_clean_title_strips_video_noise(self):
    self.assertEqual(ts.clean_title("Nàng Thơ (Official MV) [Lyrics]"), "nàng thơ")
    self.assertEqual(ts.clean_title("Shape of You (feat. X) - Remastered 2017"), "shape of you")

def test_rejects_live_and_remix(self):
    self.assertLess(ts.score_candidate("Yellow", "Coldplay", 266, "Yellow (Live)", ["Coldplay"], 280), ts.MATCH_THRESHOLD)
    self.assertLess(ts.score_candidate("Yellow", "Coldplay", 266, "Yellow - Remix", ["Coldplay"], 267), ts.MATCH_THRESHOLD)

def test_duration_over_3s_rejected(self):
    self.assertLess(ts.score_candidate("Yellow", "Coldplay", 266, "Yellow", ["Coldplay"], 270), ts.MATCH_THRESHOLD)

def test_resolve_bts_returns_direct_url(self):
    s = ts.resolve("vid1", "Yellow", "Coldplay", 266, "lossless")
    self.assertEqual(s["url"], "https://fake/yellow.flac")
    self.assertEqual((s["bit_depth"], s["sample_rate"]), (16, 44100))

def test_resolve_mpd_writes_manifest_file(self):
    s = ts.resolve("vid2", "Song24", "Artist", 200, "hires")
    self.assertTrue(s["url"].startswith("file://"))
    self.assertTrue(os.path.exists(s["url"][len("file://"):]))

def test_encrypted_stream_returns_none(self): ...      # stream.is_encrypted = True -> None
def test_miss_is_cached_for_7_days(self): ...          # search gọi đúng 1 lần cho 2 lần resolve; time.time + 7 ngày + 1 -> gọi lại
def test_stream_url_cached_10_minutes(self): ...       # get_stream gọi 1 lần trong 600 s, gọi lại sau đó
def test_network_error_returns_none(self): ...         # search ném Exception -> None, không ném ra ngoài
def test_budget_exceeded_returns_none_and_caches_later(self): ...  # search ngủ 0.3 s, budget_s=0.1 -> None; chờ luồng nền xong -> lần sau trả kết quả ngay
def test_hires_falls_back_to_lossless_quality(self): ...  # gói chỉ cho LOSSLESS: quality "hires" vẫn trả stream, audio_quality "LOSSLESS", bit_depth 16
def test_401_marks_needs_relogin(self): ...            # lỗi 401 -> None và status()["needs_relogin"] True
def test_paths_are_profile_scoped(self): ...           # đặt PROFILE_SUFFIX "_user2" -> SESSION_FILE, MATCH_CACHE_FILE, MPD_DIR đều chứa "_user2"
def test_token_never_printed(self): ...                # bắt stdout/stderr khi login_poll ok + resolve; không chứa access_token giả
def test_session_file_mode_600(self): ...              # chỉ chạy khi không phải Windows
```

- [ ] **Step 2: Chạy, phải hỏng.** `python -m unittest tests.test_tidal_source -v`. Kết quả mong đợi: `ModuleNotFoundError: No module named 'tidal_source'`.
- [ ] **Step 3: Viết `backend/tidal_source.py`.** Import `tidalapi` lười (trong hàm), để test chạy không cần cài. Map quality: `"hires" -> Quality.hi_res_lossless`, `"lossless" -> Quality.high_lossless`. Chọn bản `STEREO` (bỏ `AudioMode.dolby_atmos`). Ngân sách 4 giây: chạy khớp bài + `get_stream` trong một `threading.Thread`, `join(budget_s)`; quá giờ thì trả `None` và để luồng đó ghi cache khi xong. Ghi cache bằng file tạm rồi `os.replace`. `expires_at = time.time() + STREAM_TTL_S`. Lỗi in ra `stderr` một dòng có tên lỗi, không in nội dung phiên.
- [ ] **Step 4: Chạy, phải qua.** `python -m unittest tests.test_tidal_source -v`. Tất cả OK.
- [ ] **Step 5:** `python scripts/verify_codebase.py` qua.
- [ ] **Step 6: Commit**

```bash
git add backend/tidal_source.py tests/test_tidal_source.py requirements.txt requirements_win.txt
git commit -m "feat(lossless): Tidal source module with matching, caching and YouTube fallback"
```

---

### Task 3: Nối Tidal vào luồng phát và tạm tắt khi Nghe Cùng (backend)

**Files:**
- Modify: `backend/player_daemon.py` (`resolve_media_path` ~dòng 358, `_resolve_for_crossfade` ~559, action `play` ~902, thêm action mới gần `audio_specs` ~1193)
- Create: `tests/test_lossless_resolve.py`

**Interfaces:**
- Consumes: `tidal_source.resolve(...)`, `tidal_source.status()` (Task 2).
- Produces:
  - `get_lossless_settings() -> dict` trả `{"enabled": bool, "quality": str, "dac_mode": str}` (đọc cùng file settings như `get_current_streaming_quality`)
  - `LOSSLESS_SUSPEND_FILE = os.path.join(TEMP_DIR, f"nutsty_lossless_suspended{PROFILE_SUFFIX}")`, `is_lossless_suspended() -> bool`
  - `PLAYBACK_STATE_FILE` có thêm khóa `"source": "tidal"|"youtube"|"local"` và `"tidal": TidalStream|None` (dùng cho nhãn ở Task 6)
  - Action CLI `lossless_suspend <1|0>`: `1` ghi file cờ; nếu bài đang phát có `source == "tidal"` thì lấy `time-pos`, resolve YouTube với `force_tidal_off=True` và `loadfile <url> replace start=<pos>`. `0` xóa file cờ, không nạp lại (lossless bật lại từ bài sau). In JSON `{"suspended": bool, "reloaded": bool}`.
  - `resolve_media_path(..., skip_tidal=False, source_out=None)`: tham số mới, `source_out` là dict nhận `{"source", "tidal"}`.

- [ ] **Step 1: Viết test hỏng** trong `tests/test_lossless_resolve.py`. Thay `player_daemon.tidal_source.resolve` bằng hàm giả, thay `ytmusic_helper.resolve_stream_url` và `send_mpv_cmd` bằng hàm giả ghi lại lệnh, đặt settings vào thư mục tạm.

```python
def test_tidal_used_when_enabled(self):           # losslessEnabled true -> trả URL Tidal, source_out["source"] == "tidal"
def test_tidal_skipped_when_disabled(self):       # false -> resolve Tidal không được gọi
def test_downloaded_file_still_wins(self):        # find_local_downloaded_file có file -> trả file đó, Tidal không được gọi
def test_tidal_none_falls_back_to_youtube(self):  # Tidal trả None -> URL YouTube
def test_suspended_skips_tidal(self):             # có file cờ -> Tidal không được gọi
def test_superseded_epoch_ignores_tidal_result(self):  # Tidal giả đổi active epoch trong lúc chạy -> resolve_media_path trả ""
def test_crossfade_path_uses_tidal(self):         # _resolve_for_crossfade trả URL Tidal khi bật
def test_suspend_reloads_youtube_at_position(self):    # state source "tidal", time-pos 42.5 -> có lệnh loadfile ... "start=42.5"
def test_suspend_noop_when_playing_youtube(self): # source "youtube" -> reloaded False, không loadfile
def test_unsuspend_does_not_reload(self):         # lossless_suspend 0 -> xóa cờ, không loadfile
def test_tidal_stream_error_falls_back_at_position(self):  # action mới "stream_failed": source tidal, pos 30 -> loadfile YouTube start=30 và ghi miss cho bài này trong 10 phút
```

- [ ] **Step 2: Chạy, phải hỏng.** `python -m unittest tests.test_lossless_resolve -v`. Mong đợi: lỗi thiếu `get_lossless_settings` / tham số `source_out`.
- [ ] **Step 3: Sửa `resolve_media_path`.** Chèn bước Tidal ngay sau đoạn kiểm tra epoch đầu tiên (sau bước file đã tải), trước khối cache YouTube: điều kiện `enabled and not skip_tidal and not is_lossless_suspended() and tidal_source.status()["logged_in"]`. Kiểm `is_play_epoch_active` ngay sau khi gọi Tidal (giữ cách ghi log như các chỗ hiện có). `duration_s` lấy từ đối số mới `duration_s=0.0` (truyền từ action `play` nếu có; 0 thì `score_candidate` bỏ tiêu chí thời lượng).
- [ ] **Step 4: Sửa action `play` và `crossfade_play`.** Ghi `source`/`tidal` vào `PLAYBACK_STATE_FILE` sau khi resolve. Thêm action `lossless_suspend` và `stream_failed <pos>`. `stream_failed` được gọi khi mpv báo `end-file` lỗi trên URL Tidal: tìm chỗ xử lý lỗi hiện có trong `playback_engine.js` `handlePlayerStatus` (~dòng 1044) và gọi action này thay vì chuyển bài khi `audio_specs.source == "tidal"`.
- [ ] **Step 5: Chạy, phải qua.** `python -m unittest tests.test_lossless_resolve tests.test_audio_quality_and_lyrics_source -v`. Tất cả OK.
- [ ] **Step 6:** `node scripts/test_playback_engine.js` và `node scripts/test_playback_race.cjs` vẫn qua.
- [ ] **Step 7: Commit**

```bash
git add backend/player_daemon.py tests/test_lossless_resolve.py components/playback_engine.js
git commit -m "feat(lossless): play Tidal FLAC before YouTube, suspend during Listen Along"
```

---

### Task 4: Route đăng nhập Tidal

**Files:**
- Modify: `backend/music_routes.py` (thêm handler), `backend/route_dispatcher.py` (GET ~dòng 25, POST ~dòng 158)
- Create: `tests/test_tidal_routes.py`

**Interfaces:**
- Consumes: `tidal_source.login_start/login_poll/logout/status` (Task 2).
- Produces (HTTP qua daemon cổng 17890):
  - `GET /api/tidal/status` -> `status()`
  - `POST /api/tidal/login/start` -> `login_start()`
  - `GET /api/tidal/login/poll` -> `login_poll()`
  - `POST /api/tidal/logout` -> `{"success": true}`
  - Handler: `handle_get_tidal_status(handler)`, `handle_post_tidal_login_start(handler)`, `handle_get_tidal_login_poll(handler)`, `handle_post_tidal_logout(handler)`

- [ ] **Step 1: Viết test hỏng.** Gọi `route_dispatcher.dispatch_request(method, path, {}, "")` với `tidal_source` giả, kiểm JSON trả về đúng 4 route trên, và lỗi trong `tidal_source` trả `{"state": "error"}` chứ không làm sập handler. Theo khuôn `scripts/test_cli_dispatch.py`.
- [ ] **Step 2: Chạy, phải hỏng.** `python -m unittest tests.test_tidal_routes -v`. Mong đợi: route trả 404.
- [ ] **Step 3: Viết handler và nối vào dispatcher.** Dùng `handler._send_json(...)` như các handler hiện có.
- [ ] **Step 4: Chạy, phải qua.** `python -m unittest tests.test_tidal_routes -v` OK, `python scripts/verify_codebase.py` qua.
- [ ] **Step 5: Commit**

```bash
git add backend/music_routes.py backend/route_dispatcher.py tests/test_tidal_routes.py
git commit -m "feat(lossless): Tidal login and status routes"
```

---

### Task 5: Cài đặt, đăng nhập, modal giải thích và toast Nghe Cùng (QML)

**Files:**
- Modify: `shell.qml` (property ~dòng 291, `loadSettings` ~4502, `saveSettings` ~4608, truyền vào SettingsModal ~3785), `components/SettingsModal.qml` (thêm mục sau `streamingQuality` ~dòng 2260)
- Create: `components/LosslessExplainModal.qml`, `components/lossless_logic.js`
- Create: `scripts/test_lossless_logic.cjs`
- Modify: `AGENTS.md` cây thư mục (thêm 2 file mới, giữ ≤ 150 dòng)

**Interfaces:**
- Consumes: route Task 4, action `lossless_suspend` Task 3.
- Produces:
  - `shell.qml`: `property bool losslessEnabled: false`, `property string losslessQuality: "lossless"`, `property string dacOutputMode: "shared"`, `property var tidalStatus: null`, `property bool autoMixBeforeLossless: true`
  - `lossless_logic.js` (thuần, không đụng `win`):
    - `suspendTransition(wasActive: bool, isActive: bool, losslessEnabled: bool) -> "suspend" | "resume" | ""`
    - `dacModesFor(isWindows: bool) -> string[]` (Windows: `["shared","exclusive"]`, Linux: cả 3)
    - `normalizeLosslessSettings(obj, isWindows) -> {losslessEnabled, losslessQuality, dacOutputMode}` (giá trị lạ về mặc định; `rate_match` trên Windows về `shared`)
  - Signal `LosslessExplainModal`: `accepted(string dacMode)`, `dismissed()`

- [ ] **Step 1: Viết test hỏng** `scripts/test_lossless_logic.cjs` (theo khuôn `scripts/test_kinetic_stage.cjs`, nạp file `.js` bằng `vm`):

```js
assert.strictEqual(L.suspendTransition(false, true, true), "suspend");
assert.strictEqual(L.suspendTransition(true, false, true), "resume");
assert.strictEqual(L.suspendTransition(false, true, false), "");
assert.deepStrictEqual(L.dacModesFor(true), ["shared", "exclusive"]);
assert.strictEqual(L.normalizeLosslessSettings({dacOutputMode: "rate_match"}, true).dacOutputMode, "shared");
assert.strictEqual(L.normalizeLosslessSettings({losslessQuality: "ultra"}, false).losslessQuality, "lossless");
```

- [ ] **Step 2: Chạy, phải hỏng.** `node scripts/test_lossless_logic.cjs`. Mong đợi: không tìm thấy file.
- [ ] **Step 3: Viết `lossless_logic.js`.** Chạy lại test, phải qua.
- [ ] **Step 4: Lưu/đọc cài đặt.** Thêm 3 khóa vào `saveSettings`/`loadSettings` qua `normalizeLosslessSettings`.
- [ ] **Step 5: Mục "Lossless (Tidal)" trong `SettingsModal.qml`.** Trạng thái tài khoản (tên + gói), nút "Đăng nhập Tidal" / "Đăng xuất" (Muted Rose), công tắc lossless (bật thì mở modal, không bật thẳng), chọn chất lượng (ẩn `hires` nếu `!tidalStatus.can_hires`), chọn chế độ DAC theo `dacModesFor`. Đăng nhập: POST `/api/tidal/login/start`, `Qt.openUrlExternally(url)`, hiện mã và "Đang chờ xác nhận trên trình duyệt…", Timer 2000 ms gọi `/api/tidal/login/poll` tới `ok`/`expired`/`error`. Gói không có lossless: hiện câu nói rõ và giữ công tắc tắt. `needs_relogin`: hiện dòng nhắc đăng nhập lại. Khi `win.isCoListeningActive && losslessEnabled`: hiện dòng "Tạm tắt lossless khi Nghe Cùng".
- [ ] **Step 6: `LosslessExplainModal.qml`.** Nội dung đúng mục 8 của spec (5 ý + 3 lựa chọn DAC, Windows ẩn `rate_match` và có dòng giải thích). Nút "Để sau" (`dismissed`) và "Bật lossless" (`accepted(mode)`). Bấm "Bật lossless" thì `win.autoMixBeforeLossless = win.autoMixEnabled`, đặt `losslessEnabled = true` và `dacOutputMode`, rồi `saveSettings()`.
- [ ] **Step 7: Toast Nghe Cùng.** Trong `shell.qml`, `onIsCoListeningActiveChanged` gọi `suspendTransition`. `"suspend"`: chạy `player_daemon.py lossless_suspend 1` và `win.showToast(I18n.tr("Đang Nghe Cùng: tạm phát bản YouTube để hai bên nghe khớp nhau. Lossless sẽ bật lại khi dừng nghe cùng.", "Listening Along: playing the YouTube version so you both stay in sync. Lossless comes back when you stop."))`. `"resume"`: chạy `lossless_suspend 0` và toast `I18n.tr("Lossless đã bật lại từ bài tiếp theo.", "Lossless is back from the next song.")`. Lúc khởi động app luôn gọi `lossless_suspend 0` để xóa cờ cũ.
- [ ] **Step 8: Kiểm tra.** `node scripts/test_lossless_logic.cjs`, `node scripts/test_listen_along.mjs`, `python scripts/verify_codebase.py`, `python scripts/verify_qml_compat.py`, `qmllint components/SettingsModal.qml components/LosslessExplainModal.qml shell.qml` đều qua. Chạy app, mở Cài đặt, chụp màn hình mục mới và modal ở cả `vi` và `en`, xem ảnh để chắc không lẫn tiếng.
- [ ] **Step 9: Commit**

```bash
git add shell.qml components/SettingsModal.qml components/LosslessExplainModal.qml components/lossless_logic.js scripts/test_lossless_logic.cjs AGENTS.md
git commit -m "feat(lossless): Tidal settings, login flow, explain modal and Listen Along notices"
```

---

### Task 6: Nhãn chất lượng thật

**Files:**
- Modify: `backend/player_daemon.py` `get_audio_specs_dict` (~dòng 862)
- Create: `backend/audio_output.py` (phần đọc ALSA; Task 7 thêm phần còn lại)
- Create: `components/quality_label.js`
- Modify: `components/PlayerBarBottom.qml:734-736`, `components/AmberolDetailView.qml:609,690,709,728,747`, `components/YTMusicNowPlayingView.qml:211`
- Modify: `tests/test_audio_quality_and_lyrics_source.py` (test_01 đang kiểm giá trị mặc định cũ)
- Create: `tests/test_audio_output.py`, `scripts/test_quality_label.cjs`

**Interfaces:**
- Consumes: `PLAYBACK_STATE_FILE["source"/"tidal"]` (Task 3), `is_lossless_suspended()` (Task 3).
- Produces:
  - `audio_output.read_alsa_running_rate(proc_root: str = "/proc/asound") -> int | None` (đọc `card*/pcm*p/sub0/hw_params` của thẻ có `status` là `RUNNING`, lấy dòng `rate: N`)
  - `get_audio_specs_dict()` trả: `{"source": str, "codec": str, "bit_depth": int|None, "sample_rate": int|None, "bitrate_kbps": int|None, "channels": int|None, "lossless": bool, "output_rate": int|None, "via_windows_mixer": bool, "lossless_suspended": bool}`. Không biết thì `None`/`""`, không bịa. Giữ thêm `bitrate_str`/`sample_rate_str`/`channels` dạng chuỗi rỗng khi không biết, để code cũ không gãy.
  - Quy tắc số bit (spec để người làm quyết): nguồn Tidal lấy `bit_depth` từ `TidalStream`; còn lại đọc `audio-params/format`: `s16`->16, `s24`/`s32` với codec flac/alac -> 24, float hoặc lossy -> `None`.
  - `lossless = codec in ("flac", "alac", "wavpack", "pcm*")`.
  - `quality_label.js`: `formatQualityLabel(specs, tr) -> string`. Ví dụ: `"FLAC 24-bit · 96 kHz"`, `"FLAC 16-bit · 44.1 kHz → 48 kHz"`, `"OPUS · 141 kbps"`, `"FLAC 16-bit · 44.1 kHz · qua Windows"`, thêm `" · " + tr("Tạm tắt lossless khi Nghe Cùng", "Lossless paused while Listening Along")` khi `lossless_suspended`. Phần nào `null` thì bỏ. Không có gì thì `""`.

- [ ] **Step 1: Viết test hỏng.**
  - `tests/test_audio_output.py`: dựng cây `/proc/asound` giả trong thư mục tạm (2 thẻ, một `RUNNING` rate 48000, một `closed`) -> `48000`; không có thẻ chạy -> `None`.
  - Sửa `test_01_audio_specs_dict_structure`: với `get_mpv_property` giả trả `None` hết, `codec == ""`, `sample_rate is None`, `bitrate_kbps is None`, `lossless is False`.
  - Thêm test: mpv giả `audio-codec-name="flac"`, `audio-params={"samplerate":96000,"format":"s32","channel-count":2}` -> `bit_depth 24`, `lossless True`. Opus -> `lossless False`, `bit_depth None`.
  - `scripts/test_quality_label.cjs`: đủ 5 ví dụ ở trên và `formatQualityLabel({}, tr) === ""`.
- [ ] **Step 2: Chạy, phải hỏng.** `python -m unittest tests.test_audio_output tests.test_audio_quality_and_lyrics_source -v` và `node scripts/test_quality_label.cjs`.
- [ ] **Step 3: Viết `read_alsa_running_rate`, sửa `get_audio_specs_dict`, viết `quality_label.js`.** `output_rate` chỉ điền trên Linux và chỉ khi khác `sample_rate`. `via_windows_mixer = pc.IS_WINDOWS and dac_mode != "exclusive"`.
- [ ] **Step 4: Thay 3 chỗ hiển thị** bằng `formatQualityLabel(root.audioSpecs, I18n.tr)`. Ở `AmberolDetailView.qml` các ô codec/bitrate/sample rate/channels hiện `"—"` khi không biết, bỏ `"AAC"`, `"192 kbps"`, `"44.1 kHz"`. Ở `YTMusicNowPlayingView.qml:211` bỏ chữ `"FLAC • ..."` in sẵn.
- [ ] **Step 5: Chạy, phải qua.** Các test bước 2, `python scripts/verify_codebase.py`, `python scripts/verify_qml_compat.py`, `qmllint` 3 file QML đã sửa.
- [ ] **Step 6:** Chạy app, phát 1 bài YouTube và 1 file FLAC trong máy, chụp thanh phát và trang chi tiết, xem ảnh: YouTube ghi Opus/AAC, FLAC ghi số bit và tần số thật.
- [ ] **Step 7: Commit**

```bash
git add backend/player_daemon.py backend/audio_output.py components/quality_label.js components/PlayerBarBottom.qml components/AmberolDetailView.qml components/YTMusicNowPlayingView.qml tests/test_audio_quality_and_lyrics_source.py tests/test_audio_output.py scripts/test_quality_label.cjs
git commit -m "feat(lossless): truthful quality label from one source, no fabricated defaults"
```

---

### Task 7: Chế độ đưa âm thanh tới DAC

Làm `exclusive` trước, `rate_match` sau, cùng một task vì chung máy trạng thái.

**Files:**
- Modify: `backend/audio_output.py`, `backend/player_daemon.py` (`ensure_mpv` ~dòng 142, thêm action), `shell.qml`, `components/SettingsModal.qml`, `components/PlayerBarBottom.qml` (khóa thanh âm lượng)
- Modify: `components/lossless_logic.js`, `scripts/test_lossless_logic.cjs`, `tests/test_audio_output.py`

**Interfaces:**
- Consumes: `get_lossless_settings()` (Task 3), mục cài đặt (Task 5).
- Produces:
  - `audio_output.mpv_output_args(settings: dict) -> list[str]`: `["--audio-exclusive=yes"]` khi `enabled` và `dac_mode == "exclusive"`, còn lại `[]`.
  - `audio_output.PIPEWIRE_DROPIN = Path.home() / ".config/pipewire/pipewire.conf.d/90-nutsty-rates.conf"`
  - `audio_output.RATES = [44100, 48000, 88200, 96000, 176400, 192000]`
  - `audio_output.find_existing_allowed_rates(conf_dir: Path) -> list[tuple[str, str]]` (file, dòng) cho mọi file `*.conf` khác file của Nutsty có `allowed-rates`
  - `audio_output.write_rate_dropin(conf_dir: Path) -> dict` trả `{"written": bool, "path": str, "conflicts": [...]}`; có conflict thì không ghi
  - `audio_output.remove_rate_dropin(conf_dir: Path) -> bool` (chỉ xóa đúng file 90-nutsty-rates.conf)
  - Action CLI: `restart_mpv_keep_position` (lấy `path`+`time-pos`, tắt mpv, `ensure_mpv()` với cờ mới, nạp lại ở vị trí cũ, giữ trạng thái pause), `rate_dropin <write|remove|check>` in JSON
  - Khi exclusive: `ensure_mpv` đặt `volume=100`. Nếu mpv thoát ngay hoặc log ao báo không mở được thiết bị ở chế độ riêng: chạy lại không có cờ, ghi `{"exclusive_failed": true}` vào `PLAYBACK_STATE_FILE`.
  - `lossless_logic.js`: `dacTransition(prev: {enabled, mode}, next: {enabled, mode}) -> {restartMpv: bool, autoMixLocked: bool, restoreAutoMix: bool}`

- [ ] **Step 1: Viết test hỏng.**
  - Python: `mpv_output_args` theo 4 tổ hợp; `write_rate_dropin` trên thư mục tạm ghi đúng dòng `default.clock.allowed-rates = [ 44100 48000 88200 96000 176400 192000 ]` trong `context.properties`; có file khác chứa `allowed-rates` -> `written False`, file của Nutsty không tồn tại; `remove_rate_dropin` không xóa file khác.
  - JS: `dacTransition({enabled:true,mode:"shared"},{enabled:true,mode:"exclusive"})` -> `{restartMpv:true, autoMixLocked:true, restoreAutoMix:false}`; từ exclusive tắt lossless -> `{restartMpv:true, autoMixLocked:false, restoreAutoMix:true}`; shared -> rate_match -> `restartMpv false`; tắt lossless từ rate_match -> `restartMpv false, restoreAutoMix true`.
- [ ] **Step 2: Chạy, phải hỏng.** `python -m unittest tests.test_audio_output -v`, `node scripts/test_lossless_logic.cjs`.
- [ ] **Step 3: Viết code backend và `dacTransition`.** `ensure_mpv` nối `mpv_output_args(get_lossless_settings())` vào lệnh mpv.
- [ ] **Step 4: Nối QML.** Đổi chế độ hoặc bật/tắt lossless gọi `dacTransition`: `restartMpv` thì chạy `restart_mpv_keep_position`; `autoMixLocked` thì đặt `autoMixEnabled = false`, công tắc AutoMix bị khóa với dòng `I18n.tr("Tắt do chế độ nguyên bản", "Off in bit-perfect mode")`, thanh âm lượng khóa ở 100; `restoreAutoMix` thì `autoMixEnabled = autoMixBeforeLossless`. Thấy `exclusive_failed` trong status thì đặt `dacOutputMode = "shared"`, lưu, toast báo app khác đang giữ thiết bị. Chọn `rate_match`: gọi `rate_dropin check`, hiện hộp hỏi (chỉ ghi khi người dùng bấm đồng ý), có conflict thì hiện file và dòng đang có, không ghi; ghi xong nhắc chạy `systemctl --user restart pipewire` hoặc đăng xuất. Có nút "Gỡ cấu hình" gọi `rate_dropin remove`.
- [ ] **Step 5: Chạy, phải qua.** Các test bước 2, `python scripts/verify_codebase.py`, `python scripts/verify_qml_compat.py`, `qmllint` các file QML đã sửa.
- [ ] **Step 6: Thử thật trên Linux.** Bật exclusive, phát bài 44,1 kHz, đọc `/proc/asound/card*/pcm*p/sub0/hw_params` ra `rate: 44100`; kiểm vị trí giữ nguyên sau khi đổi chế độ; AutoMix bị khóa và trở lại khi tắt lossless.
- [ ] **Step 7: Commit**

```bash
git add backend/audio_output.py backend/player_daemon.py shell.qml components/SettingsModal.qml components/PlayerBarBottom.qml components/lossless_logic.js scripts/test_lossless_logic.cjs tests/test_audio_output.py
git commit -m "feat(lossless): exclusive and rate-matched DAC output modes"
```

---

### Task 8: Kiểm tra cuối và tài liệu kiến trúc

**Files:**
- Modify: `.agents/rules/02-audio-backend-and-queue-lifecycle.md` (một mục 5–12 dòng: tidal_source, thứ tự resolve, cờ tạm tắt Nghe Cùng, footgun MPD hết hạn; đọc file trước, giữ ≤ 100 dòng)

- [ ] **Step 1:** Chạy toàn bộ: `python -m unittest discover tests -v`, `python scripts/verify_codebase.py`, `python scripts/verify_qml_compat.py`, `qmllint components/*.qml shell.qml`, các test JS (`test_playback_engine.js`, `test_playback_race.cjs`, `test_listen_along.mjs`, `test_lossless_logic.cjs`, `test_quality_label.cjs`). Tất cả qua.
- [ ] **Step 2:** Linux, với tài khoản Tidal của người dùng: bật lossless, phát 3 bài có trên Tidal và 1 bài không có, chụp nhãn. Bắt đầu Nghe Cùng giữa bài FLAC: có toast, nhạc chuyển sang YouTube ở cùng vị trí; dừng: toast thứ hai, bài sau là FLAC.
- [ ] **Step 3:** `scripts/run_dual_profile_test.sh`: 2 profile không dùng chung phiên Tidal.
- [ ] **Step 4:** Windows (`start.bat` hoặc bản build): đăng nhập, phát FLAC, nhãn có `· qua Windows` ở shared, không thấy lựa chọn "Đúng tần số gốc", exclusive chạy hoặc tự về shared kèm thông báo.
- [ ] **Step 5:** Cập nhật file rules, kiểm `wc -l` trong ngân sách.
- [ ] **Step 6: Commit và push** theo AGENTS.md mục 5.

```bash
git add .agents/rules/02-audio-backend-and-queue-lifecycle.md
git commit -m "docs(rules): Tidal lossless resolve order and Listen Along suspension"
git push origin main
```
