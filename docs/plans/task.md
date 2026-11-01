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
