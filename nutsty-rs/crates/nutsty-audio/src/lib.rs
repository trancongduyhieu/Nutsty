//! High-performance, low-latency audio engine for Nutsty.
//! Leverages Symphonia for pure-Rust multi-codec decoding and cpal for hardware output.

pub mod decoder;
pub mod engine;
pub mod player;

pub use decoder::{AudioDecoder, DecoderError};
pub use engine::{AudioEngine, AudioError};
pub use player::CpalAudioPlayer;
