# Lyrics Romanization Suite Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Provide automated Romanization (Romaji, Romaja, Pinyin) for Japanese, Korean, and Chinese lyrics without touching original syllable timings, fully integrated into the backend and UI.

**Architecture:** Python `backend/romanizer.py` module detecting line script and applying Hangul arithmetic decomposition (SimpMusic port), pykakasi Hepburn romaji, and pypinyin. `lyrics_helper.py` injects `romanized` field into parsed lyric line dictionaries. `AmberolDetailView.qml`, `DesktopLyricsWidget.qml`, and `SettingsModal.qml` expose the toggle and render the secondary pronunciation row.

**Tech Stack:** Python 3 (pykakasi, pypinyin), Qt 6 / Quickshell QML.

---

### Task 1: Create Backend Romanizer Module (`backend/romanizer.py`)

**Files:**
- Create: `backend/romanizer.py`
- Test: `tests/test_romanizer.py`

- [ ] **Step 1: Write `backend/romanizer.py`**
Implement script detection (Hangul, Japanese, Chinese, Latin), Hangul arithmetic decomposition with liaison matching SimpMusic `HangulRomanizer.kt`, Kana/Kanji Hepburn with `pykakasi` fallback, and `pypinyin`.

- [ ] **Step 2: Write test file `tests/test_romanizer.py`**
Test Korean (`한국어` $\rightarrow$ `hangugeo`, `사랑해` $\rightarrow$ `saranghae`), Japanese (`君の名は` $\rightarrow$ `kimi no na ha` / `kun no mei ha`, `ありがとう` $\rightarrow$ `arigatou`), Chinese (`你好世界` $\rightarrow$ `nǐ hǎo shì jiè`), and English lines (`Hello World` $\rightarrow$ `None`).

- [ ] **Step 3: Run test suite**
Run: `python3 tests/test_romanizer.py`
Expected: PASS with exit code 0.

- [ ] **Step 4: Commit**
```bash
git add backend/romanizer.py tests/test_romanizer.py
git commit -m "feat(backend): add CJK lyrics romanizer engine ported from SimpMusic"
```

---

### Task 2: Integrate Romanizer into `backend/lyrics_helper.py`

**Files:**
- Modify: `backend/lyrics_helper.py`
- Modify: `requirements.txt`
- Modify: `requirements_win.txt`

- [ ] **Step 1: Update requirements**
Add `pypinyin>=0.50.0` and `pykakasi>=2.3.0` to `requirements.txt` and `requirements_win.txt`.

- [ ] **Step 2: Modify `backend/lyrics_helper.py`**
Import `romanize_line` from `romanizer.py`.
In `parse_lrc`, `_parse_ttml_lines`, and database lyrics providers, populate `"romanized": romanize_line(clean_text)`.

- [ ] **Step 3: Verify CLI output**
Run: `python3 backend/lyrics_helper.py --test-romanization`
Expected: JSON lines contain valid `romanized` strings for CJK songs and `None` for English songs.

- [ ] **Step 4: Commit**
```bash
git add backend/lyrics_helper.py requirements.txt requirements_win.txt
git commit -m "feat(lyrics): inject romanized pronunciation into parsed lyrics lines"
```

---

### Task 3: Add Settings Toggle in `shell.qml` & `components/SettingsModal.qml`

**Files:**
- Modify: `shell.qml`
- Modify: `components/SettingsModal.qml`

- [ ] **Step 1: Expose `lyricsRomanizationEnabled` in `shell.qml`**
Add state property and persistence in `nutsty_settings.json` (default `true`).

- [ ] **Step 2: Add Toggle Switch in `SettingsModal.qml`**
Add a clean frameless row in Tab 1 (Desktop Lyrics / Lời bài hát) with title `I18n.tr("Phiên âm lời bài hát Latinh", "Lyrics Romanization")` and description `I18n.tr("Hiển thị phiên âm Romaji, Romaja, Pinyin bên dưới câu hát", "Show Romaji, Romaja, and Pinyin readings under original lyrics")`.

- [ ] **Step 3: Commit**
```bash
git add shell.qml components/SettingsModal.qml
git commit -m "feat(ui): add lyrics romanization toggle in settings"
```

---

### Task 4: Display Romanized Lyrics in `AmberolDetailView.qml` & Desktop Lyrics

**Files:**
- Modify: `components/AmberolDetailView.qml`
- Modify: `components/AppleMusicDesktopLyrics.qml`
- Modify: `components/GachaAnimeLyricsView.qml`

- [ ] **Step 1: Add romanized row in `AmberolDetailView.qml`**
Display italicized, soft-opacity Latin pronunciation beneath each line when available and enabled.

- [ ] **Step 2: Add romanized row in `AppleMusicDesktopLyrics.qml` and `GachaAnimeLyricsView.qml`**
Render the reading under active/highlighted lines on desktop.

- [ ] **Step 3: Commit**
```bash
git add components/AmberolDetailView.qml components/AppleMusicDesktopLyrics.qml components/GachaAnimeLyricsView.qml
git commit -m "feat(ui): render romanized pronunciation in Amberol and Desktop Lyrics"
```

---

### Task 5: Empirical Verification & Codebase Integrity

**Files:**
- Run: `python scripts/verify_codebase.py`
- Launch app & Capture screenshot with `grim`
- Pixel audit via Python image inspection

- [ ] **Step 1: Run verification script**
Run: `python scripts/verify_codebase.py`
Expected: 100% PASS.

- [ ] **Step 2: Visual capture & inspection**
Capture live UI with `grim /tmp/screen_romanization.png` and inspect.

- [ ] **Step 3: Final commit & checklist update in `TODO.md`**
Mark items 1.3 & 27 completed in `TODO.md`.
