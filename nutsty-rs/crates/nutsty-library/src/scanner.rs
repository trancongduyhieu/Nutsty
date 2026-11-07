use crate::db::SimpDb;
use crate::model::TrackItem;
use lofty::config::ParseOptions;
use lofty::file::{AudioFile, TaggedFileExt};
use lofty::probe::Probe;
use lofty::tag::{Accessor, ItemKey};
use md5::Digest;
use rayon::prelude::*;
use std::fs::File;
use std::io::{BufWriter, Write};
use std::path::{Path, PathBuf};
use walkdir::WalkDir;

pub fn get_thumbnail_cache_dir() -> PathBuf {
    if let Some(home) = dirs::home_dir() {
        home.join(".cache").join("nutsty").join("thumbnails")
    } else {
        PathBuf::from("/tmp/nutsty/thumbnails")
    }
}

pub fn get_music_dirs() -> (Option<PathBuf>, Option<PathBuf>) {
    let home = match dirs::home_dir() {
        Some(h) => h,
        None => return (None, None),
    };

    let p_nutsty = home.join("Music").join("Nutsty").join("Tracks");
    let p_simp = home.join("Music").join("SimpMusic").join("Tracks");
    let local_dir = if p_nutsty.exists() {
        Some(p_nutsty)
    } else if p_simp.exists() {
        Some(p_simp)
    } else {
        None
    };

    let p_down = home.join("Music").join("Downloads_Phone");
    let down_dir = if p_down.exists() { Some(p_down) } else { None };

    (local_dir, down_dir)
}

pub fn is_audio_file(path: &Path) -> bool {
    let ext = match path.extension().and_then(|e| e.to_str()) {
        Some(e) => e.to_ascii_lowercase(),
        None => return false,
    };
    matches!(
        ext.as_str(),
        "opus" | "m4a" | "mp3" | "webm" | "flac" | "aac" | "ogg" | "wav" | "alac"
    )
}

pub fn extract_thumbnail(
    path: &Path,
    title: &str,
    artist: &str,
    db: &SimpDb,
    thumb_dir: &Path,
) -> (String, String) {
    let path_str = path.to_string_lossy();

    // 1. Check if a sibling image exists (<stem>.jpg, <stem>.png, etc.)
    let parent = path.parent().unwrap_or_else(|| Path::new("."));
    if let Some(stem) = path.file_stem().and_then(|s| s.to_str()) {
        for ext in &[".jpg", ".jpeg", ".png", ".webp"] {
            let sib = parent.join(format!("{}{}", stem, ext));
            if let Ok(meta) = std::fs::metadata(&sib) {
                if meta.len() > 1000 {
                    return (sib.to_string_lossy().to_string(), String::new());
                }
            }
        }
    }

    // 2. Compute deterministic MD5 hash of path
    let mut hasher = md5::Md5::new();
    hasher.update(path_str.as_bytes());
    let hash_bytes = hasher.finalize();
    let f_hash = hex::encode(hash_bytes);
    let out_thumb = thumb_dir.join(format!("{}.jpg", f_hash));

    // If cached thumbnail already exists and > 1000 bytes, use it
    if let Ok(meta) = std::fs::metadata(&out_thumb) {
        if meta.len() > 1000 {
            let (_, vid) = db.find_thumbnail(title, artist).unwrap_or_default();
            return (out_thumb.to_string_lossy().to_string(), vid);
        }
    }

    // 3. Extract embedded artwork from audio file using lofty
    let parse_opts = ParseOptions::new().read_cover_art(true);
    if let Ok(tagged_file) = Probe::open(path).and_then(|p| p.options(parse_opts).read()) {
        if let Some(tag) = tagged_file.primary_tag().or_else(|| tagged_file.first_tag()) {
            if let Some(pic) = tag.pictures().first() {
                let data = pic.data();
                if data.len() > 1000 {
                    let _ = std::fs::create_dir_all(thumb_dir);
                    if let Ok(mut f) = File::create(&out_thumb) {
                        let _ = f.write_all(data);
                        let (_, vid) = db.find_thumbnail(title, artist).unwrap_or_default();
                        return (out_thumb.to_string_lossy().to_string(), vid);
                    }
                }
            }
        }
    }

    // 4. Fallback to SimpMusic SQLite Database
    if let Some((thumb, vid)) = db.find_thumbnail(title, artist) {
        return (thumb, vid);
    }

    (String::new(), String::new())
}

pub fn scan_single_file(
    path: &Path,
    source: &str,
    db: &SimpDb,
    thumb_dir: &Path,
) -> Option<TrackItem> {
    if !path.is_file() || !is_audio_file(path) {
        return None;
    }

    let filename = path.file_name()?.to_string_lossy().to_string();
    let stem = path.file_stem()?.to_string_lossy().to_string();

    let ext = path
        .extension()
        .and_then(|e| e.to_str())
        .unwrap_or("")
        .to_ascii_lowercase();

    let codec = match ext.as_str() {
        "mp3" => "mp3",
        "m4a" | "aac" => "aac",
        "opus" => "opus",
        "flac" => "flac",
        "webm" => "opus",
        "ogg" => "vorbis",
        "wav" => "wav",
        _ => &ext,
    }
    .to_string();

    // Fast probe for metadata and properties
    let parse_opts = ParseOptions::new().read_cover_art(false);
    let tagged_file = Probe::open(path).ok()?.options(parse_opts).read().ok();

    let mut dur_str = "--:--".to_string();
    let mut duration_ms = 0u32;
    let mut duration_sec = 0.0f64;
    let mut bitrate = 0u32;

    let mut tag_title = String::new();
    let mut tag_artist = String::new();
    let mut tag_album = String::new();
    let mut tag_year = String::new();

    if let Some(ref tagged) = tagged_file {
        let props = tagged.properties();
        let dur = props.duration();
        let sec = dur.as_secs();
        let m = sec / 60;
        let s = sec % 60;
        dur_str = format!("{}:{:02}", m, s);
        duration_ms = dur.as_millis() as u32;
        duration_sec = dur.as_secs_f64();
        bitrate = props.audio_bitrate().unwrap_or(0);

        if let Some(tag) = tagged.primary_tag().or_else(|| tagged.first_tag()) {
            if let Some(t) = tag.get_string(ItemKey::TrackTitle) {
                tag_title = t.trim().to_string();
            } else if let Some(t) = tag.title() {
                tag_title = t.trim().to_string();
            }

            if let Some(a) = tag.get_string(ItemKey::TrackArtist) {
                tag_artist = a.trim().to_string();
            } else if let Some(a) = tag.artist() {
                tag_artist = a.trim().to_string();
            }

            if let Some(alb) = tag.get_string(ItemKey::AlbumTitle) {
                tag_album = alb.trim().to_string();
            } else if let Some(alb) = tag.album() {
                tag_album = alb.trim().to_string();
            }
            if let Some(yr) = tag.get_string(ItemKey::Year).or_else(|| tag.get_string(ItemKey::OriginalReleaseDate)) {
                let clean_yr: String = yr.chars().filter(|c| c.is_ascii_digit()).take(4).collect();
                tag_year = clean_yr;
            }
        }
    }

    // Determine final title & artist based on source
    let (final_title, final_artist) = if source == "Downloads" {
        let mut t = tag_title;
        let mut a = tag_artist;
        if t.is_empty() || a.is_empty() {
            if let Some((f_artist, f_title)) = stem.split_once(" - ") {
                if a.is_empty() {
                    a = f_artist.trim().to_string();
                }
                if t.is_empty() {
                    t = f_title.trim().to_string();
                }
            } else {
                if t.is_empty() {
                    t = stem.clone();
                }
                if a.is_empty() {
                    a = "Downloaded".to_string();
                }
            }
        }
        (t, a)
    } else {
        // Source Nutsty / SimpMusic
        if let Some((f_artist, f_title)) = stem.split_once(" - ") {
            (f_title.trim().to_string(), f_artist.trim().to_string())
        } else {
            let t = if !tag_title.is_empty() { tag_title } else { stem.clone() };
            let a = if !tag_artist.is_empty() { tag_artist } else { "Unknown Artist".to_string() };
            (t, a)
        }
    };

    // Thumbnail & VideoId resolution
    let (image, video_id) = extract_thumbnail(path, &final_title, &final_artist, db, thumb_dir);

    // Modified timestamp
    let mtime = std::fs::metadata(path)
        .and_then(|m| m.modified())
        .ok()
        .and_then(|t| t.duration_since(std::time::UNIX_EPOCH).ok())
        .map(|d| d.as_secs())
        .unwrap_or(0);

    Some(TrackItem {
        id: 0,
        title: final_title.clone(),
        name: final_title,
        artist: final_artist,
        album: tag_album,
        year: tag_year,
        duration: dur_str,
        duration_ms,
        duration_sec,
        bitrate,
        codec,
        source: source.to_string(),
        path: path.to_string_lossy().to_string(),
        filename,
        image,
        video_id,
        mtime,
    })
}

pub fn scan_all_tracks() -> Vec<TrackItem> {
    let thumb_dir = get_thumbnail_cache_dir();
    let _ = std::fs::create_dir_all(&thumb_dir);

    let (local_dir, down_dir) = get_music_dirs();
    let mut scan_entries = Vec::new();

    if let Some(ref l_dir) = local_dir {
        for entry in WalkDir::new(l_dir).follow_links(false).into_iter().filter_map(|e| e.ok()) {
            let p = entry.path();
            if p.is_file() && is_audio_file(p) {
                scan_entries.push((p.to_path_buf(), "Nutsty"));
            }
        }
    }

    if let Some(ref d_dir) = down_dir {
        for entry in WalkDir::new(d_dir).follow_links(false).into_iter().filter_map(|e| e.ok()) {
            let p = entry.path();
            if p.is_file() && is_audio_file(p) {
                scan_entries.push((p.to_path_buf(), "Downloads"));
            }
        }
    }

    // Collect candidate titles to filter SQLite load and save ~15MB of RAM
    let mut candidate_titles = std::collections::HashSet::with_capacity(scan_entries.len() * 2);
    for (p, _) in &scan_entries {
        if let Some(stem) = p.file_stem().and_then(|s| s.to_str()) {
            if let Some((_, f_title)) = stem.split_once(" - ") {
                candidate_titles.insert(f_title.trim().to_lowercase());
            }
            candidate_titles.insert(stem.trim().to_lowercase());
        }
    }

    let simp_db = SimpDb::load_with_candidates(Some(&candidate_titles));

    // Parallel scan with Rayon
    let mut tracks: Vec<TrackItem> = scan_entries
        .into_par_iter()
        .filter_map(|(p, source)| scan_single_file(&p, source, &simp_db, &thumb_dir))
        .collect();

    // Sort to match deterministic order (Nutsty tracks first sorted by filename, then Downloads)
    tracks.sort_by(|a, b| {
        let src_cmp = a.source.cmp(&b.source);
        if src_cmp == std::cmp::Ordering::Equal {
            a.filename.cmp(&b.filename)
        } else if a.source == "Nutsty" {
            std::cmp::Ordering::Less
        } else {
            std::cmp::Ordering::Greater
        }
    });

    for (idx, track) in tracks.iter_mut().enumerate() {
        track.id = idx + 1;
    }

    tracks
}

pub fn save_library_json(output_path: &Path, tracks: &[TrackItem]) -> std::io::Result<()> {
    let tmp_path = output_path.with_extension("json.tmp");
    let file = File::create(&tmp_path)?;
    let writer = BufWriter::new(file);
    serde_json::to_writer_pretty(writer, tracks)?;
    std::fs::rename(tmp_path, output_path)?;
    Ok(())
}
