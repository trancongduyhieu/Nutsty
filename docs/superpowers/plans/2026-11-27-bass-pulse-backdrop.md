# Bass Pulse Backdrop Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The blurred artwork backdrop behind the whole Nutsty window swells and warps faster on every bass hit of the playing song.

**Architecture:** A daemon action decodes the whole track through mpv (8 kHz mono, like AutoMix), runs SimpMusic's
BassEnvelope, and caches one pulse byte per 25 ms slot. QML fetches the bytes once per track, looks the pulse up at the
interpolated playhead each frame, and drives `LiquidWarpBackdrop`. The next track is measured when the current one passes 50%.

**Tech Stack:** Python 3 (stdlib `array`, `math`), mpv `--ao=pcm`, Quickshell/QML (`FrameAnimation`, `Process`).

**Spec:** `docs/superpowers/specs/2026-11-27-bass-pulse-backdrop-design.md`

## Global Constraints

- Cutoff 150 Hz, two one-pole low-passes; 40 slots/s; floor 0.5; window ±2 s (80 slots); quiet share 0.15; reference = 95th percentile, 200-bin log histogram over 1e-5..1.
- Pulse decay 0.14 s; zoom up to 7% (`1 + 0.07·pulse`); warp time speed `1 + 3·pulse`; at most 30 updates/s.
- Measure the next track at 50% of the current one; one measurement at a time, the current track first.
- No measuring and no pulse when: switch off (default off), Lite mode, paused, window hidden, the source is Tidal lossless.
- Cache: `<get_cache_dir()>/bass/<sha1(key)>.bass`, one byte per slot (pulse·255); empty file = measured, unusable; keep the newest 500.
- All UI strings through `I18n.tr`; no emoji; switch uses `accentColor`. Must work on Linux and Windows (compat).

## Review Focus

- A song shorter than 4 s or silent: empty pulse, backdrop still, no error (Task 1 test `silence_and_short`).
- Seeking: lookup is by position, not by stream order, so a seek lands on the right slot (Task 3 uses `currentTime` interpolation reset on every status update).
- Skipping fast: a late result for an old track must not drive the new one (Task 4: results keyed by track key, ignored when the key is not current).
- Decode failure (network, yt-dlp): action prints `{"ok": false}`, nothing cached, retried at most once per track per session (Task 2 test `missing_file`).
- Switch turned off mid-song: pulse drops to 0 and the running measurement is left to finish but not applied (Task 4).

---

### Task 1: BassEnvelope port

**Files:**
- Create: `backend/bass_envelope.py`
- Test: `scripts/test_bass_envelope.py`

**Interfaces:**
- Produces: `pulses_from_samples(samples: Sequence[float], rate: int) -> bytes` (one byte per 25 ms slot, `round(pulse·255)`); constants `SLOTS_PER_SECOND = 40`.

- [ ] **Step 1: Write the failing tests** (`scripts/test_bass_envelope.py`, ports of SimpMusic `BassEnvelopeTest`): `burst_60hz` (1 s of 60 Hz at 0.8 then 1 s silence at 8 kHz → max pulse in the burst ≥ 250, every slot of the silence after the first 0.1 s = 0); `treble_ignored` (2 kHz at 0.8 for 2 s → all slots ≤ 10); `quiet_verse_kicks` (8 s of 60 Hz kicks of 50 ms each 0.5 s at 0.2, then 8 s at 0.8 → the verse's kick slots reach ≥ 200); `silence_and_short` (0.5 s of zeros → result is all zeros or empty, no exception).
- [ ] **Step 2: Run** `python3 scripts/test_bass_envelope.py` → fails with ImportError.
- [ ] **Step 3: Implement** the filter, slot RMS, histogram percentile and `pulseAt` exactly as `references/SimpMusic/core/domain/src/commonMain/kotlin/com/maxrave/domain/mediaservice/player/BassEnvelope.kt`, computing every slot's pulse at the end.
- [ ] **Step 4: Run** the test → `test_bass_envelope: OK`.
- [ ] **Step 5: Commit** `feat(bass-pulse): port SimpMusic's bass envelope`.

### Task 2: Measure, cache and daemon action

**Files:**
- Modify: `backend/bass_envelope.py` (decode + cache), `backend/player_daemon.py` (action `bass_envelope`)
- Test: `scripts/test_bass_envelope.py` (append)

**Interfaces:**
- Consumes: `pulses_from_samples`.
- Produces: `measure(url: str, stream_args: list[str], key: str) -> bytes | None` (cache first; None on failure); CLI `python3 backend/player_daemon.py bass_envelope <path> <title> <artist>` printing `{"ok": true, "key": <key>, "slots": [int...]}` or `{"ok": false, "reason": str}`. Key = the path argument.

- [ ] **Step 1: Tests:** `local_wav_end_to_end` (write a 6 s 8 kHz WAV of 60 Hz bursts with `wave`, call `measure` → length ≈ 240 slots, has bytes ≥ 250, cache file exists, second call does not run mpv: patch `subprocess.run` to raise); `missing_file` (nonexistent path → None, no cache file).
- [ ] **Step 2: Run** → fail.
- [ ] **Step 3: Implement** decode as `crossfade_engine.decode_levels` does (mpv `--ao=pcm`, s16, 8000 Hz, mono, `--untimed`) for the whole file, cap 15 min, timeout 120 s, reading the PCM file in 1 MB chunks into the envelope. Cache write via temp file + `os.replace`; prune to 500 by mtime. Daemon action: `_resolve_for_crossfade(path, title, artist, source_out=box)`; if `box["source"] == "tidal"` print `{"ok": false, "reason": "tidal"}` without decoding; stream args from `_mpv_stream_args(YTDL_FORMAT_MAP.get(get_current_streaming_quality(), ...), ua)`.
- [ ] **Step 4: Run** test → OK; run the action by hand on one local file and one YouTube id.
- [ ] **Step 5: Commit** `feat(bass-pulse): measure and cache a track's bass pulse`.

### Task 3: Backdrop pulse

**Files:**
- Modify: `components/LiquidWarpBackdrop.qml`

**Interfaces:**
- Produces: properties `var pulseSlots` (array of 0..255 or null), `real playhead` (seconds, interpolated by the caller), `bool pulseOn`.

- [ ] **Step 1:** Replace the `NumberAnimation on animTime` with a `FrameAnimation` (same pause conditions) that advances `animTime` by `dt · (2π/50) · (1 + 3·pulse)`, wrapping at 2π·k; throttle pulse updates to ≥ 33 ms.
- [ ] **Step 2:** Each update: `target = pulseOn && pulseSlots ? pulseSlots[floor(playhead·40)]/255 : 0`; `pulse = max(target, pulse·exp(−dt/0.14))`; apply `scale: 1 + 0.07·pulse` to the warp/blur item (transform origin centre).
- [ ] **Step 3: Verify** with an offscreen harness (like the update-dialog one): fake `pulseSlots` with a hit at 1.0 s, screenshot at 1.0 s and 1.5 s → the first is visibly larger; `verify_qml_compat.py` OK.
- [ ] **Step 4: Commit** `feat(bass-pulse): backdrop swells on bass hits`.

### Task 4: Wiring, setting and next-track prefetch

**Files:**
- Modify: `shell.qml` (state, Process queue, persistence, backdrop bindings), `components/playback_engine.js` (`maybePrefetchNextBass` beside `maybePrefetchNextCover`), `components/SettingsModal.qml` (switch next to AutoMix)

**Interfaces:**
- Consumes: CLI action from Task 2; backdrop properties from Task 3.
- Produces: `win.bassPulseEnabled` (persisted as `bassPulseEnabled`), `win.requestBassPulse(trk, isCurrent)`.

- [ ] **Step 1:** `win.bassPulseEnabled` saved/loaded like `autoMixEnabled`; Settings switch "Đập theo nhịp bass" / "Pulse to the bass" with a one-line description "Nền ảnh bìa phồng nhẹ theo tiếng bass của bài đang phát." / "The artwork background swells with the bass of the playing song."
- [ ] **Step 2:** A cache `win.bassSlotsByKey` (keep 4 keys) and one `Process` (`bassProc`). Request for the current track on track change; next track from `maybePrefetchNextBass` at `currentTime ≥ 0.5·totalDuration` (pair key like the cover prefetch). Current track preempts a queued next request; a running one finishes. Results stored by key; failures remembered per key for the session.
- [ ] **Step 3:** Interpolated playhead: on every status update remember `(currentTime, Date.now())`; backdrop `playhead = isPlaying ? t0 + (now − at)/1000 : currentTime`, evaluated in the backdrop's frame tick via a function, not a binding on `Date.now()`.
- [ ] **Step 4:** Backdrop `pulseOn: bassPulseEnabled && isPlaying && !liteMode && window visible`; `pulseSlots: bassSlotsByKey[trackKeyOf(currentTrack)] || null`.
- [ ] **Step 5: Verify** `verify_codebase.py`, `verify_qml_compat.py`, `qmllint` on touched files; run the app, play a local song with a clear kick, switch on, watch the backdrop pulse; check the next song pulses at once after skipping past 50%.
- [ ] **Step 6:** CHANGELOG 2.7.0 Added entry in plain words; commit `feat(bass-pulse): artwork background pulses to the bass` and push (no tag).
