# Task Progress Tracker

| Task | Status | Description |
|---|---|---|
| Task 1: Win32 Taskbar Geometry & Window Style Bridge | Done | Implement `getTaskbarGeometry` & `setupTaskbarWindow` in `launcher_win.py`, tray menu toggle |
| Task 2: Unlock Windows Settings in `components/SettingsModal.qml` | Done | Enable settings on Windows with Placement, Alignment, Romanization controls |
| Task 3: Refactor SettingsModal dropdowns to match Image 3 | Done | Replace yellow lozenges with Dark Glass dropdown triggers and popovers matching Image 3 |
| Task 4: Integrate `kamol1dn/spicy-taskbar` (`TaskbarLyrics.exe`) | Done | Install .NET 8, remove SMTC restriction in `SmtcWatcher.cs`, add direct lyrics push and zero-latency WebSocket config in `BridgeServer.cs`, disable `VizEnabled` to avoid VM crash |
| Task 5: WebSocket Bridge in `launcher_win.py` (`TaskbarLyricsService`) | Done | Auto-spawn `bin\TaskbarLyrics.exe`, connect to `ws://localhost:9012/`, push `sp_state` and direct `push_lyrics` with `IsPartOfWord` syllable schema |
| Task 6: Connect reactive playback & settings in `shell.qml` | Done | Timer & connections update taskbar playback, placement, align, on/off dynamically |
| Task 7: PyInstaller Build & Full Release Package | Done | Package `dist\Nutsty\Nutsty.exe` with `bin\TaskbarLyrics.exe`, `bin\mpv.exe`, assets, QML |
| Task 8: Verification & Live Proof | Done | Verified WebSocket connection, `TaskbarLyrics.exe` log confirmation (`resolve: cache hit (spicy)`, `smtc: track`), zero-latency updates, and codebase contracts |
| Task 9: Atomic Single-Instance Win32 Mutex + Rapid Activation | Done | Replaced vulnerable socket-only probe with session-scoped kernel named mutex `Local\Nutsty_Master_SingleInstance_Mutex_Apple`, preventing dual instances, high CPU spikes (63%) and 600MB+ RAM bloat |
| Task 10: WebSockets 17.1 `ClientConnection` Parity & Safe Send | Done | Fixed AttributeError on `ws.closed` for websockets 17.1 via `_is_ws_open()` and added `asyncio.Lock()` concurrency guards, ensuring stable taskbar lyrics push without WebSocket aborts |
| Task 11: Fix GUI Thread Freeze via `threading.RLock()` & Lock Decoupling | Done | Fixed self-deadlock in `TaskbarLyricsService._push_state` by migrating to `threading.RLock()`, releasing lock before formatting, and eliminating repetitive lyric serialization in `taskbarLyricsPushTimer` |
| Task 12: Windows Widget Click-Through, Lyrics Restore & Low-Integrity Build Fix | Done | Widget 216x216 draggable without blocking desktop mouse, desktop + taskbar lyrics restored on Windows, `TaskbarLyricsService` process lifecycle, `build_exe.bat` resets Medium integrity label (see `.agents/rules/05-windows-build-and-runtime-lessons.md`) |
| Task 13: Refactor `LiquidGlass.qml` to MultiEffect Optical Formula | Done | Upgraded `LiquidGlass.qml` with `MultiEffect` hardware Gaussian blur (blurMax: 48), saturation 1.55x, 48% scrim, zero idle GPU capture guards, no spotlight |
| Task 14: Remove Opaque Obsidian Slab from `DownloadQueuePopover.qml` | Done | Unlocked translucent liquid glass in download popover by removing 0.90 opaque backdrop and setting 52% dark glass with hairline border |
| Task 15: Remove Opaque Obsidian Slab from `FriendRequestsPopover.qml` | Done | Unlocked translucent liquid glass in notifications popover by removing 0.90 opaque backdrop and setting 52% dark glass with hairline border |
| Task 16: End-to-End Verification of Liquid Glass Unification | Done | Verified AST scopes, QML/JS contracts, zero idle rendering and no continuous timer via `scripts/verify_codebase.py` |
| Task 17: Diagnose and Eliminate 50%+ CPU Bottleneck | Done | Profiled threads with py-spy and Win32 thread APIs: identified Mesa `opengl32sw.dll` software rasterizer forced by residual VBox registry keys, switched active adapter detection via `EnumDisplayDevicesW` to D3D11/WARP, removed 60fps infinite equalizer animations in `FriendsPulseBar`, disabled root window FBO `layer.enabled` mask; verified idle CPU dropped to 0% and RAM dropped to 96MB |
