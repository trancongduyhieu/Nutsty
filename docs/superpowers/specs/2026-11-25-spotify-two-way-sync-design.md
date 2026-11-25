# Đồng bộ hai chiều Spotify ↔ Nutsty (thiết kế)

Ngày: 2026-11-25. Trạng thái: người dùng đã duyệt.

## 1. Ý định và lý do

Người dùng (và bạn bè của họ) đang "chuyển nhà" từ Spotify sang Nutsty vì Nutsty không có quảng cáo.
Ai cũng dùng tài khoản Spotify **Free**. Trong thời gian chuyển, họ vẫn thêm/bớt bài bên Spotify và muốn
Nutsty tự theo kịp; ngược lại, thích một bài hay thêm/bớt bài trong Nutsty thì Spotify cũng đổi theo.

Giao diện vẫn là của Nutsty. Spotify chỉ là nguồn dữ liệu chạy ngầm. Spatial Flow đã bị loại chính vì nó
phủ giao diện Spotify (Home, thư viện) lên app.

Hiện tại `backend/spotify_importer.py` chỉ **nhập một lần**: mỗi lần nhập lại tạo playlist mới
`custom_pl_spotify_{pid}_{timestamp}` (trùng lặp), có lưu `spotifyId` nhưng không dùng, không nhập bài đã thích,
và `spotify_cached_playlists.json` không bao giờ hết hạn.

## 2. Mục tiêu, ngoài phạm vi, điều không được xảy ra

**Đợt 1: Spotify → Nutsty (chỉ đọc)**
- Mọi playlist trong thư viện Spotify của người dùng (playlist của họ và playlist họ theo dõi) có bản tương ứng
  trong Nutsty, tự cập nhật: bài thêm bên Spotify xuất hiện, bài xóa bên Spotify biến mất.
- Bài đã thích trên Spotify gộp vào danh sách bài đã thích của Nutsty.
- Mỗi bài Spotify chỉ khớp sang YouTube **một lần**, kết quả được nhớ lại.
- Playlist đã nhập trước đây (có `spotifyId`) được nối vào cơ chế này thay vì nhập lại.

**Đợt 2: Nutsty → Spotify (ghi ngược, có công tắc, mặc định tắt)**
- Thích / bỏ thích một bài trong Nutsty → thích / bỏ thích bên Spotify.
- Thêm / bớt bài trong một playlist đã liên kết (do người dùng sở hữu hoặc cộng tác) → thêm / bớt bên Spotify.

**Ngoài phạm vi**
- Tạo playlist mới, xóa playlist, đổi tên, đổi ảnh bìa bên Spotify.
- Đẩy thứ tự sắp xếp từ Nutsty lên Spotify (thứ tự chỉ đi theo chiều Spotify → Nutsty cho bài mới thêm).
- Trang Home, gợi ý, duyệt thư viện Spotify kiểu Spatial Flow.
- Podcast, tập podcast, file local trong playlist Spotify (bỏ qua, không báo lỗi).
- API chính thức Spotify: cần Premium cho chủ app và giới hạn 5 người dùng (thay đổi 02/2026), không hợp với người dùng Free.

**Không được xảy ra (dù kỹ thuật vẫn "chạy")**
- Bài người dùng vừa xóa ở một bên tự quay lại sau lần đồng bộ sau.
- Spotify trả về rỗng / lỗi / bị chặn mà Nutsty hiểu thành "mọi bài đã bị xóa" và xóa sạch playlist.
- Playlist trùng lặp sinh ra mỗi lần đồng bộ, hoặc bài bị thêm hai lần bên Spotify khi hai máy cùng đồng bộ.
- Ghi dồn dập lên Spotify khiến tài khoản người dùng bị chú ý / khóa.
- Dùng cookie, token hay tài khoản của người khác; pool tài khoản chung.
- Chuỗi giao diện chỉ có tiếng Việt hoặc emoji (luật AGENTS.md).

## 3. Ràng buộc

- Đăng nhập bằng cookie `sp_dc` của chính người dùng (đã có: tự đọc từ trình duyệt hoặc dán), lưu trong
  `nutsty_settings{suffix}.json`. Token web-player + TOTP lấy qua `lyrics_helper.get_spotify_access_token`;
  dữ liệu qua `api-partner.spotify.com/pathfinder/v1/query` (GraphQL persisted query) như importer đang làm.
- Đây là API nội bộ của web-player: **trái điều khoản Spotify**, và mã hash của truy vấn thay đổi theo thời gian
  (Nutsty đang dùng hash `fetchPlaylist` khác với hash trong APK Spatial Flow). Phải hỏng một cách an toàn.
- Hồ sơ (profile): mọi file dùng hậu tố `PROFILE_SUFFIX` / `_ACTIVE_SUFFIX` như `playlist_manager`.
- Đồng bộ giữa các máy (`backend/account_sync.py`) đã đồng bộ playlist và bài đã thích; cơ chế Spotify phải sống
  chung với nó (xem mục 5.7).
- Song song Linux (`route_dispatcher.py`, nutsty-daemon) và Windows (`auth_server.py`); mọi route mới phải có ở cả hai.
- Mọi chuỗi qua `I18n.tr`, icon SVG, nút theo `accentColor` (AGENTS.md mục 2).

## 4. Các hướng đã cân nhắc

| Hướng | Ưu | Nhược | Kết quả |
|---|---|---|---|
| A. API chính thức (OAuth, Client ID riêng) | Ổn định, đúng điều khoản | Chủ app phải có Premium, tối đa 5 người | Loại: người dùng và bạn bè đều Free |
| B1. Cookie, chia hai đợt: đọc tự động trước, ghi ngược sau có công tắc | Có lợi sớm, rủi ro ghi tách riêng, ai sợ thì không bật | Hai đợt giao hàng | **Được chọn** |
| B2. Cookie, hai chiều đầy đủ một lần, gồm tạo playlist | Đúng trọn mong muốn | Lâu, nhiều điểm gãy, tạo playlist qua web-player chưa có tiền lệ ổn định | Loại |
| B3. Cookie, chỉ đọc | An toàn nhất | Không đáp ứng chiều ghi | Loại (nhưng chính là Đợt 1) |

## 5. Thiết kế

### 5.1 Liên kết playlist
- Playlist Nutsty liên kết với Spotify có id cố định `custom_pl_spotify_{spotifyPlaylistId}` (không timestamp),
  nên hai máy cùng tạo ra một id và đồng bộ máy hội tụ.
- Thêm trường `spotifyLink` vào bản ghi playlist: id Spotify, `owned` (có quyền ghi hay không), danh sách
  id bài Spotify ở lần đồng bộ trước (`base`), mốc revision/snapshot Spotify nếu có, thời điểm đồng bộ cuối.
  Trạng thái này nằm **trong** bản ghi playlist để `account_sync` mang nó theo sang máy khác.
- Mỗi bài trong playlist liên kết mang thêm `spotifyId` (id bài Spotify) nếu có.
- Di trú: playlist cũ `source == "spotify_import"` có `spotifyId` → bản mới nhất của mỗi `spotifyId` trở thành
  bản liên kết (đổi sang id cố định); các bản trùng cũ hơn giữ nguyên, không liên kết, người dùng tự xóa. (Quyết định của tôi.)
- Bản nhập cũ không có `spotifyId` trên từng bài và không có `base`. Khi di trú: khớp lại từng bài Spotify (dùng
  bộ nhớ khớp, nên chỉ tốn một lần), bài nào ra videoId đã có trong playlist thì gắn `spotifyId` cho bài đó;
  `base` = mọi bài Spotify hiện tại. Bài Spotify chưa có trong playlist được thêm vào: bản nhập cũ không có lịch sử
  xóa nên không phân biệt được "đã xóa" với "mới thêm", và với việc chuyển nhà thì thiếu bài mới tệ hơn.
  Hệ quả chấp nhận được, chỉ một lần: bài người dùng từng xóa khỏi bản nhập cũ có thể quay lại. (Quyết định của tôi.)

### 5.1b Chọn playlist (người dùng đã duyệt)
- Lần đầu bật "Tự cập nhật từ Spotify", Nutsty hiện danh sách playlist trong thư viện Spotify kèm ô đánh dấu.
  Playlist của người dùng được đánh sẵn; playlist do Spotify tự tạo (chủ sở hữu là Spotify: Discover Weekly,
  Release Radar, Daily Mix...) để trống. Bài đã thích là một mục riêng, đánh sẵn.
- Chưa xác nhận lựa chọn thì chưa đồng bộ gì. Có thể đổi lựa chọn sau trong Cài đặt.
- Playlist Spotify tự tạo, nếu được chọn, đồng bộ kiểu **thay nguyên danh sách** mỗi lần: không qua gộp ba bên,
  không qua chốt chặn xóa hàng loạt, không bao giờ ghi ngược.
- Playlist mới xuất hiện bên Spotify sau đó: của người dùng thì tự thêm vào lựa chọn; do Spotify tạo thì không.

### 5.2 Bộ nhớ khớp bài
- File `spotify_match_cache{suffix}.json`: id bài Spotify → videoId YouTube (hoặc "không khớp được" kèm thời điểm thử).
- Khớp Spotify → YouTube dùng lại `match_spotify_track_to_ytmusic` (chấm điểm tên/nghệ sĩ/thời lượng hiện có).
- Bài không khớp được thử lại sau vài ngày, không phải mỗi lần đồng bộ.
- Khớp ngược YouTube → Spotify (Đợt 2): tìm bên Spotify bằng tên + nghệ sĩ, dùng cùng hàm chấm điểm và ngưỡng;
  không đủ điểm thì bài đó là "chỉ có trên Nutsty".

### 5.3 Gộp ba bên cho mỗi playlist
Với mỗi playlist liên kết, so ba tập id bài Spotify: `base` (lần trước), `remote` (Spotify bây giờ),
`local` (bài trong Nutsty có `spotifyId`):
- Có trong remote, không có trong base → bài mới bên Spotify: thêm vào Nutsty (thêm cuối, theo thứ tự Spotify).
- Có trong base, không có trong remote → Spotify đã xóa: xóa khỏi Nutsty nếu còn.
- Có trong base, không có trong local → người dùng đã xóa trong Nutsty: **không** thêm lại.
  Đợt 2 (công tắc bật, playlist `owned`): xếp lệnh xóa bên Spotify.
- Có trong local, không có trong base → người dùng thêm trong Nutsty. Đợt 2: xếp lệnh thêm bên Spotify.
- Bài không có `spotifyId` (bài YouTube thêm tay, không khớp ngược được) không bao giờ bị lần kéo về xóa.
- Sau khi áp xong, `base` = remote mới (cộng/trừ các lệnh ghi đã thành công).
Hàm gộp là hàm thuần (vào ba tập, ra danh sách thay đổi) để kiểm thử độc lập.

Bài đã thích dùng đúng quy tắc này, với "playlist" là danh sách bài đã thích của cả hai bên.
Bài đã thích của Spotify gộp vào danh sách đã thích của Nutsty (không tạo playlist riêng). (Quyết định của tôi:
ghi ngược "thích" chỉ có nghĩa khi hai bên là cùng một danh sách.)

### 5.4 Chống xóa nhầm
- Lần kéo về chỉ được coi là hợp lệ khi lấy đủ mọi trang và tổng số bài khớp với số Spotify báo.
  Lỗi mạng, 401/403/429, trả rỗng bất thường, hay phân trang dừng giữa chừng → bỏ qua playlist đó lần này, không xóa gì.
- Một lần đồng bộ định xóa quá nửa playlist (và hơn vài bài) thì dừng, không áp dụng, báo trong Cài đặt.
  Cạnh thông báo có nút "Vẫn áp dụng" cho đúng playlist đó; bấm thì lượt sau áp dụng thay đổi và `base` đi tiếp.
  Playlist không bị đóng băng mãi. (Quyết định của tôi.)

### 5.5 Lịch chạy và giới hạn tần suất
- Chạy khi mở app (chậm khoảng 20 giây), mỗi 3 giờ, và khi bấm "Đồng bộ ngay".
- Trước khi tải từng playlist, so revision/snapshot (hoặc số bài) với lần trước; không đổi thì bỏ qua.
- Gọi tuần tự, có nghỉ giữa các lần gọi; 429 thì tôn trọng `Retry-After`, lặp lại thì dừng cả lượt.
- Danh sách playlist Spotify (`spotify_cached_playlists.json`) có hạn dùng thay vì giữ mãi.

### 5.6 Ghi ngược (Đợt 2)
- Công tắc "Ghi ngược lên Spotify", mặc định tắt, có dòng giải thích rủi ro.
- Không gắn hook vào các chỗ ghi playlist / bài đã thích: thay đổi được suy ra từ phép so ở 5.3, giống cách
  `account_sync` làm, nên mọi đường sửa (menu chuột phải, kéo thả, máy khác gửi sang) đều được bắt.
- Khi bật công tắc, Nutsty lấy mốc ngay lúc đó: chỉ những thay đổi **sau** khi bật mới được đẩy lên Spotify
  (người dùng đã duyệt). Bài đã thích / bài thêm từ trước không tự đẩy.
- Nút riêng "Đẩy các bài đã thích trước đó": đẩy phần tồn đọng đó, chạy chậm qua cùng hàng đợi và giới hạn,
  có thể dừng giữa chừng, hiện tiến độ.
- Lệnh ghi xếp hàng, gửi chậm (khoảng một lệnh mỗi vài giây, giới hạn số lệnh mỗi lượt).
- Trước khi thêm, đọc lại playlist bên Spotify: bài đã có thì bỏ qua. Nhờ vậy hai máy cùng đẩy không gây trùng.
- Chỉ ghi vào playlist `owned`; playlist theo dõi của người khác chỉ đọc.
- Thao tác ghi dùng persisted query `addToPlaylist`, `removeFromPlaylist`, `addToLibrary`, `removeFromLibrary`
  (đã thấy khai báo trong APK Spatial Flow).

### 5.7 Sống chung với đồng bộ giữa các máy
- Trạng thái liên kết nằm trong bản ghi playlist nên đi theo `account_sync`.
- Công tắc "Tự cập nhật từ Spotify" là **của từng máy** (không đồng bộ). Chỉ máy bật nó mới gọi Spotify;
  máy khác nhận kết quả qua `account_sync`. Cài đặt nói rõ: chỉ nên bật trên một máy. (Quyết định của tôi.)
- `base` của bài đã thích lưu cục bộ trên máy chạy đồng bộ Spotify (`spotify_sync_state{suffix}.json`),
  không thêm loại dữ liệu mới vào cloud relay (`SYNC_KINDS` giữ nguyên, không phải deploy lại Worker).
- Máy chưa có `base` (lần đầu, hoặc vừa chuyển sang làm máy đồng bộ) chạy một lượt **lấy mốc**: `base` = Spotify
  hiện tại, chỉ kéo bài thêm về, không xóa và không ghi gì lên Spotify. Nhờ vậy không có chuyện thích lại bài đã bỏ thích.
- Máy có cookie đọc lại Spotify trước khi ghi (5.6), nên lệnh trùng không nhân đôi bài.

### 5.8 Lỗi và hỏng an toàn
- Cookie hết hạn / token ẩn danh → dừng, trạng thái trong Cài đặt: cần đăng nhập Spotify lại.
- Hash truy vấn bị Spotify đổi (lỗi persisted query) → tắt phần bị ảnh hưởng (đọc hoặc ghi), báo
  "Spotify vừa thay đổi, cần cập nhật Nutsty"; không xóa, không ghi gì thêm.
- Mọi thông báo lỗi trả về giao diện dưới dạng mã lỗi; QML dịch qua `I18n.tr` (không trả chuỗi tiếng Việt cứng từ backend).

### 5.9 Giao diện
- Cài đặt → Tài khoản → hàng "Tài khoản Spotify" hiện có, thêm: công tắc "Tự cập nhật từ Spotify",
  công tắc "Ghi ngược lên Spotify" (kèm dòng rủi ro), thời điểm đồng bộ cuối, nút "Đồng bộ ngay", lỗi gần nhất.
- Playlist liên kết có huy hiệu Spotify nhỏ (SVG) cạnh tên; bài "chỉ có trên Nutsty" có nhãn nhỏ trong playlist liên kết.
- `SpotifyImportModal` vẫn giữ để dán link playlist công khai của người khác (nhập một lần, không liên kết).
- Một component QML `SpotifySync.qml` theo khuôn `AccountSync.qml` (trạng thái, chạy, hẹn giờ), khai báo một lần trong `shell.qml`.

## 6. Để người xây dựng quyết định
- Mã hash, biến và cách đọc phản hồi của các truy vấn GraphQL (`libraryV3`, `fetchLibraryTracks`, `fetchPlaylist`,
  `searchDesktop`, các lệnh ghi); nơi lưu hash để thay nhanh khi Spotify đổi.
- Khoảng nghỉ cụ thể giữa các lần gọi, số lệnh ghi tối đa mỗi lượt, thời hạn thử lại bài không khớp.
- Tên module/route (ví dụ `backend/spotify_sync.py`, `/api/spotify/sync/*`), miễn có ở cả Linux và Windows.
- Kiểm thử: hàm gộp ba bên, chốt chặn chống xóa nhầm, bộ nhớ khớp, di trú playlist cũ — kiểm thử không gọi mạng;
  cộng `scripts/verify_codebase.py` và `scripts/verify_qml_compat.py`.
