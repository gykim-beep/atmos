use std::sync::Arc;

use symphonia::core::io::MediaSourceStream;
use symphonia::core::probe::Hint;
use symphonia::core::formats::FormatOptions;
use symphonia::core::meta::MetadataOptions;
use symphonia::core::codecs::DecoderOptions;
use symphonia::core::audio::SampleBuffer;
use std::fs::File;

pub struct SoundData {
    pub samples: Vec<f32>,
    pub channels: u16,
    pub sample_rate: u32,
}

impl SoundData {
    pub fn load_from_file(path: &std::path::Path) -> anyhow::Result<Self> {
        let file = Box::new(File::open(path)?);
        let mss = MediaSourceStream::new(file, Default::default());

        let hint = Hint::new();
        let format_opts = FormatOptions::default();
        let metadata_opts = MetadataOptions::default();
        let decoder_opts = DecoderOptions::default();

        let probed = symphonia::default::get_probe()
            .format(&hint, mss, &format_opts, &metadata_opts)?;

        let mut format = probed.format;
        let track = format.default_track().ok_or_else(|| anyhow::anyhow!("No default track"))?;
        let mut decoder = symphonia::default::get_codecs()
            .make(&track.codec_params, &decoder_opts)?;

        let track_id = track.id;
        let sample_rate = track.codec_params.sample_rate.unwrap_or(48000);
        let channels = track.codec_params.channels.map(|c| c.count() as u16).unwrap_or(2);

        let mut sample_buf = None;
        let mut all_samples = Vec::new();

        loop {
            let packet = match format.next_packet() {
                Ok(packet) => packet,
                Err(symphonia::core::errors::Error::ResetRequired) => {
                    decoder.reset();
                    continue;
                }
                Err(symphonia::core::errors::Error::IoError(err)) => {
                    if err.kind() == std::io::ErrorKind::UnexpectedEof {
                        break;
                    }
                    break; // Just break on any IO error (like EOF)
                }
                Err(_) => break,
            };

            if packet.track_id() != track_id {
                continue;
            }

            match decoder.decode(&packet) {
                Ok(audio_buf) => {
                    if sample_buf.is_none() {
                        let spec = *audio_buf.spec();
                        let duration = audio_buf.capacity() as u64;
                        sample_buf = Some(SampleBuffer::<f32>::new(duration, spec));
                    }

                    if let Some(buf) = &mut sample_buf {
                        buf.copy_interleaved_ref(audio_buf);
                        all_samples.extend_from_slice(buf.samples());
                    }
                }
                Err(symphonia::core::errors::Error::DecodeError(_)) => (),
                Err(_) => break,
            }
        }

        Ok(Self {
            samples: all_samples,
            channels,
            sample_rate,
        })
    }
}

pub struct SoundInstance {
    pub id: u32,
    pub room_id: u32,
    pub data: Option<Arc<SoundData>>,
    pub stream_receiver: Option<crossbeam_channel::Receiver<Vec<f32>>>,
    pub stream_buffer: Vec<f32>,
    pub stream_sample_rate: u32,
    pub cursor: usize,
    pub volume: f32,
    pub is_loop: bool,
    pub is_playing: bool,
    pub is_stopping: bool,
    pub output_channel: usize,
    pub output_stereo: bool,
    pub fade_weight: f32, // 0.0 to 1.0
}

impl SoundInstance {
    #[allow(clippy::too_many_arguments)]
    pub fn new(
        id: u32, 
        room_id: u32, 
        data: Option<Arc<SoundData>>, 
        stream_receiver: Option<crossbeam_channel::Receiver<Vec<f32>>>,
        stream_sample_rate: u32,
        is_loop: bool, 
        output_channel: usize,
        output_stereo: bool
    ) -> Self {
        Self {
            id,
            room_id,
            data,
            stream_receiver,
            stream_buffer: Vec::new(),
            stream_sample_rate,
            cursor: 0,
            volume: 1.0,
            is_loop,
            is_playing: true,
            is_stopping: false,
            output_channel,
            output_stereo,
            fade_weight: 0.0, // starts from 0 for fade in
        }
    }
}
