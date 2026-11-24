# Changelog

Tất cả các tính năng mới và cải tiến của Nutsty được lưu trữ tại đây.

Số phiên bản có dạng `A.B.C`, ví dụ `1.2.0`:
- **C (số thứ 3)** tăng khi bản mới chỉ sửa lỗi và chỉnh nhỏ, không có tính năng mới. Ví dụ `2.1.0` lên `2.1.1`.
- **B (số thứ 2)** tăng khi có tính năng mới mà mọi thứ cũ vẫn dùng bình thường. Số thứ 3 về 0, ví dụ `2.1.3` lên `2.2.0`.
- **A (số đầu tiên)** tăng khi có thay đổi lớn buộc bạn làm lại gì đó hoặc dữ liệu, cài đặt của bản cũ không dùng được nữa. Hai số sau về 0, ví dụ `2.4.1` lên `3.0.0`.

## [Unreleased]

### Added
- **Hẹn giờ ngủ mới, rộng và dễ dùng hơn**: Bấm nút mặt trăng ở màn Đang phát, hẹn giờ ngủ giờ mở thành một trang riêng thay cho ô nhỏ chật chội trước đây. Chọn số giờ và số phút bằng hai nút cộng trừ (cuộn chuột để chỉnh từng phút), rồi bấm "Bắt đầu hẹn giờ". Khi đang hẹn giờ, một vòng tròn đếm ngược cạn dần cho bạn thấy còn bao lâu nữa nhạc tắt. Nút "Dừng khi hết bài này" vẫn còn ngay bên dưới.
- **Chọn cách nhạc nhỏ dần trước khi tắt**: Không (nhạc dừng ngay khi hết giờ), 10 giây cuối (nhạc nhỏ dần trong 10 giây cuối), hoặc Suốt hẹn giờ (nhạc nhỏ dần đều từ lúc bắt đầu tới lúc tắt, trong lúc đó không chỉnh được âm lượng). Hủy hẹn giờ thì âm lượng trở lại như cũ.

## [2.3.1] - 2026-11-19

### Added
- **Cập nhật chỉ tải phần thay đổi**: Trước đây mỗi lần cập nhật trên Windows đều phải tải lại cả gói gần 400 MB. Giờ Nutsty so với bản bạn đang dùng và chỉ tải những tệp thật sự khác, thường chỉ còn vài chục MB. Tải dở mà mất mạng thì lần sau làm tiếp từ chỗ cũ, tệp nào tải xong rồi không tải lại. Bản này vẫn phải cập nhật theo cách cũ một lần, từ bản kế tiếp mới nhẹ.
- **Hộp thoại cập nhật mới**: Bấm "Cập nhật ngay" trong Cài đặt hoặc ở Thông báo để mở một hộp thoại riêng. Vòng chữ xoay quanh số phiên bản, thấy ngay sẽ tải bao nhiêu MB và nhẹ hơn tải cả bản bao nhiêu phần trăm, kèm danh sách điểm mới. Khi tải có phần trăm lớn, tốc độ và thời gian còn lại, có nút Hủy, xong thì bấm Khởi động lại.

### Fixed
- **Bản phát hành không còn tự đổi trình phát mpv**: Trước đây mỗi bản mới lại kéo mpv mới nhất nên một tệp gần 100 MB đổi theo, làm cập nhật nặng vô ích. Giờ mpv được giữ nguyên giữa các bản.

## [2.3.0] - 2026-11-19

### Added
- **Mẫu 8: Sân khấu chữ tối đa**: Mẫu lời bài hát trên màn hình nền nhiều trò nhất từ trước tới nay. Cả khung hình như một trang sổ vẽ tay: nét bút đôi, hình vẽ nguệch ngoạc quanh chữ, vệt bút dạ phía sau từ quan trọng nhất của câu. Nutsty nghe nhịp hát của bài để quyết định cách bày từng câu:
  - **Câu cao trào**: Khi một câu chậm lại sau mấy câu hát nhanh, câu đó đứng riêng một mình và nhận một bất ngờ lớn. Có 13 kiểu khác nhau: bóng đèn rơi xuống rồi sáng lên, đèn sân khấu rọi xuống, tia truyện tranh tỏa ra, mực loang kín chữ, con dấu đóng mạnh, quả bóng bay buộc vào chữ rồi nổ thành pháo giấy, tờ giấy nhớ bay vào dán lên, máy bay giấy lượn vào cắm vào góc chữ, cuộn băng dính lăn qua dán gạch chân, dây leo mọc quanh chữ rồi nở hoa, lò xo bật ra tách đôi chữ, tờ giấy gấp mở ra từng nếp, và bàn tay vẽ thò vào dán sticker. Mỗi bài thường có vài câu như vậy, và hai câu cao trào liền nhau không bao giờ trùng kiểu.
  - **Câu dồn dập**: Câu hát nhanh được gạch dưới từng chữ, có vệt tốc độ và khung hình giật theo nhịp.
  - **Câu xếp chồng**: Hai hoặc ba câu liền nhau được nối với nhau bằng mũi tên, ngoặc nhọn, chữ "vs", đường lượn, khung giấy kẻ ô, số thứ tự 1 2 3, bậc thang hay nét gạch nháp.
  - **Mỗi kiểu nhạc một bộ hình vẽ riêng**: Mẫu 8 nhận ra bài đang phát thuộc kiểu nhạc nào dựa vào thể loại của nghệ sĩ, lời bài hát và nhịp hát, rồi chọn hình vẽ và bất ngờ hợp với bài:
    - **Rock, metal**: tia sét, vết nứt, chữ vỡ thành mảnh, dây đàn đứt, chữ bị xé đôi.
    - **Rap, hip-hop**: vương miện, sơn chảy, bình xịt vẽ graffiti sau chữ, micro rơi xuống nảy lên, băng dính dán chéo.
    - **Nhạc nhảy, điện tử**: sóng âm, quả cầu disco hạ xuống, cột âm lượng nhảy theo tiếng hát, tia laser quét qua chữ.
    - **Nhạc êm, không lời**: mây, giọt nước loang thành vòng, chiếc lá rơi đáp lên chữ, vầng trăng lên sau chữ.
    - **Jazz, blues, soul**: nốt nhạc, đĩa than lăn vào rồi quay, làn khói bay lên, kèn thổi ra nốt nhạc.
    - **Anime, nhạc phim**: ngôi sao bốn cánh lóe sáng, giọt mồ hôi, dấu giận, vệt tập trung kiểu truyện tranh, cánh hoa anh đào bay qua.
    - **Dân ca, đồng quê**: mặt trời mọc sau chữ, đàn chim bay qua, mầm cây mọc ra từ chữ.
    - Bài ballad tình cảm vẫn giữ bộ hình vẽ ngọt ngào như cũ, kể cả khi ban nhạc chơi rock. Khi không có mạng, Nutsty đoán theo lời và nhịp hát.
  - **Bảng tùy chỉnh riêng cho mẫu 8**: Bấm nút "Tùy chỉnh" trên thẻ mẫu 8 trong Cài đặt để mở một bảng có khung xem trước lớn. Ở đó bạn chọn được:
    - **Bộ hiệu ứng**: Để Tự động thì Nutsty chọn theo thể loại bài hát, và nút Tự động ghi luôn bộ đang được chọn. Muốn thì ép hẳn một trong 8 bộ: Ngọt ngào, Rock, Rap, Nhảy, Êm dịu, Jazz, Anime, Dân ca. Rê chuột lên từng bộ để đọc nó vẽ những gì.
    - **Câu cao trào**: Tự nhiên (chỉ khi bài chậm lại), Nhiều (thường xuyên hơn nhưng không hai câu liền nhau) hoặc Mọi câu.
    - **Hình vẽ**: Ít, Vừa hoặc Nhiều hình vẽ quanh chữ.
    - **Chất phim cũ**: Bật hoặc tắt hạt nhiễu và vết xước.
  - **Biết ngay mẫu 8 đang dùng bộ nào**: Góc khung xem trước của mẫu 8 ghi tên bộ hiệu ứng hợp với bài đang phát.
- **Mẫu 7: Sân khấu chữ**: Lời hiện thành từng chồng tối đa ba câu, từ quan trọng nhất to và mang màu của hình nền. Mỗi câu một kiểu chữ và một góc máy riêng, có hạt phim cũ, vết xước và sợi tóc máy chiếu, chữ viết tay và chữ bút dạ. Lời bè trong ngoặc đứng riêng một cột bên cạnh. Từ tục bị che dưới một thanh đen nhấp nháy. Khi bài nghỉ lâu có chấm chờ chạy dần. Câu rời đi bằng cách bay lên, bị gạch ngang, bị lem hoặc bị vẽ đè.
- **Mẫu 6: Biến hóa chuyển động**: Từng chữ cái chuyển động theo tâm trạng của bài (sôi động, êm, nhiễu hay xoay vòng), mỗi câu một kiểu chuyển động mới.
- **Mẫu 5: Biểu cảm Mochy**: Từ được hát to sẽ phóng lớn, các câu xếp chồng lên nhau. Từng chữ hiện ra lần lượt, hơi mờ rồi rõ dần, chữ cái nhấc lên khi được hát và có vệt sáng màu đuổi theo lời.
- **Xem trước mẫu ngay trên thẻ chọn**: Mỗi thẻ trong danh sách mẫu lời bài hát hiện lời trên chính hình nền của bạn, kể cả hình nền video. Thẻ đang chọn và thẻ bạn rê chuột vào sẽ chạy thật theo bài đang phát, các thẻ còn lại đứng yên ở một khung hình để máy chạy nhẹ trên cả Linux và Windows. Khi chưa phát gì, thẻ dùng một bài mẫu có sẵn.
- **Mẫu Apple Music đẹp hơn**: Lời trượt mượt vào giữa, câu dài tự xuống dòng, câu xa mờ dần như ống kính máy ảnh, có bóng đổ nhẹ và lời bè nở ra ngay dưới câu chính.
- **Vòng tua nhạc quanh ảnh bìa**: Ở bảng bên của mẫu Mochy, vòng quanh ảnh bìa cho biết bài đang ở đâu và kéo được để tua.

### Fixed
- **Mẫu Điện ảnh Serif lại mang màu hình nền**: Lời bài hát ở mẫu 1 lại đổi màu theo hình nền như trước.
- **Mẫu 7 và 8 luôn mở được**: Có lúc đổi sang hai mẫu này khi Nutsty đang chạy thì lời không hiện. Giờ đổi lúc nào cũng hiện đúng.

## [2.2.0] - 2026-11-18

### Added
- **Thẻ người nghe của riêng bạn**: Bấm ảnh đại diện ở góc trên để mở trang hồ sơ. Ở đó có một tấm thẻ vàng mang tên, ảnh, số thẻ và ngày bạn tham gia Nutsty. Thẻ nghiêng theo chuột, kéo được rồi bật về chỗ cũ, bấm vào thì lật ra mặt sau có mã vạch. Bên phải có chữ NUTSTY khổng lồ trôi chậm lên trên.
- **Lời chào lần đầu**: Lần đầu mở bản mới, tấm thẻ bay vào giữa màn hình cùng pháo giấy và một lời chào lớn, rồi bay vào ảnh đại diện ở góc trên. Người mới cài và người dùng cũ nhận lời chào khác nhau. Bấm bất kỳ đâu để bỏ qua.
- **Trang hồ sơ**: Bấm vào thẻ, ảnh, tên và số thẻ bay vào đúng chỗ trên trang hồ sơ. Trang này cho xem tổng thời gian nghe theo từng khoảng thời gian, những bài nghe gần đây, danh sách phát của bạn và các nghệ sĩ bạn nghe nhiều nhất. Bấm vào một bài đã nghe để phát lại ngay.
- **Đếm thời gian nghe thật**: Nutsty ghi lại thời gian bạn thật sự nghe từng bài. Một bài được tính là một lượt khi bạn nghe đủ 30 giây, nghe lại từ đầu ở chế độ lặp một bài thì được tính thêm lượt mới.
- **Tổng kết tháng**: Cào lớp phủ trên mã vạch ở mặt sau tấm thẻ để mở bản tổng kết tháng của bạn. Khi cào có đồng xu bạc theo tay, vụn rơi ra từ chỗ vừa cào, tiếng sột soạt to nhỏ theo tốc độ tay và thẻ rung nhẹ. Cào gần hết thì phần còn lại tự bong ra. Màn hình chớp mắt một cái rồi thẻ bay đi, bản tổng kết hiện ra với chữ NUTSTY xoay từ dọc sang ngang. Các trang lần lượt cho xem thời gian nghe, nghệ sĩ nghe nhiều nhất cùng bài hát của họ lơ lửng bên cạnh, bài hát yêu thích kèm đĩa nhạc của nghệ sĩ nằm dưới ảnh bìa, một bức tường ảnh bìa các bài bạn đã nghe trong tháng và một tờ hóa đơn. Mỗi trang phát một đoạn ngắn của bài liên quan. Nhạc đang phát nhỏ dần khi mở và to dần trở lại khi đóng. Khi kết thúc, chữ NUTSTY xoay về dọc và tấm thẻ bay về chỗ cũ trên trang hồ sơ.
- **Trang thống kê chi tiết**: Trên trang hồ sơ, bấm "Xem thống kê chi tiết" để xem bạn nghe gì trong cả năm. Kéo hoặc bấm vào thước tháng ở trên cùng để chọn tháng, hoặc chọn năm khác. Trang cho xem thể loại bạn nghe nhiều nhất, nghệ sĩ và bài hát hàng đầu, bạn nghe nhiều vào ngày nào trong tuần và giờ nào trong ngày. Bấm vào từng thẻ để mở rộng xem thêm. Số liệu chỉ nằm trên máy bạn.
- **Thông tin phiên bản**: Cuối trang hồ sơ có thẻ cho biết bạn đang dùng phiên bản nào. Bấm "Giới thiệu" để xem lại những gì mới trong bản này.
- **Tổng kết mờ dần ở mép**: Trong tổng kết tháng, những gì chạy ra mép trên và mép dưới, như dải ảnh nghệ sĩ, tường ảnh bìa, tờ hóa đơn hay hàng chữ lớn chạy trên nền, giờ tan dần vào nền thay vì bị cắt ngang. Tờ hóa đơn mờ ở hai đầu ngay từ lúc mở, nên cuộn xuống rồi cuộn lên lại vẫn trông y như cũ. Ở chế độ nhẹ, hiệu ứng này được tắt để máy đỡ phải vẽ.
- **Lời chào và câu chữ vui hơn**: Mỗi lần mở Nutsty, lời chào trên Trang chủ, những dòng hiện khi danh sách hay hàng đợi còn trống, lúc đang tải và các câu trong trang thống kê được chọn ngẫu nhiên từ vài câu khác nhau, có câu tếu, có câu kiểu giới trẻ. Câu đã chọn giữ nguyên tới lần mở app sau. Tên các mục và các nút vẫn giữ nguyên để bạn dễ tìm. Có thêm lời chào riêng cho buổi khuya.
- **Chọn điều xảy ra khi đóng cửa sổ**: Trong Cài đặt có mục "Khi đóng cửa sổ" với hai lựa chọn. "Trình phát nhỏ" hiện ô nhạc vuông trên màn hình nền. "Chỉ phát nhạc" không hiện gì, nhạc vẫn phát và bạn mở lại Nutsty từ thanh tác vụ hoặc khay hệ thống.
- **Nút đóng trên trình phát nhỏ**: Góc trên bên phải trình phát nhỏ có nút X. Bấm vào để chọn ẩn trình phát nhỏ mà nhạc vẫn phát, hoặc thoát hẳn Nutsty. Không cần tìm biểu tượng ẩn trong khay hệ thống nữa.
- **Lời bài hát trên màn hình nền đã quay lại trên Windows**: Ô lời bài hát nổi trên màn hình nền giờ hiện trở lại trên Windows, không còn che màn hình bằng một khung đen hay giành mất chuột và bàn phím. Khi bị cửa sổ khác che kín, lời bài hát tạm ngừng vẽ để máy đỡ nặng.

### Fixed
- **Thanh phát nhạc luôn trong như kính**: Trước đây lớp kính mờ của thanh phát nhạc chỉ cập nhật khi cuộn ở Trang chủ, ở trang khác phải chạm vào thanh mới thấy đúng nền phía sau. Giờ cuộn ở bất kỳ đâu hay chuyển bài, lớp kính đều cập nhật theo mà máy vẫn nhẹ.
- **Tổng kết không còn lộ bài hát nghe nhiều nhất**: Khi bài nghe nhiều nhất là của nghệ sĩ nghe nhiều nhất, trang nghệ sĩ từng phát luôn bài đó, nên tới trang bài hát là đã biết trước đáp án. Giờ trang nghệ sĩ phát một bài khác của chính nghệ sĩ đó. Nếu bạn chỉ nghe đúng một bài của họ, mỗi lần mở tổng kết Nutsty gợi ý ngẫu nhiên một bài nổi tiếng khác của nghệ sĩ để bạn thử nghe. Khi bạn đã nghe thêm bài khác của họ, trang hiện luôn bài đó.
- **Kéo thẻ để cào được cả khi đã cuộn xuống**: Trước đây phải cuộn trang hồ sơ lên tận đầu mới kéo thẻ xuống để cào được. Giờ kéo thẻ xuống ở đâu cũng được, trang tự cuộn về đầu rồi mở lớp cào.
- **Cuộn được tới cuối trang hồ sơ và trang thống kê**: Phần cuối hai trang này không còn bị thanh phát nhạc che mất.
- **Lớp cào trên thẻ không còn rơi vụn lỗi**: Vụn rơi ra khi cào giờ hiện đều và đúng chỗ.
- **Không còn chữ lẫn tiếng Anh và tiếng Việt**: Nhiều chỗ trước đây hiện tiếng Anh khi đang dùng tiếng Việt, hoặc ngược lại. Giờ mỗi ngôn ngữ hiện đúng ngôn ngữ đó. Các biểu tượng cảm xúc còn sót cũng được thay bằng biểu tượng của Nutsty.
- **Thông báo thành công trong Cài đặt hiện đúng màu**: Khi dùng tiếng Việt, thông báo đã lưu thành công từng hiện màu đỏ như báo lỗi. Giờ chỉ lỗi mới hiện màu đỏ.
- **Ghi chú vừa đăng không còn biến mất trên Windows**: Trên những máy Windows chỉ cài Nutsty mà không có Python, ghi chú vừa đăng không lên được và biến mất ở lần làm mới tiếp theo. Giờ ghi chú được đăng bình thường.
- **Người dùng tên Shiraori giữ đúng tên**: Trước đây tên này bị coi như tên tạm và có thể bị thay bằng tên khác. Giờ tên của bạn được giữ nguyên.
- **Bản Windows tự cập nhật thư viện đi kèm**: Khi bản mới cần thư viện mới hơn, lần mở đầu tiên tự cài lại cho đúng thay vì dùng bản cũ. Biểu tượng động cần thư viện mới này, nên máy dùng bản cũ sẽ thấy biểu tượng đứng yên kèm lời nhắc cập nhật.
- **Đóng cửa sổ vẫn giữ biểu tượng trên thanh tác vụ**: Trên Windows, khi đóng cửa sổ, Nutsty thu xuống thanh tác vụ thay vì biến mất. Bấm vào biểu tượng là mở lại ngay. Bấm một lần vào biểu tượng trong khay hệ thống cũng mở lại cửa sổ.
- **Không còn cửa sổ đen nháy lên khi đổi bài**: Trên Windows, mỗi lần đổi bài từng có một cửa sổ dòng lệnh màu đen hiện lên rồi tắt, trông như phần mềm lạ. Giờ không còn cửa sổ nào hiện lên nữa.
- **Thoát là tắt nhạc**: Chọn thoát Nutsty thì nhạc dừng luôn, không còn phát tiếp sau khi ứng dụng đã tắt.
- **Nhẹ máy hơn**: Trên Windows, Nutsty chạy gọn trong một tiến trình thay vì ba, đỡ tốn bộ nhớ.
- **Lời chào hiện đúng tên ngay từ đầu**: Lời chào khi mở bản mới không còn hiện thoáng qua một tên khác trước khi đổi sang tên của bạn.
- **Bấm và kéo trình phát nhỏ chính xác hơn**: Một cú bấm hơi rung tay không còn bị tính là kéo, nên lần bấm đầu tiên luôn có tác dụng.

## [2.1.0] - 2026-11-17

### Added
- **Sao lưu và khôi phục thư viện**: Vào Cài đặt, mục Tài khoản, phần Sao lưu danh sách phát. Bấm "Xuất file" để lưu vào một file toàn bộ danh sách phát bạn tự tạo, các danh sách đã yêu thích, bài hát yêu thích và danh sách bài đã tải về, rồi giữ file đó trong USB, Google Drive hay gửi qua tin nhắn. Khi đổi máy hoặc cài lại Windows, bấm "Nhập file" và chọn file đó để lấy lại tất cả. Nhập file chỉ thêm vào chứ không xóa gì: danh sách chưa có sẽ được thêm mới, danh sách đã có sẽ được bổ sung những bài còn thiếu, nên nhập lại nhiều lần cũng không bị trùng.
- **Mục "Của bạn" trên Trang chủ**: Ngay dưới lời chào và hàng ghi chú của bạn bè là các ô Bài hát yêu thích, Đã tải và những danh sách phát của bạn. Bấm vào ô để mở, di chuột lên ô rồi bấm nút tròn để phát ngay. Danh sách đang phát luôn đứng đầu và có biểu tượng sóng nhạc.
- **Tự tạo ảnh bìa cho danh sách phát**: Trong bảng sửa danh sách phát, chọn ảnh bìa từ máy hoặc tự tạo một bìa mới với tên danh sách, chọn kiểu chữ, màu và mẫu dựng sẵn. Chữ tiếng Việt có dấu hiển thị đúng font. Bìa tạo ra luôn bo góc gọn gàng, không còn viền đen ở góc.
- **Bảng sửa danh sách phát mới**: Bố cục gọn gàng hơn, xem trước ảnh bìa ngay khi chỉnh, các nút mang màu của bài đang phát.
- **Trung tâm thông báo**: Bấm biểu tượng chuông để xem lại những thông báo đã qua (thêm vào danh sách phát, tải xong, lời mời nghe cùng...). Thông báo nổi cũng có biểu tượng riêng cho từng loại, dễ nhận ra hơn.
- **Lặp lại và phát ngẫu nhiên đúng kiểu**: Nút lặp có ba chế độ: tắt (hết danh sách thì dừng), lặp cả danh sách, và lặp một bài. Phát ngẫu nhiên giờ phát hết mọi bài trong danh sách rồi mới quay lại bài đã nghe, không còn một bài bị lặp lại liên tục, và nút bài trước quay về đúng bài vừa nghe.
- **Thư viện sắp xếp lại**: Ba mục Danh sách phát, Yêu thích và Đã tải nằm trong một thanh chọn bo tròn, có vệt sáng trượt mượt sang mục bạn chọn. Thư viện mở sẵn ở Danh sách phát và nhớ mục bạn xem lần trước.

### Fixed
- **Tiêu đề thư viện không còn bị cắt khi mở bảng cạnh bên**: Khi màn hình hẹp, tiêu đề và thanh chọn mục tự xuống hàng thay vì bị cắt mất ở hai bên.
- **Góc bảng cạnh bên không còn viền đen**: Bốn góc bo của bảng áp phích cạnh bên giờ mịn, không còn răng cưa tối.
- **Đóng màn hình Đang phát không còn nháy**: Khi thu nhỏ ảnh bìa về thanh phát nhạc, màn hình phía sau không còn lộ ra một thoáng trước khi hiệu ứng bắt đầu.
- **Thông báo căn giữa khi di chuột**: Vùng sáng khi di chuột lên một thông báo nằm cân giữa, không còn dính sát mép trái.
- **Bản Windows mở được trở lại**: Một số máy Windows báo lỗi "Failed to load QML root object" và không mở được ứng dụng sau khi cài bản 2.0.0. Lỗi này đã được sửa, ứng dụng mở bình thường như trước.
- **Sửa tên và ảnh bìa danh sách phát cùng lúc không còn bị mất**: Trước đây khi vừa đổi tên vừa đổi ảnh bìa trong một lần sửa, đôi khi chỉ một trong hai thay đổi được giữ lại. Giờ cả hai luôn được lưu.
- **Mở thư mục chứa bài hát trên Windows**: Lựa chọn mở thư mục chứa file trong menu chuột phải của bài hát giờ hoạt động trên Windows, mở đúng thư mục trong File Explorer.
- **Thay đổi danh sách phát luôn được lưu đủ**: Trước đây khi thêm, xóa hay sắp xếp nhiều bài liên tiếp thật nhanh, hoặc vừa chuyển danh sách từ Spotify vừa sửa một danh sách khác, đôi khi có thay đổi bị mất sau khi mở lại ứng dụng. Giờ mọi thay đổi được lưu lần lượt và không cái nào bị ghi đè.
- **Thông báo danh sách phát nói đúng sự thật**: Các thông báo như "Đã thêm vào danh sách phát" hay "Đã tạo danh sách phát mới" chỉ hiện khi thay đổi đã thật sự được lưu. Nếu không lưu được, ứng dụng báo lỗi và đưa danh sách về đúng như đang lưu, thay vì hiện như đã xong.
- **Danh sách đang mở luôn hiện mới nhất**: Khi đang xem một danh sách phát, mọi thay đổi (đổi tên, thêm bài, bỏ yêu thích...) hiện ngay trên màn hình đó và trong ô tìm bài để thêm, không còn chỗ cũ chỗ mới.

## [2.0.0] - 2026-11-16

### Added
- **Công tắc Chế độ nhẹ trong Cài đặt**: Vào Cài đặt, mục Tài khoản, chọn Chế độ nhẹ. Tự động (mặc định) chỉ bật khi máy không có card đồ họa, Bật dùng cho laptop yếu hay bị giật, Tắt luôn giữ đủ hiệu ứng. Khi bật, nền ảnh bìa và sóng âm đứng yên, mép danh sách không mờ dần và thanh thời gian cập nhật thưa hơn để máy chạy mượt và mát hơn.
- **Mời bạn bè nghe cùng**: Khi đang nghe nhạc, mở danh sách người nghe cùng trên thanh phát nhạc và chọn "Mời thêm bạn bè", hoặc bấm "Mời nghe cùng" trong ghi chú của bạn bè. Người được mời thấy một thông báo kèm bìa đĩa, tên bài và ảnh đại diện của bạn, chỉ cần bấm "Nghe cùng" là vào phát cùng lúc, hoặc "Để sau" để bỏ qua. Lời mời hết hạn sau 2 phút, mỗi người chỉ được mời lại sau 30 giây, và nếu người nhận đang nghe cùng ai khác thì thông báo sẽ nhắc rằng nhận lời sẽ rời phiên hiện tại.
- **Bình luận YouTube ngay trong bảng bên phải**: Nút mới ở giữa đáy bảng bên phải mở danh sách bình luận của bài đang nghe, kèm ảnh đại diện, thời gian, lượt thích và dấu bình luận đã ghim. Cuộn xuống để xem thêm, bấm vào một bình luận để xem các phản hồi. Khi đã đăng nhập Google, bạn có thể viết bình luận, trả lời người khác và bấm thích bình luận ngay tại đó.
- **Bảng bên phải đóng lại mượt mà**: Khi đóng bảng ở mục Bình luận hoặc Phát tiếp theo, bảng giữ nguyên lớp kính mờ và màu sắc trong lúc trượt đi thay vì chuyển sang màu xám đen. Bảng cũng cao bằng khu vực nội dung bên trái để hai bên thẳng hàng.
- **Mờ dần ở mép khi cuộn**: Trang chủ, thư viện, nghệ sĩ, danh sách phát, tìm kiếm, các hàng thẻ lướt ngang, thanh bên và các bảng cài đặt, bạn bè giờ đều mờ dần ở mép còn nội dung phía sau, nhìn mềm mại thay vì bị cắt ngang. Mép nào đã cuộn tới cùng thì hiện rõ. Bạn có thể tắt hiệu ứng này trong Cài đặt nếu máy yếu bị giật khi cuộn. Cả ba mục Lời bài hát, Bình luận và Phát tiếp theo trong bảng bên phải dùng lớp kính trong suốt nhìn xuyên xuống dưới, vẫn giữ độ đậm để dễ đọc.
- **Bảng bên phải trông liền mạch và cao cấp hơn**: Cả ba mục Lời bài hát, Bình luận và Phát tiếp theo dùng chung một nền kính mờ theo bìa đĩa, riêng hai mục danh sách được làm đậm hơn một chút cho dễ đọc. Chữ mờ dần ở mép trên và mép dưới khi cuộn, ba nút ở đáy gom vào một khung bo tròn có vệt sáng trượt theo mục đang chọn, góc bo các lớp lồng nhau khớp với nhau và chữ phụ sáng rõ hơn.
- **Chuyển bài mượt mà**: Bật trong Cài đặt để bài đang phát nhỏ dần trong lúc bài kế tiếp to dần lên, không còn khoảng lặng giữa hai bài. Bạn chọn thời lượng hòa trộn 3, 6, 9 hoặc 12 giây. Khi bạn tạm dừng, chuyển bài hay tua giữa chừng, bài mới được giữ lại ngay lập tức.
- **Tự động hòa trộn**: Ứng dụng nghe trước đoạn cuối của bài đang phát và đoạn đầu của bài kế tiếp để chọn đúng lúc chuyển: bài kết thúc đột ngột thì hòa nhanh, bài có đoạn nhỏ dần dài thì hòa chậm, đồng thời bỏ qua khoảng im lặng ở đầu và cuối bài. Hoạt động với cả nhạc trực tuyến lẫn nhạc đã tải về.
- **Chuyển bài kiểu đa nhiệm khi hòa trộn**: Gần cuối bài, bìa đĩa đang phát thu nhỏ lại và trượt sang trái, bìa bài tiếp theo trượt vào bên phải với cùng kích thước, những hạt sáng mang màu hai bìa bay qua lại giữa chúng. Khi hòa trộn xong, bìa bài cũ trượt đi và bìa bài mới phóng to về giữa, mượt như khi vuốt chuyển ứng dụng trên điện thoại.
- **Chữ "Cooking" khi đang hòa trộn**: Trong lúc hai bài hòa vào nhau, dòng thông số âm thanh dưới thanh thời gian được thay bằng chữ "Cooking" với một vệt sáng lướt từ trái sang phải, rồi trở lại như cũ khi chuyển bài xong.
- **"Cooking" trên thanh phát nhạc**: Suốt lúc hòa trộn, giữa thanh phát nhạc hiện chữ "Cooking" lấp lánh thế chỗ dòng thông số âm thanh, dù bạn chỉnh thời gian hòa trộn dài hay ngắn. Tên bài và ảnh bìa nhẹ nhàng trượt lên nhường chỗ, chữ "Cooking" trồi lên với các chữ cái xích lại gần nhau; khi bài mới đã chuyển xong, "Cooking" chìm xuống và tên bài cùng ảnh bìa quay về. Thời gian của bài mới chạy ngay và độ dài hiện sẵn.
- **Không còn tự phát lại từ đầu**: Bài hát đã tải về đôi lúc tự quay lại từ đầu khi tua gần cuối thay vì chuyển sang bài tiếp theo. Giờ bài chuyển tiếp bình thường, và chữ "Cooking" hiện ở mỗi lần hòa trộn kể cả khi tua liên tục.
- **Bìa bài cũ không còn bị trùng bìa bài mới**: Khi hòa trộn, đôi lúc bìa bên trái (bài đang hết) lại hiện thành bìa của bài sắp phát, nhất là với bài có ảnh động. Giờ bên trái luôn giữ đúng bìa bài cũ cho tới khi chuyển xong.
- **Trang chủ, thể loại và bạn bè mở nhanh hơn hẳn**: Trước đây mỗi lần ứng dụng hỏi dữ liệu đều phải khởi động lại phần xử lý từ đầu, mất gần một giây. Giờ phần đó luôn sẵn sàng, nên những gì đã có sẵn hiện ra gần như ngay lập tức và nhiều mục tải cùng lúc không còn phải xếp hàng chờ nhau. Khi không dùng một lúc, ứng dụng tự trả lại bộ nhớ.
- **Quản lý bộ nhớ đệm trong Cài đặt**: Xem nhạc, ảnh và lời bài hát đang chiếm bao nhiêu dung lượng, chọn mức tối đa 1 GB, 1,5 GB hoặc 2 GB, và dọn dẹp chỉ với một nút. Khi đầy, bài lâu chưa nghe lại sẽ được xóa trước. Dọn dẹp không đụng tới tài khoản, lịch sử nghe và lời bài hát bạn đã chọn.
- **Bìa hai bên không còn nháy ô trống**: Lúc hòa trộn, bìa bên trái hoặc bên phải đôi khi hiện ô trống một thoáng rồi mới ra ảnh thật. Giờ ảnh bìa được chuẩn bị sẵn từ trước, và mỗi bìa chỉ hiện ra khi ảnh đã sẵn sàng.
- **Lời bài hát bảng cạnh bên chuyển câu đa dạng như Mochy**: Khi giữa hai câu có khoảng nghỉ, câu cũ bay lên tan biến và câu mới trồi lên đúng vị trí đó. Khi hai câu hát nối liền nhau, câu sau chờ sẵn bên dưới rồi trượt lên thế chỗ khi câu trên bay đi. Từng chữ lần lượt hiện ra, phóng nhẹ và hết nhòe; khi rời đi thì mờ dần, bay lên và nhòe đi, chạy mượt theo đúng tần số làm tươi của màn hình.
- **Chữ sáng dần theo từng ký tự đúng nhịp hát**: Lời bài hát trên bảng cạnh bên sáng lên theo từng chữ cái đúng khoảnh khắc ca sĩ hát tới, không còn sáng cả từ một lúc hay giật cục. Khi tua bài hay mở bảng giữa chừng, câu đang hát cũng hiện ra nhẹ nhàng thay vì bật lên đột ngột.
- **Chọn nguồn lời bài hát ngay trong menu ba chấm**: Mỗi nguồn hiển thị có lời hay không và loại chạy chữ (theo từng từ hoặc theo từng câu) trước khi bạn chọn; danh sách dài có thể cuộn gọn gàng.
- **Thanh thể loại kiểu viên nhộng**: Thanh chọn thể loại cảm xúc mang phong cách giống thanh chuyển chế độ ở màn hình Đang phát; thể loại đang chọn tự đổi màu theo ảnh bìa hoặc hình nền máy tính.
- **Ảnh bìa bảng cạnh bên phát quang**: Đường cong dưới ảnh bìa tỏa ánh sáng theo màu ảnh bìa thay cho bóng đổ tối, giúp mắt tập trung vào bài hát.
- **Biểu tượng lời bài hát mới** trên thanh phát nhạc, rõ ràng và đẹp mắt hơn.
- **Đảo thể loại thông minh tại trung tâm thanh điều hướng (Dynamic Mood Island)**: Toàn bộ 11 thể loại cảm xúc được tích hợp tinh tế vào chính giữa thanh công cụ trên cùng. Ở trạng thái nghỉ, toàn bộ thể loại được thu gọn thành một viên ngọc nhỏ nhắn `[ Tất cả ]` ngay tại tâm màn hình. Khi nhấp chuột, thanh dock kính mờ nhẹ nhàng bung mở hiển thị trọn vẹn 11 thể loại cảm xúc kèm viên ngọc lướt êm ái theo thể loại được chọn, và tự động thu gọn lại sau 4.5 giây hoặc ngay khi chọn xong thể loại, giải phóng không gian trang chủ luôn rộng mở và thanh thoát. Đảo thể loại tự ẩn khi bạn mở màn hình Đang phát.
- **Khôi phục hoạt ảnh gợn sóng nhịp nhàng cho bài hát (Mochy Ripple Wave Animation)**: Khôi phục trọn vẹn hiệu ứng gợn sóng xếp tầng khi tải trang chủ hoặc đổi thể loại cảm xúc. Từng thẻ bài hát lướt nhẹ từ dưới lên với độ trễ 35 mili-giây nhịp nhàng tạo chiều sâu thị giác sống động và nghệ thuật. Hiệu ứng chỉ xuất hiện một lần duy nhất khi nạp mới hoặc đổi thể loại, khi cuộn trang xem lại các bài hát đã tải sẽ hoàn toàn cố định và mượt mà.
- **Màn hình Đang phát mới phong cách tối giản**: Ảnh bìa vuông thu gọn nằm chính giữa, tỏa quầng sáng mềm mại mang đúng hai màu chủ đạo của ảnh bìa và tự đổi màu êm dịu khi chuyển bài. Tên bài hát, ca sĩ và bộ điều khiển trắng tinh giản được căn giữa gọn gàng ngay bên dưới.
- **Thanh chuyển chế độ dạng viên nhộng**: Ở góc trên bên phải, bạn chuyển nhanh giữa Ảnh bìa, Lời bài hát và Danh sách chờ chỉ với một chạm. Nút Hẹn giờ tắt nhạc cũng nằm ngay tại đây, kèm chấm nhỏ báo hiệu khi hẹn giờ đang chạy.
- **Thanh âm lượng cân đối**: Thanh âm lượng nằm gọn giữa nút phát ngẫu nhiên và nút lặp lại, hai đầu có biểu tượng loa nhỏ (bật/tắt tiếng) và loa lớn (tăng âm lượng) đối xứng hài hòa.
- **Menu ba chấm đầy đủ**: Bấm nút ba chấm cạnh tên ca sĩ để yêu thích, thích, không thích bài hát hoặc chọn nhanh nguồn lời bài hát (Apple Music, Spotify, LRCLIB, KuGou...) mà không cần mở Cài đặt; lời bài hát được tải lại ngay theo nguồn vừa chọn.
- **Biểu tượng chờ biến hình sinh động**: Khi đang tìm lời bài hát, một hình khối mềm mại vừa xoay vừa biến hình liên tục (bánh quy, bông hoa, cỏ bốn lá...) thay cho vòng xoay đơn điệu, kể cả trên bảng áp phích cạnh bên.
- **Màn hình trống thân thiện**: Danh sách phát chưa có bài hát, mục yêu thích trống, hàng đợi trống hay lịch sử tìm kiếm trống đều có hình minh họa và lời gợi ý rõ ràng, kèm nút tìm và thêm bài hát ngay.
- **Tìm lời bài hát nhanh hơn**: Mỗi lần tìm lời bài hát luôn kết thúc trong vòng vài giây và chọn ngay phiên bản chạy chữ theo từng từ tốt nhất, không còn phải chờ các nguồn chậm.
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
- **Không còn ngốn CPU trên máy không có card đồ họa**: Trên máy ảo hoặc máy chưa cài driver card màn hình, mở Nutsty lên và phát nhạc từng chiếm tới 70-90% CPU. Giờ ứng dụng tự nhận ra và chuyển sang chế độ nhẹ: nền ảnh bìa đứng yên thay vì chuyển động, sóng âm cạnh ảnh bạn bè đứng yên, thanh thời gian cập nhật thưa hơn, mép danh sách không còn mờ dần khi cuộn. CPU chỉ còn khoảng 10-20%. Máy có card đồ họa bình thường vẫn giữ nguyên mọi hiệu ứng.
- **Nghe cùng không còn nhận lệnh lạ**: Sau khi rời phòng nghe cùng, đôi khi bạn vẫn bị coi là người nghe của chính chủ phòng cũ, và chủ phòng lại nhảy theo khi bạn tua bài. Giờ chỉ người đang thật sự ở trong phòng mới điều khiển được bài hát.
- **Tự dọn người nghe đã thoát**: Khi bạn bè tắt ứng dụng hoặc mất mạng mà không bấm rời phòng, khoảng nửa phút sau họ tự biến khỏi danh sách người nghe cùng kèm một thông báo nhỏ, thanh phát nhạc thu gọn lại như cũ.
- **Mở hai tài khoản cùng lúc trên một máy**: Cửa sổ thứ hai giờ phát đúng nhạc của chính tài khoản đó thay vì hiện bài của cửa sổ kia, và không còn bị bật trùng hai trình phát nhạc. Đóng một cửa sổ cũng không làm cửa sổ còn lại mất kết nối nữa.
- **Ghi chú không còn nháy**: Khi đăng hoặc xóa ghi chú, ghi chú cũ không còn thoáng hiện lại vài giây trước khi ghi chú mới xuất hiện.
- **Không còn tốn pin khi tạm dừng**: Trước đây, lúc nhạc đang dừng và cửa sổ đã ẩn đi, lời bài hát trên màn hình chính vẫn bị vẽ lại liên tục khiến máy nóng và tốn pin. Giờ khi bạn dừng nhạc, ứng dụng gần như không dùng tới bộ xử lý, nhẹ hơn hẳn trên máy cấu hình yếu.
- **Nhẹ bộ nhớ hơn**: Các cửa sổ ít dùng như quản lý bạn bè, ghi chú, hẹn giờ ngủ, danh sách tải về, tạo danh sách phát và có gì mới chỉ được tạo khi bạn mở và tự giải phóng sau khi đóng một lúc. Lời bài hát trên màn hình chỉ nạp kiểu hiển thị bạn đang dùng, ảnh bìa được giải mã vừa đúng kích thước hiển thị, thư viện nhạc không còn giữ sẵn toàn bộ ảnh bìa khi bạn đang ở màn khác, và phần xử lý phụ chạy nền chỉ bật khi thật sự cần rồi tự tắt sau một phút rưỡi rảnh.
- **Thanh phát nhạc gọn hơn, nút mới ở bảng bên phải**: Nút Lời bài hát và Danh sách chờ đã chuyển từ thanh phát nhạc xuống đáy bảng bên phải (bấm vào thanh phát nhạc để mở, bấm ảnh bìa để mở màn hình Đang phát). Nút nào đang không chọn sẽ mờ đi cho dễ nhìn. Các nút Nghe Cùng vẫn nằm trên thanh phát nhạc như cũ.
- **Nút Nghe Cùng trở lại trên thanh phát nhạc**: Khi có bạn nghe cùng, thanh phát nhạc giãn ra và hiện một viên nhỏ cạnh nút Thích. Trong đó có nút gửi bình luận bay để bạn bè thấy, và nút quản lý người nghe cùng (cho phép đổi bài, mời rời phiên). Nếu bạn đang nghe theo người khác, viên này hiện ảnh đại diện của họ kèm nút rời phiên. Khi phiên nghe cùng kết thúc, viên tự thu lại.
- **Bạn bè và ghi chú nhẹ máy hơn**: Việc cập nhật bạn bè, ghi chú, tin nhắn nghe cùng và bài đang nghe giờ được xử lý ngay trong phần lõi của ứng dụng. Phần xử lý nhạc trực tuyến không còn phải chạy suốt chỉ để làm việc này, nên khi bạn chỉ nghe nhạc, nó tự tắt và trả lại bộ nhớ.
- **Lời bài hát tiếng Việt bị tách chữ**: Sửa lỗi một số nguồn lời tách rời chữ cái như "n à o", giờ hiển thị đúng thành "nào".
- **Bảng bên lời bài hát**: Vùng ánh màu dưới bìa đĩa giờ mờ dần mượt mà, không còn bị cắt ngang thành một vệt tối ở gần cuối bảng.
- **Ảnh bìa khi chuyển bài**: Ảnh bìa của bài kế tiếp được chuẩn bị sẵn từ lúc bài đang phát còn khoảng 20%, nên khi chuyển bài không còn hiện nhầm ảnh bìa bài cũ, không nháy và không bị trống.
- **Bìa bên trái khi hòa trộn**: Bìa bài đang chuyển đi không còn thỉnh thoảng hiện nhầm ảnh của bài mới, và cả hai bìa chỉ hiện ảnh gọn gàng, không kèm chữ bên dưới.
- **Nút phát và thời lượng khi hòa trộn**: Trong lúc hai bài hòa vào nhau, nút phát vẫn hiện đang phát thay vì quay vòng chờ, và độ dài của bài mới hiện ngay thay vì 0:00.
- **Bìa bên trái không còn kẹt hình cũ**: Nếu bạn mở màn hình phát nhạc giữa lúc đang hòa trộn, bìa bên trái hiện đúng ảnh của bài đang chuyển đi thay vì một khung hình cũ của lần chuyển bài trước.
- **Bỏ qua bài không thích**: Khi bấm "Không thích" bài đang phát, ứng dụng chuyển sang bài kế tiếp trong hàng đợi thay vì quay lại phát bài đầu tiên.
- **Nền phía sau khi chuyển bài**: Nền màu chảy theo ảnh bìa giờ chuyển dần sang màu bài mới như chất lỏng đổi màu thay vì đổi đột ngột; khi hòa trộn, nền đổi màu cùng nhịp với âm thanh và hiệu ứng bìa đĩa.
- **Thể loại ở hai đầu thanh không còn lòi ra ngoài**: Các thể loại ở mép thanh được cắt gọn theo đường bo tròn, không còn viền đen bao quanh.
- **Quầng sáng ảnh bìa không còn vệt trắng**: Ánh sáng tỏa xuống dưới ảnh bìa mờ dần mềm mại thay vì bị cắt thành một mép thẳng trắng xóa.
- **Quầng sáng ảnh bìa tỏa tự nhiên**: Khắc phục hiện tượng quầng sáng quanh ảnh bìa bị chặn lại thành hình vuông khi tỏa xa, giờ ánh sáng lan mềm và bo tròn theo góc ảnh bìa.
- **Lời bài hát xuống dòng chuẩn xác**: Sửa lỗi câu hát đang chạy chữ bị ngắt dòng khác với câu tĩnh, khiến chữ nhảy vị trí khi chuyển câu.
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
