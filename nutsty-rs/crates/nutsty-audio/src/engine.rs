use nutsty_core::{PlaybackProgress, PlaybackStatus, Volume};
use thiserror::Error;

#[derive(Debug, Error)]
pub enum AudioError {
    #[error("Audio device unavailable: {0}")]
    DeviceError(String),
    #[error("Codec or container decode failure: {0}")]
    DecodeError(String),
    #[error("I/O error: {0}")]
    IoError(#[from] std::io::Error),
}

/// Abstract audio playback engine interface.
pub trait AudioEngine: Send + Sync {
    fn play(&self) -> Result<(), AudioError>;
    fn pause(&self) -> Result<(), AudioError>;
    fn stop(&self) -> Result<(), AudioError>;
    fn seek(&self, position_ms: u32) -> Result<(), AudioError>;
    fn set_volume(&self, volume: Volume);
    fn status(&self) -> PlaybackStatus;
    fn progress(&self) -> PlaybackProgress;
}
