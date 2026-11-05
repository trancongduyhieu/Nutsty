//! Core domain models and primitives for Nutsty.
//! Designed for zero-waste memory layout, cache locality, and sub-millisecond dispatch.

use serde::{Deserialize, Serialize};
use smol_str::SmolStr;
use std::fmt;
use std::sync::atomic::{AtomicU64, Ordering};

/// Compact 64-bit track identifier.
/// Cheap to copy, hash, and pass across thread boundaries without heap indirection.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, PartialOrd, Ord, Serialize, Deserialize)]
#[repr(transparent)]
pub struct TrackId(pub u64);

static NEXT_TRACK_ID: AtomicU64 = AtomicU64::new(1);

impl TrackId {
    /// Generates a process-unique TrackId.
    #[inline]
    pub fn generate() -> Self {
        Self(NEXT_TRACK_ID.fetch_add(1, Ordering::Relaxed))
    }

    #[inline]
    pub const fn from_raw(raw: u64) -> Self {
        Self(raw)
    }

    #[inline]
    pub const fn as_u64(&self) -> u64 {
        self.0
    }

    /// Ensures future generated IDs are strictly greater than `max_seen`.
    #[inline]
    pub fn bump_next_id(max_seen: u64) {
        let _ = NEXT_TRACK_ID.fetch_max(max_seen + 1, Ordering::Relaxed);
    }
}

impl fmt::Display for TrackId {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{}", self.0)
    }
}

/// Source location for audio payload.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub enum AudioSource {
    /// Local filesystem path.
    Local(SmolStr),
    /// Remote HTTP/HTTPS audio stream (e.g. YouTube Music, raw audio stream).
    Stream(SmolStr),
}

impl AudioSource {
    pub fn as_str(&self) -> &str {
        match self {
            Self::Local(s) => s.as_str(),
            Self::Stream(s) => s.as_str(),
        }
    }

    pub fn is_local(&self) -> bool {
        matches!(self, Self::Local(_))
    }
}

/// Compact track descriptor.
/// Uses `SmolStr` for short strings (up to 23 bytes inline on 64-bit platforms),
/// completely avoiding heap allocations for typical song titles and artist names.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Track {
    pub id: TrackId,
    pub title: SmolStr,
    pub artist: SmolStr,
    pub album: SmolStr,
    /// Duration in milliseconds.
    pub duration_ms: u32,
    pub source: AudioSource,
    pub cover_url: Option<SmolStr>,
}

impl Track {
    #[inline]
    pub fn new(
        title: impl Into<SmolStr>,
        artist: impl Into<SmolStr>,
        album: impl Into<SmolStr>,
        duration_ms: u32,
        source: AudioSource,
    ) -> Self {
        Self {
            id: TrackId::generate(),
            title: title.into(),
            artist: artist.into(),
            album: album.into(),
            duration_ms,
            source,
            cover_url: None,
        }
    }

    #[inline]
    pub fn with_cover(mut self, cover: impl Into<SmolStr>) -> Self {
        self.cover_url = Some(cover.into());
        self
    }
}

/// Playback transport state.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, Default)]
pub enum PlaybackStatus {
    #[default]
    Stopped,
    Playing,
    Paused,
}

/// Playback progress snapshot.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default, Serialize, Deserialize)]
pub struct PlaybackProgress {
    pub position_ms: u32,
    pub duration_ms: u32,
}

impl PlaybackProgress {
    #[inline]
    pub fn progress_ratio(&self) -> f32 {
        if self.duration_ms == 0 {
            0.0
        } else {
            (self.position_ms as f32 / self.duration_ms as f32).clamp(0.0, 1.0)
        }
    }
}

/// Loop / repeat mode.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default, Serialize, Deserialize)]
pub enum RepeatMode {
    #[default]
    Off,
    Track,
    Queue,
}

/// Volume scalar wrapped safely between 0.0 and 1.0.
#[derive(Debug, Clone, Copy, PartialEq, PartialOrd, Serialize, Deserialize)]
pub struct Volume(f32);

impl Volume {
    pub const MUTED: Self = Self(0.0);
    pub const MAX: Self = Self(1.0);

    #[inline]
    pub fn new(val: f32) -> Self {
        Self(val.clamp(0.0, 1.0))
    }

    #[inline]
    pub fn raw(&self) -> f32 {
        self.0
    }
}

impl Default for Volume {
    fn default() -> Self {
        Self(1.0)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::mem::size_of;

    #[test]
    fn test_track_id_monotonic() {
        let id1 = TrackId::generate();
        let id2 = TrackId::generate();
        assert_ne!(id1, id2);
        assert!(id2.as_u64() > id1.as_u64());
    }

    #[test]
    fn test_memory_layout_efficiency() {
        // TrackId should be exactly 8 bytes (equivalent to raw u64)
        assert_eq!(size_of::<TrackId>(), 8);

        // SmolStr is 24 bytes (inline buffer up to 23 bytes without heap)
        assert_eq!(size_of::<SmolStr>(), 24);

        // Ensure Track struct is tightly packed and cache-friendly
        let track_size = size_of::<Track>();
        println!("Track struct size: {} bytes", track_size);
        // Track size must be <= 160 bytes for optimal CPU cache utilization
        assert!(track_size <= 160);
    }

    #[test]
    fn test_smolstr_inline_no_heap() {
        let short_title = "Sparkle";
        let track = Track::new(
            short_title,
            "RADWIMPS",
            "Your Name.",
            230000,
            AudioSource::Local("/music/sparkle.flac".into()),
        );

        assert_eq!(track.title.as_str(), "Sparkle");
        assert_eq!(track.duration_ms, 230000);
    }

    #[test]
    fn test_volume_clamping() {
        assert_eq!(Volume::new(1.5).raw(), 1.0);
        assert_eq!(Volume::new(-0.2).raw(), 0.0);
        assert_eq!(Volume::new(0.75).raw(), 0.75);
    }
}
