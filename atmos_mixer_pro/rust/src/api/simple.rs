use crate::common::config::AppConfig;
use crate::core::state::GLOBAL_STATE;
use crate::common::commands::AudioCommand;
use crate::common::utils::hash_id;
use crate::api::error::AtmosError;
use crate::frb_generated::StreamSink;

#[flutter_rust_bridge::frb(init)]
pub fn api_init_app() {
    flutter_rust_bridge::setup_default_user_utils();
}

pub fn api_get_config(path: String) -> AppConfig {
    AppConfig::load_from_file(path).unwrap_or_default()
}

pub fn api_save_config(path: String, config: AppConfig) -> Result<(), AtmosError> {
    config.save_to_file(path)?;
    Ok(())
}

pub fn api_play_track(room_id: String, track_id: String) -> Result<(), AtmosError> {
    let config_guard = GLOBAL_STATE.config.read().unwrap();
    if let Some(config) = config_guard.as_ref() {
        if let Some(room) = config.rooms.iter().find(|r| r.id == room_id) {
            if let Some(track) = room.tracks.iter().find(|t| t.id == track_id) {
                if track.is_loop {
                    // Start DiskStreamer for BGM
                    match crate::audio::streaming::DiskStreamer::new(track.file_path.clone()) {
                        Ok(streamer) => {
                            GLOBAL_STATE.add_playing_track(track_id.clone());
                            GLOBAL_STATE.command_sender.try_send(AudioCommand::PlayTrack {
                                room_id: hash_id(&room_id),
                                track_id: hash_id(&track_id),
                                track_id_str: track_id.clone(),
                                data: None,
                                stream_receiver: Some(streamer.chunk_receiver),
                                stream_sample_rate: streamer.sample_rate,
                                is_loop: true,
                                volume: track.volume,
                                output_channel: track.output_channel as usize,
                                output_stereo: true,
                            }).map_err(|e| AtmosError { message: e.to_string() })?;
                            return Ok(());
                        }
                        Err(e) => {
                            return Err(AtmosError { message: format!("Streamer init failed: {}", e) });
                        }
                    }
                } else {
                    let cache_guard = GLOBAL_STATE.sound_cache.read().unwrap();
                    if let Some(data) = cache_guard.get(&track.file_path) {
                        GLOBAL_STATE.add_playing_track(track_id.clone());
                        GLOBAL_STATE.command_sender.try_send(AudioCommand::PlayTrack {
                            room_id: hash_id(&room_id),
                            track_id: hash_id(&track_id),
                            track_id_str: track_id.clone(),
                            data: Some(data.clone()),
                            stream_receiver: None,
                            stream_sample_rate: data.sample_rate,
                            is_loop: false,
                            volume: track.volume,
                            output_channel: track.output_channel as usize,
                            output_stereo: true,
                        }).map_err(|e| AtmosError { message: e.to_string() })?;
                        return Ok(());
                    } else {
                        return Err(AtmosError { message: format!("Cache miss for {}", track.file_path) });
                    }
                }
            }
        }
    }
    Err(AtmosError { message: "Room or track not found".to_string() })
}

pub fn api_stop_track(room_id: String, track_id: String) -> Result<(), AtmosError> {
    GLOBAL_STATE.remove_playing_track(&track_id);
    GLOBAL_STATE.command_sender.try_send(AudioCommand::StopTrack { 
        room_id: hash_id(&room_id), 
        track_id: hash_id(&track_id) 
    }).map_err(|e| AtmosError { message: e.to_string() })?;
    Ok(())
}

pub fn api_stop_all() -> Result<(), AtmosError> {
    GLOBAL_STATE.clear_playing_tracks();
    GLOBAL_STATE.set_active_room(None);
    GLOBAL_STATE.command_sender.try_send(AudioCommand::StopAll)
        .map_err(|e| AtmosError { message: e.to_string() })?;
    Ok(())
}

pub fn api_clear_room(room_id: String) -> Result<(), AtmosError> {
    // When a room is cleared, we might want to just clear playing tracks, but usually it stops them too.
    GLOBAL_STATE.clear_playing_tracks();
    {
        let mut guard = GLOBAL_STATE.active_room_id.write().unwrap();
        if guard.as_ref() == Some(&room_id) {
            *guard = None;
        }
    }
    GLOBAL_STATE.broadcast_state();
    GLOBAL_STATE.command_sender.try_send(AudioCommand::ClearRoom { room_id: hash_id(&room_id) })
        .map_err(|e| AtmosError { message: e.to_string() })?;
    Ok(())
}

pub fn api_set_master_volume(room_id: String, volume: f32) -> Result<(), AtmosError> {
    GLOBAL_STATE.command_sender.try_send(AudioCommand::SetMasterVolume { room_id: hash_id(&room_id), volume })
        .map_err(|e| AtmosError { message: e.to_string() })?;
    Ok(())
}

pub fn api_set_track_volume(room_id: String, track_id: String, volume: f32) -> Result<(), AtmosError> {
    GLOBAL_STATE.command_sender.try_send(AudioCommand::SetTrackVolume { room_id: hash_id(&room_id), track_id: hash_id(&track_id), volume })
        .map_err(|e| AtmosError { message: e.to_string() })?;
    Ok(())
}

pub fn api_create_vu_stream(sink: StreamSink<Vec<f32>>) {
    std::thread::spawn(move || {
        loop {
            let levels: Vec<f32> = GLOBAL_STATE.vu_levels.iter().map(|v| f32::from_bits(v.load(std::sync::atomic::Ordering::Relaxed))).collect();
            let _ = sink.add(levels);
            std::thread::sleep(std::time::Duration::from_millis(16));
        }
    });
}

pub fn api_start_audio_engine(device_name: Option<String>) {
    let rx = GLOBAL_STATE.command_receiver.clone();
    std::thread::spawn(move || {
        let mut engine = crate::audio::engine::AudioEngine::new();
        engine.start(device_name, rx);
        loop { std::thread::sleep(std::time::Duration::from_secs(1)); }
    });
}

pub fn api_start_osc_listener(port: u16) {
    let listener = crate::osc::listener::OscListener::new();
    listener.start(port);
}

pub fn api_create_log_stream(sink: StreamSink<String>) {
    let rx = GLOBAL_STATE.log_receiver.clone();
    std::thread::spawn(move || {
        let _ = sink.add("Rust Engine Log Stream Connected".to_string());
        while let Ok(msg) = rx.recv() {
            let _ = sink.add(msg);
        }
    });
}

#[derive(Debug, Clone)]
pub struct EngineStateUpdate {
    pub active_room_id: Option<String>,
    pub ducking_active: bool,
    pub playing_track_ids: Vec<String>,
}

pub fn api_create_engine_state_stream(sink: StreamSink<EngineStateUpdate>) {
    let rx = GLOBAL_STATE.state_receiver.clone();
    std::thread::spawn(move || {
        let _ = sink.add(EngineStateUpdate {
            active_room_id: GLOBAL_STATE.active_room_id.read().unwrap().clone(),
            ducking_active: GLOBAL_STATE.is_ducking.load(std::sync::atomic::Ordering::Relaxed),
            playing_track_ids: GLOBAL_STATE.playing_track_ids.read().unwrap().clone(),
        });
        while let Ok(state) = rx.recv() {
            let _ = sink.add(state);
        }
    });
}

pub fn api_preload_all_sounds(config: AppConfig) -> Result<(), AtmosError> {
    let mut cache = GLOBAL_STATE.sound_cache.write().unwrap();
    cache.clear();
    for room in &config.rooms {
        for track in &room.tracks {
            // Only preload SFX (not loops) to save RAM
            if !track.is_loop && !cache.contains_key(&track.file_path) {
                let path = std::path::Path::new(&track.file_path);
                match crate::audio::player::SoundData::load_from_file(path) {
                    Ok(data) => {
                        GLOBAL_STATE.log(format!("Loaded sound file: {}", track.file_path));
                        cache.insert(track.file_path.clone(), std::sync::Arc::new(data));
                    }
                    Err(e) => {
                        let err_msg = format!("Failed to load sound file {}: {}", track.file_path, e);
                        GLOBAL_STATE.log(err_msg.clone());
                        return Err(AtmosError { message: err_msg });
                    }
                }
            }
        }
    }
    let mut global_config = GLOBAL_STATE.config.write().unwrap();
    *global_config = Some(config.clone());
    drop(global_config);
    
    // Check if active_room_id exists in the new config
    let active_room_id = {
        let guard = GLOBAL_STATE.active_room_id.read().unwrap();
        guard.clone()
    };
    
    if let Some(active_id) = active_room_id {
        let room_exists = config.rooms.iter().any(|r| r.id == active_id);
        if !room_exists {
            // Room was deleted! Safely clear the room
            let _ = api_clear_room(active_id);
        }
    }
    
    Ok(())
}

#[derive(Clone, Debug)]
pub struct OutputDeviceInfo {
    pub name: String,
    pub max_channels: u32,
    pub channel_names: Vec<String>,
}

pub fn api_get_output_devices() -> Result<Vec<OutputDeviceInfo>, AtmosError> {
    use cpal::traits::{DeviceTrait, HostTrait};
    let host = cpal::default_host();
    let devices = host.output_devices().map_err(|e| AtmosError { message: e.to_string() })?;
    
    let mut device_info_list = Vec::new();
    for device in devices {
        if let Ok(name) = device.name() {
            let mut max_channels = 2; // Default fallback
            if let Ok(supported_configs) = device.supported_output_configs() {
                for config in supported_configs {
                    let channels = config.channels() as u32;
                    if channels > max_channels {
                        max_channels = channels;
                    }
                }
            }
            
            #[cfg(target_os = "macos")]
            let channel_names = crate::audio::channel_names::get_channel_names_mac(&name, max_channels);
            #[cfg(target_os = "windows")]
            let channel_names = crate::audio::channel_names::get_channel_names_win(&name, max_channels);
            #[cfg(not(any(target_os = "macos", target_os = "windows")))]
            let channel_names = crate::audio::channel_names::get_channel_names_fallback(max_channels);

            device_info_list.push(OutputDeviceInfo { name, max_channels, channel_names });
        }
    }
    Ok(device_info_list)
}

pub fn api_get_device_channel_count(device_name: String) -> Result<u32, AtmosError> {
    use cpal::traits::{DeviceTrait, HostTrait};
    let host = cpal::default_host();
    let devices = host.output_devices().map_err(|e| AtmosError { message: e.to_string() })?;
    
    for device in devices {
        if let Ok(name) = device.name() {
            if name == device_name {
                let mut max_channels = 2; // Default fallback
                if let Ok(supported_configs) = device.supported_output_configs() {
                    for config in supported_configs {
                        let channels = config.channels() as u32;
                        if channels > max_channels {
                            max_channels = channels;
                        }
                    }
                }
                return Ok(max_channels);
            }
        }
    }
    Err(AtmosError { message: format!("Device not found: {}", device_name) })
}

pub fn api_get_device_channel_names(device_name: String) -> Result<Vec<String>, AtmosError> {
    let max_channels = api_get_device_channel_count(device_name.clone())?;
    
    #[cfg(target_os = "macos")]
    let channel_names = crate::audio::channel_names::get_channel_names_mac(&device_name, max_channels);
    #[cfg(target_os = "windows")]
    let channel_names = crate::audio::channel_names::get_channel_names_win(&device_name, max_channels);
    #[cfg(not(any(target_os = "macos", target_os = "windows")))]
    let channel_names = crate::audio::channel_names::get_channel_names_fallback(max_channels);
    
    Ok(channel_names)
}
