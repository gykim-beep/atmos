use cpal::traits::{DeviceTrait, HostTrait, StreamTrait};
use std::sync::Arc;
use crossbeam_channel::unbounded;
use std::sync::Arc;
use crate::core::state::{EngineManager, SendStream};
use crate::audio::mixer::AudioMixer;
use crate::audio::player::SoundInstance;

pub struct AudioEngine {
    pub manager: Arc<EngineManager>,
    instances: Vec<SoundInstance>,
    sfx_active: usize,
}

impl AudioEngine {
    pub fn new() -> Self {
        Self {
            manager: Arc::new(EngineManager::new()),
            instances: Vec::new(),
            sfx_active: 0,
        }
    }

    pub fn initialize(&mut self) -> Result<(), String> {
        let host = cpal::default_host();
        let device = host.default_output_device().ok_or("No default output device")?;
        
        let config = device.default_output_config().map_err(|e| e.to_string())?.config();
        let sample_rate = config.sample_rate.0;
        
        let (cmd_tx, cmd_rx) = unbounded::<crate::common::commands::AudioCommand>();
        
        let mut instances = Vec::new();
        let mut sfx_active = 0;
        let mut active_room_id = 1;
        
        let stream = device.build_output_stream(
            &config,
            move |data: &mut [f32], _: &cpal::OutputCallbackInfo| {
                // Process incoming commands
                while let Ok(cmd) = cmd_rx.try_recv() {
                    match cmd {
                        crate::common::commands::AudioCommand::PlayInstance(mut inst) => {
                            let fade_len = (sample_rate as f32 * 0.3) as usize; // 300ms fade in
                            inst.play_fade_gain = 0.0;
                            inst.play_fade_target = 1.0;
                            inst.play_fade_start = 0.0;
                            inst.play_fade_total = fade_len;
                            inst.play_fade_left = fade_len;
                            
                            inst.duck_gain = 1.0;
                            inst.duck_target = 1.0;
                            inst.duck_start_gain = 1.0;
                            
                            if !inst.is_bgm {
                                sfx_active += 1;
                            }
                            
                            instances.push(inst);
                        }
                        crate::common::commands::AudioCommand::StopRoom { channels, fade_out_sec: _ } => {
                            let fade_len = (sample_rate as f32 * 0.3) as usize; // 300ms fade out
                            for inst in instances.iter_mut() {
                                if channels.contains(&inst.output_ch) {
                                    inst.play_fade_target = 0.0;
                                    inst.play_fade_start = inst.play_fade_gain;
                                    inst.play_fade_total = fade_len;
                                    inst.play_fade_left = fade_len;
                                }
                            }
                        }
                        crate::common::commands::AudioCommand::SetChannelVolume { channel, volume } => {
                            for inst in instances.iter_mut() {
                                if inst.output_ch == channel {
                                    inst.volume = volume;
                                }
                            }
                        }
                        crate::common::commands::AudioCommand::SetRoomVolume { room_id: _, volume } => {
                            // Needs mapping from room_id to instances, or we keep a mapping of channel to room_id
                            // Simplified for now: assume room volume can be set directly on instance or we don't use it yet
                        }
                        crate::common::commands::AudioCommand::SetMasterVolume { volume: _ } => {}
                    }
                }
                
                AudioMixer::process_buffer(
                    data, 
                    config.channels as usize, 
                    &mut instances,
                    &mut sfx_active,
                    active_room_id,
                    sample_rate
                );
            },
            |err| eprintln!("Stream error: {}", err),
            None
        ).map_err(|e| e.to_string())?;
        
        stream.play().map_err(|e| e.to_string())?;
        
        let mut state = self.manager.state.lock().unwrap();
        state.stream = Some(SendStream(stream));
        state.cmd_tx = Some(cmd_tx);
        
        Ok(())
    }

    pub fn stop(&self) {
        let mut state = self.manager.state.lock().unwrap();
        state.stream = None; 
    }
}
