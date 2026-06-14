use std::net::UdpSocket;
use std::thread;
use std::sync::Arc;
use rosc::OscPacket;
use crate::osc::debouncer::OscDebouncer;

use crate::common::utils::hash_id;

use std::sync::atomic::{AtomicBool, Ordering};
use lazy_static::lazy_static;

lazy_static! {
    pub static ref OSC_RUNNING_FLAG: Arc<AtomicBool> = Arc::new(AtomicBool::new(false));
}

pub struct OscListener {
    debouncer: Arc<OscDebouncer>,
}

impl Default for OscListener {
    fn default() -> Self {
        Self::new()
    }
}

impl OscListener {
    pub fn new() -> Self {
        Self {
            debouncer: Arc::new(OscDebouncer::new()),
        }
    }

    pub fn start(&self, port: u16) {
        OSC_RUNNING_FLAG.store(false, Ordering::Relaxed);
        std::thread::sleep(std::time::Duration::from_millis(600)); // wait for old to die
        OSC_RUNNING_FLAG.store(true, Ordering::Relaxed);
        
        let debouncer = self.debouncer.clone();
        let running_flag = OSC_RUNNING_FLAG.clone();
        thread::spawn(move || {
            let addr = format!("0.0.0.0:{}", port);
            let socket = match UdpSocket::bind(&addr) {
                Ok(s) => s,
                Err(e) => {
                    let err_msg = format!("Failed to bind OSC port {}: {}", port, e);
                    println!("{}", err_msg);
                    crate::core::state::GLOBAL_STATE.log(err_msg);
                    return;
                }
            };
            if let Err(e) = socket.set_read_timeout(Some(std::time::Duration::from_millis(500))) {
                println!("Warning: Failed to set read timeout on OSC socket: {}", e);
            }
            crate::core::state::GLOBAL_STATE.log(format!("OSC Listener started on {}", addr));

            let mut buf = [0u8; rosc::decoder::MTU];
            loop {
                if !running_flag.load(Ordering::Relaxed) {
                    crate::core::state::GLOBAL_STATE.log("OSC Listener stopping...".to_string());
                    break;
                }
                match socket.recv_from(&mut buf) {
                    Ok((size, _addr)) => {
                        if let Ok((_, packet)) = rosc::decoder::decode_udp(&buf[..size]) {
                            handle_packet(packet, &debouncer);
                        }
                    }
                    Err(_e) => {
                        // Timeout or other error
                        continue;
                    }
                }
            }
        });
    }
}

fn handle_packet(packet: OscPacket, debouncer: &OscDebouncer) {
    match packet {
        OscPacket::Message(msg) => {
            // Drop if arg <= 0.0 or debounce fails
            let is_trigger = msg.args.iter().any(|arg| match arg {
                rosc::OscType::Float(f) => *f > 0.0,
                rosc::OscType::Int(i) => *i > 0,
                _ => true,
            });
            if !is_trigger { return; }

            if !debouncer.should_process(&msg.addr) {
                return;
            }

            crate::core::state::GLOBAL_STATE.log(format!("Valid OSC Trigger: {}", msg.addr));
            
            // Check Theme Start first without holding lock while calling API
            let (theme_start_info, is_system_reset) = {
                let config_guard = crate::core::state::GLOBAL_STATE.config.read().unwrap_or_else(|e| e.into_inner());
                if let Some(config) = config_guard.as_ref() {
                    let is_ts = !config.theme_start_osc_address.is_empty() && msg.addr == config.theme_start_osc_address;
                    let is_sr = !config.system_reset_osc_address.is_empty() && msg.addr == config.system_reset_osc_address;
                    
                    if is_ts {
                        if let Some(first_room) = config.rooms.first() {
                            let track_ids: Vec<String> = first_room.tracks.iter().filter(|t| t.is_loop).map(|t| t.id.clone()).collect();
                            (Some((first_room.id.clone(), track_ids)), false)
                        } else {
                            (Some((String::new(), vec![])), false)
                        }
                    } else if is_sr {
                        (None, true)
                    } else {
                        (None, false)
                    }
                } else {
                    return;
                }
            };

            if is_system_reset {
                let _ = crate::api::simple::api_stop_all();
                crate::core::state::GLOBAL_STATE.log("OSC Triggered: System Reset".to_string());
                return;
            }

            if let Some(info) = theme_start_info {
                let _ = crate::api::simple::api_stop_all();
                if !info.0.is_empty() {
                    let _ = crate::api::simple::api_set_active_room(Some(info.0.clone()));
                    for track_id in info.1 {
                        let _ = crate::api::simple::api_play_track(info.0.clone(), track_id);
                    }
                }
                return;
            }

            let config_guard = crate::core::state::GLOBAL_STATE.config.read().unwrap_or_else(|e| e.into_inner());
            let config = match config_guard.as_ref() {
                Some(c) => c,
                None => return,
            };

            // Dispatcher logic: map address to config and send command
            let mut matched = false;
            for room in &config.rooms {
                if room.clear_osc_address == msg.addr {
                    // Check Gating
                    {
                        let active = crate::core::state::GLOBAL_STATE.active_room_id.read().unwrap_or_else(|e| e.into_inner());
                        if let Some(ref active_id) = *active {
                            if active_id != &room.id {
                                crate::core::state::GLOBAL_STATE.log(format!("Drop OSC (Clear): {} is not the active room", room.id));
                                continue;
                            }
                        }
                    }

                    crate::core::state::GLOBAL_STATE.clear_playing_tracks();
                    let _ = crate::core::state::GLOBAL_STATE.command_sender.try_send(crate::common::commands::AudioCommand::ClearRoom {
                        room_id: hash_id(&room.id),
                    });
                    
                    // Interlock: auto-promote next room
                    let mut next_room_id = None;
                    let mut found_current = false;
                    for r in &config.rooms {
                        if found_current {
                            next_room_id = Some(r.id.clone());
                            break;
                        }
                        if r.id == room.id {
                            found_current = true;
                        }
                    }
                    if let Some(next_id) = next_room_id {
                        crate::core::state::GLOBAL_STATE.set_active_room(Some(next_id.clone()));
                        crate::core::state::GLOBAL_STATE.log(format!("Interlock: Auto-promoted room {} to active", next_id));
                        // Also auto-play bgm for the next room
                        for next_r in &config.rooms {
                            if next_r.id == next_id {
                                for next_t in &next_r.tracks {
                                    if next_t.is_loop {
                                        let data_opt = {
                                            let cache_guard = crate::core::state::GLOBAL_STATE.sound_cache.read().unwrap_or_else(|e| e.into_inner());
                                            cache_guard.get(&next_t.file_path).cloned()
                                        };
                                        if let Some(data) = data_opt {
                                            let playing = crate::core::state::GLOBAL_STATE.playing_track_ids.read().unwrap_or_else(|e| e.into_inner());
                                            let is_playing = playing.values().any(|id| id == &next_t.id);
                                            drop(playing);
                                            
                                            if !is_playing {
                                                let instance_id = std::time::SystemTime::now()
                                                    .duration_since(std::time::UNIX_EPOCH)
                                                    .unwrap()
                                                    .as_nanos() as u64;
                                                crate::core::state::GLOBAL_STATE.add_playing_track(instance_id, next_t.id.clone());
                                                let _ = crate::core::state::GLOBAL_STATE.command_sender.try_send(crate::common::commands::AudioCommand::PlayTrack {
                                                instance_id,
                                                room_id: hash_id(&next_id),
                                                track_id: hash_id(&next_t.id),
                                                track_id_str: next_t.id.clone(),
                                                data: Some(data.clone()),
                                                stream_receiver: None,
                                                stream_sample_rate: data.sample_rate,
                                                stream_channels: data.channels,
                                                is_loop: next_t.is_loop,
                                                volume: next_t.volume,
                                                output_channel: next_t.output_channel as usize,
                                                output_stereo: next_t.output_stereo,
                                            });
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    } else {
                        crate::core::state::GLOBAL_STATE.set_active_room(None);
                    }
                    
                    matched = true;
                }
                for track in &room.tracks {
                    if track.play_osc_address == msg.addr {
                        // Check Gating
                        {
                            let active = crate::core::state::GLOBAL_STATE.active_room_id.read().unwrap_or_else(|e| e.into_inner());
                            if let Some(ref active_id) = *active {
                                if active_id != &room.id {
                                    crate::core::state::GLOBAL_STATE.log(format!("Drop OSC (Play): {} is not the active room", room.id));
                                    continue;
                                }
                            }
                        }

                        let data_opt = {
                            let cache_guard = crate::core::state::GLOBAL_STATE.sound_cache.read().unwrap_or_else(|e| e.into_inner());
                            cache_guard.get(&track.file_path).cloned()
                        };
                        if let Some(data) = data_opt {
                            let instance_id = std::time::SystemTime::now()
                                .duration_since(std::time::UNIX_EPOCH)
                                .unwrap()
                                .as_nanos() as u64;
                            crate::core::state::GLOBAL_STATE.add_playing_track(instance_id, track.id.clone());
                            let _ = crate::core::state::GLOBAL_STATE.command_sender.try_send(crate::common::commands::AudioCommand::PlayTrack {
                                instance_id,
                                room_id: hash_id(&room.id),
                                track_id: hash_id(&track.id),
                                track_id_str: track.id.clone(),
                                data: Some(data.clone()),
                                stream_receiver: None,
                                stream_sample_rate: data.sample_rate,
                                stream_channels: data.channels,
                                is_loop: track.is_loop,
                                volume: track.volume,
                                output_channel: track.output_channel as usize,
                                output_stereo: track.output_stereo,
                            });
                        } else {
                            crate::core::state::GLOBAL_STATE.log(format!("Cache miss for track file: {}", track.file_path));
                        }
                        matched = true;
                    }
                    if track.stop_osc_address == msg.addr {
                        // Check Gating
                        {
                            let active = crate::core::state::GLOBAL_STATE.active_room_id.read().unwrap_or_else(|e| e.into_inner());
                            if let Some(ref active_id) = *active {
                                if active_id != &room.id {
                                    crate::core::state::GLOBAL_STATE.log(format!("Drop OSC (Stop): {} is not the active room", room.id));
                                    continue;
                                }
                            }
                        }

                        let _ = crate::core::state::GLOBAL_STATE.command_sender.try_send(crate::common::commands::AudioCommand::StopTrack {
                            room_id: hash_id(&room.id),
                            track_id: hash_id(&track.id),
                        });
                        matched = true;
                    }
                }
            }
            if !matched {
                crate::core::state::GLOBAL_STATE.log(format!("No matching track found for OSC address: {}", msg.addr));
            }
        }
        OscPacket::Bundle(bundle) => {
            for packet in bundle.content {
                handle_packet(packet, debouncer);
            }
        }
    }
}
