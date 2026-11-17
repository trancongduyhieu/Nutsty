# ADR-0007: PlaylistStore & Confirmed Playlist Writes over HTTP

- **Status**: Accepted
- **Date**: 2026-11-17
- **Deciders**: User, Claude
- **Informed by**: `codebase-design`, `grill-with-docs`, `improve-codebase-architecture` (candidate C), `GLOSSARY.md`

---

## 1. Context and Problem Statement

Custom playlist state is spread over `shell.qml` (`customPlaylists`, `playlists`, `favoritePlaylists`,
`selectedCustomPlaylist`, `lastLibraryPlaylist`), `playback_engine.js` and `NavSidebar.qml`. Every write
(create, rename, add, remove, reorder, delete, favorite) is a **fire-and-forget write**: QML applies an
optimistic patch, runs `Quickshell.execDetached(["python3", "playlist_manager.py", ...])`, then guesses when
the file is written with `refreshPlaylistsTimer` (300 ms) and reloads everything.

Problems this causes:
1. **Lost writes**: two writes started close together each load the file, modify their copy and save; the
   second save overwrites the first (seen with rename + set cover, fixed ad hoc in 2.1.0). `spotify_importer.py`
   also writes the same file from another process.
2. **No result**: `execDetached` returns nothing, so a failed write still shows a success toast and the UI keeps
   an optimistic patch that never reached disk.
3. **Stale selection**: `selectedCustomPlaylist` is a copied object, re-synced by hand in `customPlaylistsProc`;
   `playlistTrackSearchModal.playlist` is another copy.
4. **Three "is custom" checks** that disagree (`shell.qml` handleSelectPlaylist, `playback_engine.js`
   loadPlaylistTracks, `NavSidebar.qml`).
5. Track arrays are passed as argv JSON (Linux limit 128 KB per argument).

---

## 2. Decision Drivers

- **Locality**: one module owns playlist state and the write path.
- **Correctness**: no lost writes, the UI shows what is on disk, errors are visible.
- **Dual-Platform Parity**: Linux (Quickshell + nutsty-daemon) and Windows (compat + auth_server) behave the same.
- **Contract Preservation**: child components call `win.*` functions and read `win.customPlaylists`; keep them.
- **Compat safety**: only QML features already proven to load through `compat/` (see `verify_qml_compat.py`).

---

## 3. Considered Options

### C1. Where races are fixed
- **Option A (chosen)**: backend is the authority. A cross-process file lock (`fcntl` on Linux, `msvcrt` on
  Windows) wraps every load-modify-save in `playlist_manager.py`, used by `spotify_importer.py` too; the store
  also serializes its own writes. Pros: fixes races from any writer. Cons: small lock helper per platform.
- Option B: serialize in QML only. Cons: does not cover `spotify_importer.py` or two windows of one profile.

### C2. Module shape
- **Option A (chosen)**: `components/PlaylistStore.qml`, a `QtObject` declared once in `shell.qml` as
  `id: playlistStore`. Pros: QML properties give change notification for free; no `property alias` needed.
- Option B: a `.js` engine like ADR-0003. Cons: JS libraries cannot hold notifying state, so `win` would still
  own the properties and the copies.

ADR-0003 rejected a separate `.qml` because of `property alias` compat risk. This ADR avoids aliases: `win`
reads the store through **plain property bindings** (`property var customPlaylists: playlistStore.customPlaylists`)
and keeps its `win.*` functions as 1-line delegates, so ADR-0003's contract still holds.

### C3. Open playlist
- **Option A (chosen)**: the store keeps only `selectedId`; the selected object is derived from
  `customPlaylists`. While a just-created id is not loaded yet, the last known object is used as fallback.
- Option B: keep copying the object. Cons: the stale-copy bug stays.

### C4. Definition of custom playlist
- **Option A (chosen)**: `isCustom(pl)` = id starts with `custom_pl_` (also covers `custom_pl_spotify_*`).
  `isCustom`, `isLocal`, `type`, `source` stay as data only. Local albums (`local_alb_*`) also carry `isLocal`.

### C5. Transport
- **Option A (chosen)**: `POST /api/playlists/<op>` to `127.0.0.1:17890` via `XMLHttpRequest`; body is JSON,
  response is the **playlist write result**. Both routers get the route: `route_dispatcher.py` (Linux, behind
  nutsty-daemon) and `auth_server.py` (Windows). Pros: real result and status, no argv limit, ~ms on a warm worker.
- Option B: compat/Quickshell `Process` with stdout. Cons: on Windows stdout arrives once at the end, no stderr,
  `running=false` does not kill; a new process per write on Linux (~65 ms).

---

## 4. Decision Outcome

- Writes go through `playlistStore`, one at a time. Each write applies its optimistic patch at once, then the
  playlist write result replaces it. On failure the store reloads from the backend and shows a bilingual toast.
  Success toasts are shown only after the result arrives.
- Favorites (`favoritePlaylists`) live in the store too.
- `refreshPlaylistsTimer`, `customPlaylistsProc`, `favPlaylistsProc` and the dead `deleteCustomPlaylist` in
  `playback_engine.js` are removed. Backup import and Spotify import call `playlistStore.reload()`.
- **Profile**: one daemon serves every profile window, so each request carries `profile`
  (`Quickshell.env("NUTSTY_PROFILE")`). The backend resolves the file suffix per request, never from the worker's env.

---

## 5. Interfaces

- `playlistStore` properties: `customPlaylists`, `favoritePlaylists`, `selectedId`, `selected` (read-only), `busy`.
- `playlistStore` functions: `reload()`, `isCustom(pl)`, `isFavorite(pl)`, `select(id, fallbackObj)`,
  `create(title, desc, cover, tracks, cb)`, `update(id, title, desc, cover)`, `addTracks(id, tracks)`,
  `removeTrack(id, track)`, `reorder(id, from, to)`, `remove(id)`, `toggleFavorite(pl)`.
- HTTP: `POST /api/playlists/{list,list_favorites,create,rename,add,remove,reorder,delete,toggle_favorite}`,
  body `{profile, ...}`, response `{success, playlists, favorites, playlist?, error?}`.
- The CLI (`playlist_manager.py <cmd>`) stays for backup export/import and scripts.
