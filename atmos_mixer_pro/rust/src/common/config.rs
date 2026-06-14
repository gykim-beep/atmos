use serde::{Deserialize, Serialize};
use std::fs;
use std::path::Path;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AppConfig {
    pub osc_port: u16,
    pub device_name: Option<String>,
    pub buffer_size: u32,
    #[serde(default)]
    pub theme_start_osc_address: String,
    #[serde(default)]
    pub system_reset_osc_address: String,
    #[serde(default)]
    pub rooms: Vec<RoomConfig>,
}

impl Default for AppConfig {
    fn default() -> Self {
        Self {
            osc_port: 8000,
            device_name: None,
            buffer_size: 256,
            theme_start_osc_address: String::new(),
            system_reset_osc_address: String::new(),
            rooms: Vec::new(),
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RoomConfig {
    pub id: String,
    pub name: String,
    pub color_hex: String,
    pub volume: f32, // 0.0 to 1.0
    #[serde(default)]
    pub clear_osc_address: String,
    #[serde(default)]
    pub tracks: Vec<TrackConfig>,
}

fn default_true() -> bool { true }

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TrackConfig {
    pub id: String,
    pub name: String,
    pub file_path: String,
    pub volume: f32, // 0.0 to 1.0
    pub is_loop: bool, // true = BGM, false = SFX
    pub output_channel: u32, // 1 to 24 (1-indexed for user, mapped to 0-23 internally)
    #[serde(default = "default_true")]
    pub output_stereo: bool,
    #[serde(default)]
    pub play_osc_address: String,
    #[serde(default)]
    pub stop_osc_address: String,
}

impl AppConfig {
    pub fn load_from_file<P: AsRef<Path>>(path: P) -> anyhow::Result<Self> {
        let path = path.as_ref();
        if !path.exists() {
            // 파일이 없으면 기본값으로 생성
            let default_config = Self::default();
            default_config.save_to_file(path)?;
            return Ok(default_config);
        }
        let content = fs::read_to_string(path)?;
        match serde_json::from_str(&content) {
            Ok(config) => Ok(config),
            Err(e) => {
                let backup_path = path.with_extension("corrupted.json");
                let _ = fs::copy(path, backup_path);
                Err(e.into())
            }
        }
    }

    pub fn save_to_file<P: AsRef<Path>>(&self, path: P) -> anyhow::Result<()> {
        let content = serde_json::to_string_pretty(self)?;
        // 부모 디렉토리가 없으면 생성
        let path_ref = path.as_ref();
        if let Some(parent) = path_ref.parent() {
            fs::create_dir_all(parent)?;
        }
        
        // 원자적 쓰기(Atomic Write) 적용: tmp에 먼저 쓰고 rename (OS 수준 안전 보장)
        let tmp_path = path_ref.with_extension("tmp");
        fs::write(&tmp_path, content)?;
        fs::rename(&tmp_path, path_ref)?;
        
        Ok(())
    }
}
