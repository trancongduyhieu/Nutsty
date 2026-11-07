use rusqlite::Connection;
use serde_json::Value;
use std::collections::{HashMap, HashSet};
use std::path::Path;

#[derive(Debug, Default)]
pub struct SimpDb {
    title_artist_map: HashMap<(String, String), (String, String)>,
    title_map: HashMap<String, (String, String)>,
}

impl SimpDb {
    pub fn load_default() -> Self {
        Self::load_with_candidates(None)
    }

    pub fn load_with_candidates(candidate_titles: Option<&HashSet<String>>) -> Self {
        let home = match dirs::home_dir() {
            Some(h) => h,
            None => return Self::default(),
        };

        let p1 = home.join("Music").join("Nutsty").join("extracted").join("Music Database");
        let p2 = home.join("Music").join("SimpMusic").join("extracted").join("Music Database");

        if p1.exists() {
            Self::load_from_path(&p1, candidate_titles)
        } else if p2.exists() {
            Self::load_from_path(&p2, candidate_titles)
        } else {
            Self::default()
        }
    }

    pub fn load_from_path(db_path: &Path, candidate_titles: Option<&HashSet<String>>) -> Self {
        let conn = match Connection::open_with_flags(
            db_path,
            rusqlite::OpenFlags::SQLITE_OPEN_READ_ONLY | rusqlite::OpenFlags::SQLITE_OPEN_NO_MUTEX,
        ) {
            Ok(c) => c,
            Err(_) => return Self::default(),
        };

        // Minimize SQLite internal buffer and memory-mapping footprint
        let _ = conn.execute_batch("PRAGMA mmap_size = 0; PRAGMA cache_size = -256;");

        let mut stmt = match conn.prepare(
            "SELECT title, artistName, videoId, thumbnails FROM song WHERE videoId IS NOT NULL",
        ) {
            Ok(s) => s,
            Err(_) => return Self::default(),
        };

        let mut title_artist_map = HashMap::new();
        let mut title_map = HashMap::new();

        let rows = stmt.query_map([], |row| {
            let title: Option<String> = row.get(0)?;
            let artist_name: Option<String> = row.get(1)?;
            let video_id: Option<String> = row.get(2)?;
            let thumbnails: Option<String> = row.get(3)?;
            Ok((title, artist_name, video_id, thumbnails))
        });

        if let Ok(iter) = rows {
            for row_res in iter.flatten() {
                let (raw_title, raw_artist, raw_vid, raw_thumb) = row_res;
                let title = match raw_title {
                    Some(t) if !t.trim().is_empty() => t.trim().to_string(),
                    _ => continue,
                };
                let t_clean = title.to_lowercase();
                let c_title = strip_brackets(&t_clean);

                // If candidate filter is provided, skip unneeded tracks
                if let Some(candidates) = candidate_titles {
                    if !candidates.contains(&t_clean)
                        && !candidates.contains(&c_title)
                        && !candidates.iter().any(|c| c.contains(&t_clean) || t_clean.contains(c))
                    {
                        continue;
                    }
                }
                let vid = match raw_vid {
                    Some(v) if !v.trim().is_empty() => v.trim().to_string(),
                    _ => continue,
                };

                let thumb_url = match raw_thumb {
                    Some(t) if !t.trim().is_empty() => {
                        let t_str = t.trim();
                        if t_str.contains("googleusercontent.com") || t_str.contains("ggpht.com") {
                            normalize_google_thumb(t_str)
                        } else {
                            format!("https://i.ytimg.com/vi/{}/hqdefault.jpg", vid)
                        }
                    }
                    _ => format!("https://i.ytimg.com/vi/{}/hqdefault.jpg", vid),
                };

                let info = (thumb_url, vid);
                let t_clean = title.to_lowercase();

                let mut artists = Vec::new();
                if let Some(a_str) = raw_artist {
                    let a_trimmed = a_str.trim();
                    if let Ok(parsed) = serde_json::from_str::<Value>(a_trimmed) {
                        if let Some(arr) = parsed.as_array() {
                            for item in arr {
                                if let Some(s) = item.as_str() {
                                    artists.push(s.trim().to_lowercase());
                                }
                            }
                        } else if let Some(s) = parsed.as_str() {
                            artists.push(s.trim().to_lowercase());
                        }
                    }
                    if artists.is_empty() && !a_trimmed.is_empty() {
                        artists.push(a_trimmed.to_lowercase());
                    }
                }

                for art in artists {
                    title_artist_map.insert((t_clean.clone(), art), info.clone());
                }
                title_map.insert(t_clean, info);
            }
        }

        Self {
            title_artist_map,
            title_map,
        }
    }

    pub fn find_thumbnail(&self, title_str: &str, artist_str: &str) -> Option<(String, String)> {
        let lower_t = title_str.trim().to_lowercase();
        let lower_a = artist_str.trim().to_lowercase();

        // 1. Exact title + artist match
        if let Some(info) = self.title_artist_map.get(&(lower_t.clone(), lower_a.clone())) {
            return Some(info.clone());
        }

        // Split artist by comma, ampersand, slash
        for sub_a in lower_a.split(&[',', '&', '/'][..]) {
            let trimmed_sub = sub_a.trim();
            if !trimmed_sub.is_empty() {
                if let Some(info) = self.title_artist_map.get(&(lower_t.clone(), trimmed_sub.to_string())) {
                    return Some(info.clone());
                }
            }
        }

        // 2. Match by artist + loose title
        for ((m_title, m_art), val) in &self.title_artist_map {
            if (m_art == &lower_a || m_art.contains(&lower_a) || lower_a.contains(m_art))
                && (m_title == &lower_t || m_title.contains(&lower_t) || lower_t.contains(m_title))
            {
                return Some(val.clone());
            }
        }

        // 3. Cleaned title match (without brackets)
        let c_title = strip_brackets(&lower_t);
        if let Some(info) = self.title_map.get(&c_title) {
            return Some(info.clone());
        }

        None
    }
}

fn normalize_google_thumb(url: &str) -> String {
    if let Some(idx) = url.find("=w") {
        format!("{}=w1200-h1200-l90-rj", &url[..idx])
    } else {
        url.to_string()
    }
}

fn strip_brackets(s: &str) -> String {
    let mut out = String::with_capacity(s.len());
    let mut depth = 0;
    for c in s.chars() {
        match c {
            '(' | '[' | '{' => depth += 1,
            ')' | ']' | '}' => {
                if depth > 0 {
                    depth -= 1;
                }
            }
            _ => {
                if depth == 0 {
                    out.push(c);
                }
            }
        }
    }
    out.trim().to_string()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_strip_brackets() {
        assert_eq!(strip_brackets("Song Title (Official Music Video)"), "Song Title");
        assert_eq!(strip_brackets("Track [Remix] {2024}"), "Track");
    }

    #[test]
    fn test_normalize_google_thumb() {
        let raw = "https://yt3.googleusercontent.com/abc=w100-h100-l90";
        assert_eq!(
            normalize_google_thumb(raw),
            "https://yt3.googleusercontent.com/abc=w1200-h1200-l90-rj"
        );
    }
}
