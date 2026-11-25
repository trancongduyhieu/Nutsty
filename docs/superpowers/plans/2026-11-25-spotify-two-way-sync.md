# Spotify Two-Way Sync Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Keep chosen Spotify playlists and Liked Songs mirrored into Nutsty automatically (phase 1), and push likes and playlist add/remove made in Nutsty back to Spotify behind an opt-in switch (phase 2).

**Architecture:** A thin web-player GraphQL client (`spotify_web.py`) on the user's own `sp_dc` cookie, a pure three-way merge (`spotify_sync_merge.py`), per-device state and match cache (`spotify_sync_state.py`), and an orchestrator (`spotify_sync.py`) exposed at `POST /api/spotify/sync/<op>`. QML gets a `SpotifySync.qml` QtObject modelled on `AccountSync.qml` and a `SpotifySyncSection.qml` in Settings. No hooks in write paths: changes are inferred by diffing, like `account_sync.py`.

**Tech Stack:** Python 3.11 stdlib (`urllib`, `json`, `threading`, `unittest`), Qt 6 / QML (Quickshell, PySide6 compat on Windows).

**Spec:** `docs/superpowers/specs/2026-11-25-spotify-two-way-sync-design.md`

## Global Constraints

- Only the user's own `sp_dc` (`lyrics_helper.get_spotify_spdc()` / `get_spotify_access_token()`); never shared accounts or pools.
- Every file is per profile: suffix from `playlist_manager._ACTIVE_SUFFIX` inside `pm.profile_scope(profile)`; config dir `pc.get_config_dir()`.
- Playlist writes go through `playlist_manager.locked()` + `load_playlists()` / `save_playlists()`; liked writes through `pm._read_json(pm._liked_file())` / `pm._write_json` under the same lock.
- Linked playlist id is exactly `custom_pl_spotify_{spotifyPlaylistId}` (no timestamp).
- "Auto-update from Spotify" is per device, default off; nothing syncs until the playlist selection is confirmed.
- Write-back is default off; only changes after it is switched on are pushed; backlog only via the "push earlier likes" action.
- Write-back only to playlists the user owns; Spotify-made playlists (owner id `spotify`) are replace-wholesale, never guarded, never written.
- Schedule: first run ~20 s after start, then every 3 h, plus "Sync now".
- Mass-delete guard: block when a pull would remove more than half of `base` and more than 3 tracks, until the user presses "Apply anyway" for that playlist.
- Backend returns error codes (`auth_expired`, `rate_limited`, `query_changed`, `network`, `mass_delete_blocked`), never UI text; QML maps them through `I18n.tr("…", "…")`.
- UI: no emoji, SVG icons only, buttons take `accentColor`, danger uses Muted Rose `Qt.rgba(244, 63, 94, 0.12)`; Linux and Windows parity (route must answer on `route_dispatcher` and `auth_server`).
- No change to `cloud_relay` (`SYNC_KINDS` stays as is).

## Review Focus

1. Spotify returns an empty or truncated page list (network blip, 429 mid-pagination) → nothing is removed locally. Test in Task 2 (`test_incomplete_remote_rejected`) and Task 5 (`test_truncated_fetch_removes_nothing`).
2. A Spotify track cannot be matched to YouTube → it is retried later, not silently dropped forever. Test in Task 5 (`test_unmatched_remote_add_retried_later`).
3. User deletes a track in Nutsty while write-back is off → it never comes back on later syncs. Test in Task 2 (`test_local_removal_not_readded`) and Task 5 (`test_local_delete_survives_two_syncs`).
4. Two devices with the same account both have write-back → no duplicate add on Spotify. Test in Task 8 (`test_push_add_skips_track_already_remote`).
5. Cookie expires mid-cycle → status shows `auth_expired`, local data untouched, next cycle retries. Test in Task 5 (`test_auth_error_leaves_files_untouched`).

---

## Phase 1: Spotify → Nutsty

### Task 1: Web-player client (`spotify_web.py`)

**Files:**
- Create: `backend/spotify_web.py`
- Create: `scripts/spotify_sync_smoke.py` (manual, read-only, uses the developer's own cookie; not in CI)
- Test: `scripts/test_spotify_sync.py` (new; unittest, temp `XDG_CONFIG_HOME` like `scripts/test_playlist_backend.py`)

**Interfaces:**
- Produces:
  - Exceptions: `SpotifyError(Exception)` with `.code: str`; subclasses `SpotifyAuthError` (`auth_expired`), `SpotifyRateLimited` (`rate_limited`, `.retry_after: float`), `SpotifyQueryChanged` (`query_changed`), `SpotifyNetworkError` (`network`).
  - `PERSISTED_QUERIES: dict[str, str]` op name → sha256 (seed: `fetchPlaylist` from `spotify_importer.py`; `libraryV3`, `fetchLibraryTracks`, `profileAttributes`, `searchDesktop`, `addToPlaylist`, `removeFromPlaylist`, `addToLibrary`, `removeFromLibrary` from the Spatial Flow APK table `references/SpatialFlow-apk/src/sources/defpackage/x47.java`).
  - `class SpotifyWebClient(spdc: str, transport=None, min_interval: float = 0.4)`; `transport(url, payload: dict, headers: dict) -> (status: int, headers: dict, body: dict)` is injectable for tests.
  - `client.me() -> dict` `{id, name}`.
  - `client.library_playlists() -> list[dict]` items `{id, title, image, ownerId, ownerName, owned: bool, spotifyMade: bool, revision: str, trackCount: int}`.
  - `client.playlist_items(pid) -> RemoteList`; `client.liked_items() -> RemoteList`.
  - `@dataclass RemoteList(items: list[dict], total: int, revision: str, complete: bool)`; item `{spotifyId, uid, name, artist, album, duration_ms, image}`.
  - `client.search_tracks(title, artist, limit=10) -> list[dict]` items `{spotifyId, name, artist, duration_ms}`.
  - Write ops (used in Task 8): `add_to_playlist(pid, uris)`, `remove_from_playlist(pid, uids)`, `add_to_library(uris)`, `remove_from_library(uris)`.

- [ ] **Step 1: Write failing tests** in `scripts/test_spotify_sync.py`, class `WebClientTests`, using a fake transport:
  - `test_paginates_until_total`: fake returns 2 pages of 100 + 1 page of 20 with `totalCount=220` → `RemoteList.complete is True`, `len(items) == 220`.
  - `test_short_page_marks_incomplete`: fake returns 100 then raises network error → raises `SpotifyNetworkError` (not a partial list).
  - `test_429_raises_rate_limited_with_retry_after`: status 429, header `Retry-After: 7` → `SpotifyRateLimited.retry_after == 7`.
  - `test_persisted_query_not_found_maps_to_query_changed`: body `{"errors":[{"message":"PersistedQueryNotFound"}]}` → `SpotifyQueryChanged`.
  - `test_401_maps_to_auth_expired`.
  - `test_spotify_made_flag`: owner uri `spotify:user:spotify` → `spotifyMade True, owned False`; owner == `me().id` → `owned True`.
- [ ] **Step 2: Run** `python scripts/test_spotify_sync.py` → FAIL (`ModuleNotFoundError: spotify_web`).
- [ ] **Step 3: Implement `backend/spotify_web.py`.** Endpoint `https://api-partner.spotify.com/pathfinder/v1/query` (POST, headers as in `spotify_importer.fetch_spotify_playlist_from_pathfinder`, `client-token` from `lyrics_helper._spotify_get_client_token()`). Token from `lyrics_helper.get_spotify_access_token(spdc)`; empty token → `SpotifyAuthError`. Enforce `min_interval` between calls. Page size 100 for playlists, 50 for library/liked. `uid` comes from each playlist item (needed for removal).
- [ ] **Step 4: Run tests** → PASS.
- [ ] **Step 5: Write `scripts/spotify_sync_smoke.py`**: reads cookie via `lyrics_helper.get_spotify_spdc()`, prints `me()`, count of `library_playlists()`, first playlist's `RemoteList.total/complete`, `liked_items().total`, one `search_tracks`. Read ops only. Run it once with the developer's own cookie; if an op raises `SpotifyQueryChanged` or the response shape differs, update the hash / variables from the open.spotify.com network tab before continuing. Record in the commit message which ops were verified live.
- [ ] **Step 6: Commit** `feat(spotify-sync): web-player GraphQL client`.

### Task 2: Pure merge (`spotify_sync_merge.py`)

**Files:**
- Create: `backend/spotify_sync_merge.py`
- Test: `scripts/test_spotify_sync.py` (class `MergeTests`)

**Interfaces:**
- Produces:
  - `@dataclass MergeResult(pull_add: list[str], pull_remove: list[str], push_add: list[str], push_remove: list[str], new_base: list[str])` (all Spotify track ids; `pull_add` keeps remote order).
  - `three_way(base: list[str], remote: list[str], local: list[str], write_back: bool, unmatched: set[str] = frozenset()) -> MergeResult`.
  - `remote_is_valid(remote: RemoteList-like with .complete, .total, .items) -> bool`.
  - `mass_delete_blocked(base_len: int, remove_len: int) -> bool` (rule from Global Constraints).

Rules (from spec 5.3): in remote not base → `pull_add` (unless already local); in base not remote → `pull_remove` if local; in base not local → never re-added, `push_remove` only if `write_back`; in local not base and not remote → `push_add` only if `write_back`. `new_base` = remote ∖ `unmatched` (so unmatched additions are retried), plus `push_add`, minus `push_remove` (assumed to succeed; Task 8 corrects on failure).

- [ ] **Step 1: Write failing tests:**
  - `test_remote_add_pulled_in_remote_order`: base `[a]`, remote `[a,c,b]`, local `[a]` → `pull_add == [c,b]`.
  - `test_remote_remove_pulled`: base `[a,b]`, remote `[a]`, local `[a,b]` → `pull_remove == [b]`.
  - `test_local_removal_not_readded`: base `[a,b]`, remote `[a,b]`, local `[a]`, write_back False → `pull_add == []`, `push_remove == []`, `new_base == [a,b]`.
  - `test_local_removal_pushed_when_write_back`: same with write_back True → `push_remove == [b]`.
  - `test_local_add_pushed_only_when_write_back`.
  - `test_unmatched_excluded_from_new_base`: remote `[a,x]`, unmatched `{x}` → `x not in new_base`.
  - `test_incomplete_remote_rejected`: `complete False` or `len(items) != total` → `remote_is_valid` False.
  - `test_mass_delete_guard`: `(10, 6)` True; `(10, 5)` False; `(4, 3)` False; `(6, 4)` True.
- [ ] **Step 2: Run** → FAIL.
- [ ] **Step 3: Implement** the three functions.
- [ ] **Step 4: Run** → PASS.
- [ ] **Step 5: Commit** `feat(spotify-sync): three-way merge and guards`.

### Task 3: State and match cache (`spotify_sync_state.py`)

**Files:**
- Create: `backend/spotify_sync_state.py`
- Test: `scripts/test_spotify_sync.py` (class `StateTests`)

**Interfaces:**
- Produces (all inside the caller's `pm.profile_scope`):
  - `load_state() -> dict` / `save_state(state: dict)` on `spotify_sync_state{suffix}.json`. Keys: `enabled: bool`, `selectionConfirmed: bool`, `selected: list[str]` (Spotify playlist ids), `likedSelected: bool`, `likedBase: list[str] | None`, `writeBack: bool`, `writeBackSince: float`, `localBaseline: dict[str, list[str]]` (Nutsty list key → track unique keys at switch-on; key `"liked"` or playlist id), `forceApply: list[str]`, `lastSync: float`, `lastError: str`, `blocked: list[str]`, `unmatchedCount: int`, `backlog: dict` (Task 9).
  - `MatchCache` on `spotify_match_cache{suffix}.json`: `get(spotify_id) -> dict | None` (cached track or `{"unmatched": True, "triedAt": t}`), `put(spotify_id, track: dict | None)`, `should_retry(spotify_id, now) -> bool` (retry unmatched after 3 days), `find_by_video(video_id) -> str | None` (reverse lookup, used in Task 8).
- [ ] **Step 1: Write failing tests:** defaults when file missing (`enabled False`, `selectionConfirmed False`, `likedBase None`); round trip; profile isolation (`profile_scope("user2")` writes `spotify_sync_state_user2.json` or whatever `_suffix_for` yields — assert files differ); `should_retry` False at +1 day, True at +3 days + 1 s; `find_by_video` returns the Spotify id.
- [ ] **Step 2: Run** → FAIL. **Step 3: Implement.** **Step 4: Run** → PASS.
- [ ] **Step 5: Commit** `feat(spotify-sync): per-device state and match cache`.

### Task 4: Legacy import migration

**Files:**
- Modify: `backend/spotify_sync.py` (create file; this task adds only `migrate_legacy_imports`)
- Modify: `backend/spotify_importer.py` — `match_spotify_track_to_ytmusic` returns `spotifyId` (input track's `id`) in its dict; one-shot imports keep the timestamped id (they stay unlinked).
- Test: `scripts/test_spotify_sync.py` (class `MigrationTests`)

**Interfaces:**
- Consumes: `MatchCache`, `RemoteList`.
- Produces: `migrate_legacy_imports(playlists: list[dict], remote_by_pid: dict[str, RemoteList], match: Callable[[dict], dict | None], cache: MatchCache) -> list[dict]` — returns the new playlists list.
  - For each `spotifyId` with `source == "spotify_import"`: the newest (`createdAt`) becomes linked: id/playlistId → `custom_pl_spotify_{pid}`, add `spotifyLink = {"id": pid, "owned": ..., "base": [...], "revision": ..., "syncedAt": ...}`; tracks whose `videoId` equals a matched remote track get `spotifyId`; remote tracks not present are appended (spec 4: accepted one-time return of deleted tracks); `base` = all remote ids that matched.
  - Older duplicates untouched. Already-linked ids are skipped (idempotent).
- [ ] **Step 1: Failing tests:** `test_newest_duplicate_becomes_linked`, `test_tracks_get_spotify_id_by_video_match`, `test_missing_remote_tracks_appended`, `test_migration_idempotent` (run twice → same output).
- [ ] **Step 2–4:** run FAIL → implement → PASS.
- [ ] **Step 5: Commit** `feat(spotify-sync): link legacy Spotify imports`.

### Task 5: Pull orchestrator

**Files:**
- Modify: `backend/spotify_sync.py`
- Modify: `backend/spotify_importer.py` — `fetch_user_spotify_playlists` cache gets a 6 h TTL (stamp `{"fetchedAt", "playlists"}`; old list format = expired).
- Test: `scripts/test_spotify_sync.py` (class `PullTests`, fake client + fake matcher)

**Interfaces:**
- Consumes: Tasks 1–4.
- Produces:
  - `sync_once(profile: str = "", client=None, matcher=None) -> dict` → `{"success": bool, "error": code | "", "changed": {"playlists": bool, "liked": bool}, "blocked": [pid], "unmatched": int}`. `client` defaults to `SpotifyWebClient(lyrics_helper.get_spotify_spdc())`, `matcher` to `spotify_importer.match_spotify_track_to_ytmusic`. Returns early with `success False` when `enabled` or `selectionConfirmed` is False. A process-wide lock prevents overlapping runs.
  - `list_choices(profile) -> dict` `{"playlists": [library item + "selected": bool], "liked": bool}` — default selection: `owned` True and `spotifyMade` False.
  - `set_selection(profile, ids: list[str], liked: bool)` → sets `selectionConfirmed True`.
  - `set_enabled(profile, enabled: bool)`, `force_apply(profile, pid)`, `status(profile) -> dict`.

Per cycle: migration (Task 4) once → for each selected playlist: skip if `revision` unchanged; fetch; if `not remote_is_valid` skip; Spotify-made → replace tracks wholesale with matched remote order; else `three_way(...)`, check `mass_delete_blocked` unless pid in `forceApply` (then clear it), apply `pull_add` (match via cache/matcher, append) and `pull_remove`, store `new_base`. Liked: if `likedBase is None` → baseline run (base = remote, only pull_add of tracks missing locally, no removals). Liked entries written in the `catalog_engine.add_liked_song` shape plus `spotifyId`. New user-owned Spotify playlists appear in `selected` automatically; Spotify-made ones do not. Any `SpotifyError` → stop the cycle, `lastError = e.code`, no file written for the playlist in progress.

- [ ] **Step 1: Failing tests:**
  - `test_disabled_or_unconfirmed_does_nothing`.
  - `test_creates_linked_playlist_with_fixed_id`.
  - `test_truncated_fetch_removes_nothing` (fake returns `complete False`).
  - `test_local_delete_survives_two_syncs`.
  - `test_unmatched_remote_add_retried_later` (matcher returns None first, track later; advance clock 3 days).
  - `test_mass_delete_blocked_then_force_apply`.
  - `test_spotify_made_replaced_wholesale_without_guard`.
  - `test_liked_first_run_is_baseline_only` (local liked missing a remote one → added; local liked not on Spotify → kept; nothing removed).
  - `test_auth_error_leaves_files_untouched` (compare file bytes before/after).
  - `test_new_owned_playlist_auto_selected_spotify_made_not`.
  - `test_playlist_list_cache_expires_after_6h` (importer).
- [ ] **Step 2–4:** FAIL → implement → PASS.
- [ ] **Step 5: Commit** `feat(spotify-sync): pull Spotify playlists and liked songs`.

### Task 6: HTTP route on both platforms

**Files:**
- Modify: `backend/spotify_sync.py` — add `handle_http_path(handler, path, body)` (same shape as `account_sync.handle_http_path`; ops `run`, `status`, `choices`, `set_selection`, `set_enabled`, `force_apply`; `run` executes in a background thread and returns `{"success": True, "started": True}`, result lands in `status`).
- Modify: `backend/route_dispatcher.py` — `elif clean_path.startswith("/api/spotify/sync/")` next to `/api/sync/` (line ~247).
- Modify: `backend/auth_server.py` only if its `do_POST` fallthrough to `route_dispatcher.dispatch_request` does not reach the new prefix.
- Test: `scripts/test_spotify_sync.py` (class `RouteTests`, mirror `test_playlist_backend.py`'s two-router test)
- Modify: `.github/workflows/verify.yml` — add `python scripts/test_spotify_sync.py`.

- [ ] **Step 1: Failing test** `test_status_route_on_both_routers`: POST `/api/spotify/sync/status` with `{"profile": ""}` through `route_dispatcher` and `auth_server` → both 200 with `enabled False`. `test_unknown_op_404`.
- [ ] **Step 2–4:** FAIL → implement → PASS.
- [ ] **Step 5: Run** `python scripts/verify_codebase.py` → no errors.
- [ ] **Step 6: Commit** `feat(spotify-sync): /api/spotify/sync routes on Linux and Windows`.

### Task 7: QML: SpotifySync object, Settings section, badge

**Files:**
- Create: `components/SpotifySync.qml` (QtObject, pattern of `components/AccountSync.qml`)
- Create: `components/SpotifySyncSection.qml` (pattern of `components/LosslessSettingsSection.qml`)
- Create: `assets/icons/spotify-link.svg` (small mono glyph, `currentColor`)
- Modify: `shell.qml` — declare `SpotifySync { id: spotifySync }` near `AccountSync` (~line 5323); on `remoteChanged` reload `playlistStore` / `likedSongsFileView` like `accountSync`; pass to `SettingsModal`.
- Modify: `components/SettingsModal.qml` — place `SpotifySyncSection` under the "Tài khoản Spotify" row in the Account tab, visible when a cookie is set.
- Modify: `components/PlaylistDetailView.qml` — badge next to title when `playlist.spotifyLink`; small "Only in Nutsty" label on tracks without `spotifyId` in a linked playlist.
- Modify: `components/I18n.qml` only if strings need a central table (otherwise inline `I18n.tr`).

**Interfaces:**
- Consumes: Task 6 routes.
- Produces (`SpotifySync.qml`): properties `enabled`, `selectionConfirmed`, `running`, `lastSync`, `lastError`, `blocked`, `unmatched`, `choices`, `writeBack`, `backlog`; signals `remoteChanged(var changed)`; functions `run()`, `refreshStatus()`, `loadChoices()`, `confirmSelection(ids, liked)`, `setEnabled(on)`, `forceApply(pid)`, `setWriteBack(on)` and `pushBacklog()` / `cancelBacklog()` (wired in Tasks 8–9). Timer: first run 20 s after start, interval 3 h, only when `enabled && selectionConfirmed`.

UI copy (exact pairs):
- Toggle: `I18n.tr("Tự cập nhật từ Spotify", "Auto-update from Spotify")`, sub `I18n.tr("Chỉ nên bật trên một máy. Các máy khác nhận qua đồng bộ tài khoản.", "Turn this on for one device only. Your other devices get the changes through account sync.")`
- Picker title `I18n.tr("Chọn playlist để đồng bộ", "Choose playlists to sync")`, liked row `I18n.tr("Bài hát đã thích", "Liked Songs")`, confirm `I18n.tr("Bắt đầu đồng bộ", "Start syncing")`, Spotify-made hint `I18n.tr("Spotify tự tạo, thay mới mỗi lần", "Made by Spotify, replaced each time")`.
- `I18n.tr("Đồng bộ ngay", "Sync now")`, `I18n.tr("Đồng bộ lần cuối lúc %1", "Last synced at %1")`, unmatched `I18n.tr("%1 bài chưa tìm được bản trên YouTube", "%1 songs not found on YouTube yet")`.
- Errors: `auth_expired` → `I18n.tr("Phiên Spotify đã hết hạn. Hãy đăng nhập Spotify lại.", "Your Spotify session expired. Sign in to Spotify again.")`; `rate_limited` → `I18n.tr("Spotify đang giới hạn, sẽ thử lại sau.", "Spotify is rate limiting, will retry later.")`; `query_changed` → `I18n.tr("Spotify vừa thay đổi, cần cập nhật Nutsty.", "Spotify changed something, Nutsty needs an update.")`; `network` → `I18n.tr("Không kết nối được Spotify.", "Could not reach Spotify.")`.
- Blocked: `I18n.tr("%1 định xóa nhiều bài, đã tạm dừng", "%1 would remove many songs, paused")` + button `I18n.tr("Vẫn áp dụng", "Apply anyway")`.
- Badge tooltip `I18n.tr("Đồng bộ với Spotify", "Synced with Spotify")`, track label `I18n.tr("Chỉ có trên Nutsty", "Only in Nutsty")`.

- [ ] **Step 1: Implement** the files above.
- [ ] **Step 2: Run** `python scripts/verify_codebase.py` and `python scripts/verify_qml_compat.py` → both pass (compat proves Windows loads it).
- [ ] **Step 3: Run** `qmllint components/SpotifySync.qml components/SpotifySyncSection.qml components/PlaylistDetailView.qml` → no new errors.
- [ ] **Step 4: Visual check:** `./run.sh`, open Settings → Account, screenshot in both `vi` and `en`; open a linked playlist, screenshot badge. Check: no emoji, no grey-black buttons, no mixed-language strings.
- [ ] **Step 5: End-to-end with the developer's own account:** enable, pick 1–2 small playlists + Liked Songs, Sync now; add a song on Spotify, Sync now → appears; remove one on Spotify → disappears; delete one in Nutsty, Sync now twice → stays deleted.
- [ ] **Step 6: Commit** `feat(spotify-sync): settings section, sync object and playlist badge`.

---

## Phase 2: Nutsty → Spotify

### Task 8: Write-back queue

**Files:**
- Modify: `backend/spotify_sync.py`, `backend/spotify_sync_state.py`
- Test: `scripts/test_spotify_sync.py` (class `PushTests`)

**Interfaces:**
- Consumes: `three_way(..., write_back=True)`, client write ops, `MatchCache.find_by_video`.
- Produces: `set_write_back(profile, on: bool)` — on: `writeBack True`, `writeBackSince = now`, `localBaseline` = current track unique keys (`pm.get_track_unique_key`) of every linked owned playlist and of liked; off: clears baseline. Route op `set_write_back`.
  - `reverse_match(track: dict, client, cache) -> str | None`: cache `find_by_video` first, else `client.search_tracks(title, artist)` scored with `spotify_importer.calculate_track_match_score` (Spotify candidate as `yt_candidate` argument with `durationMs`), threshold 50; result cached.

During `sync_once` when `writeBack` and playlist `owned` (or liked): local tracks without `spotifyId` whose key is not in `localBaseline` get `reverse_match`; matched → set `spotifyId` (persist) → part of `local`. Unmatched stay "Only in Nutsty". Then for `push_add`: re-read remote (fresh `playlist_items` / `liked_items`) and drop ids already there; send in batches. `push_remove` uses `uid` from the fresh remote list for playlists, URIs for liked. Pacing: ≥ 3 s between write calls, ≤ 30 writes per cycle; the rest waits for the next cycle (they stay out of `new_base`). A failed write removes its id's effect from `new_base`.

- [ ] **Step 1: Failing tests:**
  - `test_write_back_off_pushes_nothing`.
  - `test_only_changes_after_switch_on_are_pushed` (liked before switch-on not pushed; liked after → `add_to_library` called).
  - `test_push_add_skips_track_already_remote`.
  - `test_unlike_pushes_remove_from_library`.
  - `test_remove_in_owned_playlist_uses_uid`.
  - `test_followed_playlist_never_written`.
  - `test_write_cap_30_per_cycle_rest_next_cycle` (fake clock, no real sleep).
  - `test_failed_write_not_in_base`.
  - `test_reverse_match_threshold` (score < 50 → None, cached as unmatched).
- [ ] **Step 2–4:** FAIL → implement → PASS.
- [ ] **Step 5: Live check with the developer's own account on a throwaway Spotify playlist** (create it by hand on Spotify): extend `scripts/spotify_sync_smoke.py --write <playlistId>` to add then remove one known track; confirm in the Spotify app. Fix hashes/variables if `SpotifyQueryChanged`.
- [ ] **Step 6: Commit** `feat(spotify-sync): push likes and playlist edits to Spotify`.

### Task 9: Backlog push

**Files:**
- Modify: `backend/spotify_sync.py`
- Test: `scripts/test_spotify_sync.py` (class `BacklogTests`)

**Interfaces:**
- Produces: `start_backlog(profile) -> dict`, `cancel_backlog(profile) -> dict`; route ops `backlog_start`, `backlog_cancel`; `status()` includes `backlog = {"running": bool, "done": int, "total": int, "unmatched": int}`.
  - Scope: liked songs only (the action is "push earlier likes"): entries in `localBaseline["liked"]` without a Spotify counterpart. Runs in a background thread with the same pacing (≥ 3 s per write), cancellable between writes; on finish removes pushed keys from `localBaseline["liked"]`.
- [ ] **Step 1: Failing tests:** `test_backlog_pushes_pre_switch_likes`, `test_backlog_cancel_stops_between_writes`, `test_backlog_requires_write_back_on`.
- [ ] **Step 2–4:** FAIL → implement → PASS.
- [ ] **Step 5: Commit** `feat(spotify-sync): push earlier likes on request`.

### Task 10: Write-back UI and docs

**Files:**
- Modify: `components/SpotifySync.qml`, `components/SpotifySyncSection.qml`
- Modify: `.agents/rules/02-audio-backend-and-queue-lifecycle.md` (one 5–12 line entry: feature, files, mechanism, footgun "empty remote ≠ delete"; read the file first, stay ≤ 100 lines)
- Modify: `CHANGELOG.md` (user-facing wording, no programming terms, per `.agents/rules/04`)

UI copy:
- Toggle `I18n.tr("Ghi ngược lên Spotify", "Write back to Spotify")`, sub `I18n.tr("Thích, thêm hoặc bớt bài trong Nutsty sẽ đổi cả bên Spotify. Cách này dùng phiên web của Spotify, trái điều khoản Spotify và có rủi ro nhỏ với tài khoản.", "Likes and playlist edits in Nutsty also change Spotify. This uses Spotify's web session, which breaks Spotify's terms and carries a small risk to your account.")`
- Button `I18n.tr("Đẩy các bài đã thích trước đó", "Push earlier likes")`, progress `I18n.tr("Đã đẩy %1/%2", "Pushed %1/%2")`, cancel `I18n.tr("Dừng", "Stop")`.

- [ ] **Step 1: Implement.**
- [ ] **Step 2: Run** `python scripts/verify_codebase.py`, `python scripts/verify_qml_compat.py`, `python scripts/test_spotify_sync.py` → all pass.
- [ ] **Step 3: Visual check** both locales, screenshot the section with write-back on and backlog running.
- [ ] **Step 4: Commit** `feat(spotify-sync): write-back switch and backlog action`.
