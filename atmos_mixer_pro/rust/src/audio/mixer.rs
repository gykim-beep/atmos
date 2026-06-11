use crate::audio::player::SoundInstance;

const DUCK_GAIN: f32 = 0.30;

pub struct AudioMixer;

impl AudioMixer {
    pub fn process_buffer(
        buffer: &mut [f32],
        num_channels: usize,
        instances: &mut Vec<SoundInstance>,
        sfx_active: &mut usize,
        _active_room_id: usize,
        sample_rate: u32,
    ) {
        for sample in buffer.iter_mut() {
            *sample = 0.0;
        }

        let frames = buffer.len() / num_channels;
        let mut newly_finished_sfx = Vec::new();

        for inst in instances.iter_mut() {
            if inst.is_marked_for_removal {
                continue;
            }
            if inst.output_ch >= num_channels {
                continue;
            }
            
            // Ducking fade
            if inst.duck_fade_left > 0 {
                let adv = frames.min(inst.duck_fade_left);
                inst.duck_fade_left -= adv;
                let progress = if inst.duck_fade_total > 0 {
                    1.0 - (inst.duck_fade_left as f32 / inst.duck_fade_total as f32)
                } else {
                    1.0
                };
                inst.duck_gain = inst.duck_start_gain + (inst.duck_target - inst.duck_start_gain) * progress;
                if inst.duck_fade_left == 0 {
                    inst.duck_gain = inst.duck_target;
                }
            } else if inst.is_bgm {
                // If we are a BGM, we check sfx_active and transition if needed
                if *sfx_active > 0 && inst.duck_target != DUCK_GAIN {
                    // Start ducking down (150ms)
                    inst.duck_target = DUCK_GAIN;
                    inst.duck_start_gain = inst.duck_gain;
                    let duck_len = (sample_rate as f32 * 0.15) as usize; // 150ms
                    inst.duck_fade_total = duck_len;
                    inst.duck_fade_left = duck_len;
                } else if *sfx_active == 0 && inst.duck_target != 1.0 {
                    // Start ducking up (300ms)
                    inst.duck_target = 1.0;
                    inst.duck_start_gain = inst.duck_gain;
                    let duck_len = (sample_rate as f32 * 0.3) as usize; // 300ms
                    inst.duck_fade_total = duck_len;
                    inst.duck_fade_left = duck_len;
                }
            }

            // Play fade
            if inst.play_fade_left > 0 {
                let adv = frames.min(inst.play_fade_left);
                inst.play_fade_left -= adv;
                let progress = if inst.play_fade_total > 0 {
                    1.0 - (inst.play_fade_left as f32 / inst.play_fade_total as f32)
                } else {
                    1.0
                };
                inst.play_fade_gain = inst.play_fade_start + (inst.play_fade_target - inst.play_fade_start) * progress;
                if inst.play_fade_left == 0 {
                    inst.play_fade_gain = inst.play_fade_target;
                    if inst.play_fade_target <= 0.0 {
                        inst.is_marked_for_removal = true;
                        if !inst.is_bgm {
                            newly_finished_sfx.push(inst.id.clone());
                        }
                        continue;
                    }
                }
            }

            let data_len = inst.data.samples.len() / inst.data.channels as usize;
            let end = inst.position + frames;
            let mut chunk = vec![0.0; frames];

            if end <= data_len {
                let start_idx = inst.position * inst.data.channels as usize;
                for i in 0..frames {
                    chunk[i] = inst.data.samples[start_idx + i * inst.data.channels as usize];
                }
                
                inst.position = end;
                if end == data_len {
                    if inst.loop_play {
                        inst.position = 0;
                    } else {
                        inst.is_marked_for_removal = true;
                        if !inst.is_bgm {
                            newly_finished_sfx.push(inst.id.clone());
                        }
                    }
                }
            } else {
                let avail = data_len.saturating_sub(inst.position);
                if avail > 0 {
                    let start_idx = inst.position * inst.data.channels as usize;
                    for i in 0..avail {
                        chunk[i] = inst.data.samples[start_idx + i * inst.data.channels as usize];
                    }
                }
                if inst.loop_play {
                    let need = frames.saturating_sub(avail);
                    for i in 0..need {
                        if i * (inst.data.channels as usize) < inst.data.samples.len() {
                             chunk[avail + i] = inst.data.samples[i * (inst.data.channels as usize)];
                        }
                    }
                    inst.position = need;
                } else {
                    inst.is_marked_for_removal = true;
                    if !inst.is_bgm {
                        newly_finished_sfx.push(inst.id.clone());
                    }
                }
            }

            let duck = inst.duck_gain;

            let gain = inst.volume * duck * inst.room_volume * inst.play_fade_gain;
            
            for i in 0..frames {
                buffer[i * num_channels + inst.output_ch] += chunk[i] * gain;
            }
        }
        
        instances.retain(|inst| !inst.is_marked_for_removal);

        *sfx_active = sfx_active.saturating_sub(newly_finished_sfx.len());

        // Soft clip
        for sample in buffer.iter_mut() {
            *sample = sample.tanh();
        }
    }
}
