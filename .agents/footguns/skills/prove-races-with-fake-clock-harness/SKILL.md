---
name: prove-races-with-fake-clock-harness
description: Chứng minh và khoá race của playback/Nghe Cùng bằng cách chạy CHÍNH file engine JS (playback_engine.js, social_engine.js) trong node vm với Date.now giả, Quickshell/XHR giả và status mpv thật đã ghi lại. Dùng khi nghi ngờ lỗi do skip nhanh hoặc event trễ mà không tái hiện được bằng tay, trước khi sửa một lỗi timing, hoặc khi cần test cho logic QML JS không có test runner.
---

# Race phải tái hiện được trước khi sửa

Race kiểu "skip nhanh thì đôi khi sai" không bắt được bằng cách bấm tay, và nếu sửa mà không có
bằng chứng thì không biết đã sửa đúng chưa. Các file `.js` import trong QML là JS thuần (chỉ dùng
`Quickshell`, `I18n`, `XMLHttpRequest`, `Date`), nên có thể nạp nguyên văn vào `vm` của Node và
điều khiển thời gian bằng tay:

```js
// adapted: scripts/test_playback_race.cjs
let NOW = 1_000_000;
const FakeDate = class extends Date { static now() { return NOW; } };
const execLog = [], xhrLog = [];
const sandbox = { console, Math, JSON, Number, String, Array, Object, Boolean, parseInt, isNaN,
    Date: FakeDate, I18n: { tr: (vi) => vi },
    Quickshell: { execDetached: (c) => execLog.push(c.slice(1).join(" ")), env: () => "" },
    XMLHttpRequest: function () { this.open = (m, u) => { this.url = u; };
        this.setRequestHeader = () => {}; this.send = (b) => xhrLog.push({ url: this.url, body: b }); } };
vm.createContext(sandbox);
vm.runInContext(fs.readFileSync(ROOT + "/components/playback_engine.js", "utf8"), sandbox);
// win giả: currentTrack là accessor để ghi lại state đúng lúc gán (như QML gọi handler)
Object.defineProperty(win, "currentTrack", { get: () => cur, set: (v) => { cur = v; onSet(win, v); } });
PE.triggerRapidTrackSwitch(win, B);  NOW += 170;  PE.handlePlayerStatus(win, staleA(120, false));
```

## Traps

**Dùng status THẬT, không tự bịa.** Lỗi stale-status chỉ hiện vì mpv trả `filename:
"videoplayback"`, `is_loading: false` và path googlevideo của bài cũ. Một status giả "hợp lý"
(`is_loading: true`) sẽ cho test xanh trên code lỗi. Hãy chép một mẫu từ
`curl -s 127.0.0.1:17890/api/player/status` trong lúc bài đang resolve.

**Nạp file thật, không chép hàm ra test.** Hàm chép ra sẽ lệch dần với code thật, và test khi đó
chứng minh code của test. `vm.runInContext(readFileSync(...))` buộc test chạy đúng thứ ship.

**Hai engine, hai context.** `social_engine.js` và `playback_engine.js` định nghĩa trùng tên
(`listenSyncData`). Nạp chung một context thì file sau ghi đè file trước, và test sẽ kiểm tra nhầm
hàm. Dùng `vm.createContext(Object.assign({}, sandbox))` cho mỗi engine.

**Phải dùng `.cjs`.** Có một `~/package.json` lạc chỗ với `"type": "module"`, khiến Node coi mọi
`.js` bên dưới HOME là ESM và báo `require is not defined`. Đặt đuôi `.cjs` để không phụ thuộc vào
cấu hình máy.

**Viết bước chứng minh trước, bước sửa sau.** Trình tự: harness in `BUG` cho từng giả thuyết → sửa
→ cùng harness in `ok`. Bài test cuối giữ lại cả các nhánh KHÔNG được chặn (quay lại bài mpv đang
giữ, timeout 25s), vì bản vá thường chặn quá tay.

**Test có sẵn có thể đã đỏ từ trước.** `scripts/test_playback_engine.js` fail cả trên HEAD
(`currentTime` undefined, kỳ vọng 15.4). Chạy nó trên `git stash` trước khi đổ lỗi cho thay đổi
của mình, và báo riêng là lỗi có sẵn.

**Harness không thay được kiểm thử thật.** Nó chứng minh logic JS. Nó không chứng minh bridge Rust,
độ trễ relay hay hành vi mpv khi seek trên stream. Hai profile song song
(`scripts/run_dual_profile_test.sh`) và skip tay trên app vẫn là bước cuối.

## Verifying it

```bash
node scripts/test_playback_race.cjs
python scripts/verify_codebase.py
python scripts/verify_qml_compat.py
```

Lệnh đầu kết thúc bằng `ALL PLAYBACK RACE TESTS PASSED` và exit code 0. Khi thêm một race mới,
hãy thêm một khối trong file đó theo mẫu "dựng win → đẩy NOW → gọi handler → assert trên
`execLog`/`xhrLog`/state". Đừng tạo file test mới cho từng lỗi.
