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
        if out_channels == 0 || output.is_empty() {
            return;
        }
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

                let step = instance.stream_sample_rate as f64 / self.sample_rate as f64;
                
                let channels = (instance.stream_channels as usize).max(1);

                let mut idx_f = instance.cursor;
                let mut idx_base = idx_f as usize;
                let mut frac = (idx_f - (idx_base as f64)) as f32;
                let mut idx_i = idx_base * channels;

                let mut val_l = 0.0;
                let mut val_r = 0.0;
                let mut has_sample = false;

                let get_sample = |buf: &[f32], idx: usize, chs: usize| -> (f32, f32) {
                    if idx < buf.len() {
                        let l = buf[idx];
                        let r = if chs > 1 && idx + 1 < buf.len() { buf[idx + 1] } else { l };
                        (l, r)
                    } else {
                        (0.0, 0.0)
                    }
                };

                if let Some(stream_rx) = &instance.stream_receiver {
                    if instance.is_loop {
                        if idx_i >= instance.stream_buffer.len() {
                            match stream_rx.try_recv() {
                                Ok(new_chunk) => {
                                    let frames_in_chunk = if instance.stream_buffer.is_empty() {
                                        0.0
                                    } else {
                                        (instance.stream_buffer.len() / channels) as f64
                                    };
                                    let old_chunk = std::mem::replace(&mut instance.stream_buffer, new_chunk);
                                    let _ = self.buf_gc_tx.try_send(old_chunk);
                                    
                                    instance.cursor -= frames_in_chunk;
                                    if instance.cursor < 0.0 { instance.cursor = 0.0; } // safety bound
                                    idx_f = instance.cursor;
                                    idx_base = idx_f as usize;
                                    frac = (idx_f - (idx_base as f64)) as f32;
                                    idx_i = idx_base * channels;
                                }
                                Err(crossbeam_channel::TryRecvError::Disconnected) => {
                                    // Stream finished or errored permanently
                                    instance.is_stopping = true;
                                }
                                Err(crossbeam_channel::TryRecvError::Empty) => {
                                    // Stream is lagging, just output silence and don't advance cursor
                                }
                            }
                        }
                        
                        if idx_i < instance.stream_buffer.len() {
                            let (l1, r1) = get_sample(&instance.stream_buffer, idx_i, channels);
                            let (l2, r2) = if idx_i + channels < instance.stream_buffer.len() {
                                get_sample(&instance.stream_buffer, idx_i + channels, channels)
                            } else {
                                (l1, r1) // In future, peek into next chunk. For now, flat end.
                            };
                            
                            val_l = l1 + frac * (l2 - l1);
                            val_r = r1 + frac * (r2 - r1);
                            has_sample = true;
                        } else {
                            // Buffer is empty but stream is not disconnected.
                            // We treat it as having a silent sample to keep the track alive.
                            val_l = 0.0;
                            val_r = 0.0;
                            has_sample = true; 
                            // But we shouldn't advance the cursor! So we need a way to tell the mixer not to advance.
                            // We'll set a flag or just handle it below.
                        }
                    }
                } else if let Some(data) = &instance.data {
                    if idx_i < data.samples.len() {
                        let (l1, r1) = get_sample(&data.samples, idx_i, channels);
                        let mut next_idx = idx_i + channels;
                        if next_idx >= data.samples.len() && instance.is_loop {
                            next_idx = 0;
                        }
                        
                        let (l2, r2) = get_sample(&data.samples, next_idx, channels);
                        
                        val_l = l1 + frac * (l2 - l1);
                        val_r = r1 + frac * (r2 - r1);
                        has_sample = true;
                    } else if instance.is_loop {
                        let frames_in_data = (data.samples.len() / channels) as f64;
                        instance.cursor -= frames_in_data;
                        if instance.cursor < 0.0 { instance.cursor = 0.0; }
                        
                        idx_f = instance.cursor;
                        idx_base = idx_f as usize;
                        frac = (idx_f - (idx_base as f64)) as f32;
                        idx_i = idx_base * channels;

                        if idx_i < data.samples.len() {
                            let (l1, r1) = get_sample(&data.samples, idx_i, channels);
                            let mut next_idx = idx_i + channels;
                            if next_idx >= data.samples.len() {
                                next_idx = 0;
                            }
                            let (l2, r2) = get_sample(&data.samples, next_idx, channels);
                            
                            val_l = l1 + frac * (l2 - l1);
                            val_r = r1 + frac * (r2 - r1);
                            has_sample = true;
                        }
                    }
                }

                if has_sample {
                    if instance.output_channel < out_channels {
                        if instance.output_stereo {
                            let out_idx_l = frame * out_channels + instance.output_channel;
                            let mut wrote_r = false;
                            
                            if out_idx_l < output.len() {
                                output[out_idx_l] += val_l * current_vol; 
                            }
                            
                            if instance.output_channel + 1 < out_channels {
                                let out_idx_r = out_idx_l + 1;
                                if out_idx_r < output.len() {
                                    output[out_idx_r] += val_r * current_vol;
                                    wrote_r = true;
                                }
                            }
                            
                            if !wrote_r && out_idx_l < output.len() {
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
                    }

                    if instance.stream_receiver.is_some() && idx_i >= instance.stream_buffer.len() {
                        // Buffer is empty, stream is lagging. Don't advance cursor.
                    } else {
                        instance.cursor += step;
                    }
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

        // Soft clipping (Cubic) to prevent integer overflow and harsh distortion at DAC
        for sample in output.iter_mut() {
            let x = *sample;
            if x <= -1.0 {
                *sample = -1.0;
            } else if x >= 1.0 {
                *sample = 1.0;
            } else {
                *sample = 1.5 * x - 0.5 * x * x * x;
            }
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
