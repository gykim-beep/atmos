use cpal::traits::{DeviceTrait, HostTrait, StreamTrait};
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
        
        let mut instances = Vec::new(); // In a real scenario, this needs to be shared or sent via channel
        let mut sfx_active = 0;
        
        let stream = device.build_output_stream(
            &config,
            move |data: &mut [f32], _: &cpal::OutputCallbackInfo| {
                AudioMixer::process_buffer(
                    data, 
                    config.channels as usize, 
                    &mut instances,
                    &mut sfx_active,
                    1
                );
            },
            |err| eprintln!("Stream error: {}", err),
            None
        ).map_err(|e| e.to_string())?;
        
        stream.play().map_err(|e| e.to_string())?;
        
        let mut state = self.manager.state.lock().unwrap();
        state.stream = Some(SendStream(stream));
        
        Ok(())
    }

    pub fn stop(&self) {
        let mut state = self.manager.state.lock().unwrap();
        state.stream = None; 
    }
}
