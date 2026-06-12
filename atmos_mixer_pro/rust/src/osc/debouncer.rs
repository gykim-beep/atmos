use std::collections::HashMap;
use std::time::{Duration, Instant};
use std::sync::Mutex;

const DEBOUNCE_MS: u64 = 250;

pub struct OscDebouncer {
    last_triggers: Mutex<HashMap<String, Instant>>,
}

impl Default for OscDebouncer {
    fn default() -> Self {
        Self::new()
    }
}

impl OscDebouncer {
    pub fn new() -> Self {
        Self {
            last_triggers: Mutex::new(HashMap::new()),
        }
    }

    pub fn should_process(&self, address: &str) -> bool {
        let mut map = self.last_triggers.lock().unwrap();
        let now = Instant::now();
        if let Some(&last_time) = map.get(address) {
            if now.duration_since(last_time) < Duration::from_millis(DEBOUNCE_MS) {
                return false; // Drop it
            }
        }
        map.insert(address.to_string(), now);
        true
    }
}
