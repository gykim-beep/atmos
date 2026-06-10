use std::collections::HashMap;
use std::time::{Duration, Instant};

pub struct OscDebouncer {
    last_triggers: HashMap<String, Instant>,
    gate_time: Duration,
}

impl OscDebouncer {
    pub fn new(gate_millis: u64) -> Self {
        Self {
            last_triggers: HashMap::new(),
            gate_time: Duration::from_millis(gate_millis),
        }
    }

    pub fn should_allow(&mut self, address: &str, file: &str) -> bool {
        let key = format!("{}:{}", address, file);
        let now = Instant::now();
        
        if let Some(&last_time) = self.last_triggers.get(&key) {
            if now.duration_since(last_time) < self.gate_time {
                return false;
            }
        }
        
        self.last_triggers.insert(key, now);
        true
    }
}
