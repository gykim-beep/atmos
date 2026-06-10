use std::sync::{Arc, Mutex};
use std::collections::HashMap;
use crossbeam_channel::Sender;
use crate::common::commands::AudioCommand;
use crate::audio::player::SoundData;

pub struct SendStream(pub cpal::Stream);
unsafe impl Send for SendStream {}
unsafe impl Sync for SendStream {}

pub struct GlobalEngineState {
    pub stream: Option<SendStream>,
    pub cmd_tx: Option<Sender<AudioCommand>>,
    pub loaded_assets: HashMap<String, Arc<SoundData>>,
    pub active_device_name: String,
    pub active_channels: usize,
    pub active_sample_rate: u32,
    pub room_volumes: HashMap<usize, f32>,
    pub active_room_id: usize,
}

pub struct EngineManager {
    pub state: Mutex<GlobalEngineState>,
}

impl EngineManager {
    pub fn new() -> Self {
        Self {
            state: Mutex::new(GlobalEngineState {
                stream: None,
                cmd_tx: None,
                loaded_assets: HashMap::new(),
                active_device_name: String::new(),
                active_channels: 2,
                active_sample_rate: 48000,
                room_volumes: HashMap::new(),
                active_room_id: 1,
            }),
        }
    }
}
