# Task Tracker

| Task | Status | Notes |
| :--- | :--- | :--- |
| Phase 1: Investigate DesktopLyricsWidget interaction, dragging, volume, and play/pause on Windows | Completed | Investigated: Qt.WindowTransparentForInput in PanelWindow.qml disabled all mouse input |
| Phase 2: Identify root cause in DesktopLyricsWidget.qml / compat layer | Completed | PanelWindow.qml lacked native window masking bridge; hardcoded transparent flag |
| Phase 3: Implement fix for mouse interaction and dragging on Windows | Completed | Added setWindowMaskRect and clearWindowMask in launcher_win.py NutstyBridge and dynamic masking in PanelWindow.qml |
| Phase 4: Verification with tests and interactive screenshot verification | Completed | Automated integration tests passed 100% (dragging, volume wheel, play/pause, mask hit-testing, screen capture) |
| Phase 5: Fix Liquid Glass HLSL compilation & Direct3D 11/12 support on Windows | Completed | Baked HLSL 50 and GLSL into assets/shaders/liquid_glass.frag.qsb using PySide6 qsb.exe |
| Phase 6: Restore Linux-identical Wallpaper Atmosphere & prevent raw window bleed-through on pause | Completed | Implemented masterBackdropStack with solid #0a0b0e foundation, MultiEffect blurred Windows wallpaper atmosphere, and adaptive dark scrim |
| Phase 7: Fix DesktopMusicWidget square mini-widget when closing/minimizing main window | Completed | Fixed onCloseWindowRequested/onMinimizeWindowRequested in shell.qml, added screen-bounds clamping and 1.34x letterbox crop in DesktopMusicWidget.qml |
| Phase 8: Stop previous song immediately in mpv when switching to a new online song | Completed | Added immediate send_mpv_cmd(["stop"]) and stale-request timestamp guard before resolve_media_path() in backend/player_daemon.py |
| Phase 9: Prioritize local downloaded audio files (0ms latency) on both Windows and Linux | Completed | Added findLocalDownloadedTrack in shell.qml and find_local_downloaded_file in backend/player_daemon.py |
| Phase 10: Task 1 - Backend Spotify Importer Module (`backend/spotify_importer.py`) | Completed | Spotify playlist fetch, track extraction, and SpotDL-style YouTube Music matching engine |
| Phase 10: Task 2 - API Routes Registration (`backend/music_routes.py` & `backend/auth_server.py`) | Completed | Expose /api/spotify/playlists, /api/spotify/import_playlist, and /api/spotify/import_status |
| Phase 10: Task 3 - UI Modal Component (`components/SpotifyImportModal.qml`) | Completed | Liquid glass modal with bimodal i18n, no emoji, and real-time progress bar |
| Phase 10: Task 4 - UI Triggers Integration (`components/SettingsModal.qml` & `components/NavSidebar.qml`) | Completed | Trigger buttons in Settings and NavSidebar with auto-reload of custom playlists |
| Phase 10: Task 5 - Comprehensive Verification & Desktop Screenshot | Completed | verify_codebase.py, API verification, and live UI screenshot verification |
