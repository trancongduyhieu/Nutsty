#!/usr/bin/env python3
"""
Nutsty Lyrics Romanization Engine
Ported and adapted from SimpMusic's LyricsRomanizer architecture.
Provides lightweight per-line pronunciation transliteration for:
- Korean Hangul (Algorithmic arithmetic decomposition with Liaison & Assimilation rules, 0-dependency)
- Japanese Romaji (Hepburn standard for Kana + pykakasi for Kanji)
- Chinese Pinyin (pypinyin with tone diacritics)

Preserves original word timings & timestamps without altering the primary lyric sheet.
"""

from __future__ import annotations
import re
from typing import Optional, Set, Tuple, List, Dict

# ──────────────────────────────────────────────────────────────────────────────
# 1. Korean Hangul Romanizer (Pure Algorithmic — SimpMusic Port)
# ──────────────────────────────────────────────────────────────────────────────

SYLLABLE_BASE = 0xAC00
MEDIAL_COUNT = 21
FINAL_COUNT = 28
SILENT_INITIAL = 11  # ㅇ index

INITIALS = [
    "g", "kk", "n", "d", "tt", "r", "m", "b", "pp",
    "s", "ss", "", "j", "jj", "ch", "k", "t", "p", "h"
]

MEDIALS = [
    "a", "ae", "ya", "yae", "eo", "e", "yeo", "ye", "o",
    "wa", "wae", "oe", "yo", "u", "wo", "we", "wi", "yu",
    "eu", "ui", "i"
]

# When NOT followed by a vowel (unreleased stop)
FINALS = [
    "", "k", "k", "k", "n", "n", "n", "t", "l", "k", "m",
    "l", "l", "l", "p", "l", "m", "p", "p", "t", "t",
    "ng", "t", "t", "k", "t", "p", "t"
]

# When moving to next syllable's empty initial ㅇ (liaison)
FINALS_AS_INITIAL = [
    "", "g", "kk", "ks", "n", "nj", "nh", "d", "l", "lg", "lm",
    "lb", "ls", "lt", "lp", "lh", "m", "b", "bs", "s", "ss",
    "ng", "j", "ch", "k", "t", "p", "h"
]

# Assimilations: (final_idx, next_initial_idx) -> replacement for final
ASSIMILATIONS: Dict[Tuple[int, int], str] = {}
# ㄱ/ㄲ/ㅋ before ㄴ(2) or ㅁ(6) -> ng (e.g. 학년 hangnyeon, 국물 gungmul)
for _f in [1, 2, 24]:
    ASSIMILATIONS[(_f, 2)] = "ng"
    ASSIMILATIONS[(_f, 6)] = "ng"
# ㅂ/ㅍ before ㄴ(2) or ㅁ(6) -> m (e.g. 입니다 imnida)
for _f in [17, 26]:
    ASSIMILATIONS[(_f, 2)] = "m"
    ASSIMILATIONS[(_f, 6)] = "m"
# ㄷ/ㅅ/ㅆ/ㅈ/ㅊ/ㅌ/ㅎ before ㄴ(2) or ㅁ(6) -> n (e.g. 닫는 danneun)
for _f in [7, 19, 20, 22, 23, 25, 27]:
    ASSIMILATIONS[(_f, 2)] = "n"
    ASSIMILATIONS[(_f, 6)] = "n"
# ㄴ before ㄹ(5) -> l (신라 Silla); ㄹ before ㄴ(2) -> l (설날 seollal)
ASSIMILATIONS[(4, 5)] = "l"
ASSIMILATIONS[(8, 2)] = "l"


class Jamo:
    __slots__ = ("initial", "medial", "final")

    def __init__(self, initial: int, medial: int, final: int):
        self.initial = initial
        self.medial = medial
        self.final = final


def decompose_hangul(char: str) -> Optional[Jamo]:
    code = ord(char)
    offset = code - SYLLABLE_BASE
    if offset < 0 or offset >= MEDIAL_COUNT * FINAL_COUNT * len(INITIALS):
        return None
    initial = offset // (MEDIAL_COUNT * FINAL_COUNT)
    medial = (offset % (MEDIAL_COUNT * FINAL_COUNT)) // FINAL_COUNT
    final = offset % FINAL_COUNT
    return Jamo(initial, medial, final)


def apply_liaison(final_idx: int, next_jamo: Optional[Jamo]) -> str:
    if final_idx == 0:
        return ""
    if next_jamo is None:
        return FINALS[final_idx]
    if next_jamo.initial == SILENT_INITIAL:
        return FINALS_AS_INITIAL[final_idx]
    return ASSIMILATIONS.get((final_idx, next_jamo.initial), FINALS[final_idx])


def romanize_hangul(text: str) -> str:
    """Romanize Korean Hangul into Revised Romanization with Liaison & Assimilations."""
    result: List[str] = []
    idx = 0
    length = len(text)
    while idx < length:
        ch = text[idx]
        jamo = decompose_hangul(ch)
        if jamo is None:
            result.append(ch)
            idx += 1
            continue

        next_jamo = decompose_hangul(text[idx + 1]) if idx + 1 < length else None
        result.append(INITIALS[jamo.initial])
        result.append(MEDIALS[jamo.medial])
        result.append(apply_liaison(jamo.final, next_jamo))
        idx += 1
    return "".join(result)


# ──────────────────────────────────────────────────────────────────────────────
# 2. Japanese Kana & Kanji Romanizer (Hepburn Standard)
# ──────────────────────────────────────────────────────────────────────────────

YOUON: Dict[str, str] = {
    "きゃ": "kya", "きゅ": "kyu", "きょ": "kyo",
    "しゃ": "sha", "しゅ": "shu", "しょ": "sho",
    "ちゃ": "cha", "ちゅ": "chu", "ちょ": "cho",
    "にゃ": "nya", "にゅ": "nyu", "にょ": "nyo",
    "ひゃ": "hya", "ひゅ": "hyu", "ひょ": "hyo",
    "みゃ": "mya", "みゅ": "myu", "みょ": "myo",
    "りゃ": "rya", "りゅ": "ryu", "りょ": "ryo",
    "ぎゃ": "gya", "ぎゅ": "gyu", "ぎょ": "gyo",
    "じゃ": "ja", "じゅ": "ju", "じょ": "jo",
    "びゃ": "bya", "びゅ": "byu", "びょ": "byo",
    "ぴゃ": "pya", "ぴゅ": "pyu", "ぴょ": "pyo",
    "ふぁ": "fa", "ふぃ": "fi", "ふぇ": "fe", "ふぉ": "fo",
    "うぃ": "wi", "うぇ": "we", "てぃ": "ti", "でぃ": "di",
    "とぅ": "tu", "どぅ": "du", "ゔぁ": "va", "ゔぃ": "vi",
    "ゔぇ": "ve", "ゔぉ": "vo", "しぇ": "she", "ちぇ": "che",
    "じぇ": "je"
}

KANA: Dict[str, str] = {
    'あ': "a", 'い': "i", 'う': "u", 'え': "e", 'お': "o",
    'か': "ka", 'き': "ki", 'く': "ku", 'け': "ke", 'こ': "ko",
    'さ': "sa", 'し': "shi", 'す': "su", 'せ': "se", 'そ': "so",
    'た': "ta", 'ち': "chi", 'つ': "tsu", 'て': "te", 'と': "to",
    'な': "na", 'に': "ni", 'ぬ': "nu", 'ね': "ne", 'の': "no",
    'は': "ha", 'ひ': "hi", 'ふ': "fu", 'へ': "he", 'ほ': "ho",
    'ま': "ma", 'み': "mi", 'む': "mu", 'め': "me", 'も': "mo",
    'や': "ya", 'ゆ': "yu", 'よ': "yo",
    'ら': "ra", 'り': "ri", 'る': "ru", 'れ': "re", 'ろ': "ro",
    'わ': "wa", 'を': "o", 'ん': "n",
    'が': "ga", 'ぎ': "gi", 'ぐ': "gu", 'げ': "ge", 'ご': "go",
    'ざ': "za", 'じ': "ji", 'ず': "zu", 'ぜ': "ze", 'ぞ': "zo",
    'だ': "da", 'ぢ': "ji", 'づ': "zu", 'de': "de", 'ど': "do",
    'ば': "ba", 'び': "bi", 'ぶ': "bu", 'べ': "be", 'ぼ': "bo",
    'ぱ': "pa", 'ぴ': "pi", 'ぷ': "pu", 'ぺ': "pe", 'ぽ': "po",
    'ぁ': "a", 'ぃ': "i", 'ぅ': "u", 'ぇ': "e", 'ぉ': "o",
    'ゃ': "ya", 'ゅ': "yu", 'ょ': "yo", 'ゔ': "vu"
}

KATAKANA_OFFSET = 0x60
SOKUON_HIRAGANA = 'っ'
CHOUON = 'ー'

# Lazy pykakasi instance
_kks_instance = None


def _get_kakasi():
    global _kks_instance
    if _kks_instance is None:
        try:
            import pykakasi
            _kks_instance = pykakasi.kakasi()
        except Exception:
            _kks_instance = False
    return _kks_instance if _kks_instance is not False else None


def to_hiragana(text: str) -> str:
    res = []
    for c in text:
        code = ord(c)
        if 0x30A1 <= code <= 0x30F6:  # Katakana ァ..ヶ
            res.append(chr(code - KATAKANA_OFFSET))
        else:
            res.append(c)
    return "".join(res)


def romanize_kana(text: str) -> str:
    kana = to_hiragana(text)
    res = []
    idx = 0
    length = len(kana)

    def peek_next(pos: int) -> Optional[str]:
        if pos >= length:
            return None
        if pos + 1 < length:
            pair = kana[pos:pos + 2]
            if pair in YOUON:
                return YOUON[pair]
        return KANA.get(kana[pos])

    while idx < length:
        ch = kana[idx]
        if ch == SOKUON_HIRAGANA:
            next_romaji = peek_next(idx + 1)
            if next_romaji and next_romaji[0] not in "aiueo":
                res.append(next_romaji[0])
            idx += 1
            continue

        if ch == CHOUON:
            if res and res[-1] and res[-1][-1] in "aiueo":
                res.append(res[-1][-1])
            idx += 1
            continue

        if idx + 1 < length:
            pair = kana[idx:idx + 2]
            if pair in YOUON:
                res.append(YOUON[pair])
                idx += 2
                continue

        single = KANA.get(ch)
        if single is not None:
            res.append(single)
            idx += 1
            continue

        res.append(ch)
        idx += 1

    return "".join(res)


def romanize_japanese(text: str) -> str:
    kks = _get_kakasi()
    if kks is not None:
        try:
            converted = kks.convert(text)
            chunks = []
            for item in converted:
                h = item.get("hepburn", "")
                if h:
                    chunks.append(h)
                else:
                    chunks.append(item.get("orig", ""))
            raw = " ".join(chunks)
            # Clean punctuation spacing: " , " -> ", ", " . " -> ". "
            raw = re.sub(r'\s+([,.:;?!~])', r'\1', raw)
            return raw.strip()
        except Exception:
            pass
    return romanize_kana(text)


# ──────────────────────────────────────────────────────────────────────────────
# 3. Chinese Pinyin Romanizer
# ──────────────────────────────────────────────────────────────────────────────

_pypinyin_mod = None


def _get_pypinyin():
    global _pypinyin_mod
    if _pypinyin_mod is None:
        try:
            import pypinyin
            _pypinyin_mod = pypinyin
        except Exception:
            _pypinyin_mod = False
    return _pypinyin_mod if _pypinyin_mod is not False else None


def romanize_chinese(text: str) -> str:
    py = _get_pypinyin()
    if py is not None:
        try:
            res = py.lazy_pinyin(text, style=py.Style.TONE)
            raw = " ".join(res)
            raw = re.sub(r'\s+([,.:;?!~，。！？])', r'\1', raw)
            return raw.strip()
        except Exception:
            pass
    return text


# ──────────────────────────────────────────────────────────────────────────────
# 4. Script Detection & Unified Pipeline
# ──────────────────────────────────────────────────────────────────────────────

def detect_script(line: str) -> str:
    """
    Detect primary script of a lyric line.
    Returns: 'HANGUL' | 'JAPANESE' | 'HAN' | 'LATIN'
    """
    has_hangul = False
    has_kana = False
    has_han = False

    for ch in line:
        code = ord(ch)
        # Korean Hangul syllables and jamo
        if (0xAC00 <= code <= 0xD7AF) or (0x1100 <= code <= 0x11FF) or (0x3130 <= code <= 0x318F):
            has_hangul = True
            break
        # Japanese Hiragana and Katakana
        elif (0x3040 <= code <= 0x309F) or (0x30A0 <= code <= 0x30FF):
            has_kana = True
        # CJK Unified Ideographs (Hanzi / Kanji)
        elif (0x4E00 <= code <= 0x9FFF) or (0x3400 <= code <= 0x4DBF):
            has_han = True

    if has_hangul:
        return 'HANGUL'
    if has_kana:
        return 'JAPANESE'
    if has_han:
        # CJK ideographs without kana: treat as Chinese (or Kanji-only lines)
        return 'HAN'
    return 'LATIN'


def romanize_line(line: str, enabled_languages: Optional[Set[str]] = None) -> Optional[str]:
    """
    Romanize a single lyric line into Latin script.
    
    Returns romanized string, or None if:
    - line is empty or purely whitespace
    - line is Latin / English / numbers (avoids duplicate text rows)
    - output is identical to input
    """
    if not line or not line.strip():
        return None

    stripped = line.strip()
    script = detect_script(stripped)

    if script == 'LATIN':
        return None

    if enabled_languages is not None:
        if script == 'HANGUL' and 'KOREAN' not in enabled_languages:
            return None
        if script == 'JAPANESE' and 'JAPANESE' not in enabled_languages:
            return None
        if script == 'HAN' and 'CHINESE' not in enabled_languages:
            return None

    romanized: Optional[str] = None
    if script == 'HANGUL':
        romanized = romanize_hangul(stripped)
    elif script == 'JAPANESE':
        romanized = romanize_japanese(stripped)
    elif script == 'HAN':
        romanized = romanize_chinese(stripped)

    if not romanized or romanized.strip() == stripped:
        return None

    return romanized.strip()
