# Lyrics Romanization Suite (SimpMusic-Inspired Hybrid Engine)

## Context & Problem Statement
Users listening to East Asian music (Japanese Anime/J-Pop, Korean K-Pop, and Chinese C-Pop) often cannot read Kanji/Hanzi or Hangul directly. SimpMusic solved this with a dedicated per-line Romanization layer that provides Latin-script pronunciation without modifying original lyric timings.
Nutsty needs a lightweight, high-performance lyrics romanization pipeline that:
1. Automatically identifies Japanese (Romaji), Korean (Romaja), and Chinese (Pinyin) per line.
2. Preserves 100% of rich sync timings `<mm:ss.xx>`, word flow animations, and plain LRC sync.
3. Renders an elegant secondary pronunciation row beneath active and upcoming lyrics in `AmberolDetailView` and `DesktopLyricsWidget`.
4. Provides a toggle switch in `SettingsModal` ("Phiên âm lời bài hát Latinh (Romanization)") to turn on/off with zero overhead.

## Architecture

```
                    ┌────────────────────────┐
                    │ Lyrics Source (LRC/DB) │
                    └───────────┬────────────┘
                                │
                    ┌───────────▼────────────┐
                    │  backend/romanizer.py  │
                    │  (Detect Script Line)  │
                    └─────┬──────┬──────┬────┘
           Hangul (KR)    │      │      │ Hanzi (ZH)
     ┌────────────────────┘      │      └────────────────────┐
     │                           │ Kana/Kanji (JA)           │
┌────▼─────────────────┐  ┌──────▼─────────────┐   ┌─────────▼──────────────┐
│  HangulRomanizer     │  │  JapaneseRomanizer │   │  ChineseRomanizer      │
│  (0-dep Arithmetic   │  │  (pykakasi /       │   │  (pypinyin Tone Marks) │
│   Decomposition)     │  │   Kana fallback)   │   └─────────┬──────────────┘
└────┬─────────────────┘  └──────┬─────────────┘             │
     │                           │                           │
     └───────────────────────────┼───────────────────────────┘
                                 │
                    ┌────────────▼───────────┐
                    │   lyrics_helper.py     │
                    │ Line: { ..., romanized}│
                    └────────────┬───────────┘
                                 │ IPC
                    ┌────────────▼───────────┐
                    │    QML UI Layer        │
                    │  - AmberolDetailView   │
                    │  - DesktopLyricsWidget │
                    │  - SettingsModal       │
                    └────────────────────────┘
```

### 1. Script Detection (Per-Line)
- Korean (Hangul): Unicode block `\uAC00`–`\uD7AF`, `\u1100`–`\u11FF`, `\u3130`–`\u318F`.
- Japanese (Kana & Kanji): Hiragana `\u3040`–`\u309F`, Katakana `\u30A0`–`\u30FF`, or CJK Ideographs with Kana presence.
- Chinese (Hanzi): CJK Ideographs `\u4E00`–`\u9FFF` without Kana.
- Latin / Pure English / Numbers / Punctuation: Detected as Latin $\rightarrow$ returns `None` (avoids mangling English lines).

### 2. Romanization Algorithms
- **Korean**: Ported from SimpMusic `HangulRomanizer.kt`. Decomposes Unicode codepoint `code - 0xAC00` into `initial` (19), `medial` (21), and `final` (28). Implements liaison and final consonant sound shift. Zero external dependencies.
- **Japanese**: `pykakasi` converts Kanji $\rightarrow$ Hepburn Romaji. Pure Kana fallback implements Hepburn table with Youon (`きゃ` $\rightarrow$ `kya`), Sokuon (`っ` $\rightarrow$ double consonant), and Chouon (`ー` $\rightarrow$ elongated vowel).
- **Chinese**: `pypinyin` produces standard Hanyu Pinyin with tonal diacritics (`nǐ hǎo`).

### 3. Settings & Persistence
- Stored in `nutsty_settings.json` under `lyricsRomanizationEnabled: bool` (default: `true`).
- QML `SettingsModal.qml` Tab 1 ("Desktop Lyrics" / "Lời bài hát") provides a master toggle switch.

### 4. UI Rendering Specifications
- **`AmberolDetailView.qml`**:
  - Below `staticLineTxt` or `appleMusicFlowLoader`: Text element with `font.pixelSize: 13`, `font.italic: true`, `opacity: 0.72`, `color: isCurrent ? accentColor : "#a0a5b5"`.
  - Only visible if `modelData.romanized && settings.lyricsRomanizationEnabled`.
- **`DesktopLyricsWidget.qml` (`AppleMusicDesktopLyrics.qml` / `GachaAnimeLyricsView.qml`)**:
  - Under active and upcoming lines: Clean secondary row with ambient shadow, rendering pronunciation clearly.
