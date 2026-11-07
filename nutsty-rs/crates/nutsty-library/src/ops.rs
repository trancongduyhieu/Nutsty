use crate::db::SimpDb;
use crate::model::{AlbumGroup, BatchDeleteResult, DeleteResult, TrackItem};
use crate::scanner::{get_music_dirs, get_thumbnail_cache_dir, scan_single_file};
use md5::Digest;
use std::collections::HashMap;
use std::fs::File;
use std::io::{BufReader, BufWriter};
use std::path::{Path, PathBuf};

pub fn load_tracks(json_path: &Path) -> Vec<TrackItem> {
    if !json_path.exists() {
        return Vec::new();
    }
    if let Ok(file) = File::open(json_path) {
        let reader = BufReader::new(file);
        if let Ok(tracks) = serde_json::from_reader(reader) {
            return tracks;
        }
    }
    Vec::new()
}

pub fn save_tracks_atomic(json_path: &Path, tracks: &[TrackItem]) -> std::io::Result<()> {
    let tmp_path = json_path.with_extension("json.tmp");
    let file = File::create(&tmp_path)?;
    let writer = BufWriter::new(file);
    serde_json::to_writer_pretty(writer, tracks)?;
    std::fs::rename(tmp_path, json_path)?;
    Ok(())
}

pub fn delete_track(
    json_path: &Path,
    target_path: &str,
    filename: &str,
    title: &str,
) -> DeleteResult {
    let mut deleted_files = Vec::new();
    let mut candidates = Vec::new();

    if !target_path.is_empty() && !target_path.starts_with("ytdl://") {
        candidates.push(PathBuf::from(target_path));
    }

    if !filename.is_empty() {
        let (local_dir, down_dir) = get_music_dirs();
        if let Some(l) = local_dir {
            candidates.push(l.join(filename));
        }
        if let Some(d) = down_dir {
            candidates.push(d.join(filename));
        }
    }

    for cp in candidates {
        if cp.exists() {
            if let Ok(()) = std::fs::remove_file(&cp) {
                deleted_files.push(cp.to_string_lossy().to_string());
            }
            let lrc = cp.with_extension("lrc");
            if lrc.exists() {
                if let Ok(()) = std::fs::remove_file(&lrc) {
                    deleted_files.push(lrc.to_string_lossy().to_string());
                }
            }
        }
    }

    let tracks = load_tracks(json_path);
    let mut new_tracks = Vec::new();

    let target_p_str = target_path.trim();
    let fn_str = filename.trim();
    let title_lower = title.trim().to_lowercase();

    for t in tracks {
        let mut remove = false;
        if !target_p_str.is_empty() && t.path == target_p_str {
            remove = true;
        } else if !fn_str.is_empty() && (t.filename == fn_str || t.path.ends_with(fn_str)) {
            remove = true;
        } else if !title_lower.is_empty() && t.title.to_lowercase() == title_lower {
            remove = true;
        }

        if !remove {
            new_tracks.push(t);
        }
    }

    for (idx, t) in new_tracks.iter_mut().enumerate() {
        t.id = idx + 1;
    }

    let remaining = new_tracks.len();
    let _ = save_tracks_atomic(json_path, &new_tracks);

    DeleteResult {
        success: true,
        deleted_files,
        remaining_tracks: remaining,
        error: None,
    }
}

pub fn batch_delete_tracks(json_path: &Path, paths: &[String]) -> BatchDeleteResult {
    let mut deleted_count = 0;
    let path_set: std::collections::HashSet<&str> = paths
        .iter()
        .map(|s| s.as_str())
        .filter(|s| !s.is_empty() && !s.starts_with("ytdl://"))
        .collect();

    for p_str in &path_set {
        let p = Path::new(p_str);
        if p.exists() {
            if let Ok(()) = std::fs::remove_file(p) {
                deleted_count += 1;
            }
        }
        let lrc = p.with_extension("lrc");
        if lrc.exists() {
            let _ = std::fs::remove_file(lrc);
        }
    }

    let tracks = load_tracks(json_path);
    let mut new_tracks: Vec<TrackItem> = tracks
        .into_iter()
        .filter(|t| !path_set.contains(t.path.as_str()))
        .collect();

    for (idx, t) in new_tracks.iter_mut().enumerate() {
        t.id = idx + 1;
    }

    let remaining = new_tracks.len();
    let _ = save_tracks_atomic(json_path, &new_tracks);

    BatchDeleteResult {
        success: true,
        deleted_count,
        remaining_tracks: remaining,
        error: None,
    }
}

pub fn add_track(
    json_path: &Path,
    audio_path: &str,
    custom_title: &str,
    custom_artist: &str,
    custom_video_id: &str,
    custom_image: &str,
) -> Option<TrackItem> {
    let p = Path::new(audio_path);
    if !p.exists() {
        return None;
    }

    let thumb_dir = get_thumbnail_cache_dir();
    let simp_db = SimpDb::load_default();

    let mut item = scan_single_file(p, "Downloads", &simp_db, &thumb_dir)?;

    if !custom_title.trim().is_empty() {
        item.title = custom_title.trim().to_string();
        item.name = item.title.clone();
    }
    if !custom_artist.trim().is_empty() {
        item.artist = custom_artist.trim().to_string();
    }
    if !custom_video_id.trim().is_empty() {
        item.video_id = custom_video_id.trim().to_string();
    }
    if !custom_image.trim().is_empty() {
        item.image = custom_image.trim().to_string();
    }

    let mut tracks = load_tracks(json_path);
    let mut updated = false;

    for t in tracks.iter_mut() {
        if t.path == item.path || t.filename == item.filename {
            t.title = item.title.clone();
            t.name = item.title.clone();
            t.artist = item.artist.clone();
            t.duration = item.duration.clone();
            t.duration_ms = item.duration_ms;
            t.duration_sec = item.duration_sec;
            t.mtime = item.mtime;
            if !item.image.is_empty() {
                t.image = item.image.clone();
            }
            if !item.video_id.is_empty() {
                t.video_id = item.video_id.clone();
            }
            item.id = t.id;
            updated = true;
            break;
        }
    }

    if !updated {
        item.id = 1;
        tracks.insert(0, item.clone());
    }

    for (idx, t) in tracks.iter_mut().enumerate() {
        t.id = idx + 1;
    }

    let _ = save_tracks_atomic(json_path, &tracks);
    Some(item)
}

pub fn get_grouped_albums(json_path: &Path) -> Vec<AlbumGroup> {
    let mut tracks = load_tracks(json_path);
    if tracks.is_empty() {
        tracks = crate::scanner::scan_all_tracks();
        let _ = save_tracks_atomic(json_path, &tracks);
    }

    let mut albums_map: HashMap<String, AlbumGroup> = HashMap::new();

    for t in tracks {
        let alb_name = t.album.trim().to_string();
        let art_name = if t.artist.trim().is_empty() {
            "Downloaded".to_string()
        } else {
            t.artist.trim().to_string()
        };

        let key = if alb_name.is_empty() {
            format!("{} - Singles", art_name)
        } else {
            alb_name
        };

        let entry = albums_map.entry(key.clone()).or_insert_with(|| {
            let mut hasher = md5::Md5::new();
            hasher.update(key.as_bytes());
            let hash_bytes = hasher.finalize();
            let hash_hex = hex::encode(hash_bytes);
            let alb_id = format!("local_alb_{}", &hash_hex[..12]);

            AlbumGroup {
                id: alb_id.clone(),
                browse_id: alb_id,
                item_type: "album".to_string(),
                is_local: true,
                title: key.clone(),
                name: key.clone(),
                artist: art_name.clone(),
                year: t.year.clone(),
                image: t.image.clone(),
                track_count: 0,
                duration: String::new(),
                tracks: Vec::new(),
            }
        });

        if entry.image.is_empty() && !t.image.is_empty() {
            entry.image = t.image.clone();
        }
        entry.tracks.push(t);
    }

    let mut albums: Vec<AlbumGroup> = albums_map
        .into_values()
        .map(|mut alb| {
            alb.track_count = alb.tracks.len();
            let mut dur_secs: u64 = 0;
            for trk in &alb.tracks {
                if trk.duration_ms > 0 {
                    dur_secs += (trk.duration_ms as u64) / 1000;
                } else {
                    let parts: Vec<&str> = trk.duration.split(':').collect();
                    if parts.len() == 2 {
                        if let (Ok(m), Ok(s)) = (parts[0].parse::<u64>(), parts[1].parse::<u64>()) {
                            dur_secs += m * 60 + s;
                        }
                    }
                }
            }

            if dur_secs > 0 {
                let m = dur_secs / 60;
                let s = dur_secs % 60;
                alb.duration = if m > 0 {
                    format!("{} mins, {} secs", m, s)
                } else {
                    format!("{} secs", s)
                };
            } else {
                alb.duration = format!("{} songs", alb.track_count);
            }
            alb
        })
        .collect();

    albums.sort_by(|a, b| a.title.to_lowercase().cmp(&b.title.to_lowercase()));
    albums
}
