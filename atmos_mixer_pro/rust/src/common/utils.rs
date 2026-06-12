use std::collections::hash_map::DefaultHasher;
use std::hash::{Hash, Hasher};

pub fn hash_id(id: &str) -> u32 {
    let mut hasher = DefaultHasher::new();
    id.hash(&mut hasher);
    hasher.finish() as u32
}
