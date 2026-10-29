#!/usr/bin/env python3
"""
Lyrics Engine — Parsers for LRC, Rich-Sync Syllables, and TTML Apple Music.
"""

from __future__ import annotations
import re
import html
from typing import List, Dict, Any, Optional


def clean_vocal_markers(text: str) -> str:
    if not text:
        return ""
    # Strip voice/vocal prefixes like "v1: ", "v2: ", "bgv: ", "[v1] ", "(v1) ", "vocal 1: ", "[vocal 2]"
    t = re.sub(r'^(?:v\d+|bgv|bg|vocal\s*\d*)\s*:\s*', '', text, flags=re.IGNORECASE)
    t = re.sub(r'^[\[\(](?:v\d+|bgv|bg|vocal\s*\d*)[\]\)]\s*:?\s*', '', t, flags=re.IGNORECASE)
    return t.strip()


def strip_rich_sync_tags(text: str) -> str:
    if not text:
        return ""
    t = re.sub(r'<[0-9:.]+>', ' ', text)
    t = html.unescape(t)
    t = re.sub(r'\s+', ' ', t).strip()
    return clean_vocal_markers(t)


def parse_rich_sync_words(line_str: str, default_start: float = 0.0) -> List[Dict[str, Any]]:
    """Parse <mm:ss.xx> word timestamps embedded in a LRC line."""
    if not line_str or "<" not in line_str or ">" not in line_str:
        return []
    pattern = re.compile(r'<(\d{1,2}):(\d{1,2}(?:\.\d+)?)>\s*([^<]*)')
    matches = list(pattern.finditer(line_str))
    if not matches:
        return []
    words = []
    for i, m in enumerate(matches):
        mins, secs = int(m.group(1)), float(m.group(2))
        start_t = round(mins * 60.0 + secs, 3)
        txt = clean_vocal_markers(html.unescape(m.group(3).strip()))
        if not txt:
            continue
        if i + 1 < len(matches):
            nm = matches[i + 1]
            end_t = round(int(nm.group(1)) * 60.0 + float(nm.group(2)), 3)
        else:
            end_t = round(start_t + 0.5, 3)
        dur = max(0.08, round(end_t - start_t, 3))
        words.append({
            "text": txt,
            "start": start_t,
            "end": end_t,
            "duration": dur,
            "isHeld": dur >= 0.85,
        })
    return words


def parse_lrc(lrc_text: str) -> List[Dict[str, Any]]:
    """Parse LRC text -> list of lyric line dicts.
    Lines with <mm:ss.xx> tags get hasWords=True (real syllable data).
    Plain lines get hasWords=False + isSynthetic=True -> Full-Line Highlight in QML.
    """
    if not lrc_text:
        return []
    results = []
    time_regex = re.compile(r'\[(\d{1,2}):(\d{1,2}(?:\.\d+)?)\]')

    for line in lrc_text.splitlines():
        line = line.strip()
        if not line:
            continue
        if re.match(r'^\[[a-zA-Z]+:', line):
            continue
        matches = list(time_regex.finditer(line))
        if not matches:
            continue
        last_match = matches[-1]
        raw_text = line[last_match.end():].strip()
        clean_text = strip_rich_sync_tags(raw_text)
        if not clean_text or clean_text in ("♪", "♫", "🎵"):
            continue
        syllable_words = parse_rich_sync_words(raw_text)
        for m in matches:
            mins, secs = int(m.group(1)), float(m.group(2))
            total_sec = round(mins * 60.0 + secs, 3)
            end_sec = max((w["end"] for w in syllable_words), default=None)
            results.append({
                "time": total_sec,
                "endTime": end_sec if end_sec is not None else round(total_sec + 4.5, 3),
                "text": clean_text,
                "hasWords": bool(syllable_words),
                "isSynthetic": not bool(syllable_words),
                "words": syllable_words,
            })
    results.sort(key=lambda x: x["time"])

    # Fill in endTime for lines without syllable timestamps
    for i, it in enumerate(results):
        if not it.get("hasWords"):
            if i + 1 < len(results):
                it["endTime"] = results[i + 1]["time"]
            else:
                it["endTime"] = round(it["time"] + 5.0, 3)
    return results


def parse_ttml_time(t: str) -> float:
    """Parse TTML time '1:23.456' or '83.456' -> float seconds."""
    t = t.strip()
    parts = t.split(":")
    if len(parts) == 3:
        h, m, s = parts
        return int(h) * 3600 + int(m) * 60 + float(s)
    elif len(parts) == 2:
        m, s = parts
        return int(m) * 60 + float(s)
    else:
        try:
            return float(t.replace("s", ""))
        except ValueError:
            return 0.0


def parse_ttml_body(ttml_text: str) -> List[Dict[str, Any]]:
    """Parse TTML XML string -> list of word-level synced line dicts."""
    if not ttml_text:
        return []
    lines = []
    p_pattern = re.compile(r'<p\s+begin="([^"]+)"\s+end="([^"]+)"[^>]*>(.*?)</p>', re.DOTALL)
    span_pattern = re.compile(r'<span\s+begin="([^"]+)"\s+end="([^"]+)"[^>]*>([^<]+)</span>')

    for p_match in p_pattern.finditer(ttml_text):
        line_begin = parse_ttml_time(p_match.group(1))
        line_end = parse_ttml_time(p_match.group(2))
        inner = p_match.group(3)

        spans = list(span_pattern.finditer(inner))
        words = []
        for sm in spans:
            wb = parse_ttml_time(sm.group(1))
            we = parse_ttml_time(sm.group(2))
            raw_wtxt = clean_vocal_markers(html.unescape(sm.group(3)).strip())
            if not raw_wtxt:
                continue
            dur = max(0.08, round(we - wb, 3))
            words.append({
                "text": raw_wtxt,
                "start": round(wb, 3),
                "end": round(we, 3),
                "duration": dur,
                "isHeld": dur >= 0.85,
            })

        plain_text = clean_vocal_markers(html.unescape(re.sub(r'<[^>]+>', '', inner)).strip())
        if not plain_text or plain_text in ("♪", "♫", "🎵"):
            continue

        if words:
            lines.append({
                "time": round(line_begin, 3),
                "endTime": round(line_end, 3),
                "text": plain_text,
                "hasWords": True,
                "isSynthetic": False,
                "words": words,
            })
        else:
            lines.append({
                "time": round(line_begin, 3),
                "endTime": round(line_end, 3),
                "text": plain_text,
                "hasWords": False,
                "isSynthetic": True,
                "words": [],
            })

    lines.sort(key=lambda x: x["time"])
    return lines
