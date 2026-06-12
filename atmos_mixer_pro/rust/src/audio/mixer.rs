use crate::audio::player::SoundInstance;
use crate::core::state::GLOBAL_STATE;
use std::sync::atomic::Ordering;

pub struct DuckingState {
    pub is_ducking: bool,
    pub ducking_weight: f32, // 1.0 down to 0.3
}

pub struct AudioMixer {
    pub instances: Vec<Option<SoundInstance>>, // Fixed capacity object pool
    pub sample_rate: u32,
    pub ducking: DuckingState,
    pub gc_sender: crossbeam_channel::Sender<SoundInstance>,
    pub buf_gc_tx: crossbeam_channel::Sender<Vec<f32>>,
}

impl AudioMixer {
    pub fn new(sample_rate: u32, gc_sender: crossbeam_channel::Sender<SoundInstance>) -> Self {
        let (buf_gc_tx, buf_gc_rx) = crossbeam_channel::bounded::<Vec<f32>>(1024);
        std::thread::spawn(move || {
            while let Ok(_buf) = buf_gc_rx.recv() {
                // Buffer is dropped here in a background thread, preventing heap deallocation in the audio thread
            }
        });

        let mut instances = Vec::with_capacity(256);
        for _ in 0..256 {
            instances.push(None);
        }
        Self {
            instances,
            sample_rate,
            ducking: DuckingState {
                is_ducking: false,
                ducking_weight: 1.0,
            },
            gc_sender,
            buf_gc_tx,
        }
    }

    pub fn process(&mut self, output: &mut [f32], out_channels: usize) {
        // Clear output buffer
        for sample in output.iter_mut() {
            *sample = 0.0;
        }

        let frames = output.len() / out_channels;
        
        let fade_frames = (self.sample_rate as f32 * 0.3) as usize; // 300ms fade
        let duck_down_frames = (self.sample_rate as f32 * 0.15) as usize; // 150ms duck down
        let duck_up_frames = (self.sample_rate as f32 * 0.3) as usize; // 300ms duck up

        // Check if any SFX is playing (not loop)
        let has_sfx = self.instances.iter().any(|inst| {
            if let Some(inst) = inst {
                !inst.is_loop && inst.is_playing && !inst.is_stopping
            } else {
                false
            }
        });

        if has_sfx && !self.ducking.is_ducking {
            self.ducking.is_ducking = true;
        } else if !has_sfx && self.ducking.is_ducking && self.ducking.ducking_weight <= 0.3 {
            self.ducking.is_ducking = false; // Start unducking
        }

        for frame in 0..frames {
            // Update ducking weight per frame
            if self.ducking.is_ducking {
                if self.ducking.ducking_weight > 0.3 {
                    self.ducking.ducking_weight -= 0.7 / duck_down_frames as f32;
                }
                if self.ducking.ducking_weight < 0.3 {
                    self.ducking.ducking_weight = 0.3;
                }
            } else {
                if self.ducking.ducking_weight < 1.0 {
                    self.ducking.ducking_weight += 0.7 / duck_up_frames as f32;
                }
                if self.ducking.ducking_weight > 1.0 {
                    self.ducking.ducking_weight = 1.0;
                }
            }

            for instance in self.instances.iter_mut().flatten() {
                if !instance.is_playing {
                    continue;
                }

                // Update fade weight
                if instance.is_stopping {
                    instance.fade_weight -= 1.0 / fade_frames as f32;
                    if instance.fade_weight <= 0.0 {
                        instance.fade_weight = 0.0;
                        instance.is_playing = false;
                        continue;
                    }
                } else {
                    instance.fade_weight += 1.0 / fade_frames as f32;
                    if instance.fade_weight > 1.0 {
                        instance.fade_weight = 1.0;
                    }
                }

                let mut current_vol = instance.volume * instance.fade_weight;
                if instance.is_loop {
                    current_vol *= self.ducking.ducking_weight; // Ducking only affects BGM
                }

                let step = instance.stream_sample_rate as f32 / self.sample_rate as f32;
                
                let channels = if let Some(data) = &instance.data {
                    data.channels as usize
                } else {
                    2 // Assume BGM stream is stereo
                };

                let idx_f = instance.cursor as f32 * step;
                let mut idx_i = (idx_f as usize) * channels;

                let mut val_l = 0.0;
                let mut val_r = 0.0;
                let mut has_sample = false;

                if let Some(stream_rx) = &instance.stream_receiver {
                    if instance.is_loop {
                        if idx_i >= instance.stream_buffer.len() {
                            if let Ok(new_chunk) = stream_rx.try_recv() {
                                let old_chunk = std::mem::replace(&mut instance.stream_buffer, new_chunk);
                                let _ = self.buf_gc_tx.try_send(old_chunk);
                                instance.cursor = 0;
                                idx_i = 0;
                            }
                        }
                        
                        if idx_i + 1 < instance.stream_buffer.len() {
                            val_l = instance.stream_buffer[idx_i];
                            val_r = instance.stream_buffer[idx_i + 1];
                            has_sample = true;
                        } else if idx_i < instance.stream_buffer.len() {
                            val_l = instance.stream_buffer[idx_i];
                            val_r = val_l; // Fallback to mono if odd length
                            has_sample = true;
                        }
                    }
                } else if let Some(data) = &instance.data {
                    if idx_i + 1 < data.samples.len() {
                        val_l = data.samples[idx_i];
                        if channels > 1 {
                            val_r = data.samples[idx_i + 1];
                        } else {
                            val_r = val_l;
                        }
                        has_sample = true;
                    } else if instance.is_loop {
                        instance.cursor = 0;
                        idx_i = 0;
                        if idx_i + 1 < data.samples.len() {
                            val_l = data.samples[idx_i];
                            if channels > 1 {
                                val_r = data.samples[idx_i + 1];
                            } else {
                                val_r = val_l;
                            }
                            has_sample = true;
                        }
                    }
                }

                if has_sample {
                    if instance.output_stereo {
                        let out_idx_l = frame * out_channels + instance.output_channel;
                        if out_idx_l < output.len() {
                            output[out_idx_l] += val_l * current_vol; 
                        }
                        
                        let out_idx_r = frame * out_channels + instance.output_channel + 1;
                        // Prevent out of bounds if output_channel was the last one
                        if out_idx_r < output.len() && (instance.output_channel + 1 < out_channels) {
                            output[out_idx_r] += val_r * current_vol;
                        } else if out_idx_l < output.len() {
                            // Mix right channel into left if right channel is out of bounds for current device
                            output[out_idx_l] += val_r * current_vol;
                        }
                    } else {
                        // Mix down to mono
                        let mono_val = (val_l + val_r) * 0.5;
                        let out_idx = frame * out_channels + instance.output_channel;
                        if out_idx < output.len() {
                            output[out_idx] += mono_val * current_vol;
                        }
                    }

                    instance.cursor += 1;
                } else {
                    instance.is_stopping = true;
                }
            }
        }

        // Compute VU levels (Peak per channel)
        for ch in 0..out_channels {
            if ch >= 64 { break; }
            let mut peak: f32 = 0.0;
            for frame in 0..frames {
                let sample_idx = frame * out_channels + ch;
                if sample_idx < output.len() {
                    let val = output[sample_idx].abs();
                    if val > peak {
                        peak = val;
                    }
                }
            }
            
            // Simple decay or hold (just raw peak for now, flutter side can smooth it)
            GLOBAL_STATE.vu_levels[ch].store(peak.to_bits(), Ordering::Relaxed);
        }

        // Soft clipping using pseudo-tanh
        for sample in output.iter_mut() {
            let x = *sample;
            // fast approximation of tanh to avoid expensive float math
            let x2 = x * x;
            *sample = x * (27.0 + x2) / (27.0 + 9.0 * x2);
        }

        // Remove stopped instances by moving to GC thread (heap-free drop)
        for slot in self.instances.iter_mut() {
            if let Some(inst) = slot {
                if !inst.is_playing {
                    if let Some(old) = slot.take() {
                        let _ = self.gc_sender.try_send(old);
                    }
                }
            }
        }
    }
}
