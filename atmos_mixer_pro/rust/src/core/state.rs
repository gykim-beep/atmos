use std::sync::atomic::{AtomicU32, AtomicBool, Ordering};
use std::sync::Arc;
use crossbeam_channel::{Sender, Receiver, bounded};
use lazy_static::lazy_static;
use crate::common::commands::AudioCommand;
use crate::api::simple::EngineStateUpdate;

lazy_static! {
    pub static ref GLOBAL_STATE: Arc<GlobalEngineState> = Arc::new(GlobalEngineState::new());
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum RoomState {
    Locked,
    Active,
    Cleared,
}

use std::sync::RwLock;
use std::collections::HashMap;
use crate::audio::player::SoundData;
use crate::common::config::AppConfig;

pub struct GlobalEngineState {
    // Command channel to audio thread (Lock-free MPSC)
    pub command_sender: Sender<AudioCommand>,
    // The receiver will be taken by the audio thread. Using crossbeam, receivers can be cloned.
    pub command_receiver: Receiver<AudioCommand>,
    
    pub log_sender: Sender<String>,
    pub log_receiver: Receiver<String>,
    
    pub state_sender: Sender<EngineStateUpdate>,
    pub state_receiver: Receiver<EngineStateUpdate>,
    
    // Active room tracking
    pub active_room_id: RwLock<Option<String>>,
    pub is_ducking: AtomicBool,
    // VU levels for up to 64 output channels, stored as f32 bits
    pub vu_levels: Vec<AtomicU32>,
    pub sound_cache: RwLock<HashMap<String, Arc<SoundData>>>,
    pub config: RwLock<Option<AppConfig>>,
    pub playing_track_ids: RwLock<Vec<String>>,
}

impl Default for GlobalEngineState {
    fn default() -> Self {
        Self::new()
    }
}

impl GlobalEngineState {
    pub fn new() -> Self {
        let (tx, rx) = bounded(1024);
        let (log_tx, log_rx) = bounded(1024);
        let (state_tx, state_rx) = bounded(1024);
        
        let mut vu = Vec::with_capacity(64);
        for _ in 0..64 {
            vu.push(AtomicU32::new(0));
        }
        Self {
            command_sender: tx,
            command_receiver: rx,
            log_sender: log_tx,
            log_receiver: log_rx,
            state_sender: state_tx,
            state_receiver: state_rx,
            active_room_id: RwLock::new(None),
            is_ducking: AtomicBool::new(false),
            vu_levels: vu,
            sound_cache: RwLock::new(HashMap::new()),
            config: RwLock::new(None),
            playing_track_ids: RwLock::new(Vec::new()),
        }
    }

    pub fn broadcast_state(&self) {
        let room_id = self.active_room_id.read().unwrap().clone();
        let ducking = self.is_ducking.load(Ordering::Relaxed);
        let playing_track_ids = self.playing_track_ids.read().unwrap().clone();
        let _ = self.state_sender.try_send(EngineStateUpdate {
            active_room_id: room_id,
            ducking_active: ducking,
            playing_track_ids,
        });
    }

    pub fn set_active_room(&self, room_id: Option<String>) {
        {
            let mut guard = self.active_room_id.write().unwrap();
            *guard = room_id;
        }
        self.broadcast_state();
    }

    pub fn set_ducking(&self, ducking: bool) {
        self.is_ducking.store(ducking, Ordering::Relaxed);
        self.broadcast_state();
    }

    pub fn log(&self, msg: String) {
        println!("{}", msg);
        let _ = self.log_sender.try_send(msg);
    }

    pub fn add_playing_track(&self, track_id: String) {
        let mut guard = self.playing_track_ids.write().unwrap();
        if !guard.contains(&track_id) {
            guard.push(track_id);
        }
        drop(guard);
        self.broadcast_state();
    }

    pub fn remove_playing_track(&self, track_id: &str) {
        let mut guard = self.playing_track_ids.write().unwrap();
        if let Some(pos) = guard.iter().position(|x| x == track_id) {
            guard.remove(pos);
            drop(guard);
            self.broadcast_state();
        }
    }

    pub fn clear_playing_tracks(&self) {
        {
            let mut guard = self.playing_track_ids.write().unwrap();
            guard.clear();
        }
        self.broadcast_state();
    }
}
