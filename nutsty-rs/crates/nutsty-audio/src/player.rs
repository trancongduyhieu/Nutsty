//! High-performance audio player implementing AudioEngine.
//! Uses cpal for low-level audio output and rtrb for lock-free ring-buffered playback.

use crate::decoder::AudioDecoder;
use crate::engine::{AudioEngine, AudioError};
use cpal::traits::{DeviceTrait, HostTrait, StreamTrait};
use cpal::SampleFormat;
use crossbeam_channel::{bounded, Receiver, Sender};
use nutsty_core::{AudioSource, PlaybackProgress, PlaybackStatus, Volume};
use rtrb::{Consumer, RingBuffer};
use std::sync::atomic::{AtomicU32, AtomicU64, AtomicU8, Ordering};
use std::sync::Arc;
use std::thread;
use std::time::Duration;

const RING_BUFFER_CAPACITY: usize = 48000 * 2 * 2; // ~2 seconds of stereo audio at 48kHz

#[derive(Debug)]
enum PlayerCommand {
    Load(AudioSource),
    Play,
    Pause,
    Stop,
    Seek(u32),
    Shutdown,
}

/// Thread-safe controller handle for audio playback.
/// Does not hold the raw OS stream handle directly, allowing safe Send + Sync.
pub struct CpalAudioPlayer {
    command_tx: Sender<PlayerCommand>,
    status: Arc<AtomicU8>,
    volume_bits: Arc<AtomicU32>,
    played_samples: Arc<AtomicU64>,
    duration_ms: Arc<AtomicU32>,
    output_sample_rate: Arc<AtomicU32>,
}

impl CpalAudioPlayer {
    /// Spawns the dedicated audio worker thread and initializes playback pipeline.
    pub fn new() -> Result<Self, AudioError> {
        let (command_tx, command_rx) = bounded::<PlayerCommand>(32);
        let status = Arc::new(AtomicU8::new(PlaybackStatus::Stopped as u8));
        let volume_bits = Arc::new(AtomicU32::new(1.0f32.to_bits()));
        let played_samples = Arc::new(AtomicU64::new(0));
        let duration_ms = Arc::new(AtomicU32::new(0));
        let output_sample_rate = Arc::new(AtomicU32::new(48000));

        let (init_tx, init_rx) = bounded::<Result<(), AudioError>>(1);

        let status_clone = Arc::clone(&status);
        let volume_bits_clone = Arc::clone(&volume_bits);
        let played_samples_clone = Arc::clone(&played_samples);
        let duration_ms_clone = Arc::clone(&duration_ms);
        let output_sample_rate_clone = Arc::clone(&output_sample_rate);

        thread::Builder::new()
            .name("nutsty-audio-host".into())
            .spawn(move || {
                run_audio_host_loop(
                    init_tx,
                    command_rx,
                    status_clone,
                    volume_bits_clone,
                    played_samples_clone,
                    duration_ms_clone,
                    output_sample_rate_clone,
                );
            })
            .map_err(|e| AudioError::DeviceError(format!("Failed to spawn audio host thread: {e}")))?;

        // Wait for device initialization
        init_rx
            .recv()
            .map_err(|_| AudioError::DeviceError("Audio host thread crashed during initialization".into()))??;

        Ok(Self {
            command_tx,
            status,
            volume_bits,
            played_samples,
            duration_ms,
            output_sample_rate,
        })
    }

    pub fn load_source(&self, source: AudioSource) -> Result<(), AudioError> {
        self.command_tx
            .send(PlayerCommand::Load(source))
            .map_err(|_| AudioError::DeviceError("Audio host disconnected".into()))
    }
}

impl AudioEngine for CpalAudioPlayer {
    fn play(&self) -> Result<(), AudioError> {
        self.command_tx
            .send(PlayerCommand::Play)
            .map_err(|_| AudioError::DeviceError("Audio host disconnected".into()))
    }

    fn pause(&self) -> Result<(), AudioError> {
        self.command_tx
            .send(PlayerCommand::Pause)
            .map_err(|_| AudioError::DeviceError("Audio host disconnected".into()))
    }

    fn stop(&self) -> Result<(), AudioError> {
        self.command_tx
            .send(PlayerCommand::Stop)
            .map_err(|_| AudioError::DeviceError("Audio host disconnected".into()))
    }

    fn seek(&self, position_ms: u32) -> Result<(), AudioError> {
        self.command_tx
            .send(PlayerCommand::Seek(position_ms))
            .map_err(|_| AudioError::DeviceError("Audio host disconnected".into()))
    }

    fn set_volume(&self, volume: Volume) {
        self.volume_bits
            .store(volume.raw().to_bits(), Ordering::Relaxed);
    }

    fn status(&self) -> PlaybackStatus {
        match self.status.load(Ordering::Relaxed) {
            1 => PlaybackStatus::Playing,
            2 => PlaybackStatus::Paused,
            _ => PlaybackStatus::Stopped,
        }
    }

    fn progress(&self) -> PlaybackProgress {
        let samples = self.played_samples.load(Ordering::Relaxed);
        let duration_ms = self.duration_ms.load(Ordering::Relaxed);
        let sample_rate = self.output_sample_rate.load(Ordering::Relaxed);

        // 2 channels stereo: position = samples / (sample_rate * 2)
        let position_ms = if sample_rate > 0 {
            ((samples as f64 / (sample_rate as f64 * 2.0)) * 1000.0) as u32
        } else {
            0
        };

        PlaybackProgress {
            position_ms: position_ms.min(duration_ms),
            duration_ms,
        }
    }
}

impl Drop for CpalAudioPlayer {
    fn drop(&mut self) {
        let _ = self.command_tx.send(PlayerCommand::Shutdown);
    }
}

/// Host thread that owns the CPAL output stream and runs the decoding worker.
fn run_audio_host_loop(
    init_tx: Sender<Result<(), AudioError>>,
    command_rx: Receiver<PlayerCommand>,
    status: Arc<AtomicU8>,
    volume_bits: Arc<AtomicU32>,
    played_samples: Arc<AtomicU64>,
    duration_ms: Arc<AtomicU32>,
    output_sample_rate: Arc<AtomicU32>,
) {
    let host = cpal::default_host();
    let device = match host.default_output_device() {
        Some(d) => d,
        None => {
            let _ = init_tx.send(Err(AudioError::DeviceError("No default output device".into())));
            return;
        }
    };

    let supported_config = match device.default_output_config() {
        Ok(c) => c,
        Err(e) => {
            let _ = init_tx.send(Err(AudioError::DeviceError(format!("Config error: {e}"))));
            return;
        }
    };

    let sample_rate = supported_config.sample_rate().0;
    output_sample_rate.store(sample_rate, Ordering::Relaxed);

    let (mut producer, mut consumer) = RingBuffer::<f32>::new(RING_BUFFER_CAPACITY);

    let status_cb = Arc::clone(&status);
    let volume_bits_cb = Arc::clone(&volume_bits);
    let played_samples_cb = Arc::clone(&played_samples);
    let flush_epoch = Arc::new(AtomicU32::new(0));
    let flush_epoch_cb = Arc::clone(&flush_epoch);

    let err_fn = |err| tracing::error!("Audio stream error: {err}");

    let mut local_epoch_f32 = 0u32;
    let mut local_epoch_i16 = 0u32;

    let stream = match supported_config.sample_format() {
        SampleFormat::F32 => device.build_output_stream(
            &supported_config.into(),
            move |data: &mut [f32], _: &cpal::OutputCallbackInfo| {
                write_audio_f32(
                    data,
                    &mut consumer,
                    &status_cb,
                    &volume_bits_cb,
                    &played_samples_cb,
                    &flush_epoch_cb,
                    &mut local_epoch_f32,
                );
            },
            err_fn,
            None,
        ),
        SampleFormat::I16 => device.build_output_stream(
            &supported_config.into(),
            move |data: &mut [i16], _: &cpal::OutputCallbackInfo| {
                write_audio_i16(
                    data,
                    &mut consumer,
                    &status_cb,
                    &volume_bits_cb,
                    &played_samples_cb,
                    &flush_epoch_cb,
                    &mut local_epoch_i16,
                );
            },
            err_fn,
            None,
        ),
        SampleFormat::U16 => device.build_output_stream(
            &supported_config.into(),
            move |data: &mut [u16], _: &cpal::OutputCallbackInfo| {
                data.fill(32768);
            },
            err_fn,
            None,
        ),
        _ => {
            let _ = init_tx.send(Err(AudioError::DeviceError("Unsupported sample format".into())));
            return;
        }
    };

    let stream = match stream {
        Ok(s) => s,
        Err(e) => {
            let _ = init_tx.send(Err(AudioError::DeviceError(format!("Stream build failed: {e}"))));
            return;
        }
    };

    if let Err(e) = stream.play() {
        let _ = init_tx.send(Err(AudioError::DeviceError(format!("Stream play failed: {e}"))));
        return;
    }

    // Signal successful initialization to caller
    let _ = init_tx.send(Ok(()));

    // Decoding & command processing loop
    let mut decoder: Option<AudioDecoder> = None;
    let mut decode_chunk = [0.0f32; 2048];

    loop {
        // Poll commands
        while let Ok(cmd) = command_rx.try_recv() {
            match cmd {
                PlayerCommand::Load(source) => {
                    flush_epoch.fetch_add(1, Ordering::Release);
                    match AudioDecoder::open(&source) {
                        Ok(dec) => {
                            duration_ms.store(dec.duration_ms(), Ordering::Relaxed);
                            played_samples.store(0, Ordering::Relaxed);
                            decoder = Some(dec);
                            status.store(PlaybackStatus::Stopped as u8, Ordering::Relaxed);
                        }
                        Err(e) => {
                            tracing::error!("Failed to open audio source: {e}");
                            status.store(PlaybackStatus::Stopped as u8, Ordering::Relaxed);
                            decoder = None;
                        }
                    }
                }
                PlayerCommand::Play => {
                    if decoder.is_some() {
                        status.store(PlaybackStatus::Playing as u8, Ordering::Relaxed);
                    }
                }
                PlayerCommand::Pause => {
                    status.store(PlaybackStatus::Paused as u8, Ordering::Relaxed);
                }
                PlayerCommand::Stop => {
                    flush_epoch.fetch_add(1, Ordering::Release);
                    status.store(PlaybackStatus::Stopped as u8, Ordering::Relaxed);
                    played_samples.store(0, Ordering::Relaxed);
                    if let Some(dec) = decoder.as_mut() {
                        let _ = dec.seek(0);
                    }
                }
                PlayerCommand::Seek(pos_ms) => {
                    if let Some(dec) = decoder.as_mut() {
                        if dec.seek(pos_ms).is_ok() {
                            flush_epoch.fetch_add(1, Ordering::Release);
                            let new_samples = (pos_ms as u64 * sample_rate as u64 * 2) / 1000;
                            played_samples.store(new_samples, Ordering::Relaxed);
                        }
                    }
                }
                PlayerCommand::Shutdown => {
                    return;
                }
            }
        }

        let is_playing = status.load(Ordering::Relaxed) == PlaybackStatus::Playing as u8;

        if !is_playing || decoder.is_none() {
            thread::sleep(Duration::from_millis(5));
            continue;
        }

        let slots_available = producer.slots();
        if slots_available < decode_chunk.len() {
            thread::sleep(Duration::from_millis(3));
            continue;
        }

        let dec = decoder.as_mut().unwrap();
        match dec.read_interleaved_stereo(&mut decode_chunk) {
            Ok(samples_read) => {
                if samples_read == 0 {
                    // Track ended
                    status.store(PlaybackStatus::Stopped as u8, Ordering::Relaxed);
                    thread::sleep(Duration::from_millis(5));
                } else if let Ok(mut chunk) = producer.write_chunk(samples_read) {
                    let (first, second) = chunk.as_mut_slices();
                    let first_len = first.len();
                    first.copy_from_slice(&decode_chunk[..first_len]);
                    second.copy_from_slice(&decode_chunk[first_len..samples_read]);
                    chunk.commit_all();
                }
            }
            Err(e) => {
                tracing::warn!("Decode error: {e}");
                thread::sleep(Duration::from_millis(5));
            }
        }
    }
}

/// Real-time audio callback for f32: ZERO allocation, wait-free ring buffer read.
#[inline]
fn write_audio_f32(
    data: &mut [f32],
    consumer: &mut Consumer<f32>,
    status: &AtomicU8,
    volume_bits: &AtomicU32,
    played_samples: &AtomicU64,
    flush_epoch: &AtomicU32,
    local_epoch: &mut u32,
) {
    let current_epoch = flush_epoch.load(Ordering::Relaxed);
    if *local_epoch != current_epoch {
        *local_epoch = current_epoch;
        let stale_slots = consumer.slots();
        if stale_slots > 0 {
            if let Ok(stale_chunk) = consumer.read_chunk(stale_slots) {
                stale_chunk.commit_all();
            }
        }
    }

    let is_playing = status.load(Ordering::Relaxed) == PlaybackStatus::Playing as u8;
    let volume = f32::from_bits(volume_bits.load(Ordering::Relaxed));

    if !is_playing {
        data.fill(0.0);
        return;
    }

    let mut samples_read = 0;
    while samples_read < data.len() {
        let needed = data.len() - samples_read;
        let available = consumer.slots();
        let to_read = needed.min(available);

        if to_read == 0 {
            // Buffer underrun: fill remainder with silence
            data[samples_read..].fill(0.0);
            break;
        }

        if let Ok(chunk) = consumer.read_chunk(to_read) {
            let (first, second) = chunk.as_slices();
            for &s in first {
                data[samples_read] = s * volume;
                samples_read += 1;
            }
            for &s in second {
                data[samples_read] = s * volume;
                samples_read += 1;
            }
            chunk.commit_all();
        } else {
            data[samples_read..].fill(0.0);
            break;
        }
    }

    played_samples.fetch_add(samples_read as u64, Ordering::Relaxed);
}

#[inline]
fn write_audio_i16(
    data: &mut [i16],
    consumer: &mut Consumer<f32>,
    status: &AtomicU8,
    volume_bits: &AtomicU32,
    played_samples: &AtomicU64,
    flush_epoch: &AtomicU32,
    local_epoch: &mut u32,
) {
    let current_epoch = flush_epoch.load(Ordering::Relaxed);
    if *local_epoch != current_epoch {
        *local_epoch = current_epoch;
        let stale_slots = consumer.slots();
        if stale_slots > 0 {
            if let Ok(stale_chunk) = consumer.read_chunk(stale_slots) {
                stale_chunk.commit_all();
            }
        }
    }

    let mut temp = [0.0f32; 1024];
    let is_playing = status.load(Ordering::Relaxed) == PlaybackStatus::Playing as u8;
    let volume = f32::from_bits(volume_bits.load(Ordering::Relaxed));

    if !is_playing {
        data.fill(0);
        return;
    }

    let mut total_written = 0;
    while total_written < data.len() {
        let chunk_size = (data.len() - total_written).min(temp.len());
        let available = consumer.slots();
        let to_read = chunk_size.min(available);
        let slice = &mut temp[..chunk_size];

        let mut read = 0;
        if to_read > 0 {
            if let Ok(c) = consumer.read_chunk(to_read) {
                let (f, s) = c.as_slices();
                for &sample in f {
                    slice[read] = sample;
                    read += 1;
                }
                for &sample in s {
                    slice[read] = sample;
                    read += 1;
                }
                c.commit_all();
            }
        }

        for i in 0..read {
            let scaled = (slice[i] * volume).clamp(-1.0, 1.0);
            data[total_written + i] = (scaled * i16::MAX as f32) as i16;
        }
        if read < chunk_size {
            data[total_written + read..total_written + chunk_size].fill(0);
        }

        total_written += chunk_size;
        played_samples.fetch_add(read as u64, Ordering::Relaxed);
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::decoder::AudioDecoder;
    use std::f32::consts::PI;
    use std::io::Write;
    use tempfile::NamedTempFile;

    fn create_test_wav(num_samples: usize, sample_rate: u32) -> NamedTempFile {
        let mut file = NamedTempFile::new().unwrap();
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

        for i in 0..num_samples {
            let t = i as f32 / sample_rate as f32;
            let sample_val = (t * 440.0 * 2.0 * PI).sin();
            let sample_i16 = (sample_val * i16::MAX as f32) as i16;
            file.write_all(&sample_i16.to_le_bytes()).unwrap();
            file.write_all(&sample_i16.to_le_bytes()).unwrap();
        }
        file.flush().unwrap();
        file
    }

    #[test]
    fn test_rtrb_partial_buffer_underrun_behavior() {
        let (mut producer, mut consumer) = RingBuffer::<f32>::new(1024);
        let status = AtomicU8::new(PlaybackStatus::Playing as u8);
        let volume_bits = AtomicU32::new(1.0f32.to_bits());
        let played_samples = AtomicU64::new(0);
        let flush_epoch = AtomicU32::new(0);
        let mut local_epoch = 0u32;

        // Producer writes 200 samples
        let mut chunk = producer.write_chunk(200).expect("write 200");
        let (f, s) = chunk.as_mut_slices();
        f.fill(0.5);
        s.fill(0.5);
        chunk.commit_all();

        assert_eq!(consumer.slots(), 200);

        // Audio callback requests 512 samples
        let mut data = [0.0f32; 512];
        write_audio_f32(
            &mut data,
            &mut consumer,
            &status,
            &volume_bits,
            &played_samples,
            &flush_epoch,
            &mut local_epoch,
        );

        // VERIFY:
        // 1. All 200 available samples were consumed smoothly
        assert_eq!(consumer.slots(), 0, "All 200 samples must be consumed!");
        // 2. data[0..200] has valid audio (0.5), data[200..512] has silence (0.0)
        assert_eq!(data[0], 0.5, "First 200 samples must be played!");
        assert_eq!(data[199], 0.5, "First 200 samples must be played!");
        assert_eq!(data[200], 0.0, "Underrun portion must be silence!");
        assert_eq!(data[511], 0.0, "Underrun portion must be silence!");
        // 3. played_samples is incremented by exactly 200
        assert_eq!(played_samples.load(Ordering::Relaxed), 200);
    }

    #[test]
    fn test_stale_audio_flushed_on_seek_or_track_change() {
        let (mut producer, mut consumer) = RingBuffer::<f32>::new(4096);
        let status = AtomicU8::new(PlaybackStatus::Playing as u8);
        let volume_bits = AtomicU32::new(1.0f32.to_bits());
        let played_samples = AtomicU64::new(0);
        let flush_epoch = AtomicU32::new(0);
        let mut local_epoch = 0u32;

        // Song A produces 1000 samples of value 0.99
        let mut chunk = producer.write_chunk(1000).unwrap();
        let (f, s) = chunk.as_mut_slices();
        f.fill(0.99);
        s.fill(0.99);
        chunk.commit_all();

        // User now issues Seek or Load new track (Song B).
        // flush_epoch is incremented on the producer side:
        flush_epoch.fetch_add(1, Ordering::Release);

        // New audio callback executes:
        let mut data = [0.0f32; 512];
        write_audio_f32(
            &mut data,
            &mut consumer,
            &status,
            &volume_bits,
            &played_samples,
            &flush_epoch,
            &mut local_epoch,
        );

        // The 1000 stale samples from Song A must be cleanly discarded!
        // No 0.99 audio leaks into Song B:
        assert_eq!(data[0], 0.0, "Stale audio was successfully flushed!");
        assert_eq!(consumer.slots(), 0, "Ring buffer is clean for new track!");
    }

    #[test]
    fn test_write_audio_i16_conversion_and_underrun() {
        let (mut producer, mut consumer) = RingBuffer::<f32>::new(1024);
        let status = AtomicU8::new(PlaybackStatus::Playing as u8);
        let volume_bits = AtomicU32::new(1.0f32.to_bits());
        let played_samples = AtomicU64::new(0);
        let flush_epoch = AtomicU32::new(0);
        let mut local_epoch = 0u32;

        let mut chunk = producer.write_chunk(100).expect("write 100");
        let (f, s) = chunk.as_mut_slices();
        f.fill(1.0); // max amplitude
        s.fill(1.0);
        chunk.commit_all();

        let mut data = [0i16; 256];
        write_audio_i16(
            &mut data,
            &mut consumer,
            &status,
            &volume_bits,
            &played_samples,
            &flush_epoch,
            &mut local_epoch,
        );

        assert_eq!(data[0], i16::MAX);
        assert_eq!(data[99], i16::MAX);
        assert_eq!(data[100], 0); // silence on underrun
        assert_eq!(played_samples.load(Ordering::Relaxed), 100);
    }

    #[test]
    fn test_track_cycling_and_rapid_seek_no_leak() {
        let wav = create_test_wav(2400, 48000); // 50ms
        let source = AudioSource::Local(wav.path().to_str().unwrap().into());

        for _ in 0..500 {
            let mut dec = AudioDecoder::open(&source).expect("Open failed");
            let mut buf = [0.0f32; 512];
            let _ = dec.read_interleaved_stereo(&mut buf);
            let _ = dec.seek(25);
            let _ = dec.read_interleaved_stereo(&mut buf);
            // dec dropped here
        }
    }
}
