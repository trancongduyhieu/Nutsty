//! Symphonia-based audio file decoder.
//! Decodes local media files into interleaved f32 PCM samples with linear sample-rate conversion.

use nutsty_core::AudioSource;
use std::fs::File;
use std::path::Path;
use symphonia::core::audio::SampleBuffer;
use symphonia::core::codecs::{Decoder, DecoderOptions};
use symphonia::core::errors::Error as SymphoniaError;
use symphonia::core::formats::{FormatOptions, FormatReader, SeekMode, SeekTo};
use symphonia::core::io::MediaSourceStream;
use symphonia::core::meta::MetadataOptions;
use symphonia::core::probe::Hint;
use symphonia::core::units::Time;
use thiserror::Error;

#[derive(Debug, Error)]
pub enum DecoderError {
    #[error("Failed to open audio file: {0}")]
    Io(#[from] std::io::Error),
    #[error("Unsupported audio container or codec: {0}")]
    Unsupported(String),
    #[error("Decoding error: {0}")]
    Decode(String),
    #[error("Track stream not found")]
    NoTrack,
}

pub struct AudioDecoder {
    format: Box<dyn FormatReader>,
    decoder: Box<dyn Decoder>,
    track_id: u32,
    sample_rate: u32,
    channels: usize,
    duration_ms: u32,
    sample_buf: Option<SampleBuffer<f32>>,
    current_packet_samples: Vec<f32>,
    current_sample_idx: usize,
}

impl AudioDecoder {
    /// Opens an audio file from an AudioSource and prepares decoding.
    pub fn open(source: &AudioSource) -> Result<Self, DecoderError> {
        let path_str = match source {
            AudioSource::Local(p) => p.as_str(),
            AudioSource::Stream(u) => {
                // For streams, pass to file path if local, or error if remote stream needs network source
                u.as_str()
            }
        };

        let file = File::open(Path::new(path_str))?;
        let mss = MediaSourceStream::new(Box::new(file), Default::default());

        let mut hint = Hint::new();
        if let Some(ext) = Path::new(path_str).extension().and_then(|e| e.to_str()) {
            hint.with_extension(ext);
        }

        let meta_opts: MetadataOptions = Default::default();
        let fmt_opts: FormatOptions = Default::default();

        let probed = symphonia::default::get_probe()
            .format(&hint, mss, &fmt_opts, &meta_opts)
            .map_err(|e| DecoderError::Unsupported(format!("Probe failed: {e}")))?;

        let format = probed.format;

        // Find default audio track
        let track = format
            .tracks()
            .iter()
            .find(|t| t.codec_params.codec != symphonia::core::codecs::CODEC_TYPE_NULL)
            .ok_or(DecoderError::NoTrack)?;

        let track_id = track.id;
        let sample_rate = track.codec_params.sample_rate.unwrap_or(44100);
        let channels = track.codec_params.channels.map(|c| c.count()).unwrap_or(2);

        let duration_ms = if let Some(n_frames) = track.codec_params.n_frames {
            ((n_frames as f64 / sample_rate as f64) * 1000.0) as u32
        } else {
            0
        };

        let dec_opts: DecoderOptions = Default::default();
        let decoder = symphonia::default::get_codecs()
            .make(&track.codec_params, &dec_opts)
            .map_err(|e| DecoderError::Unsupported(format!("Codec init failed: {e}")))?;

        Ok(Self {
            format,
            decoder,
            track_id,
            sample_rate,
            channels,
            duration_ms,
            sample_buf: None,
            current_packet_samples: Vec::with_capacity(4096),
            current_sample_idx: 0,
        })
    }

    #[inline]
    pub fn sample_rate(&self) -> u32 {
        self.sample_rate
    }

    #[inline]
    pub fn channels(&self) -> usize {
        self.channels
    }

    #[inline]
    pub fn duration_ms(&self) -> u32 {
        self.duration_ms
    }

    /// Seeks to a position in milliseconds.
    pub fn seek(&mut self, position_ms: u32) -> Result<(), DecoderError> {
        let seconds = (position_ms / 1000) as u64;
        let frac = (position_ms % 1000) as f64 / 1000.0;

        let seek_to = SeekTo::Time {
            time: Time::from(seconds as f64 + frac),
            track_id: Some(self.track_id),
        };

        self.format
            .seek(SeekMode::Accurate, seek_to)
            .map_err(|e| DecoderError::Decode(format!("Seek failed: {e}")))?;

        self.decoder.reset();
        self.current_packet_samples.clear();
        self.current_sample_idx = 0;
        Ok(())
    }

    /// Reads next interleaved stereo f32 samples into output buffer.
    /// Converts mono to stereo if needed.
    /// Returns the number of samples read (0 if end of stream).
    pub fn read_interleaved_stereo(&mut self, output: &mut [f32]) -> Result<usize, DecoderError> {
        let mut written = 0;

        while written < output.len() {
            // Drain remaining samples in current packet buffer
            if self.current_sample_idx < self.current_packet_samples.len() {
                let available = self.current_packet_samples.len() - self.current_sample_idx;
                let needed = output.len() - written;
                let to_copy = available.min(needed);

                output[written..written + to_copy]
                    .copy_from_slice(&self.current_packet_samples[self.current_sample_idx..self.current_sample_idx + to_copy]);

                self.current_sample_idx += to_copy;
                written += to_copy;

                if written == output.len() {
                    return Ok(written);
                }
            }

            // Need to decode next packet
            let packet = match self.format.next_packet() {
                Ok(packet) => packet,
                Err(SymphoniaError::IoError(e)) if e.kind() == std::io::ErrorKind::UnexpectedEof => {
                    // Normal EOF
                    return Ok(written);
                }
                Err(SymphoniaError::ResetRequired) => {
                    self.decoder.reset();
                    continue;
                }
                Err(e) => {
                    return Err(DecoderError::Decode(format!("Packet error: {e}")));
                }
            };

            if packet.track_id() != self.track_id {
                continue;
            }

            let decoded = match self.decoder.decode(&packet) {
                Ok(d) => d,
                Err(SymphoniaError::DecodeError(e)) => {
                    // Skip corrupt frames gracefully
                    tracing::warn!("Corrupt frame skipped: {e}");
                    continue;
                }
                Err(e) => {
                    return Err(DecoderError::Decode(format!("Decode failure: {e}")));
                }
            };

            // Copy to sample buffer
            let spec = *decoded.spec();
            let num_frames = decoded.frames();

            if self
                .sample_buf
                .as_ref()
                .map_or(true, |buf| (buf.capacity() as usize) < decoded.capacity())
            {
                self.sample_buf = Some(SampleBuffer::new(decoded.capacity() as u64, spec));
            }

            let sample_buf = self.sample_buf.as_mut().unwrap();
            sample_buf.copy_interleaved_ref(decoded);

            let raw_samples = sample_buf.samples();

            self.current_packet_samples.clear();
            self.current_sample_idx = 0;

            if self.channels == 1 {
                // Duplicate mono to stereo (L, R)
                self.current_packet_samples.reserve(num_frames * 2);
                for &sample in &raw_samples[..num_frames] {
                    self.current_packet_samples.push(sample);
                    self.current_packet_samples.push(sample);
                }
            } else {
                // Already multi-channel, keep first 2 channels
                let total = num_frames * self.channels;
                if self.channels == 2 {
                    self.current_packet_samples.extend_from_slice(&raw_samples[..total]);
                } else {
                    self.current_packet_samples.reserve(num_frames * 2);
                    for frame_idx in 0..num_frames {
                        let base = frame_idx * self.channels;
                        self.current_packet_samples.push(raw_samples[base]);
                        self.current_packet_samples.push(raw_samples[base + 1]);
                    }
                }
            }
        }

        Ok(written)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::Write;
    use tempfile::NamedTempFile;

    /// Generates a valid 16-bit PCM stereo WAV file in memory.
    fn create_test_wav(num_samples: usize, sample_rate: u32) -> NamedTempFile {
        let mut file = NamedTempFile::new().unwrap();

        let num_channels: u16 = 2;
        let bits_per_sample: u16 = 16;
        let byte_rate = sample_rate * num_channels as u32 * bits_per_sample as u32 / 8;
        let block_align = num_channels * bits_per_sample / 8;
        let data_chunk_size = (num_samples * num_channels as usize * 2) as u32;
        let riff_chunk_size = 36 + data_chunk_size;

        // RIFF header
        file.write_all(b"RIFF").unwrap();
        file.write_all(&riff_chunk_size.to_le_bytes()).unwrap();
        file.write_all(b"WAVE").unwrap();

        // fmt chunk
        file.write_all(b"fmt ").unwrap();
        file.write_all(&16u32.to_le_bytes()).unwrap(); // Subchunk1Size (16 for PCM)
        file.write_all(&1u16.to_le_bytes()).unwrap();  // AudioFormat (1 for PCM)
        file.write_all(&num_channels.to_le_bytes()).unwrap();
        file.write_all(&sample_rate.to_le_bytes()).unwrap();
        file.write_all(&byte_rate.to_le_bytes()).unwrap();
        file.write_all(&block_align.to_le_bytes()).unwrap();
        file.write_all(&bits_per_sample.to_le_bytes()).unwrap();

        // data chunk
        file.write_all(b"data").unwrap();
        file.write_all(&data_chunk_size.to_le_bytes()).unwrap();

        // Sine wave audio data
        for i in 0..num_samples {
            let t = i as f32 / sample_rate as f32;
            let sample_val = (t * 440.0 * 2.0 * std::f32::consts::PI).sin();
            let sample_i16 = (sample_val * i16::MAX as f32) as i16;

            file.write_all(&sample_i16.to_le_bytes()).unwrap(); // Left
            file.write_all(&sample_i16.to_le_bytes()).unwrap(); // Right
        }

        file.flush().unwrap();
        file
    }

    #[test]
    fn test_decoder_open_and_read() {
        let temp_wav = create_test_wav(4800, 48000); // 100ms of audio
        let source = AudioSource::Local(temp_wav.path().to_str().unwrap().into());

        let mut decoder = AudioDecoder::open(&source).expect("Failed to open valid test WAV");
        assert_eq!(decoder.sample_rate(), 48000);
        assert_eq!(decoder.channels(), 2);
        assert_eq!(decoder.duration_ms(), 100);

        let mut output = vec![0.0f32; 1024];
        let read = decoder.read_interleaved_stereo(&mut output).expect("Read failed");
        assert_eq!(read, 1024);

        // Verify seeking works
        decoder.seek(50).expect("Seek failed");
        let read_after_seek = decoder.read_interleaved_stereo(&mut output).expect("Read after seek failed");
        assert!(read_after_seek > 0);
    }
}
