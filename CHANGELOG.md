# Changelog

Tất cả các tính năng mới và cải tiến của Nutsty được lưu trữ tại đây.

## [1.0.8] - 2026-11-10

### Added
- **Đảo thể loại thông minh tại trung tâm thanh điều hướng (Dynamic Mood Island)**: Toàn bộ 11 thể loại cảm xúc được tích hợp tinh tế vào chính giữa thanh công cụ trên cùng. Ở trạng thái nghỉ, toàn bộ thể loại được thu gọn thành một viên ngọc nhỏ nhắn `[ Tất cả ]` ngay tại tâm màn hình. Khi nhấp chuột, thanh dock kính mờ nhẹ nhàng bung mở hiển thị trọn vẹn 11 thể loại cảm xúc kèm viên ngọc lướt êm ái theo thể loại được chọn, và tự động thu gọn lại sau 4.5 giây hoặc ngay khi chọn xong thể loại, giải phóng không gian trang chủ luôn rộng mở và thanh thoát.
- **Khôi phục hoạt ảnh gợn sóng nhịp nhàng cho bài hát (Mochy Ripple Wave Animation)**: Khôi phục trọn vẹn hiệu ứng gợn sóng xếp tầng khi tải trang chủ hoặc đổi thể loại cảm xúc. Từng thẻ bài hát lướt nhẹ từ dưới lên với độ trễ 35 mili-giây nhịp nhàng tạo chiều sâu thị giác sống động và nghệ thuật. Hiệu ứng chỉ xuất hiện một lần duy nhất khi nạp mới hoặc đổi thể loại, khi cuộn trang xem lại các bài hát đã tải sẽ hoàn toàn cố định và mượt mà.

## [1.0.7] - 2026-11-10

### Added
- **Đảo thể loại thông minh bung mở & thu gọn (Dynamic Mood Island)**: Toàn bộ các thể loại cảm xúc được gom gọn thành một viên ngọc nhỏ nhắn `[ Tất cả ]` ở chính giữa trang chủ. Khi bấm vào, thanh dock kính mờ nhẹ nhàng bung mở hiển thị trọn vẹn 11 thể loại cảm xúc (kể cả thể loại "Tập trung") kèm viên ngọc lướt êm ái theo thể loại được chọn, và tự động thu gọn sau 4.5 giây giúp không gian nghe nhạc luôn thoáng đãng, tinh tế.
- **Bảng áp phích nghệ thuật cạnh bên (Mochy Side Panel)**: Bấm vào thanh phát nhạc bên dưới để mở nhanh bảng áp phích trình diễn lời bài hát và ảnh bìa khổ lớn cạnh bên màn hình. Thanh phát nhạc tự động lướt sang trái và co giãn cân xứng nhường chỗ cho bảng áp phích, mang lại trải nghiệm xem lời bài hát sống động mà không che khuất danh sách nhạc.
- **Chuyển động thanh phát nhạc nhịp nhàng & chống bấm nhanh**: Khi bạn chuyển đổi qua lại giữa các màn hình hoặc bấm liên tục vào thanh phát nhạc, thanh lướt êm dịu với độ mượt mà cao, loại bỏ hoàn toàn cảm giác giật cục hay trễ khung hình.
- **Đồng bộ xóa bài hát tức thì khỏi thư viện**: Khi xóa bài hát tải về, bài hát sẽ biến mất ngay lập tức khỏi màn hình thư viện mà không cần tải lại trang, đồng thời tự động cập nhật danh sách và bộ nhớ đệm ngầm một cách liền mạch.
- **Lời bài hát song ca & đối đáp điện ảnh**: Tự động nhận diện và phân chia giọng hát nam nữ hoặc các ca sĩ song ca (như *Die With A Smile*, *Señorita*). Câu hát của từng ca sĩ được căn chỉnh trực quan hai bên trái - phải hoặc đồng ca ở giữa hài hòa, cố định vị trí chuẩn xác ngay từ khung hình đầu tiên.
- **Hiệu ứng chữ hoa nở tỏa sáng khi ngân nga**: Từng âm tiết khi ca sĩ ngân dài sẽ nở rộng mềm mại và tỏa quầng sáng êm dịu theo đúng nhịp điệu của bài hát, tạo cảm giác sống động như thưởng thức một MV âm nhạc nghệ thuật.
- **Chấm tròn đếm ngược dạo nhạc thông minh**: Khi bài hát có đoạn nhạc dạo (từ 4 giây trở lên), 3 dấu chấm tròn sẽ nhẹ nhàng bung nở và phát sáng đếm ngược từng nhịp điệu, giúp bạn biết chính xác thời điểm câu hát tiếp theo chuẩn bị bắt đầu.
- **Căn lề cân đối chuẩn xác theo ca sĩ**: Dấu chấm dạo nhạc được căn chỉnh thẳng tắp theo lề lời bài hát của từng ca sĩ (bên trái, bên phải hoặc đồng ca chính giữa), tạo nên bố cục cân đối và thuận mắt.
- **Quầng sáng tỏa tròn 360° tự nhiên**: Ánh sáng xung quanh các chấm tròn được hoàn thiện tỏa tròn mềm mại và chuyển màu sống động theo bìa bài hát.
- **Giọng hát bè tự động bung nở & thu gọn**: Các câu bè phụ trong ngoặc đơn tự động bung mở mềm mại khi cất tiếng và thu lại nhịp nhàng sau khi dứt câu, loại bỏ hoàn toàn hiện tượng chớp nháy hay biến mất đột ngột.
- **Cuộn trang thông minh & đệm chờ 3.5 giây**: Khi bạn lăn chuột hoặc kéo lướt lên xuống để xem lại lời bài hát trước đó, màn hình sẽ giữ nguyên vị trí cho bạn thoải mái đọc trong 3.5 giây mà không bị giật hay nhảy cóc về câu ca sĩ đang hát. Hết 3.5 giây không chạm chuột, danh sách sẽ tự động lướt êm ái trở lại câu hát hiện tại.
- **Lăn chuột siêu nhạy và mượt mà**: Khôi phục hoàn toàn khả năng lăn con lăn chuột trên toàn bộ danh sách lời bài hát với độ nhạy cao, cuộn trơn tru tự nhiên trên cả chuột rời và bàn rê cảm ứng máy tính xách tay.
- **Căn chỉnh tầm mắt quang học chuẩn phòng chiếu**: Khoảng trống phía trên danh sách lời bài hát được tối ưu vừa vặn, câu hát đang thể hiện luôn nằm đúng tầm mắt nhìn tự nhiên nhất, kết hợp hiệu ứng làm mờ quang học điện ảnh giúp bạn hoàn toàn đắm chìm vào bài hát.
- **Phát nhạc siêu tốc tức thì**: Nghe nhạc trực tuyến ngay trong tích tắc chưa đầy 1 giây, loại bỏ hoàn toàn cảm giác chờ đợi khi chọn bài mới.
- **Phát lại không cần mạng & không độ trễ**: Bài hát đã nghe sẽ được lưu trữ thông minh vào bộ nhớ đệm ổ cứng, bấm nghe lại là cất tiếng ngay lập tức (0 giây) kể cả khi mất kết nối mạng.
- **Hệ thống đa nguồn lời bài hát song song**: Tự động tìm kiếm đồng thời qua nhiều kho lời bài hát lớn hàng đầu (Apple Music, YouTube Music, LRCLIB, KuGou...) để chọn ra phiên bản lời chuẩn xác nhất với đúng ngôn ngữ gốc của bài hát.
- **Tùy chọn 9 nguồn lời bài hát linh hoạt**: Trong phần Cài đặt, bạn có thể tự do chọn nguồn lời bài hát yêu thích như Apple Music, SimpMusic, KuGou, Spotify hay phụ đề YouTube chính thức.
- **Thanh phát nhạc kính lỏng viên nhộng**: Thiết kế thanh điều khiển nổi dạng viên nhộng trong suốt hiện đại, làm mờ êm ái hình ảnh bên dưới giúp tên bài hát và ca sĩ luôn nổi bật, dễ nhìn.
- **Quầng sáng tỏa lan khi giữ chuột**: Khi bạn nhấn giữ vào thanh phát nhạc, thanh sẽ phóng to nhẹ nhàng và tỏa ra vầng sáng nam châm mềm mại bám theo con trỏ chuột.
- **Thanh trượt âm lượng dạng dọc**: Bấm vào biểu tượng loa để mở thanh điều chỉnh âm lượng dọc nhỏ gọn, hỗ trợ bấm chọn mức âm lượng tức thì hoặc lăn con lăn chuột cực kỳ thuận tiện.
- **Hàng đợi bài hát tiếp theo**: Bấm biểu tượng danh sách cạnh nút Thích để mở nhanh danh sách các bài hát chuẩn bị phát.
- **Nút Thích và Đóng tiện lợi**: Trái tim đổi sang màu đỏ rực rỡ khi bạn yêu thích bài hát; nút [✕] giúp dừng phát và làm gọn thanh phát nhạc khi cần.
- **Hiển thị chất lượng nhạc & nguồn lời bài hát**: Biết chính xác chất lượng âm thanh đang nghe (Opus, AAC, FLAC Lossless) cùng nguồn cung cấp lời bài hát (Spotify, Apple Music, LRCLIB) ngay dưới tên ca sĩ.
- **Lời bài hát chạy từng từ một**: Phân biệt và ghi chú rõ ràng những bài hát có hỗ trợ nhấc chữ phát sáng theo từng từ khớp với giọng hát ca sĩ.
- **Bộ điều khiển gốc siêu tốc**: Nâng cấp bộ cầu nối điều khiển âm nhạc chuyên dụng bằng ngôn ngữ Rust với tốc độ phản hồi chỉ 1 mili-giây, đảm bảo mọi thao tác bấm đều ăn ngay lập tức.
- **Khung xương chờ dập dềnh êm ái & Chuyển giao 3 nhịp quang học**: Khi ứng dụng nạp dữ liệu bài hát, các khung xương vị trí hiển thị một dải sóng ánh sáng nhẹ nhàng quét ngang toàn bộ danh sách. Khi dữ liệu xuất hiện, khung xương mờ dần êm dịu và bài hát lướt nhẹ vào vị trí mà không bị chớp giật hay nhảy hình đột ngột.
- **Hiệu ứng trượt tầng nối đuôi thanh lịch**: Các bài hát, album và danh sách phát khi xuất hiện lần đầu sẽ lần lượt lướt nhẹ từ dưới lên theo hiệu ứng xếp tầng bậc thang mềm mại, tạo chiều sâu thị giác sống động. Hệ thống ghi nhớ thông minh chỉ diễn hoạt một lần duy nhất, khi bạn cuộn lên xuống xem lại sẽ hoàn toàn cố định, trơn tru.
- **Lướt ngang danh sách bài hát siêu mượt**: Nâng cấp toàn bộ các hàng bài hát, album và video lướt ngang bằng cơ chế tái sử dụng khung hình ảo hóa. Dù danh sách có hàng trăm bài hát, ứng dụng chỉ vẽ các mục đang hiển thị trên màn hình, giúp thao tác lướt qua lại bằng chuột hoặc phím mũi tên nhẹ như bay, không tốn tài nguyên máy tính.
- **Cô lập vùng vẽ đồ họa & Nền kính lỏng thích ứng tĩnh**: Toàn bộ các sóng âm chuyển động và hiệu ứng nhịp điệu được cô lập gọn gàng trong ranh giới riêng biệt, ngăn chặn hoàn toàn việc vẽ lại không cần thiết toàn bộ cửa sổ kính mờ. Thanh phát nhạc tự động nhận biết khi đứng yên để ngắt vẽ lại nền kính, đưa mức tiêu thụ đồ họa lúc nghỉ về 0%.
- **Tự động xả sạch RAM và hạ tải thông minh khi ẩn hoặc không chạm**: Khi bạn chuyển sang làm việc trên ứng dụng khác hoặc thu nhỏ Nutsty thành widget góc màn hình, ứng dụng tự động giảm tần số làm mới, tạm dừng toàn bộ hiệu ứng chuyển động ngầm và chủ động thu hồi hàng trăm Megabyte bộ nhớ RAM trả lại cho hệ thống máy tính sau 15 giây. Khi bạn bấm quay lại, toàn bộ giao diện phục hồi tức thì với tốc độ 60 khung hình/giây.
- **Nền mờ kính lỏng siêu nhẹ & Mát máy (Blur Effect Cache)**: Ứng dụng kỹ thuật thu nhỏ ảnh trước khi làm mờ kết hợp chuẩn hóa các nấc làm mờ cố định, giúp hiệu ứng kính mờ và quầng sáng nền vẫn mềm mại như nhung nhưng cắt giảm tới 80% tải đồ họa và bộ nhớ VRAM của máy tính. Đồng thời, các lớp mờ bị che khuất sẽ tự động ngắt hoàn toàn để tiết kiệm pin tối đa.
- **Tối ưu hóa bộ nhớ chuyên sâu & Thu hồi tài nguyên đồ họa ngầm**: Tự động giải phóng các vùng đệm hình ảnh và khuôn cắt bo tròn ngay khi hình ảnh nằm ngoài màn hình hoặc bị ẩn. Tinh chỉnh bộ đệm nạp trước thông minh giúp cắt giảm hơn 370 Megabyte bộ nhớ hoạt động, mang lại trải nghiệm cực kỳ mát máy và tiết kiệm pin mà vẫn giữ trọn độ mượt mà khi cuộn lướt.
- **Nền chất lỏng sống động & Quầng sáng quét lời bài hát điện ảnh (Liquid Warp & Lagged Bloom Engine)**: Nâng cấp toàn diện trải nghiệm hình ảnh khi phát nhạc với công nghệ biến dạng chất lỏng 2 chiều thời gian thực. Bìa bài hát được chuyển hóa thành các dải lụa màu sắc mềm mại, liên tục cuộn trôi và thở theo nhịp điệu bài hát mà không làm nóng máy hay tốn pin. Tốc độ sóng được tinh chỉnh giảm xuống mức lững lờ, thư thái và quý phái (chu kỳ 50 giây tuần hoàn khép kín hoàn hảo), kết hợp đồng bộ tone màu đen huyền bí sâu thẳm dịu mắt xuyên suốt cả hai màn hình, triệt tiêu hoàn toàn hiện tượng chói lóa ánh trắng khi gặp ảnh bìa sáng màu.
- **Phân tách hoàn hảo cử chỉ Nhấn giữ (Hold) và Nhấp nhanh (Click) trên thanh phát nhạc**: Khôi phục trọn vẹn khả năng nhấn giữ chuột trái ở bất kỳ đâu trên thanh phát nhạc để kích hoạt hiệu ứng quầng sáng Spotlight rực rỡ và phóng to nhẹ theo con trỏ chuột mà không bị kẹt bởi tiêu đề hay tên nghệ sĩ. Thao tác nhấp chuột nhanh sẽ mở/đóng bảng áp phích cạnh bên dứt khoát, và khi buông chuột sau khi nhấn giữ ngắm Spotlight thì thanh nhạc tự động thu về êm đềm mà không làm gián đoạn hay đóng/mở bảng áp phích ngoài ý muốn.

### Fixed
- **Bố cục đáp ứng phẳng tuyệt đối cho hàng thẻ bài hát (Responsive Flush-Fit Carousel)**: Khắc phục triệt để hiện tượng mục "Nghe lại" (thẻ chữ nhật 16:9) và các hàng danh sách bài hát bị hở một khoảng trống lớn ở mép phải khi mở bảng áp phích hoặc bị xén dở dang khi mở rộng cửa sổ. Ứng dụng tự động tính toán số lượng thẻ vừa khít 100% bề rộng hiển thị theo tỷ lệ chuẩn, loại bỏ hoàn toàn tình trạng thẻ bị tàng hình vô lý, đảm bảo mọi hàng bài hát luôn dừng thẳng tắp sát mép nút điều hướng, chuẩn xác đến từng pixel ("không thiếu không dư").
- **Tự động chuyển bài mượt mà không bị ngắt tiếng**: Khắc phục triệt để hiện tượng bài hát khi phát hết không tự động chuyển sang bài tiếp theo mà lại bị dừng khựng ở trạng thái nghỉ, đảm bảo âm nhạc luôn ngân vang liên tục và liền mạch.
- **Khắc phục lỗi mất hiệu ứng quầng sáng Spotlight khi giữ chuột vào thanh phát nhạc**: Sửa triệt để xung đột sự kiện chuột giữa các vùng chữ và thân thanh phát, đảm bảo cử chỉ nhấn giữ để tỏa sáng và cử chỉ nhấp mở bảng áp phích luôn nhận lệnh chính xác và độc lập tuyệt đối.
- **Khắc phục hiện tượng chói lóa nền trắng trên màn hình phát nhạc**: Đồng bộ lớp phủ tối huyền bí, giữ trọn độ sâu và tương phản cao cấp của giao diện kể cả khi bài hát có ảnh bìa màu trắng sáng.
- **Cân đối khoảng cách đáy và lề cạnh bên hoàn hảo**: Tinh chỉnh khoảng cách lề dưới đáy bằng đúng khoảng cách lề bên phải, tạo nên bố cục cân xứng, thẳng tắp và thuận mắt trên toàn bộ cửa sổ ứng dụng.
- **Phân tách vùng bấm trên thanh phát nhạc**: Bấm vào ảnh bìa nhỏ sẽ mở xem chi tiết bài hát, bấm vào thân thanh phát để mở bảng áp phích, và các nút điều khiển âm lượng, chuyển bài, yêu thích luôn nhận lệnh độc lập, không bị bấm nhầm lẫn.
- **Hiển thị đầy đủ mọi thể loại nhạc không bị cắt viền**: Khắc phục hiện tượng thể loại "Tập trung" bị xén mất chữ hoặc chém mép viền, đảm bảo toàn bộ 11 thẻ thể loại đều hiển thị vuông vắn, tròn trịa và rõ ràng.
- **Không tự động che kín màn hình khi bấm phát nhạc**: Khắc phục hiện tượng chọn phát một bài hát từ danh sách trang chủ hoặc nghệ sĩ làm phóng to màn hình lời bài hát che mất danh sách đang xem.
- **Phát bài hát tải về trực tiếp không độ trễ**: Khi phát các bài hát đã tải về trong máy tính, nhạc cất tiếng ngay lập tức từ bộ nhớ cục bộ mà không cần kết nối mạng hay gửi yêu cầu chờ đợi.
- **Chấm dứt hiện tượng chớp nháy và biến mất đột ngột khi đổi thể loại nhạc**: Khắc phục triệt để lỗi khi bấm chọn thể loại tâm trạng (như Năng lượng, Thư giãn) bị hiện tạm bợ danh sách cũ rồi đột ngột biến mất để hiện danh sách mới. Nutsty hiện khung xương chờ đúng tên thể loại hoặc hoán đổi trực tiếp tại chỗ không chớp nháy khi đã có sẵn trong bộ nhớ đệm.
- **Nút Dừng & Phát nhạc dứt khoát tuyệt đối**: Sửa triệt để hiện tượng bấm Dừng nhưng nhạc vẫn chạy hoặc bấm Phát bị đảo ngược trạng thái, phản hồi cực kỳ chuẩn xác và ổn định.
- **Điều hướng bài hát chuẩn xác**: Thao tác chuyển bài kế tiếp và quay lại bài trước hoạt động mượt mà, đúng danh sách và đúng nhịp điệu của hàng đợi.
- **Tự động co gọn dấu chấm khi hết đoạn dạo**: Khắc phục hiện tượng dấu chấm bị lưu lại trên màn hình; khi chuẩn bị vào câu hát mới, 3 chấm sẽ tự động thu gọn êm ái về 0 và biến mất hoàn toàn.
- **Khắc phục vệt cắt góc cạnh của quầng sáng phát quang**: Loại bỏ triệt để hiện tượng quầng sáng bị xén viền hình chữ nhật, ánh sáng tỏa đều 360 độ dịu mắt và liền mạch.
- **Chấm dứt hiện tượng nhảy cóc lời bài hát khi cuộn**: Sửa triệt để lỗi danh sách lời bài hát tự động nhảy vọt xuống theo câu hát khi bạn đang kéo lên xem lại các câu trước, đảm bảo khung nhìn luôn đứng yên vững vàng cho bạn thoải mái đọc lời.
- **Triệt tiêu hiện tượng chớp nháy câu hát bè**: Khắc phục lỗi câu hát bè phụ bị biến mất rồi xuất hiện lại hoặc giật khựng khi chuyển câu, toàn bộ hiệu ứng hoa nở và thu hồi diễn ra mượt mà và liền mạch.
- **Khắc phục lỗi tê liệt con lăn chuột**: Sửa lỗi không cuộn được bằng con lăn chuột trên màn hình lời bài hát, thao tác lướt trang trở lại mượt mà, siêu nhạy và tự nhiên.
- **Phát nhạc mượt mà cất tiếng ngay lập tức**: Khắc phục triệt để lỗi bấm vào bài hát bị dừng ở giây 0:00 không có tiếng, nhạc luôn cất tiếng tức thì, ổn định và êm tai.
- **Lời bài hát tiếng Anh liền mạch tự nhiên**: Khắc phục hiện tượng các từ vựng tiếng Anh bị ngắt rời vụn vặt (như "member", "realized"), đảm bảo toàn bộ từ ngữ hiển thị trọn vẹn, chuẩn xác và dễ đọc khi hát theo.
- **Loại bỏ triệt để lời dịch sai lệch**: Hệ thống chấm điểm thông minh tự động ngăn chặn các bản dịch máy tiếng Trung bị gán nhầm vào bài hát tiếng Việt, Âu Mỹ hoặc tiếng Nhật.
- **Sửa lỗi tự chuyển nguồn lời bài hát**: Khắc phục tình trạng chọn nguồn Apple Music nhưng bị nhảy nhầm về nguồn khác, đảm bảo luôn nhận đúng lời bài hát chất lượng cao nhất.
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
