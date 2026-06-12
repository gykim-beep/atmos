#[derive(Debug, Clone)]
pub struct AtmosError {
    pub message: String,
}

impl std::fmt::Display for AtmosError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "AtmosError: {}", self.message)
    }
}

impl std::error::Error for AtmosError {}

impl From<anyhow::Error> for AtmosError {
    fn from(err: anyhow::Error) -> Self {
        Self {
            message: err.to_string(),
        }
    }
}

impl From<std::io::Error> for AtmosError {
    fn from(err: std::io::Error) -> Self {
        Self {
            message: err.to_string(),
        }
    }
}
