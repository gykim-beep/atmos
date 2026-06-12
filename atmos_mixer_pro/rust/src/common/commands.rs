use std::sync::Arc;
use crate::audio::player::SoundData;

#[derive(Clone)]
pub enum AudioCommand {
    PlayTrack {
        room_id: u32,
        track_id: u32,
        data: Option<Arc<SoundData>>,
        stream_receiver: Option<crossbeam_channel::Receiver<Vec<f32>>>,
        stream_sample_rate: u32,
        is_loop: bool,
        volume: f32,
        output_channel: usize,
        output_stereo: bool,
    },
    StopTrack { room_id: u32, track_id: u32 },
    StopAll,
    SetMasterVolume { room_id: u32, volume: f32 },
    SetTrackVolume { room_id: u32, track_id: u32, volume: f32 },
    ClearRoom { room_id: u32 },
}
