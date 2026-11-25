# Tidal Lossless cho người dùng DAC

## Vì sao làm
Người đã bỏ tiền mua tai nghe tốt và DAC (khoảng 3 triệu trở lên) muốn nghe được hết chất lượng đó khi cắm vào máy tính. Nutsty hiện chỉ phát luồng YouTube nén (Opus/AAC khoảng 256 kbps), nên với nhóm người này không có lý do để chọn Nutsty. Lossless là lý do để họ chọn app, không phải tính năng phụ.

Người dùng vẫn dùng Nutsty như bình thường (trang chủ, tìm kiếm, playlist, Nghe Cùng, AutoMix), chỉ là nghe hay hơn và **thấy được** mình đang nghe gì.

## Mục tiêu
1. Người dùng đăng nhập **tài khoản Tidal của chính họ** và phát FLAC (16-bit 44,1 kHz, và HiRes tới 24-bit 192 kHz nếu tài khoản và phương thức đăng nhập cho phép).
2. Tidal **âm thầm thay luồng YouTube** của đúng bài đó. Không có kho nhạc Tidal riêng, không có trang tìm kiếm Tidal riêng.
3. Bài không tìm được trên Tidal thì phát bản YouTube như cũ, không bao giờ im lặng hay báo lỗi chặn.
4. Thanh phát hiện nhãn chất lượng **thật** đang phát (ví dụ `FLAC · 24-bit · 96 kHz`), lấy từ mpv chứ không lấy từ metadata Tidal.
5. Có lựa chọn đưa âm thanh tới DAC đúng tần số gốc của bài.
6. Khi bật, một bảng giải thích nói rõ chuyện gì sẽ xảy ra (xem "Bảng bật lossless").
7. Chạy được trên cả Linux (Niri/CachyOS) và Windows (`launcher_win.py`). Chỗ nào hai nền tảng khác nhau thì nói rõ trên giao diện.

## Không làm (lần này)
- Dolby Atmos và render ra tai nghe: thiết kế riêng sau.
- Tải nhạc FLAC từ Tidal về máy (`download_manager.py`): để sau.
- Kho nhạc, playlist, thư viện, trang chủ của Tidal.
- Qobuz, Deezer, Apple Music.

## Tuyệt đối không làm
- Dùng tài khoản chung, token phát tán, "source pool" kiểu SpatialFlow, hay server proxy của bên thứ ba (Monochrome/hifi-api). Chỉ dùng tài khoản người dùng tự đăng nhập.
- Phát luồng bị mã hóa (`Stream.is_encrypted`): bỏ qua và quay về YouTube.
- Làm hỏng Nghe Cùng: sự kiện vẫn mang `videoId`, và trong lúc Nghe Cùng thì tạm tắt Tidal (mục 3).
- Hiện nhãn "Lossless" khi thứ đang thực sự phát không phải lossless.
- Tự ghi cấu hình hệ thống mà không hỏi người dùng.

## Hiện trạng (đã khảo sát)
- Mọi bài online gắn với YouTube `videoId`. `playablePathOf` (`components/playback_engine.js:247`) trả về `ytdl://<vid>`.
- Bộ phát là mpv, do `backend/player_daemon.py` điều khiển. Điểm đổi `ytdl://` thành URL phát được là `resolve_media_path` (`player_daemon.py:358`): ưu tiên file đã tải, sau đó cache 20 phút, sau đó `ytmusic_helper.resolve_stream_url`, cuối cùng `ytdl://` để mpv tự lấy qua yt-dlp.
- AutoMix chạy 2 tiến trình mpv (mpv chính và mpv "tail" trong `backend/crossfade_engine.py`), mỗi tiến trình có bộ lọc `af` fade, rồi bộ trộn của hệ thống cộng 2 tiếng. `decode_levels` giải mã URL để phân tích mức âm.
- Chất lượng chọn trong `SettingsModal.qml` (`streamingQuality`: `high_opus`, `high_aac`, `medium`, `low`), lưu ở `nutsty_settings.json`.
- `player_daemon.py:862` đã đọc `audio-codec-name` và `audio-params` từ mpv để báo codec/tần số cho UI.
- PipeWire trên máy dev đang khóa `clock.allowed-rates = [ 48000 ]`, nên mọi thứ bị chuyển về 48 kHz trước khi tới DAC. Windows ở chế độ dùng chung cũng chuyển về một tần số cố định.
- Python: Linux 3.14, bản Windows đóng gói Python 3.11 (`_internal/python311.dll`, CI `python-version: '3.11'`). tidalapi 0.9.0 cần 3.11 trở lên, nên cả hai đều được.

## Các cách đã cân nhắc
| Cách | Đánh đổi | Kết quả |
| :--- | :--- | :--- |
| **A. tidalapi + tài khoản của người dùng, thay luồng trong `resolve_media_path`** | Người dùng phải có gói Tidal. Phải tự khớp bài YouTube với bài Tidal. Sạch về pháp lý, ổn định. | **Chọn** |
| B. API trung gian công khai (Monochrome / hifi-api, như Mochy) | Không cần tài khoản, nhưng server chạy bằng tài khoản của người dựng, hay chết bất chợt, vùng xám. | Loại |
| C. Source pool tài khoản chung (như SpatialFlow) | Dùng tài khoản của người khác. | Loại, vi phạm "Tuyệt đối không làm" |
| D. Kho nhạc Tidal riêng trong app | Tốn công giao diện, chia đôi app, phá Nghe Cùng. | Loại, đi ngược mục tiêu 2 |

## Thiết kế

### 1. Thư viện
`tidalapi` (EbbLabs/python-tidal, LGPL-3.0, dùng như thư viện nên không ảnh hưởng giấy phép Nutsty) thêm vào `requirements.txt` và `requirements_win.txt`, có ghim phiên bản (`tidalapi==0.9.0`). Mã nguồn tham khảo ở `references/python-tidal` và `references/mopidy-tidal`.

### 2. Module mới `backend/tidal_source.py` (Deep Module)
Bên ngoài chỉ thấy vài hàm:
- `login_start() -> {url, code, expires_in}`: bắt đầu đăng nhập kiểu thiết bị (`session.login_oauth()`), trả link `verification_uri_complete` để UI mở trình duyệt.
- `login_poll() -> {state: pending|ok|expired|error, account, subscription}`
- `logout()`
- `status() -> {logged_in, account, can_hires}`
- `resolve(video_id, title, artist, duration_s) -> TidalStream | None`

Bên trong:
- **Phiên đăng nhập** lưu bằng `save_session_to_file` vào `platform_compat.get_config_dir()`, tên file có `PROFILE_SUFFIX` (giống `ytmusic_auth.py`) để test 2 profile chạy song song. Quyền file 600 trên Linux. Token không bao giờ ghi ra log.
- **Khớp bài:** `session.search("<nghệ sĩ> <tên bài đã làm sạch>", models=[Track])`, chấm điểm theo tên bài (bỏ các phần "(Official Video)", "feat.", "Remastered"...), nghệ sĩ, và thời lượng lệch ≤ 3 giây. Lấy bài điểm cao nhất nếu vượt ngưỡng. Ưu tiên bản `STEREO` (Atmos để sau). Kết quả lưu vào `tidal_matches.json` (cache dir), kể cả lần không tìm thấy (nhớ 7 ngày, tránh tìm lại liên tục). YouTube Music không trả ISRC nên không khớp theo ISRC.
- **Lấy luồng:** `track.get_stream()` với `config.quality` lấy theo setting (mục 4).
  - Luồng BTS: lấy `manifest.get_urls()[0]` (link FLAC trực tiếp).
  - Luồng MPD: ghi `stream.get_manifest_data()` ra `tidal_<id>.mpd` trong temp dir, trả `file://...` (cách của mopidy-tidal).
  - `is_encrypted` thì trả `None`.
  - `TidalStream = {url, codec, bit_depth, sample_rate, audio_quality, tidal_id, expires_at}`. URL Tidal có hạn nên cache ngắn (10 phút), không dùng chung cache 20 phút của YouTube.
- **Lỗi:** mạng lỗi, 401, 429 hay không có gói đều trả `None` và ghi `stderr`. Không chặn phát. 401 sau khi làm mới token thất bại thì đánh dấu "cần đăng nhập lại" để UI hiện.
- **Thời gian:** việc khớp bài + lấy luồng có giới hạn 4 giây. Quá thì phát YouTube cho lần này, phần còn lại chạy nền để cache cho lần sau.

### 3. Nối vào luồng phát
Trong `resolve_media_path`, sau bước "file đã tải trên đĩa" và trước bước cache YouTube: nếu lossless bật và Tidal đã đăng nhập thì gọi `tidal_source.resolve(...)`. Có kết quả thì trả URL Tidal, không thì đi tiếp đường YouTube như cũ. Vẫn kiểm tra `is_play_epoch_active` trước và sau khi gọi mạng, giống code hiện tại.
- Đường `_resolve_for_crossfade` (bài tiếp theo của AutoMix) đi qua cùng logic, nên bài tiếp theo cũng là FLAC.
- `decode_levels` chạy được trên URL FLAC/MPD. Cần đo thời gian, vì FLAC lớn hơn Opus khoảng 10 lần.
- File đã tải (Opus từ YouTube) vẫn ưu tiên như cũ. Đây là ràng buộc đã biết: bài đã tải sẽ không lên FLAC. Bảng bật lossless có ghi một dòng về điều này.
- **Nghe Cùng: tạm tắt Tidal (người dùng quyết định).** Bản YouTube thường là bản video, có đoạn mở đầu dài hơn bản Tidal, trong khi ngưỡng tự tua lại là 2 giây (`DRIFT_TOLERANCE_SEC`, `social_engine.js:711`), nên phát lẫn 2 bản sẽ lệch và tua liên tục. Vì vậy:
  - Trong lúc máy này đang Nghe Cùng (làm chủ phòng hay người nghe), `resolve_media_path` bỏ qua Tidal và phát YouTube. Giao thức và sự kiện không đổi, vẫn gửi `videoId`.
  - Lúc bắt đầu Nghe Cùng mà đang phát FLAC: nạp lại bản YouTube ngay tại vị trí tương ứng để hai bên khớp (chấp nhận một khoảng ngắt nhỏ). Chế độ DAC giữ nguyên.
  - Lúc dừng Nghe Cùng: lossless bật lại **từ bài tiếp theo**, không ngắt bài đang nghe.
  - **Thông báo rõ ràng:** khi bắt đầu Nghe Cùng mà lossless đang bật, hiện toast (song ngữ, icon SVG, không emoji): "Đang Nghe Cùng: tạm phát bản YouTube để hai bên nghe khớp nhau. Lossless sẽ bật lại khi dừng nghe cùng." Khi dừng thì hiện toast: "Lossless đã bật lại từ bài tiếp theo." Trong lúc Nghe Cùng, nhãn chất lượng ghi thêm "Tạm tắt lossless khi Nghe Cùng", và mục cài đặt lossless hiện cùng dòng trạng thái đó.
- Bộ nhớ đệm của mpv: luồng FLAC dùng chung `--demuxer-cache-dir`. Cần kiểm tra dung lượng đĩa, vì FLAC to hơn nhiều.

### 4. Cài đặt
Trong `nutsty_settings.json`:
- `losslessEnabled` (mặc định `false`)
- `losslessQuality`: `"lossless"` (FLAC 16/44,1) hoặc `"hires"` (tới 24/192). Mặc định là `"hires"` nếu `can_hires`, không thì `"lossless"`.
- `dacOutputMode`: `"shared"` (mặc định, không đổi gì), `"rate_match"` (chỉ Linux), `"exclusive"`.

Trong `SettingsModal.qml`, thêm một mục "Lossless (Tidal)" gồm: trạng thái tài khoản, nút đăng nhập/đăng xuất, công tắc lossless (bật sẽ mở bảng giải thích), chọn chất lượng, chọn cách đưa âm thanh tới DAC. Mọi chuỗi đều qua `I18n.tr`, icon dùng SVG, nút dùng `accentColor`, nút đăng xuất dùng Muted Rose.

### 5. Đăng nhập (UI)
Bấm "Đăng nhập Tidal", backend gọi `login_start`, Nutsty mở trình duyệt mặc định tới link và hiện mã cùng trạng thái "Đang chờ xác nhận trên trình duyệt…". UI hỏi `login_poll` mỗi 2 giây cho tới khi xong hoặc hết hạn. Xong thì hiện tên tài khoản và gói. Gói không có lossless thì nói rõ và giữ công tắc tắt.

HiRes: code tidalapi ghi `login_pkce` là "cách duy nhất" để lấy HiRes, còn README của mopidy-tidal có chỗ nói OAuth cũng được. **Phải thử bằng tài khoản thật (bước spike).** Nếu OAuth không ra HiRes thì có 2 hướng: (a) bản đầu chỉ có FLAC 16-bit, hoặc (b) làm thêm đăng nhập PKCE bằng một server nhỏ trên localhost nhận URL chuyển hướng (cách `web_auth_server.py` của mopidy-tidal). Chọn sau khi spike, người dùng duyệt.

### 6. Đưa âm thanh tới DAC
| Chế độ | Linux | Windows | AutoMix | Âm lượng trong app |
| :--- | :--- | :--- | :--- | :--- |
| `shared` | Qua PipeWire ở tần số đang khóa (máy dev: 48 kHz) | WASAPI dùng chung | Giữ | Giữ |
| `rate_match` | PipeWire đổi tần số theo bài | Không có | Giữ. Trong lúc chồng tiếng, nếu 2 bài khác tần số thì một bài bị chuyển đổi tạm | Giữ |
| `exclusive` | mpv `--audio-exclusive=yes` | mpv `--audio-exclusive=yes` (WASAPI exclusive) | **Tắt** | Cố định 100%, chỉnh trên DAC |

- `rate_match`: Nutsty đề nghị ghi `~/.config/pipewire/pipewire.conf.d/90-nutsty-rates.conf` với `default.clock.allowed-rates = [ 44100 48000 88200 96000 176400 192000 ]`. **Phải hỏi người dùng trước khi ghi**, có nút gỡ bỏ (xóa đúng file đó). Đây là file của người dùng, không đụng file hệ thống, không cần sudo. Báo rằng cần khởi động lại PipeWire (`systemctl --user restart pipewire`) hoặc đăng xuất. Nutsty không tự khởi động lại. Nếu đã có cấu hình `allowed-rates` khác thì đọc ra và báo, không ghi đè.
- `exclusive`: mpv chính chạy `--audio-exclusive=yes`. Phải đặt lúc khởi động mpv, nên đổi chế độ là khởi động lại mpv (tiến trình chính), giữ nguyên vị trí đang phát. AutoMix tự tắt và công tắc AutoMix hiện trạng thái "Tắt do chế độ nguyên bản". Âm lượng gửi `volume=100` và thanh âm lượng bị khóa. Nếu mpv không mở được thiết bị ở chế độ riêng (app khác đang giữ) thì quay về `shared` và báo cho người dùng.
- **Thiết bị (quyết định của Claude):** cả `exclusive` lẫn `rate_match` đều dùng thiết bị ra mặc định của hệ thống, không có phần chọn thiết bị, không đi thẳng ALSA `hw:`. Trên Linux là PipeWire với `--audio-exclusive=yes`, trên Windows là WASAPI exclusive. Phần chọn DAC để sau nếu spike cho thấy cần.
- **Tiêu chí đạt của spike:** DAC nhận đúng tần số của bài. Trên Linux kiểm bằng `/proc/asound/card*/pcm*p/sub0/hw_params` khi phát bài 44,1 kHz và 96 kHz. Trên Windows kiểm bằng log của mpv (`--msg-level=ao=v`) và bảng điều khiển của DAC nếu có. Không yêu cầu kiểm chứng từng bit.
- **Máy trạng thái (quyết định của Claude):** `dacOutputMode` chỉ có tác dụng khi `losslessEnabled` bật. Khi đang bật thì áp dụng cho **mọi** bài, kể cả bài quay về YouTube và file trong máy. Tắt lossless thì về `shared`, chỉ khởi động lại mpv nếu trước đó là `exclusive`, và AutoMix trở về giá trị người dùng đã đặt trước đó (lưu lại lúc tắt). Tidal hết hạn hoặc cần đăng nhập lại thì chế độ DAC vẫn giữ nguyên, chỉ nguồn nhạc quay về YouTube.
- Khi lossless bật và không dùng `exclusive`, các bộ lọc hiện có (fade của AutoMix) chỉ chạy lúc chồng tiếng. Ngoài lúc đó không thêm bộ lọc nào khác.

### 7. Nhãn chất lượng
(Quyết định của Claude, sau khi reviewer chỉ ra lỗi của bản trước.)
- **Một nguồn duy nhất:** `get_audio_specs_dict` (`player_daemon.py`) là nơi duy nhất tạo thông tin chất lượng. **Bỏ các giá trị bịa** (mặc định `AAC`, `192 kbps`, `48.0 kHz`): không biết thì không hiện. Cả 3 chỗ đang hiện codec đều đọc từ nguồn này và bỏ chữ cứng: `PlayerBarBottom.qml:735`, `AmberolDetailView.qml:609`/`:728` (giá trị mặc định `"44.1 kHz"`), `YTMusicNowPlayingView.qml:211` (chữ `"FLAC • ..."` in sẵn).
- **Nội dung:** codec, số bit và tần số của **nguồn**, lấy từ `audio-codec-name` và `audio-params` (gồm `format` để biết số bit). Áp dụng cho mọi bài: Tidal, file FLAC trong máy (cũng là lossless thật), và YouTube (ghi Opus/AAC, không bao giờ ghi Lossless).
- **Tần số DAC thực nhận:** `audio-out-params` của mpv không thấy việc chuyển tần số ở tầng hệ thống, nên không dùng nó để kết luận.
  - Linux: đọc tần số thật của thiết bị từ `/proc/asound/card*/pcm*p/sub0/hw_params` (thẻ đang `RUNNING`), hỏi lại mỗi khi đổi bài. Nếu khác nguồn thì ghi thêm `→ 48 kHz`. Không đọc được thì không ghi gì.
  - Windows ở `shared`: không đọc tần số mix của WASAPI, mà ghi thêm `· qua Windows` để không hứa sai. Ở `exclusive` thì không ghi thêm gì.
- Nhãn dùng SVG icon, màu `accentColor`.

### 8. Bảng bật lossless
Bật công tắc thì hiện modal (song ngữ). Nội dung đã thống nhất:
- Bài tìm được trên Tidal sẽ phát FLAC. Bài không có trên Tidal vẫn phát bản YouTube như cũ.
- Hiện nhãn chất lượng thật trên thanh phát.
- Dùng nhiều dữ liệu mạng hơn: khoảng 30–50 MB/bài thay vì 3–5 MB.
- Khi Nghe Cùng, Nutsty tạm phát bản YouTube để hai bên nghe khớp nhau, rồi bật lại lossless khi dừng.
- (Thêm) Bài đã tải về máy vẫn phát bản đã tải.
- Chọn cách đưa âm thanh tới DAC (3 lựa chọn, mặc định là lựa chọn đầu):
  - "Qua hệ thống" (`shared`, cả 2 nền tảng): giữ mọi tính năng. Vẫn là FLAC nhưng hệ thống có thể chuyển tần số trước khi tới DAC.
  - "Đúng tần số gốc" (`rate_match`, chỉ Linux): giữ AutoMix, trong vài giây chuyển bài có thể bị chuyển đổi tần số tạm thời.
  - "Nguyên bản tuyệt đối" (`exclusive`): tắt AutoMix, âm lượng trong app cố định 100%, app khác không phát được tiếng qua DAC.
  - Trên Windows không hiện "Đúng tần số gốc", kèm một dòng giải thích vì sao muốn đúng tần số thì phải mất AutoMix.
- Nút: "Để sau" và "Bật lossless".

## Thứ tự làm và kiểm chứng
0. **Spike (bỏ đi sau khi xong):** script đăng nhập OAuth, khớp 10 bài, phát luồng BTS và MPD bằng mpv trên Linux và Windows. Kiểm tra: HiRes có ra với OAuth không, `decode_levels` mất bao lâu, mpv có đọc MPD không, `--audio-exclusive` có chạy với DAC thật không. Kết quả ghi vào `docs/evidence/`.
1. `tidal_source.py` + test (khớp bài, cache, quay về YouTube khi lỗi, bỏ luồng mã hóa) với dữ liệu giả, không gọi mạng.
2. Nối vào `resolve_media_path` / `_resolve_for_crossfade`.
3. Cài đặt + đăng nhập trong `SettingsModal.qml`.
4. Nhãn chất lượng.
5. Chế độ DAC (`exclusive` trước, `rate_match` sau).
6. Kiểm tra theo AGENTS.md mục 5 (`verify_codebase.py`, `verify_qml_compat.py`, `qmllint`, chạy app và chụp màn hình), trên cả Linux và Windows.

## Để người làm tự quyết
- Ngưỡng điểm khớp bài và cách làm sạch tên bài (có thể tham khảo `TrackMatcher` của Mochy).
- Bố cục chi tiết của mục cài đặt và modal, miễn là theo design system.
- Cách đọc số bit từ `audio-params/format` (s16/s32/float).

## Rủi ro
- Tidal đổi API hoặc client ID: phụ thuộc tidalapi cập nhật. Ghim phiên bản, lỗi thì luôn quay về YouTube.
- Khớp sai bài (bản live, bản remix): ngưỡng thời lượng giúp giảm. Có thể thêm nút "Phát bản YouTube cho bài này" sau.
- Dung lượng đĩa cache của mpv tăng lên vì FLAC.
