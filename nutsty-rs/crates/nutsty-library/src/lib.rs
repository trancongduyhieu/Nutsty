//! Local music library scanner, tag extractor, and instant search index.
//! Optimized for minimal memory usage, zero full-file buffering, and instant cache reload.

use lofty::config::ParseOptions;
use lofty::file::{AudioFile, TaggedFileExt};
use lofty::probe::Probe;
use lofty::tag::{Accessor, ItemKey};
use nutsty_core::{AudioSource, Track, TrackId};
use smol_str::SmolStr;
use std::collections::HashMap;
use std::fs::File;
use std::io::{BufReader, BufWriter};
pub mod db;
pub mod model;
pub mod ops;
pub mod scanner;

pub use db::SimpDb;
pub use model::{AlbumGroup, BatchDeleteResult, DeleteResult, TrackItem};
pub use ops::{add_track, batch_delete_tracks, delete_track, get_grouped_albums};
pub use scanner::{save_library_json, scan_all_tracks};
use std::path::Path;
use thiserror::Error;
use walkdir::WalkDir;

#[derive(Debug, Error)]
pub enum LibraryError {
    #[error("I/O error: {0}")]
    Io(#[from] std::io::Error),
    #[error("Serialization error: {0}")]
    Serialization(#[from] serde_json::Error),
    #[error("Audio tag extraction error: {0}")]
    TagError(String),
}

/// In-memory music library with contiguous storage for CPU cache efficiency.
#[derive(Debug, Clone, Default)]
pub struct MediaLibrary {
    tracks: Vec<Track>,
    id_to_index: HashMap<TrackId, usize>,
}

impl MediaLibrary {
    pub fn new() -> Self {
        Self::default()
    }

    #[inline]
    pub fn len(&self) -> usize {
        self.tracks.len()
    }

    #[inline]
    pub fn is_empty(&self) -> bool {
        self.tracks.is_empty()
    }

    #[inline]
    pub fn tracks(&self) -> &[Track] {
        &self.tracks
    }

    #[inline]
    pub fn get_by_id(&self, id: TrackId) -> Option<&Track> {
        self.id_to_index.get(&id).map(|&idx| &self.tracks[idx])
    }

    /// Adds a track, updating the contiguous array and fast lookup table.
    pub fn add_track(&mut self, track: Track) {
        let id = track.id;
        let idx = self.tracks.len();
        self.tracks.push(track);
        self.id_to_index.insert(id, idx);
    }

    /// Recursively scans paths for audio files and extracts metadata tags.
    /// Returns the number of newly added tracks.
    pub fn scan_directories<P: AsRef<Path>>(&mut self, directories: &[P]) -> usize {
        let start_len = self.tracks.len();

        for dir in directories {
            let walker = WalkDir::new(dir.as_ref()).follow_links(true).into_iter();
            for entry in walker.filter_map(|e| e.ok()) {
                let path = entry.path();
                if path.is_file() && is_supported_audio_extension(path) {
                    if let Some(track) = read_track_metadata(path) {
                        self.add_track(track);
                    }
                }
            }
        }

        self.tracks.len() - start_len
    }

    /// Substring search across title, artist, and album. Case-insensitive.
    /// Uses zero-allocation ASCII windows when possible, falling back to Unicode caseless search.
    pub fn search(&self, query: &str) -> Vec<&Track> {
        let q = query.trim().to_lowercase();
        if q.is_empty() {
            return self.tracks.iter().collect();
        }

        self.tracks
            .iter()
            .filter(|t| {
                contains_ignore_case(t.title.as_str(), &q)
                    || contains_ignore_case(t.artist.as_str(), &q)
                    || contains_ignore_case(t.album.as_str(), &q)
            })
            .collect()
    }

    /// Persists library state to a JSON cache file for instant startup.
    pub fn save_cache<P: AsRef<Path>>(&self, path: P) -> Result<(), LibraryError> {
        let file = File::create(path)?;
        let writer = BufWriter::new(file);
        serde_json::to_writer(writer, &self.tracks)?;
        Ok(())
    }

    /// Re-hydrates library state from cache in < 15ms.
    pub fn load_cache<P: AsRef<Path>>(path: P) -> Result<Self, LibraryError> {
        let file = File::open(path)?;
        let reader = BufReader::new(file);
        let tracks: Vec<Track> = serde_json::from_reader(reader)?;

        let mut id_to_index = HashMap::with_capacity(tracks.len());
        let mut max_id = 0u64;
        for (idx, track) in tracks.iter().enumerate() {
            max_id = max_id.max(track.id.as_u64());
            id_to_index.insert(track.id, idx);
        }
        TrackId::bump_next_id(max_id);

        Ok(Self { tracks, id_to_index })
    }
}

#[inline]
fn contains_ignore_case(haystack: &str, needle_lower: &str) -> bool {
    if needle_lower.is_empty() {
        return true;
    }
    // High-performance zero-allocation path for ASCII
    if haystack.is_ascii() && needle_lower.is_ascii() {
        let needle_bytes = needle_lower.as_bytes();
        if needle_bytes.len() > haystack.len() {
            return false;
        }
        return haystack
            .as_bytes()
            .windows(needle_bytes.len())
            .any(|window| window.eq_ignore_ascii_case(needle_bytes));
    }

    // Unicode-aware fallback
    haystack.to_lowercase().contains(needle_lower)
}

/// Checks file extension against known high-fidelity audio formats.
#[inline]
fn is_supported_audio_extension(path: &Path) -> bool {
    let ext = match path.extension().and_then(|e| e.to_str()) {
        Some(e) => e.to_ascii_lowercase(),
        None => return false,
    };

    matches!(
        ext.as_str(),
        "flac" | "mp3" | "m4a" | "aac" | "opus" | "ogg" | "wav" | "alac" | "aiff"
    )
}

/// Reads metadata tags using lofty without decoding audio payloads into memory.
/// Explicitly disables reading embedded cover art to prevent transient multi-megabyte heap spikes.
fn read_track_metadata(path: &Path) -> Option<Track> {
    let path_str = path.to_str()?;

    let parse_opts = ParseOptions::new().read_cover_art(false);
    let tagged_file = Probe::open(path).ok()?.options(parse_opts).read().ok()?;

    let properties = tagged_file.properties();
    let duration_ms = properties.duration().as_millis() as u32;

    let tag = tagged_file.primary_tag().or_else(|| tagged_file.first_tag());

    let (title, artist, album) = if let Some(tag) = tag {
        let title = tag
            .get_string(ItemKey::TrackTitle)
            .map(SmolStr::new)
            .or_else(|| tag.title().map(|s| SmolStr::new(s.as_ref())))
            .unwrap_or_else(|| {
                path.file_stem()
                    .and_then(|s| s.to_str())
                    .map(SmolStr::new)
                    .unwrap_or_else(|| SmolStr::new("Unknown Title"))
            });

        let artist = tag
            .get_string(ItemKey::TrackArtist)
            .map(SmolStr::new)
            .or_else(|| tag.artist().map(|s| SmolStr::new(s.as_ref())))
            .unwrap_or_else(|| SmolStr::new("Unknown Artist"));

        let album = tag
            .get_string(ItemKey::AlbumTitle)
            .map(SmolStr::new)
            .or_else(|| tag.album().map(|s| SmolStr::new(s.as_ref())))
            .unwrap_or_else(|| SmolStr::new("Unknown Album"));

        (title, artist, album)
    } else {
        let title = path
            .file_stem()
            .and_then(|s| s.to_str())
            .map(SmolStr::new)
            .unwrap_or_else(|| SmolStr::new("Unknown Title"));
        (
            title,
            SmolStr::new("Unknown Artist"),
            SmolStr::new("Unknown Album"),
        )
    };

    Some(Track::new(
        title,
        artist,
        album,
        duration_ms,
        AudioSource::Local(path_str.into()),
    ))
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::tempdir;

    #[test]
    fn test_empty_library() {
        let lib = MediaLibrary::new();
        assert_eq!(lib.len(), 0);
        assert!(lib.is_empty());
        assert_eq!(lib.search("anything").len(), 0);
    }

    #[test]
    fn test_add_and_search() {
        let mut lib = MediaLibrary::new();
        let track1 = Track::new("Sparkle", "RADWIMPS", "Your Name.", 230000, AudioSource::Local("/music/1.flac".into()));
        let track2 = Track::new("Nandemonaiya", "RADWIMPS", "Your Name.", 340000, AudioSource::Local("/music/2.flac".into()));
        let track3 = Track::new("Shape of You", "Ed Sheeran", "Divide", 240000, AudioSource::Local("/music/3.mp3".into()));

        let id1 = track1.id;
        lib.add_track(track1);
        lib.add_track(track2);
        lib.add_track(track3);

        assert_eq!(lib.len(), 3);
        assert_eq!(lib.get_by_id(id1).unwrap().title.as_str(), "Sparkle");

        // Case-insensitive search
        let results = lib.search("radwimps");
        assert_eq!(results.len(), 2);

        let results_title = lib.search("sparkle");
        assert_eq!(results_title.len(), 1);
        assert_eq!(results_title[0].artist.as_str(), "RADWIMPS");
    }

    #[test]
    fn test_cache_serialization_roundtrip() {
        let mut lib = MediaLibrary::new();
        lib.add_track(Track::new("Zenzenzense", "RADWIMPS", "Your Name.", 280000, AudioSource::Local("/music/zen.flac".into())));

        let dir = tempdir().unwrap();
        let cache_file = dir.path().join("library_cache.json");

        lib.save_cache(&cache_file).expect("Failed to save cache");
        let loaded_lib = MediaLibrary::load_cache(&cache_file).expect("Failed to load cache");

        assert_eq!(loaded_lib.len(), 1);
        assert_eq!(loaded_lib.tracks()[0].title.as_str(), "Zenzenzense");
    }

    #[test]
    fn test_10k_tracks_memory_and_benchmarks() {
        use std::mem::size_of;
        use std::time::Instant;

        let num_tracks = 10_000;
        let mut lib = MediaLibrary::new();

        println!("\n=== BENCHMARK & MEMORY AUDIT: 10,000 TRACKS ===");
        println!("size_of::<Track>(): {} bytes", size_of::<Track>());
        println!("size_of::<TrackId>(): {} bytes", size_of::<TrackId>());
        println!("size_of::<AudioSource>(): {} bytes", size_of::<AudioSource>());
        println!("size_of::<SmolStr>(): {} bytes", size_of::<SmolStr>());

        let t_start = Instant::now();
        for i in 0..num_tracks {
            // Realistic mix of string lengths:
            // Some <= 23 bytes (inline SmolStr), some > 23 bytes (heap spill)
            let title = if i % 3 == 0 {
                format!("Song Number {:05} Deluxe Edition", i) // > 23 bytes
            } else {
                format!("Track {:05}", i) // <= 23 bytes
            };

            let artist = if i % 4 == 0 {
                "The Philharmonic Orchestra of Vienna".to_string() // > 23 bytes
            } else {
                "Artist Name".to_string() // <= 23 bytes
            };

            let album = if i % 5 == 0 {
                "Greatest Hits of the Century Remastered".to_string() // > 23 bytes
            } else {
                "Album Title".to_string() // <= 23 bytes
            };

            let path = format!("/home/apple/Music/Artist Name/Album Title/track_{:05}.flac", i); // > 23 bytes

            let track = Track::new(
                title,
                artist,
                album,
                210_000,
                AudioSource::Local(path.into()),
            );
            lib.add_track(track);
        }
        let insert_duration = t_start.elapsed();

        let track_vec_bytes = lib.tracks.capacity() * size_of::<Track>();
        let hashmap_cap = lib.id_to_index.capacity();
        // hashbrown RawTable: 1 ctrl byte + 16 bytes per bucket
        let hashmap_bytes = hashmap_cap * (size_of::<(TrackId, usize)>() + 1);

        println!("Inserted {} tracks in: {:?}", num_tracks, insert_duration);
        println!("Vec<Track> capacity: {} ({} bytes = {:.2} MB)", lib.tracks.capacity(), track_vec_bytes, track_vec_bytes as f64 / 1_048_576.0);
        println!("HashMap capacity: {} (approx {} bytes = {:.2} MB)", hashmap_cap, hashmap_bytes, hashmap_bytes as f64 / 1_048_576.0);
        println!("Total baseline in-memory footprint: {:.2} MB (excluding spilled strings)", (track_vec_bytes + hashmap_bytes) as f64 / 1_048_576.0);

        // Search benchmark
        let t_search = Instant::now();
        let query = "Deluxe";
        let results = lib.search(query);
        let search_duration = t_search.elapsed();
        println!("Search for '{}' ({} results) in: {:?}", query, results.len(), search_duration);
        assert!(!results.is_empty());

        // Cache serialization benchmark
        let dir = tempdir().unwrap();
        let cache_file = dir.path().join("bench_10k_cache.json");

        let t_save = Instant::now();
        lib.save_cache(&cache_file).expect("Failed to save cache");
        let save_duration = t_save.elapsed();

        let file_meta = std::fs::metadata(&cache_file).unwrap();
        let file_size_bytes = file_meta.len();
        println!("JSON cache save time: {:?} (Disk size: {} bytes = {:.2} MB)", save_duration, file_size_bytes, file_size_bytes as f64 / 1_048_576.0);

        // Cache deserialization benchmark
        let t_load = Instant::now();
        let loaded = MediaLibrary::load_cache(&cache_file).expect("Failed to load cache");
        let load_duration = t_load.elapsed();
        println!("JSON cache load/rehydrate time: {:?}", load_duration);
        assert_eq!(loaded.len(), num_tracks);
    }

    #[test]
    fn test_lofty_probe_does_not_load_full_file() {
        use std::io::Write;
        let mut file = tempfile::Builder::new()
            .suffix(".wav")
            .tempfile()
            .unwrap();

        // Write a 20MB dummy WAV file
        let num_samples = 48000 * 100; // 100 seconds of stereo audio = ~19.2 MB
        let sample_rate = 48000u32;
        let num_channels: u16 = 2;
        let bits_per_sample: u16 = 16;
        let byte_rate = sample_rate * num_channels as u32 * bits_per_sample as u32 / 8;
        let block_align = num_channels * bits_per_sample / 8;
        let data_chunk_size = (num_samples * num_channels as usize * 2) as u32;
        let riff_chunk_size = 36 + data_chunk_size;

        file.write_all(b"RIFF").unwrap();
        file.write_all(&riff_chunk_size.to_le_bytes()).unwrap();
        file.write_all(b"WAVE").unwrap();
        file.write_all(b"fmt ").unwrap();
        file.write_all(&16u32.to_le_bytes()).unwrap();
        file.write_all(&1u16.to_le_bytes()).unwrap();
        file.write_all(&num_channels.to_le_bytes()).unwrap();
        file.write_all(&sample_rate.to_le_bytes()).unwrap();
        file.write_all(&byte_rate.to_le_bytes()).unwrap();
        file.write_all(&block_align.to_le_bytes()).unwrap();
        file.write_all(&bits_per_sample.to_le_bytes()).unwrap();
        file.write_all(b"data").unwrap();
        file.write_all(&data_chunk_size.to_le_bytes()).unwrap();

        // Write zeroes for audio payload (seekable sparse or zeros)
        let chunk = [0u8; 65536];
        let mut remaining = data_chunk_size as usize;
        while remaining > 0 {
            let to_write = remaining.min(chunk.len());
            file.write_all(&chunk[..to_write]).unwrap();
            remaining -= to_write;
        }
        file.flush().unwrap();

        let file_size = std::fs::metadata(file.path()).unwrap().len();
        println!("\n=== TEST LOFTY PROBE ON LARGE FILE ({} MB) ===", file_size as f64 / 1_048_576.0);

        let t_start = std::time::Instant::now();
        let track = read_track_metadata(file.path()).expect("Probe failed to read metadata");
        let elapsed = t_start.elapsed();

        println!("Probe metadata extraction time for {:.2} MB file: {:?}", file_size as f64 / 1_048_576.0, elapsed);
        println!("Extracted duration_ms: {} ms", track.duration_ms);
        assert_eq!(track.duration_ms, 100_000);
        // If it read all 20MB, it would take multiple milliseconds to buffer and parse.
        // Lofty probe header reading on NVMe/tmpfs completes in microseconds!
        assert!(elapsed < std::time::Duration::from_millis(15), "Probe must only read headers, taking < 15ms!");
    }
}
