---
name: drop-late-async-responses
description: Mọi request bất đồng bộ gắn với "bài hiện tại" (palette màu, lyric, cover, metadata) phải mang một token yêu cầu, và kết quả về muộn mà token không khớp bài hiện tại thì bị bỏ. Dùng khi skip nhanh làm màu accent, cover hoặc lyric của bài trước hiện đè lên bài sau, khi có hai đường fetch (HTTP và Process fallback) cùng ghi một state, hoặc khi thêm một fetch mới chạy theo currentTrack.
---

# Câu trả lời đến sau cùng không phải câu trả lời đúng

Skip A → B → C trong 1 giây sẽ bắn ba request palette. Thời gian trả lời phụ thuộc cache, mạng
và kích thước ảnh, nên thứ tự về là ngẫu nhiên. Nếu callback nào cũng ghi `songAccentColor`,
màu của bài về cuối thắng, mà bài đó thường là A (ảnh chưa cache, chậm nhất). Cách chữa: ghi lại
bài mà request mới nhất được gửi cho, và mỗi callback tự đối chiếu trước khi ghi:

```qml
// adapted: shell.qml
property string paletteRequestUrl: ""
function fetchSongPalette(imgUrl) {
    if (!imgUrl) { win.paletteRequestUrl = ""; win.songAccentColor = win.wallpaperAccentColor; return; }
    win.paletteRequestUrl = imgUrl;
    xhr.onreadystatechange = function() {
        if (xhr.readyState !== XMLHttpRequest.DONE) return;
        if (win.paletteRequestUrl !== imgUrl) return;       // closure giữ token của chính nó
        ...
        songPaletteProc.forUrl = imgUrl;                    // fallback Process mang token riêng
    };
}
// Process: if (songPaletteProc.forUrl !== win.paletteRequestUrl) return;
```

## Traps

**Mỗi đường trả kết quả cần token riêng.** HTTP dùng closure `imgUrl`. Fallback `nutsty-bridge
palette` là một `Process` dùng chung, stdout tới qua `SplitParser` và không có closure, nên token
phải nằm trên chính Process (`property string forUrl`). Chỉ guard đường HTTP thì đường fallback
(Windows hoặc khi daemon chưa lên) vẫn ghi màu cũ.

**Request "không có gì" cũng phải xoá token.** Bài không có cover thì đi nhánh return sớm. Nếu
không đặt `paletteRequestUrl = ""`, response của bài trước vẫn khớp token cũ và ghi đè màu nền
mặc định mà ta vừa đặt. Tương tự trong `onCurrentTrackChanged`: đổi bài thì xoá token trước khi
quyết định có fetch hay không.

**Token là "bài đang xin", không phải "bài đang hiển thị".** So với `win.currentTrack` cũng được,
nhưng dễ sai với bài không có URL cover ổn định (cover được resolve sau qua
`currentResolvedCover`). Gói đúng giá trị đã gửi đi (URL ảnh) rồi so lại chính giá trị đó.

**Hủy process cũ là một cách khác, nhưng không thay được token.** Lyric dùng
`lyricsProc.running = false` trước khi gán lệnh mới. Cách đó dựa trên việc mỗi lần chỉ có một
process. Nhưng một dòng stdout đã nằm trong buffer lúc dừng có còn được giao hay không thì CHƯA
được kiểm chứng; nếu thấy lyric của bài trước nhảy vào, hãy thêm token như với palette. Với XHR,
`abort()` vẫn kích hoạt `onreadystatechange` (readyState DONE, status 0), nên vẫn cần token.

**Đừng dùng timestamp làm token.** "Response mới hơn thắng" vẫn sai: request A gửi lúc t=0 về
lúc t=900ms, sau request C gửi lúc t=500ms về lúc t=600ms. Timestamp của A cũ hơn nhưng nó về
sau, và nếu so theo "về sau thắng" thì A ghi đè. Cái cần so là danh tính của thứ được yêu cầu.

## Verifying it

```bash
grep -n "paletteRequestUrl\|forUrl" shell.qml
grep -n "XMLHttpRequest()" components/*.qml shell.qml | wc -l
```

Lệnh đầu phải thấy: khai báo property, phép gán trong `fetchSongPalette`, guard trong
`onreadystatechange`, guard trong `SplitParser.onRead`, và phép xoá trong
`onCurrentTrackChanged`. Lệnh thứ hai là điểm danh: với mỗi XHR có callback ghi state theo bài
hiện tại, hãy kiểm tra nó có token hay chưa. Thử bằng tay: bật app, bấm Next 4 lần trong 1 giây,
rồi đợi 3 giây. Màu accent phải là màu của bài cuối.
