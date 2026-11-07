//! High-performance native Rust implementation of Chromatic Salience Palette Extractor.
//! Replaces the Python / Pillow / NumPy pipeline with sub-millisecond OKLAB/OKLCH clustering.

use image::imageops::FilterType;
use serde::{Deserialize, Serialize};
use std::collections::{HashMap, HashSet};
use std::fs;
use std::path::PathBuf;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SongPaletteResult {
    #[serde(rename = "highlightColor", default)]
    pub highlight_color: String,
    #[serde(rename = "accentColor", default)]
    pub accent_color: String,
    #[serde(rename = "backgroundTint", default)]
    pub background_tint: String,
    #[serde(default)]
    pub theme: String,
    #[serde(rename = "baseTextColor", default = "default_base_text_color")]
    pub base_text_color: String,
}

fn default_base_text_color() -> String {
    "#f8fafc".to_string()
}

impl Default for SongPaletteResult {
    fn default() -> Self {
        Self {
            highlight_color: "#deb06c".to_string(),
            accent_color: "#deb06c".to_string(),
            background_tint: "#161514".to_string(),
            theme: "warm_classic".to_string(),
            base_text_color: "#f8fafc".to_string(),
        }
    }
}

#[inline(always)]
fn srgb_to_linear(c: f32) -> f32 {
    if c <= 0.04045 {
        c / 12.92
    } else {
        ((c + 0.055) / 1.055).powf(2.4)
    }
}

#[inline(always)]
fn linear_to_srgb(c: f32) -> f32 {
    let c = c.clamp(0.0, 1.0);
    if c <= 0.0031308 {
        12.92 * c
    } else {
        1.055 * c.powf(1.0 / 2.4) - 0.055
    }
}

/// Convert sRGB [0..255] to OKLAB (L, a, b, C, h)
#[inline]
pub fn rgb_to_oklab(r: u8, g: u8, b: u8) -> (f32, f32, f32, f32, f32) {
    let lr = srgb_to_linear(r as f32 / 255.0);
    let lg = srgb_to_linear(g as f32 / 255.0);
    let lb = srgb_to_linear(b as f32 / 255.0);

    let l = (0.4122214708 * lr + 0.5363325363 * lg + 0.0514459929 * lb).cbrt();
    let m = (0.2119034982 * lr + 0.6806995451 * lg + 0.1073969566 * lb).cbrt();
    let s = (0.0883024619 * lr + 0.2817188376 * lg + 0.6299787005 * lb).cbrt();

    let big_l = 0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s;
    let a = 1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s;
    let b_val = 0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s;

    let c = (a * a + b_val * b_val).sqrt();
    let h = b_val.atan2(a);
    (big_l, a, b_val, c, h)
}

/// Convert OKLCH (L, C, h) to sRGB Hex string `#rrggbb`
pub fn oklch_to_hex(big_l: f32, c: f32, h: f32) -> String {
    let a = c * h.cos();
    let b_val = c * h.sin();

    let l = (big_l + 0.3963377774 * a + 0.2158037573 * b_val).powi(3);
    let m = (big_l - 0.1055613458 * a - 0.0638541728 * b_val).powi(3);
    let s = (big_l - 0.0894841775 * a - 1.2914855480 * b_val).powi(3);

    let lr = 4.0767434721 * l - 3.3077115913 * m + 0.2309699292 * s;
    let lg = -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s;
    let lb = -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s;

    let r = (linear_to_srgb(lr) * 255.0).round().clamp(0.0, 255.0) as u8;
    let g = (linear_to_srgb(lg) * 255.0).round().clamp(0.0, 255.0) as u8;
    let b = (linear_to_srgb(lb) * 255.0).round().clamp(0.0, 255.0) as u8;

    format!("#{r:02x}{g:02x}{b:02x}")
}

/// Classify hue angle in degrees to Nutsty theme name
pub fn get_theme_name_from_deg(deg: f32) -> &'static str {
    let norm_deg = (deg % 360.0 + 360.0) % 360.0;
    if norm_deg >= 330.0 || norm_deg < 38.0 {
        "crimson"
    } else if (38.0..75.0).contains(&norm_deg) {
        "gold"
    } else if (75.0..170.0).contains(&norm_deg) {
        "emerald"
    } else if (170.0..260.0).contains(&norm_deg) {
        "sapphire"
    } else {
        "amethyst"
    }
}

/// K-Means clustering in OKLAB space with deterministic farthest-point seeding
fn kmeans_oklab(points: &[(f32, f32, f32)], k: usize, iters: usize) -> Vec<(f32, f32, f32, usize)> {
    let n = points.len();
    if n == 0 {
        return Vec::new();
    }
    if n <= k {
        return points.iter().map(|&(l, a, b)| (l, a, b, 1)).collect();
    }

    // 1. Deterministic farthest-point seeding
    let mut centroids = Vec::with_capacity(k);
    centroids.push(points[0]);

    while centroids.len() < k {
        let mut best_pt = points[0];
        let mut max_d = -1.0f32;

        for p in points.iter().step_by(6) {
            let mut min_d = f32::MAX;
            for c in &centroids {
                let d = (p.0 - c.0).powi(2) + (p.1 - c.1).powi(2) + (p.2 - c.2).powi(2);
                if d < min_d {
                    min_d = d;
                }
            }
            if min_d > max_d {
                max_d = min_d;
                best_pt = *p;
            }
        }
        centroids.push(best_pt);
    }

    // 2. K-means iterations
    let mut cluster_sums = vec![(0.0f32, 0.0f32, 0.0f32, 0usize); k];

    for _ in 0..iters {
        for sum in &mut cluster_sums {
            *sum = (0.0, 0.0, 0.0, 0);
        }

        for p in points {
            let mut best_idx = 0;
            let mut best_dist = f32::MAX;
            for (i, c) in centroids.iter().enumerate() {
                let d = (p.0 - c.0).powi(2) + (p.1 - c.1).powi(2) + (p.2 - c.2).powi(2);
                if d < best_dist {
                    best_dist = d;
                    best_idx = i;
                }
            }
            let entry = &mut cluster_sums[best_idx];
            entry.0 += p.0;
            entry.1 += p.1;
            entry.2 += p.2;
            entry.3 += 1;
        }

        for i in 0..k {
            let count = cluster_sums[i].3;
            if count > 0 {
                let inv = 1.0 / count as f32;
                centroids[i] = (
                    cluster_sums[i].0 * inv,
                    cluster_sums[i].1 * inv,
                    cluster_sums[i].2 * inv,
                );
            }
        }
    }

    centroids
        .into_iter()
        .zip(cluster_sums.into_iter())
        .map(|(c, s)| (c.0, c.1, c.2, s.3))
        .collect()
}

/// Extract palette parameters from raw RGB pixel buffer
pub fn extract_palette_from_rgb_buffer(pixels: &[(u8, u8, u8)]) -> SongPaletteResult {
    if pixels.is_empty() {
        return SongPaletteResult::default();
    }

    let ok_all: Vec<(f32, f32, f32, f32, f32)> = pixels
        .iter()
        .map(|&(r, g, b)| rgb_to_oklab(r, g, b))
        .collect();

    // Pre-filter pixels with noticeable artistic color (Chroma >= 0.028)
    let chroma_pixels: Vec<(f32, f32, f32)> = ok_all
        .iter()
        .filter(|p| p.3 >= 0.028)
        .map(|p| (p.0, p.1, p.2))
        .collect();

    let chroma_ratio = chroma_pixels.len() as f32 / ok_all.len() as f32;

    if chroma_ratio >= 0.05 {
        // Cluster chromatic pixels into 4 distinct artistic hue candidates
        let clusters = kmeans_oklab(&chroma_pixels, 4, 8);

        // Select best cluster by Visual Salience: count^0.35 * C
        let mut best = clusters[0];
        let mut best_score = -1.0f32;

        for c in &clusters {
            let c_chroma = (c.1 * c.1 + c.2 * c.2).sqrt();
            let score = (c.3 as f32).powf(0.35) * c_chroma;
            if score > best_score {
                best_score = score;
                best = *c;
            }
        }

        let best_c = (best.1 * best.1 + best.2 * best.2).sqrt();
        let best_h = best.2.atan2(best.1);
        let best_deg = (best_h.to_degrees() % 360.0 + 360.0) % 360.0;
        let top_theme = get_theme_name_from_deg(best_deg).to_string();

        // 1. Highlight Color: Luminous Jewel Tone (L=0.82, C in [0.08, 0.12])
        let norm_c_hl = (best_c * 1.4).clamp(0.08, 0.12);
        let highlight_color = oklch_to_hex(0.82, norm_c_hl, best_h);

        // 2. Accent Color: UI Interactive Tone (L=0.68, C in [0.10, 0.16])
        let norm_c_acc = (best_c * 1.3).clamp(0.10, 0.16);
        let accent_color = oklch_to_hex(0.68, norm_c_acc, best_h);

        // 3. Background Tint: Dark Organic Glass Tint (L=0.16, C in [0.02, 0.04])
        let norm_c_bg = (best_c * 0.6).clamp(0.02, 0.04);
        let background_tint = oklch_to_hex(0.16, norm_c_bg, best_h);

        SongPaletteResult {
            highlight_color,
            accent_color,
            background_tint,
            theme: top_theme,
            base_text_color: "#f8fafc".to_string(),
        }
    } else {
        // Pure monochrome/pencil sketch without color:
        // Fallback to timeless, luxurious Vintage Champagne Gold
        SongPaletteResult {
            highlight_color: "#deb06c".to_string(),
            accent_color: "#deb06c".to_string(),
            background_tint: "#161514".to_string(),
            theme: "warm_classic".to_string(),
            base_text_color: "#f8fafc".to_string(),
        }
    }
}

/// Resolve platform-appropriate cache file for song palettes
fn get_cache_file_path() -> PathBuf {
    #[cfg(windows)]
    {
        if let Ok(appdata) = std::env::var("LOCALAPPDATA") {
            let p = PathBuf::from(appdata).join("Nutsty").join("cache");
            let _ = fs::create_dir_all(&p);
            return p.join("song_palettes.json");
        }
    }

    if let Ok(home) = std::env::var("HOME") {
        let p = PathBuf::from(home).join(".cache").join("nutsty");
        let _ = fs::create_dir_all(&p);
        return p.join("song_palettes.json");
    }

    std::env::temp_dir().join("nutsty_song_palettes.json")
}

/// Read from JSON disk cache
fn read_cache(key: &str) -> Option<SongPaletteResult> {
    let path = get_cache_file_path();
    let content = fs::read_to_string(path).ok()?;
    let map: HashMap<String, SongPaletteResult> = serde_json::from_str(&content).ok()?;
    map.get(key).cloned()
}

/// Write to bounded JSON disk cache
fn write_cache(key: &str, result: &SongPaletteResult) {
    let path = get_cache_file_path();
    let mut map: HashMap<String, SongPaletteResult> = if let Ok(content) = fs::read_to_string(&path) {
        serde_json::from_str(&content).unwrap_or_default()
    } else {
        HashMap::new()
    };

    map.insert(key.to_string(), result.clone());

    if map.len() > 500 {
        let keys_to_keep: HashSet<String> = map.keys().take(400).cloned().collect();
        map.retain(|k, _| keys_to_keep.contains(k));
    }

    if let Ok(serialized) = serde_json::to_string_pretty(&map) {
        let _ = fs::write(path, serialized);
    }
}

/// Clean local file path from file:// prefixes
fn normalize_file_path(src: &str) -> PathBuf {
    let s = src.trim();
    if let Some(stripped) = s.strip_prefix("file:///") {
        #[cfg(windows)]
        {
            if stripped.len() > 2 && stripped.as_bytes()[1] == b':' {
                return PathBuf::from(stripped);
            }
        }
        return PathBuf::from(format!("/{stripped}"));
    } else if let Some(stripped) = s.strip_prefix("file://") {
        return PathBuf::from(stripped);
    }

    if let Some(stripped) = s.strip_prefix("~/") {
        if let Ok(home) = std::env::var("HOME") {
            return PathBuf::from(home).join(stripped);
        }
    }

    PathBuf::from(s)
}

/// Extract palette from image source (file path or remote URL)
pub fn extract_song_palette(src: &str) -> SongPaletteResult {
    let clean_src = src.trim();
    if clean_src.is_empty() {
        return SongPaletteResult::default();
    }

    // 1. Check cache first
    if let Some(cached) = read_cache(clean_src) {
        return cached;
    }

    // 2. Load image bytes
    let img_res = if clean_src.starts_with("http://") || clean_src.starts_with("https://") {
        // Download via curl for zero-dependency HTTP support
        let output = std::process::Command::new("curl")
            .args(["-s", "-L", "--max-time", "5", clean_src])
            .output();

        match output {
            Ok(out) if out.status.success() && !out.stdout.is_empty() => {
                image::load_from_memory(&out.stdout)
            }
            _ => return SongPaletteResult::default(),
        }
    } else {
        let path = normalize_file_path(clean_src);
        if !path.exists() {
            return SongPaletteResult::default();
        }
        match image::ImageReader::open(&path) {
            Ok(reader) => match reader.with_guessed_format() {
                Ok(guessed) => guessed.decode(),
                Err(_) => image::open(&path),
            },
            Err(_) => return SongPaletteResult::default(),
        }
    };

    let img = match img_res {
        Ok(i) => i,
        Err(_) => return SongPaletteResult::default(),
    };

    // 3. Fast downsample to 96x96 (9,216 pixels) using Triangle/Bilinear sampling for optimal speed + quality
    let thumb = img.resize_exact(96, 96, FilterType::Triangle);
    let rgb = thumb.to_rgb8();
    let mut pixels = Vec::with_capacity(96 * 96);

    for p in rgb.pixels() {
        pixels.push((p[0], p[1], p[2]));
    }

    // 4. Extract palette
    let result = extract_palette_from_rgb_buffer(&pixels);

    // 5. Save to disk cache
    write_cache(clean_src, &result);

    result
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_extract_thumbnail() {
        let path = "/home/apple/.cache/nutsty/thumbnails/a01318451eeaaaf36900165e55046ba0.jpg";
        let res = extract_song_palette(path);
        println!("Extracted palette: {:?}", res);
        assert!(!res.highlight_color.is_empty());
        assert_eq!(res.theme, "crimson");
    }
}
