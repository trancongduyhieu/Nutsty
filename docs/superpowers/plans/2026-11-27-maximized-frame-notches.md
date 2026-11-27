# Khung viền + tai thỏ khi phóng to — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Khi phóng to, Nutsty có dải kính tối 6px quanh app và 3 tai thỏ (trái: thu gọn ở Đang phát; giữa: icon điều hướng; phải: ◻ ✕) với hairline liền mạch.

**Architecture:** Một hàm JS thuần dựng path SVG (ngoài + lỗ có tai) → `WindowFrameNotches.qml` vẽ bằng `Shape` (OddEvenFill + hairline). `TopHeaderBar` có chế độ `notchMode`: cao 44 (90 ở trang chủ để mood island treo dưới tai giữa), nút nhỏ lại và đặt vào vị trí tai; khung là con của header (z âm) nên nằm trên nội dung nhưng dưới nút.

**Tech Stack:** QML (QtQuick.Shapes), JS `.pragma library`, Node test.

**Spec:** `docs/superpowers/specs/2026-11-27-maximized-frame-notches-design.md`

## Global Constraints
- Số đo liner: dải `B=6`, tai cao `H=30`, loe `R=8`, bo dưới `BR=15`, góc trong `RC=12`, đệm dưới nội dung 4 (nút cao 26).
- Đệm nội dung: tai giữa 4 mỗi bên; tai phải trái 6/phải 2; tai trái trái 2/phải 6. Bề rộng nội dung làm tròn lên số chẵn.
- Tô `Qt.rgba(0,0,0,0.35)`, hairline `Qt.rgba(1,1,1,0.10)` 1px.
- Chuỗi qua `I18n.tr`; icon qua `AppIcon`; hover nút dùng `accentColor` (✕ dùng `Qt.rgba(244/255,63/255,94/255,…)`).
- Cửa sổ thường không đổi gì.

## Review Focus
- Trang chủ mở mood island khi phóng to: island treo dưới tai giữa, không chồng icon; `moodCovers` trả false ở notchMode.
- Mở/đóng Đang phát khi phóng to: tai trái hiện/ẩn, path cập nhật; nút thu gọn trong view bị ẩn, cụm chế độ không đụng tai phải.
- Cửa sổ rất hẹp (tai giữa chạm tai phải): path không tự cắt — kẹp vị trí tai giữa.
- Kéo dải trên / nhấp đôi để khôi phục vẫn chạy.
- Windows (`compat/`): `verify_qml_compat.py` nạp được component mới.

---

### Task 1: Hàm dựng path khung

**Files:** Create `components/window_frame_logic.js`, `scripts/test_window_frame_logic.cjs`

**Interfaces — Produces:** `framePath(W, Hh, leftW, centerW, rightW) -> string` (path SVG gồm hình chữ nhật ngoài + lỗ; `leftW/rightW` = 0 nghĩa là không có tai, góc bo `RC`); `innerPath(...)` cùng tham số, chỉ đường lỗ (cho hairline); `notchOuterWidth(kind, contentW)`; hằng `B, H, R, BR, RC`.

- [ ] Test: tai giữa 228px ở W=1600 → path chứa `L 686 6` (x1 = 800 − (228+16)/2 = 678 → sau đường loe) … cụ thể assert: không tai trái → chứa `A 12 12 0 0 1 18 6`; có tai trái → không chứa đoạn bo góc trên-trái; cửa sổ hẹp → tai giữa bị kẹp, không có tọa độ x giảm dần trên mép trên.
- [ ] Chạy `node scripts/test_window_frame_logic.cjs` → FAIL (thiếu file).
- [ ] Viết hàm theo thứ tự đi vòng lỗ theo chiều kim đồng hồ: loe = sweep 1, bo đáy = sweep 0.
- [ ] Chạy lại → PASS.

### Task 2: `WindowFrameNotches.qml`
**Files:** Create `components/WindowFrameNotches.qml`; Modify `components/qmldir`.
**Interfaces — Consumes:** Task 1. **Produces:** props `leftContentWidth`, `centerContentWidth`, `rightContentWidth` (real), `frameHeight`.
- [ ] `Shape` 2 `ShapePath` (`PathSvg`), `fillRule: ShapePath.OddEvenFill`, không nhận chuột.
- [ ] `python scripts/verify_qml_compat.py` → OK.

### Task 3: Nối vào header / shell / Đang phát
**Files:** Modify `components/TopHeaderBar.qml`, `shell.qml` (~2815), `components/YTMusicNowPlayingView.qml` (~1964-2000).
- [ ] TopHeaderBar: props `notchMode`, `frameHeight`; signal `collapseRequested`; nav cluster tách khỏi RowLayout, đặt ở tâm (notch) hoặc trái (thường); nút 26px ở notchMode; nút ◻ ✕ vào tai phải; nút thu gọn ở tai trái khi `isNowPlayingOpen`.
- [ ] shell: `notchMode: win.maximized || win.fullscreen`, `frameHeight: masterContainer.height`, `onCollapseRequested: win.isNowPlayingOpen = false`; nội dung lề 6px.
- [ ] Đang phát: prop `chromeInNotch` ẩn `collapseBtn`, `topMargin` cụm chế độ 14 → 8 khi notch (dưới tai phải).
- [ ] Chạy verify_codebase, verify_qml_compat, qmllint; chạy thật trên Niri, chụp ảnh; commit.
