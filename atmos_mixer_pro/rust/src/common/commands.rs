use crate::audio::player::SoundInstance;

pub enum AudioCommand {
    PlayInstance(SoundInstance),
    StopRoom {
        channels: Vec<usize>,
        fade_out_sec: f32,
    },
    SetChannelVolume {
        channel: usize,
        volume: f32,
    },
    SetRoomVolume {
        room_id: usize,
        volume: f32,
    },
    SetMasterVolume {
        volume: f32,
    },
}
