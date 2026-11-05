//! Synced Lyrics Engine for Nutsty.
//! Provides O(log N) zero-allocation lookup, millisecond precision,
//! and resilient parsing of LRC formats.

use serde::{Deserialize, Serialize};
use smol_str::SmolStr;
use std::fmt;
use thiserror::Error;

#[derive(Debug, Error, PartialEq, Eq)]
pub enum LyricsError {
    #[error("No valid timestamped lyric lines found in payload")]
    EmptyLyrics,
    #[error("Invalid timestamp syntax: {0}")]
    InvalidTimestamp(String),
}

/// A single timestamped lyric line.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct LyricLine {
    /// Start time in milliseconds.
    pub start_ms: u32,
    /// End time in milliseconds (derived from the subsequent line or estimated duration).
    pub end_ms: u32,
    /// Lyric text payload.
    pub text: SmolStr,
}

impl LyricLine {
    #[inline]
    pub fn is_active_at(&self, position_ms: u32) -> bool {
        position_ms >= self.start_ms && position_ms < self.end_ms
    }
}

/// Structured synced lyrics container with contiguous memory layout.
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct SyncedLyrics {
    lines: Vec<LyricLine>,
}

impl SyncedLyrics {
    /// Parses standard LRC content into a sorted, normalized SyncedLyrics structure.
    /// Handles multiple timestamps per line, sub-second centiseconds (.xx) and milliseconds (.xxx).
    pub fn parse_lrc(input: &str) -> Result<Self, LyricsError> {
        let mut raw_lines: Vec<(u32, SmolStr)> = Vec::new();
        let mut timestamps = Vec::with_capacity(4);

        for line in input.lines() {
            let trimmed = line.trim();
            if trimmed.is_empty() {
                continue;
            }

            timestamps.clear();

            // Extract all timestamps from the line: [mm:ss.xx] or [mm:ss.xxx]
            let mut text_start_idx = 0;
            let bytes = trimmed.as_bytes();
            let mut i = 0;
            while i < bytes.len() {
                if bytes[i] == b'[' {
                    if let Some(close_bracket) = trimmed[i..].find(']') {
                        let tag = &trimmed[i + 1..i + close_bracket];
                        if let Some(ts_ms) = parse_timestamp(tag) {
                            timestamps.push(ts_ms);
                            i += close_bracket + 1;
                            text_start_idx = i;
                            continue;
                        }
                    }
                }
                break;
            }

            if !timestamps.is_empty() {
                let text = trimmed[text_start_idx..].trim();
                let smol_text = SmolStr::new(text);
                if timestamps.len() == 1 {
                    raw_lines.push((timestamps[0], smol_text));
                } else {
                    for &ts in &timestamps[..timestamps.len() - 1] {
                        raw_lines.push((ts, smol_text.clone()));
                    }
                    raw_lines.push((timestamps[timestamps.len() - 1], smol_text));
                }
            }
        }

        if raw_lines.is_empty() {
            return Err(LyricsError::EmptyLyrics);
        }

        // Sort by start timestamp ascending
        raw_lines.sort_by_key(|(ts, _)| *ts);

        // Zero-clone contiguous LyricLine array creation
        let mut lines = Vec::with_capacity(raw_lines.len());
        let mut iter = raw_lines.into_iter().peekable();

        while let Some((start_ms, text)) = iter.next() {
            let end_ms = match iter.peek() {
                Some((next_ts, _)) => {
                    if *next_ts > start_ms {
                        *next_ts
                    } else {
                        // Concurrent / duplicate timestamp: guarantee minimum active duration
                        start_ms + 3_000
                    }
                }
                None => start_ms + 5_000, // default 5 seconds window for final line
            };

            lines.push(LyricLine {
                start_ms,
                end_ms,
                text, // Moved without heap duplication!
            });
        }

        Ok(Self { lines })
    }

    #[inline]
    pub fn is_empty(&self) -> bool {
        self.lines.is_empty()
    }

    #[inline]
    pub fn len(&self) -> usize {
        self.lines.len()
    }

    #[inline]
    pub fn lines(&self) -> &[LyricLine] {
        &self.lines
    }

    /// O(log N) binary search for the active lyric line index at a given playback timestamp.
    /// Returns None if playback is before the first lyric line.
    #[inline]
    pub fn find_current_index(&self, position_ms: u32) -> Option<usize> {
        if self.lines.is_empty() || position_ms < self.lines[0].start_ms {
            return None;
        }

        // Binary search for the first line with start_ms > position_ms
        match self.lines.binary_search_by_key(&position_ms, |line| line.start_ms) {
            Ok(exact_match) => Some(exact_match),
            Err(insertion_point) => {
                if insertion_point > 0 {
                    Some(insertion_point - 1)
                } else {
                    None
                }
            }
        }
    }

    /// Returns a direct zero-allocation reference to the active lyric line.
    /// Returns None if position is before the first line or after the active duration of the current line.
    #[inline]
    pub fn line_at(&self, position_ms: u32) -> Option<&LyricLine> {
        let idx = self.find_current_index(position_ms)?;
        let line = &self.lines[idx];
        if line.is_active_at(position_ms) {
            Some(line)
        } else {
            None
        }
    }
}

/// Parses an LRC timestamp string: e.g. "01:23.45" or "01:23.456" or "01:23"
#[inline]
fn parse_timestamp(tag: &str) -> Option<u32> {
    let mut parts = tag.split(':');
    let minutes_str = parts.next()?;
    let seconds_str = parts.next()?;
    if parts.next().is_some() {
        return None;
    }

    let minutes: u32 = minutes_str.parse().ok()?;

    let (seconds, ms) = if let Some((sec_str, frac_str)) = seconds_str.split_once('.') {
        let sec: u32 = sec_str.parse().ok()?;
        let frac: u32 = frac_str.parse().ok()?;
        let frac_ms = match frac_str.len() {
            1 => frac * 100,
            2 => frac * 10,
            3 => frac,
            _ => frac_str[..3].parse().ok()?,
        };
        (sec, frac_ms)
    } else {
        let sec: u32 = seconds_str.parse().ok()?;
        (sec, 0)
    };

    Some(minutes * 60_000 + seconds * 1_000 + ms)
}

impl fmt::Display for SyncedLyrics {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        for line in &self.lines {
            let m = line.start_ms / 60_000;
            let s = (line.start_ms % 60_000) / 1000;
            let ms = (line.start_ms % 1000) / 10;
            writeln!(f, "[{:02}:{:02}.{:02}] {}", m, s, ms, line.text)?;
        }
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const SAMPLE_LRC: &str = r#"
[ti:Sparkle]
[ar:RADWIMPS]
[al:Your Name.]
[00:15.30]Caught in a never-ending game
[00:20.50]Seems like the world still tries to tame me
[00:25.80]If that's the way it will be
[00:30.10]I will struggle until the end
"#;

    #[test]
    fn test_parse_valid_lrc() {
        let lyrics = SyncedLyrics::parse_lrc(SAMPLE_LRC).expect("LRC should parse cleanly");
        assert_eq!(lyrics.len(), 4);

        assert_eq!(lyrics.lines()[0].start_ms, 15300);
        assert_eq!(lyrics.lines()[0].end_ms, 20500);
        assert_eq!(lyrics.lines()[0].text.as_str(), "Caught in a never-ending game");

        assert_eq!(lyrics.lines()[1].start_ms, 20500);
        assert_eq!(lyrics.lines()[1].end_ms, 25800);
    }

    #[test]
    fn test_binary_search_accuracy() {
        let lyrics = SyncedLyrics::parse_lrc(SAMPLE_LRC).unwrap();

        // Before any lyrics
        assert_eq!(lyrics.find_current_index(5000), None);
        assert!(lyrics.line_at(5000).is_none());

        // Exactly on start
        assert_eq!(lyrics.find_current_index(15300), Some(0));
        assert_eq!(lyrics.line_at(15300).unwrap().text.as_str(), "Caught in a never-ending game");

        // Midway through line 1
        assert_eq!(lyrics.find_current_index(18000), Some(0));

        // Right at line 2 boundary
        assert_eq!(lyrics.find_current_index(20500), Some(1));
        assert_eq!(lyrics.line_at(20500).unwrap().text.as_str(), "Seems like the world still tries to tame me");

        // During last line (start 30100, end 35100)
        assert_eq!(lyrics.find_current_index(32000), Some(3));
        assert_eq!(lyrics.line_at(32000).unwrap().text.as_str(), "I will struggle until the end");

        // Way after last line ends (Outro silence: index is still 3, but line is inactive)
        assert_eq!(lyrics.find_current_index(60000), Some(3));
        assert!(lyrics.line_at(60000).is_none());
    }

    #[test]
    fn test_multi_timestamp_lrc() {
        let multi_lrc = "[00:10.00][00:30.00]Repeated chorus";
        let lyrics = SyncedLyrics::parse_lrc(multi_lrc).unwrap();
        assert_eq!(lyrics.len(), 2);
        assert_eq!(lyrics.lines()[0].start_ms, 10000);
        assert_eq!(lyrics.lines()[1].start_ms, 30000);
    }
}
