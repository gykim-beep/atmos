use std::sync::Arc;

pub struct SoundData {
    pub samples: Vec<f32>,
    pub sample_rate: u32,
    pub channels: u16,
}

#[derive(Clone)]
pub struct SoundInstance {
    pub id: String,
    pub data: Arc<SoundData>,
    pub position: usize,
    pub output_ch: usize,
    pub volume: f32,
    pub room_volume: f32,
    pub loop_play: bool,
    pub is_bgm: bool,
    
    // Ducking logic ported from Python TrackState
    pub duck_gain: f32,
    pub duck_target: f32,
    pub duck_start_gain: f32,
    pub duck_fade_total: usize,
    pub duck_fade_left: usize,
    
    // Play Fade logic ported from Python TrackState
    pub play_fade_gain: f32,
    pub play_fade_target: f32,
    pub play_fade_start: f32,
    pub play_fade_total: usize,
    pub play_fade_left: usize,

    pub is_marked_for_removal: bool,
}
