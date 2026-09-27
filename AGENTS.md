# AGENTS.md - Nutsty Master Architecture & Pair-Programming Guide

Tài liệu đặc tả "Hiến pháp kiến trúc", quy chuẩn kỹ thuật cốt lõi và hệ thống chỉ mục phân tầng dành cho AI Agent / Assistant khi phát triển dự án **Nutsty**.

---

## 1. Tổng Quan Dự Án (Project Overview)

**Nutsty** là trình phát nhạc cục bộ và máy tính để bàn đa nền tảng (Dual-Platform Desktop Music & Streaming Player) được tối ưu hóa song song cho cả **Linux Wayland (Niri compositor / CachyOS)** và **Windows (`launcher_win.py` / Win32 + System Tray)**:
- **Giao diện người dùng hiện đại**: Viết bằng **Quickshell (Qt 6 / QML)** với tăng tốc GPU phần cứng, hỗ trợ native Wayland layer-shell trên Linux và PySide6 QML + `QSystemTrayIcon` trên Windows.
- **Backend phát nhạc độ trễ thấp**: Trình điều khiển **Python IPC daemon** (`backend/player_daemon.py`) giao tiếp qua Unix Domain Socket (`/tmp/nutsty_mpv.sock` trên Linux) hoặc Named Pipe (`\\.\pipe\nutsty_mpv` trên Windows) với `mpv` (gapless playback, hardware decoding, flac/m4a/opus/mp3/ytdl streams).
- **Desktop Lyrics & Widget 216x216**: Hiển thị lyric nổi *Instrument Serif* trên desktop và widget mini vuông (`DesktopMusicWidget.qml`) kèm System Tray icon trên Windows.
- **Bộ máy màu sắc thích ứng Chromatic Salience (OKLAB / OKLCH)**: Trích xuất màu điểm nhấn từ hình nền và cập nhật theo thời gian thực vào `nutsty_palette.json`.
- **Mạng xã hội & Đồng bộ Edge toàn cầu**: Kiến trúc **Cloudflare Workers + Cloudflare D1** định tuyến kết bạn, trạng thái nghe cùng (`Listen Along`) xuyên nền tảng (`Linux <-> Windows`) và ghi chú 24h qua HTTPS.

---

## 2. Quy Tắc Tối Thượng Bất Khả Xâm Phạm (Non-Negotiable Core Rules)

> [!CAUTION]
> 1. **TUYỆT ĐỐI KHÔNG DÙNG EMOJI TRONG GIAO DIỆN**: Mọi nút bấm, trạng thái, modal hay icon phải dùng file SVG hoặc component icon có sẵn (`components/AppIcon.qml` hoặc `assets/icons/*.svg`). Tuyệt đối không dùng ký tự emoji (như 🎵, 📥, ⚙️, ❌) vì gây vỡ giao diện và "phèn".
> 2. **QUY TẮC SONG NGỮ NGHIÊM NGẶT (STRICT BIMODAL LOCALIZATION - NO HYBRID SPANGLISH)**:
>    - Mọi chuỗi ký tự hiển thị trên toàn bộ giao diện **BẮT BUỘC** phải sử dụng qua helper `I18n.tr("Tiếng Việt", "English")` từ singleton `components/I18n.qml`.
>    - Khi ở tiếng Việt (`locale === "vi"`): 100% tiếng Việt thuần túy. Khi ở tiếng Anh (`locale === "en"`): 100% tiếng Anh chuẩn. Không để sót tiếng Anh nửa nạc nửa mỡ.
> 3. **PORTABILITY & NON-HARDCODING**: Tuyệt đối không hardcode đường dẫn người dùng (như `/home/apple/...`). Luôn dùng `Quickshell.env("HOME")` hoặc `pathlib.Path.home()`.
> 4. **WAYBAR & STATUS BAR THUỘC NOCTALIA**: Tinh chỉnh thanh trạng thái Waybar/Noctalia là của repo `noctalia-shell`, không trộn lẫn vào code của Nutsty.
> 5. **RANH GIỚI NGHIÊM NGẶT GIỮA TODO.MD VÀ AGENTS.MD**:
>    - `TODO.md`: Chứa toàn bộ lộ trình (Roadmap), danh sách công việc cần làm kèm checklist `[ ]` / `[x]`.
>    - `AGENTS.md`: Là cẩm nang kiến trúc và chuẩn kỹ thuật của codebase. **CHỈ CHỨA NHỮNG GÌ ĐÃ ĐƯỢC THỰC THI VÀ KIỂM CHỨNG THÀNH CÔNG**.
> 6. **QUY TRÌNH NGHIÊN CỨU TRƯỚC KHI THAY ĐỔI (RESEARCH WORKFLOW)**:
>    - Trước khi thêm thư viện mới, thay đổi kiến trúc hoặc áp dụng pattern mới, AI **BẮT BUỘC** phải:
>      1. Tra cứu tài liệu chính thức (`search_web`, `read_url_content`).
>      2. Đánh giá ưu/nhược điểm, hiệu năng và các giải pháp thay thế.
>      3. Khảo sát các dự án nguồn mở hàng đầu (OSS Best Practices) xem cách họ giải quyết bài toán tương tự.
>      4. Đưa ra giải pháp kỹ thuật tối ưu và trình bày rõ ràng trước khi viết mã nguồn.
> 7. **CHUẨN HÓA MŨI TÊN ĐIỀU HƯỚNG CAROUSEL (`components/NavArrowButton.qml`)**:
>    - Mọi nút lướt ngang carousel `<` và `>` **BẮT BUỘC** dùng `components/NavArrowButton.qml`.
>    - Tự động liên kết `accentColor`, hover scale 1.06x và tự làm mờ khi chạm giới hạn cuộn (`canScroll`). Riêng `CategorizedSearchView.qml` không dùng nút `< >`.
> 8. **CẤM NÚT XÁM ĐEN (DYNAMIC CHROMATIC SALIENCE & MUTED ROSE)**:
>    - Tuyệt đối cấm tạo các nút bấm hoặc popover menu mang màu xám đen chết (`rgba(255, 255, 255, 0.06)`, `#18181b`, `#27272a`).
>    - Nút tương tác phải hấp thụ màu sắc động `accentColor`. Nút xóa/nguy hiểm dùng sắc thái đỏ hoa hồng dịu (Muted Rose `Qt.rgba(244, 63, 94, 0.12)`).
> 9. **QUY TẮC CẬP NHẬT TÀI LIỆU KIẾN TRÚC (ANTI-BLOAT & STRICT BUDGET)**:
>    - **Cấm append nối đuôi mù quáng (No Blind Appends)**: Bắt buộc đọc file rule tương ứng trước (`view_file`), tích hợp có cấu trúc vào đúng domain trong `.agents/rules/`.
>    - **Giới hạn cứng ngân sách**: `AGENTS.md` $\le$ 150 dòng (< 15 KB), mỗi file trong `.agents/rules/` $\le$ 100 dòng (< 10 KB). Nếu vượt, bắt buộc phải refactor và nén gọn trước khi lưu.
>    - **Cấm paste code diffs**: Không đưa code diffs hay code mẫu dài > 5 dòng vào tài liệu kiến trúc. Mỗi đề mục chỉ dài 5–12 dòng: Tên tính năng, Tệp liên quan, Cơ chế hoạt động cốt lõi và Bẫy lỗi (Footgun).
> 10. **QUY TRÌNH ĐÚC KẾT KỸ NĂNG & CODE MẪU XUẤT SẮC (`04-code-recipes-and-patterns.md`)**:
>     - Khi người dùng yêu cầu lưu lại một kỹ năng, pattern hoặc đoạn code mẫu mà AI đã thực hiện tốt: AI **BẮT BUỘC** tự động đúc kết thành 1 thẻ Pattern chuẩn (Tên Pattern, Bài toán giải quyết, Khối code mẫu hoàn chỉnh ~15–25 dòng không hardcode, và Lưu ý quan trọng) rồi ghi vào `.agents/rules/04-code-recipes-and-patterns.md`.
>     - Ngân sách dòng linh hoạt cho file này là $\le$ 200 dòng (< 18 KB) để đảm bảo code mẫu không bị cắt xén logic cốt lõi.
> 11. **ĐỒNG BỘ & TỐI ƯU ĐA NỀN TẢNG SONG SONG (DUAL-PLATFORM PARITY: LINUX NIRI/CACHYOS & WINDOWS)**:
>     - Khi viết hoặc sửa bất kỳ tính năng nào (UI, bo góc đồng tâm $R_{\text{trong}} = R_{\text{ngoài}} - \text{Khoảng cách}$, tải nhạc, phát nhạc local/online, Nghe Cùng), AI **BẮT BUỘC** phải tối ưu và đảm bảo hoạt động hoàn hảo trên cả **Linux Wayland (Niri / CachyOS)** lẫn **Windows (`launcher_win.py` + `compat/Quickshell`)**.
>     - Trên Windows: Cửa sổ chính (`masterContainer`) bắt buộc bọc `MultiEffect` mask bo tròn đồng tâm ($R_{\text{ngoài}} = 24\text{px}$, viền hairline 1px), tích hợp icon khay hệ thống (`QSystemTrayIcon`) gồm 2 lựa chọn **"Mở cửa sổ chính (Open Full)"** và **"Tắt ứng dụng (Quit)"**, và hỗ trợ tải nhạc trực tiếp không phụ thuộc `ffmpeg`.

---

## 3. Cấu Trúc Thư Mục (Repository Structure)

```
/home/apple/Applications/FrostifyLocal/
├── run.sh / start.bat              # Script khởi chạy 1-chạm trên Linux (run.sh) & Windows (start.bat)
├── launcher_win.py                 # Entry point PySide6 + System Tray + Win32 bridge trên Windows
├── shell.qml                       # Entry point QML chính (FloatingWindow Nutsty + DesktopLyricsWidget)
├── compat/Quickshell/              # Lớp tương thích Quickshell QML cho Windows (FloatingWindow, Process)
├── assets/                         # Font Instrument Serif, SVG icons, dữ liệu tĩnh
├── scripts/
│   ├── verify_codebase.py          # Kiểm tra AST scope, py_compile & QML/JS contracts (< 1s)
│   └── run_dual_profile_test.sh    # Launcher test 2 profile song song (user1 & user2)
├── cloud_relay/                    # Cloudflare Worker & D1 Serverless Global Relay
│   ├── schema.sql                  # Schema D1 (users, friendships, events, notes)
│   ├── wrangler.toml               # Cấu hình Cloudflare Workers & D1 database binding
│   └── src/index.js                # Serverless Edge Router & Logic mạng xã hội toàn cầu
├── backend/
│   ├── auth_server.py              # Resident HTTP router daemon (port 17890)
│   ├── social_relay_core.py        # Deep Module mạng xã hội, SSOT identity, unified cache
│   ├── stream_resolver.py          # Audio stream resolver (Android client, 403 prevention)
│   ├── catalog_engine.py           # Shelves, mood continuation, artist/album/search
│   ├── song_enrichment.py          # Metadata enrichment, lyrics, related tracks
│   ├── ytmusic_auth.py             # Google OAuth & cookie session manager
│   ├── ytmusic_helper.py           # Facade tổng hợp 4 module streaming & catalog
│   ├── download_manager.py         # Daemon tải nhạc đa luồng (yt-dlp, FFmpeg, socket IPC)
│   ├── library.py                  # Bộ quét thư viện nhạc (~/Music) qua Mutagen
│   ├── lyrics_helper.py            # Trích xuất và phân giải file LRC (syncedlyrics fallback)
│   ├── palette_extractor.py        # OKLAB Chromatic Salience Clustering
│   ├── player_daemon.py            # Điều khiển mpv qua /tmp/nutsty_mpv.sock
│   └── platform_compat.py          # SSOT đường dẫn cấu hình (~/.config/noctalia) & đa nền tảng
├── components/
│   ├── social_engine.js            # Logic JS mạng xã hội, Listen Along, normalizePeer (SSOT #3)
│   ├── playback_engine.js          # Logic JS điều phối playback, queue mutations, MPV status
│   ├── AmberolDetailView.qml       # Màn hình chi tiết bài hát, đĩa xoay và lyric cuộn
│   ├── AppleMusicDesktopLyrics.qml # Mẫu 2: Parametric Multi-Line Engine (DoF quang học)
│   ├── CircularSpinner.qml         # Con quay loading xoay tròn phong cách Nutsty
│   ├── CoListenersPopover.qml      # Popover danh sách người nghe cùng & nút Dừng
│   ├── DesktopLyricsWidget.qml     # Universal Lyrics Harness (Host Layer-Shell, kéo thả)
│   ├── DownloadManager.qml         # State manager đồng bộ tải xuống từ download_manager.py
│   ├── DownloadQueuePopover.qml    # Popover quản lý hàng đợi tải xuống Minimalist Clean
│   ├── EnchantingSentence.qml      # Component từng câu lyric: staggered baselines, Gacha pop
│   ├── FloatingChatBubble.qml      # Hiển thị bong bóng chat bay Danmaku khi nghe cùng
│   ├── FriendsPulseBar.qml         # Thanh avatar bạn bè 24h pulse lướt ngang ở HomeFeed
│   ├── FriendStoryModal.qml        # Modal xem ghi chú bạn bè, đĩa nhạc xoay & nút Nghe Cùng
│   ├── GachaAnimeLyricsView.qml    # Mẫu 1: Gacha Anime Pop (Instrument Serif)
│   ├── HomeFeedView.qml            # Màn hình trang chủ online: Mood pills, carousels, grids
│   ├── LibraryData.qml             # Model quản lý danh sách bài hát trong QML
│   ├── LibraryLoader.qml           # Loader nạp dữ liệu từ library.json
│   ├── MainTrackGrid.qml           # Grid danh sách bài hát & nút phát tuần tự
│   ├── MarqueeText.qml             # Chữ cuộn ngang mượt mà khi text dài vượt giới hạn
│   ├── NavArrowButton.qml          # Nút mũi tên < > đồng bộ màu động accentColor
│   ├── NavSidebar.qml              # Sidebar điều hướng [ Playlists | Queue ]
│   ├── PlayerBarBottom.qml         # Thanh phát nhạc chính Nutsty
│   ├── PostNoteModal.qml           # Modal đăng ghi chú 24h kèm bài hát
│   ├── RoundedImage.qml            # Bo góc Design System (HiDPI 2x, lazy VRAM, fallback)
│   ├── SettingsModal.qml           # Modal đăng nhập Google Account Dark Glass
│   ├── SuggestTrackToast.qml       # Toast tương tác nhận đề xuất bài hát
│   ├── Theme.qml                   # Hệ thống token màu, bo góc, padding
│   ├── TrackCard.qml               # Card hiển thị bài hát trong grid
│   ├── TrackContextMenu.qml        # Menu chuột phải Dark Glass
│   ├── TrackRow.qml                # Dòng hiển thị bài hát trong hàng đợi
│   └── UserNoteDetailModal.qml     # Modal xem/xóa ghi chú cá nhân Dark Glass
├── .agents/rules/                  # Quy tắc & kiến trúc chuyên sâu phân tầng
├── AGENTS.md                       # File này (Hiến pháp kiến trúc tối cao)
└── TODO.md                         # Danh sách tính năng và lộ trình phát triển đã chốt
```

---

## 4. Hệ Thống Quy Tắc & Kiến Trúc Chuyên Sâu (Progressive Disclosure Index)

Để tối ưu hóa ngữ cảnh và không làm tràn bộ nhớ của AI, các đặc tả kỹ thuật chi tiết và bẫy lỗi xương máu (Footguns) được phân tầng vào thư mục `.agents/rules/`. AI **BẮT BUỘC** gọi `view_file` trên tệp quy tắc tương ứng trước khi thực hiện chỉnh sửa trong từng phân vùng:

| Lĩnh vực phụ trách | Tệp quy tắc chuyên sâu | Nội dung cốt lõi & Bẫy lỗi (Footguns) |
| :--- | :--- | :--- |
| **Giao diện, Đồ họa & Kính lỏng** | [01-design-system-and-visual-effects.md](file:///.agents/rules/01-design-system-and-visual-effects.md) | - Thuật toán Kính lỏng Liquid Glass (Vibrancy 1.6x, chống đục trắng SimpMusic).<br/>- Định lý bo góc đồng tâm $R_{\text{con}} = R_{\text{mẹ}} - \text{Padding}$ & viền hairline 1px.<br/>- **Footgun #1**: Cơ chế xuyên thấu hình nền khi pause (`win.isPlaying ? 1.0 : 0.0`).<br/>- Bo góc avatar người dùng qua `MultiEffect` không vỡ góc đen. |
| **Âm thanh, IPC & Hàng đợi** | [02-audio-backend-and-queue-lifecycle.md](file:///.agents/rules/02-audio-backend-and-queue-lifecycle.md) | - Backend Python daemon & Unix Socket `/tmp/nutsty_mpv.sock` (gapless stream).<br/>- Modular Backend (`SocialRelayCore`, `stream_resolver`, `catalog_engine`) & 3 SSOT.<br/>- `playback_engine.js` hợp nhất audio/queue; loại bỏ CLI subprocess.<br/>- **Cơ chế Snapshot & Reset Queue an toàn** khi chuyển đổi Mood Chips.<br/>- Trình tải nhạc đa luồng `download_manager.py` & Lưu trữ cài đặt an toàn. |
| **Lời bài hát Desktop Lyrics** | [03-desktop-lyrics-engine.md](file:///.agents/rules/03-desktop-lyrics-engine.md) | - Host Native Wayland Layer-Shell qua Quickshell.<br/>- 4 Presets: Gacha Anime Pop (Instrument Serif), Apple Music Multi-line DoF, Motion Blur, Kinetic Typography.<br/>- **Tuyệt đối cấm viền trắng (White Halo)**, dùng Universal Cinematic Shadows.<br/>- Đồng bộ âm tiết Syllable-level Karaoke & Elastic scaling (SimpMusic Footgun #217). |
| **Kỹ Năng & Mẫu Code Chuẩn** | [04-code-recipes-and-patterns.md](file:///.agents/rules/04-code-recipes-and-patterns.md) | - Thẻ Pattern chuẩn cho các kỹ năng/giải pháp xuất sắc đã được kiểm chứng.<br/>- Code mẫu chuẩn Dynamic Accent & Liquid Glass Button.<br/>- Bố cục đa ngôn ngữ song ngữ co giãn (`Row` + `I18n.tr`). |

---

## 5. Quy Chuẩn Kiểm Tra Trước Khi Hoàn Thành (Mandatory Verification)

Mọi thay đổi mã nguồn trước khi báo cáo hoàn thành hoặc commit đều **BẮT BUỘC** trải qua quy trình kiểm thử 4 bước:
1. **Kiểm tra tĩnh toàn diện (< 1s)**: `python scripts/verify_codebase.py` (kiểm tra `py_compile`, AST symbol scope chống `NameError`, và hợp đồng QML/JS).
2. **Kiểm tra cú pháp QML**: `qmllint components/*.qml shell.qml` (hoặc trình nạp QML).
3. **Thực nghiệm giao diện trực quan**: Chạy ứng dụng qua `run_command` -> Chụp ảnh màn hình -> Xem trực tiếp bằng `view_file` để đánh giá kết quả thực tế.
4. **Git Commit & Push**: Đảm bảo commit thông điệp rõ ràng theo chuẩn Conventional Commits và push lên nhánh `main`.
