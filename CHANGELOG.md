# Changelog

Tất cả các tính năng mới và cải tiến của Nutsty được lưu trữ tại đây.

## [1.0.8] - 2026-11-06

### Added
- **Phát nhạc siêu tốc tức thì**: Nghe nhạc trực tuyến ngay trong tích tắc chưa đầy 1 giây, loại bỏ hoàn toàn cảm giác chờ đợi khi chọn bài mới.
- **Phát lại không cần mạng & không độ trễ**: Bài hát đã nghe sẽ được lưu trữ thông minh vào bộ nhớ đệm ổ cứng, bấm nghe lại là cất tiếng ngay lập tức (0 giây) kể cả khi mất kết nối mạng.
- **Hệ thống đa nguồn lời bài hát song song**: Tự động tìm kiếm đồng thời qua nhiều kho lời bài hát lớn hàng đầu (Apple Music, YouTube Music, LRCLIB, KuGou...) để chọn ra phiên bản lời chuẩn xác nhất với đúng ngôn ngữ gốc của bài hát.
- **Hát song ca phân vai ca sĩ nam và nữ**: Tự động nhận diện giọng ca sĩ chính và ca sĩ song ca để chia lời hát sang hai bên trái - phải trực quan, kèm các đoạn ré phụ âm và đối đáp sinh động.
- **Tùy chọn 9 nguồn lời bài hát linh hoạt**: Trong phần Cài đặt, bạn có thể tự do chọn nguồn lời bài hát yêu thích như Apple Music, SimpMusic, KuGou, Spotify hay phụ đề YouTube chính thức.

### Fixed
- **Loại bỏ triệt để lời dịch sai lệch**: Hệ thống chấm điểm thông minh tự động ngăn chặn các bản dịch máy tiếng Trung bị gán nhầm vào bài hát tiếng Việt, Âu Mỹ hoặc tiếng Nhật.
- **Sửa lỗi tự chuyển nguồn lời bài hát**: Khắc phục tình trạng chọn nguồn Apple Music nhưng bị nhảy nhầm về nguồn khác, đảm bảo luôn nhận đúng lời bài hát chất lượng cao nhất.

## [1.0.7] - 2026-11-04

### Added
- **Thanh phát nhạc kính lỏng viên nhộng**: Thiết kế thanh điều khiển nổi dạng viên nhộng trong suốt hiện đại, làm mờ êm ái hình ảnh bên dưới giúp tên bài hát và ca sĩ luôn nổi bật, dễ nhìn.
- **Quầng sáng tỏa lan khi giữ chuột**: Khi bạn nhấn giữ vào thanh phát nhạc, thanh sẽ phóng to nhẹ nhàng và tỏa ra vầng sáng nam châm mềm mại bám theo con trỏ chuột.
- **Thanh trượt âm lượng dạng dọc**: Bấm vào biểu tượng loa để mở thanh điều chỉnh âm lượng dọc nhỏ gọn, hỗ trợ bấm chọn mức âm lượng tức thì hoặc lăn con lăn chuột cực kỳ thuận tiện.
- **Hàng đợi bài hát tiếp theo**: Bấm biểu tượng danh sách cạnh nút Thích để mở nhanh danh sách các bài hát chuẩn bị phát.
- **Nút Thích và Đóng tiện lợi**: Trái tim đổi sang màu đỏ rực rỡ khi bạn yêu thích bài hát; nút [✕] giúp dừng phát và làm gọn thanh phát nhạc khi cần.
- **Hiển thị chất lượng nhạc & nguồn lời bài hát**: Biết chính xác chất lượng âm thanh đang nghe (Opus, AAC, FLAC Lossless) cùng nguồn cung cấp lời bài hát (Spotify, Apple Music, LRCLIB) ngay dưới tên ca sĩ.
- **Lời bài hát chạy từng từ một**: Phân biệt và ghi chú rõ ràng những bài hát có hỗ trợ nhấc chữ phát sáng theo từng từ khớp với giọng hát ca sĩ.

### Fixed
- **Nút Thích 1 chạm dứt khoát**: Bấm một lần là gắn tim và thêm ngay bài hát vào thư viện yêu thích, bấm lại là huỷ thích tức thì mà không bị giật ngược trạng thái.
- **Phát ngẫu nhiên trong Thư viện & Danh sách phát**: Bấm "Phát ngẫu nhiên" xáo trộn ngay danh sách bài hát đang xem và phát ngẫu nhiên ở thanh phát nhạc bên dưới, không còn bị phóng to che kín màn hình.
- **Sắp xếp bài hát Cũ nhất & Mới nhất chuẩn xác**: Bộ lọc sắp xếp hoạt động chính xác cho cả bài hát yêu thích lẫn bài hát tải về, giúp bạn dễ dàng tìm lại bài hát mới thêm hoặc bài hát nghe đầu tiên.
- **Bảng âm lượng tối giản & biểu tượng loa sắc nét**: Bảng âm lượng dạng viên nhộng tối giản không còn viền màu bao quanh; biểu tượng loa hiển thị đầy đủ các vòng sóng âm tròn trịa, không bị cắt mép.
- **Nghe nhạc trực tuyến liền mạch**: Khắc phục lỗi bài hát bị đứng không phát ra tiếng khi nghe từ YouTube Music, đảm bảo nhạc luôn cất tiếng ngay lập tức.
- **Thanh tiến trình bài hát chính xác**: Đường tiến trình bài hát chạy sáng mượt mà theo đúng thời gian phát thực tế kèm chấm tròn kéo tua trực quan.
- **Chuẩn hóa chất lượng phát trực tuyến**: Sửa lỗi tự động chuyển về định dạng thông thường khi đã chọn chất lượng cao Opus trong Cài đặt, đảm bảo bạn luôn được thưởng thức âm thanh chi tiết và sống động nhất.
- **Bộ nhớ đệm lời bài hát thông minh**: Ghi nhớ chính xác nguồn lời bài hát đã lưu về máy để phát tức thì ở các lần nghe sau mà không cần tải lại.

## [1.0.6] - 2026-11-04

### Added
- **Lời bài hát trên màn hình & thanh Taskbar**: Bật/tắt lời bài hát nổi tự do trên màn hình máy tính hoặc hiển thị chữ chạy ngay trên thanh tác vụ bên dưới màn hình Windows.
- **Lời bài hát lướt sóng kiểu Apple Music**: Từng chữ phát sáng và nhấc nổi nhịp nhàng theo đúng giọng ca sĩ đang hát thay vì nhảy giật từng dòng.
- **Chấm tròn đếm ngược dạo nhạc**: Khi bài hát có đoạn nhạc dạo đầu hoặc giữa bài, 3 dấu chấm sẽ phát sáng đếm ngược giúp bạn biết chính xác khi nào ca sĩ cất giọng.

### Fixed
- **Chuyển bài mượt mà**: Bấm "Không thích" sẽ tự động bỏ qua và phát bài tiếp theo ngay lập tức, không còn bị khựng danh sách phát.
- **Hoạt động ổn định trên cả Windows và Linux**: Sửa triệt để lỗi không mở được ứng dụng sau khi cập nhật, đảm bảo mở là nghe ngay trên mọi hệ thống.

## [1.0.4.2] - 2026-10-30

### Added
- **Phiên âm lời bài hát tiếng Nhật, Hàn, Trung**: Tự động hiển thị chữ phiên âm Latin (Romaji, Romaja, Pinyin) bên dưới câu hát gốc giúp bạn dễ dàng hát theo bài hát yêu thích.
- **Thanh phát nhạc nền kính tối màu**: Lớp nền sẫm màu chống lem chữ khi cuộn danh sách bài hát, giúp nhìn rõ tên bài hát và ca sĩ mà không bị rối mắt.
- **Ảnh bìa và video bìa sắc nét**: Tự động tải ảnh bìa chất lượng cao và hiển thị video bìa chuyển động của bài hát từ Apple Music và Spotify.
- **Hẹn giờ tắt nhạc êm dịu**: Tự động giảm dần âm lượng trước khi tắt nhạc để bạn đi vào giấc ngủ dễ chịu hơn.

## [1.0.4.1] - 2026-10-24

### Fixed
- **Tiết kiệm pin và mát máy**: Tối ưu hóa xử lý đồ họa giúp máy tính chạy mát hơn, không bị nóng máy khi thu nhỏ cửa sổ.
- **Nghe nhạc không gián đoạn**: Tăng tốc độ tải nhạc trực tuyến, nghe nhạc mượt mà ngay cả khi mạng yếu.
- **Cửa sổ mini ổn định**: Bấm vào biểu tượng sóng âm trên widget góc màn hình để mở lại cửa sổ chính dễ dàng.

## [1.0.4] - 2026-10-12

### Added
- **Chất lượng âm thanh cao cấp**: Thưởng thức âm thanh trong trẻo, chi tiết với chuẩn nhạc trực tuyến chất lượng cao.
- **Tải trước bài hát**: Tự động nạp trước bài tiếp theo để chuyển bài nghe liền mạch không phải chờ đợi.

## [1.0.3] - 2026-09-23

### Added
- **Chia sẻ bài hát trong Ghi chú**: Đính kèm bài hát bạn yêu thích vào ghi chú 24h để bạn bè cùng nghe và tương tác.
- **Nghe nhạc cùng bạn bè mượt mà**: Khắc phục lỗi kết nối giúp bạn và bạn bè nghe chung một bài hát cùng lúc trên cả Windows và Linux.
