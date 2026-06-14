use std::sync::atomic::{AtomicU32, AtomicBool, Ordering};
use std::sync::Arc;
use crossbeam_channel::{Sender, Receiver, bounded};
use lazy_static::lazy_static;
use crate::common::commands::AudioCommand;
use crate::api::simple::EngineStateUpdate;
use crate::frb_generated::StreamSink;

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
    
    pub active_room_id: RwLock<Option<String>>,
    pub is_ducking: AtomicBool,
    // VU levels for up to 64 output channels, stored as f32 bits
    pub vu_levels: Vec<AtomicU32>,
    pub sound_cache: RwLock<HashMap<String, Arc<SoundData>>>,
    pub config: RwLock<Option<AppConfig>>,
    pub playing_track_ids: RwLock<HashMap<u64, String>>,
    pub broadcast_lock: std::sync::Mutex<()>,
    
    pub log_sink: RwLock<Option<StreamSink<String>>>,
    pub state_sink: RwLock<Option<StreamSink<EngineStateUpdate>>>,
}

impl Default for GlobalEngineState {
    fn default() -> Self {
        Self::new()
    }
}

impl GlobalEngineState {
    pub fn new() -> Self {
        let (tx, rx) = bounded(1024);
        
        let mut vu = Vec::with_capacity(64);
        for _ in 0..64 {
            vu.push(AtomicU32::new(0));
        }
        Self {
            command_sender: tx,
            command_receiver: rx,
            active_room_id: RwLock::new(None),
            is_ducking: AtomicBool::new(false),
            vu_levels: vu,
            sound_cache: RwLock::new(HashMap::new()),
            config: RwLock::new(None),
            playing_track_ids: RwLock::new(HashMap::new()),
            broadcast_lock: std::sync::Mutex::new(()),
            log_sink: RwLock::new(None),
            state_sink: RwLock::new(None),
        }
    }

    pub fn broadcast_state(&self) {
        let room_id = self.active_room_id.read().unwrap().clone();
        let ducking = self.is_ducking.load(Ordering::Relaxed);
        let playing_track_ids = {
            let guard = self.playing_track_ids.read().unwrap();
            let mut unique_ids: Vec<String> = guard.values().cloned().collect();
            unique_ids.sort();
            unique_ids.dedup();
            unique_ids
        };
        
        let update = EngineStateUpdate {
            active_room_id: room_id,
            ducking_active: ducking,
            playing_track_ids,
        };
        
        if let Some(sink) = self.state_sink.read().unwrap().as_ref() {
            let _ = sink.add(update);
        }
    }

    pub fn set_active_room(&self, room_id: Option<String>) {
        let _lock = self.broadcast_lock.lock().unwrap();
        {
            let mut guard = self.active_room_id.write().unwrap();
            *guard = room_id;
        }
        self.broadcast_state();
    }

    pub fn set_ducking(&self, ducking: bool) {
        let _lock = self.broadcast_lock.lock().unwrap();
        self.is_ducking.store(ducking, Ordering::Relaxed);
        self.broadcast_state();
    }

    pub fn log(&self, msg: String) {
        println!("{}", msg);
        if let Some(sink) = self.log_sink.read().unwrap().as_ref() {
            let _ = sink.add(msg);
        }
    }

    pub fn add_playing_track(&self, instance_id: u64, track_id: String) {
        let _lock = self.broadcast_lock.lock().unwrap();
        let mut guard = self.playing_track_ids.write().unwrap();
        guard.insert(instance_id, track_id);
        drop(guard);
        self.broadcast_state();
    }

    pub fn remove_playing_track(&self, instance_id: u64) {
        let _lock = self.broadcast_lock.lock().unwrap();
        let mut guard = self.playing_track_ids.write().unwrap();
        if guard.remove(&instance_id).is_some() {
            drop(guard);
            self.broadcast_state();
        }
    }

    pub fn clear_playing_tracks(&self) {
        let _lock = self.broadcast_lock.lock().unwrap();
        {
            let mut guard = self.playing_track_ids.write().unwrap();
            guard.clear();
        }
        self.broadcast_state();
    }
}
