use std::sync::{Arc, Mutex};
use lazy_static::lazy_static;
use flutter_rust_bridge::frb;
use crate::audio::engine::AudioEngine;
use crate::common::config::{load_config, AppConfig, RoomConfig, TrackConfig};
use crate::osc::listener::OscServer;

lazy_static! {
    static ref AUDIO_ENGINE: Mutex<AudioEngine> = Mutex::new(AudioEngine::new());
    static ref OSC_SERVER: Mutex<OscServer> = Mutex::new(OscServer::new());
}

#[frb(init)]
pub fn init_app() {
    flutter_rust_bridge::setup_default_user_utils();
}

pub fn start_audio_engine() -> Result<(), String> {
    let mut engine = AUDIO_ENGINE.lock().unwrap();
    engine.initialize()
}

pub fn stop_audio_engine() {
    let engine = AUDIO_ENGINE.lock().unwrap();
    engine.stop();
}

pub fn load_app_config(path: String) -> Result<AppConfig, String> {
    load_config(&path)
}

pub fn get_available_devices() -> Vec<String> {
    use cpal::traits::{DeviceTrait, HostTrait};
    let host = cpal::default_host();
    let mut devices = Vec::new();
    if let Ok(devs) = host.output_devices() {
        for d in devs {
            if let Ok(name) = d.name() {
                devices.push(name);
            }
        }
    }
    devices
}

pub fn start_osc_server(port: u16, sink: flutter_rust_bridge::StreamSink<String>) -> Result<(), String> {
    let server = OSC_SERVER.lock().unwrap();
    server.start("0.0.0.0".to_string(), port, move |addr| {
        let _ = sink.add(addr);
    })
}

pub fn stop_osc_server() {
    let server = OSC_SERVER.lock().unwrap();
    server.stop();
}
