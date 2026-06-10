use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::fs::File;
use std::io::Read;

#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct TrackConfig {
    #[serde(default)]
    pub file: String,
    #[serde(default)]
    pub output_ch: usize,
    #[serde(default = "default_volume")]
    pub volume: f32,
    #[serde(default)]
    pub is_bgm: bool,
    #[serde(default)]
    pub loop_play: bool,
    #[serde(default)]
    pub osc_play: String,
    #[serde(default)]
    pub osc_stop: String,
}

fn default_volume() -> f32 { 0.75 }

#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct RoomConfig {
    #[serde(default)]
    pub id: usize,
    #[serde(default)]
    pub name: String,
    #[serde(default = "default_master_volume")]
    pub master_volume: f32,
    #[serde(default)]
    pub osc_clear: String,
    #[serde(default)]
    pub tracks: Vec<TrackConfig>,
}

fn default_master_volume() -> f32 { 1.0 }

#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct AppConfig {
    #[serde(default)]
    pub audio_device: HashMap<String, String>,
    #[serde(default = "default_osc")]
    pub osc: OscConfig,
    #[serde(default)]
    pub rooms: Vec<RoomConfig>,
}

#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct OscConfig {
    pub host: String,
    pub port: u16,
}

fn default_osc() -> OscConfig {
    OscConfig { host: "0.0.0.0".to_string(), port: 8000 }
}

pub fn load_config(path: &str) -> Result<AppConfig, String> {
    let mut file = File::open(path).map_err(|e| format!("Failed to open config file: {}", e))?;
    let mut contents = String::new();
    file.read_to_string(&mut contents).map_err(|e| format!("Failed to read config file: {}", e))?;
    
    let config: AppConfig = serde_json::from_str(&contents).map_err(|e| format!("Failed to parse config: {}", e))?;
    Ok(config)
}
