use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TrackItem {
    pub id: usize,
    pub title: String,
    pub name: String,
    pub artist: String,
    #[serde(default)]
    pub album: String,
    #[serde(default)]
    pub year: String,
    pub duration: String,
    #[serde(default)]
    pub duration_ms: u32,
    #[serde(default)]
    pub duration_sec: f64,
    #[serde(default)]
    pub bitrate: u32,
    #[serde(default)]
    pub codec: String,
    pub source: String,
    pub path: String,
    pub filename: String,
    #[serde(default)]
    pub image: String,
    #[serde(default, rename = "videoId")]
    pub video_id: String,
    #[serde(default)]
    pub mtime: u64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AlbumGroup {
    pub id: String,
    #[serde(rename = "browseId")]
    pub browse_id: String,
    #[serde(rename = "type")]
    pub item_type: String,
    #[serde(rename = "isLocal")]
    pub is_local: bool,
    pub title: String,
    pub name: String,
    pub artist: String,
    #[serde(default)]
    pub year: String,
    #[serde(default)]
    pub image: String,
    #[serde(rename = "trackCount")]
    pub track_count: usize,
    pub duration: String,
    pub tracks: Vec<TrackItem>,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct DeleteResult {
    pub success: bool,
    #[serde(skip_serializing_if = "Vec::is_empty", default)]
    pub deleted_files: Vec<String>,
    #[serde(default)]
    pub remaining_tracks: usize,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub error: Option<String>,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct BatchDeleteResult {
    pub success: bool,
    #[serde(default)]
    pub deleted_count: usize,
    #[serde(default)]
    pub remaining_tracks: usize,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub error: Option<String>,
}
