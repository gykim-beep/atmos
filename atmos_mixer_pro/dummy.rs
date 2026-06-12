                let idx_f = instance.cursor as f32 * step;
                let idx_base = idx_f as usize;
                let frac = idx_f - (idx_base as f32);
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
                            if let Ok(new_chunk) = stream_rx.try_recv() {
                                let old_chunk = std::mem::replace(&mut instance.stream_buffer, new_chunk);
                                let _ = self.buf_gc_tx.try_send(old_chunk);
                                instance.cursor = 0;
                                // Recalculate idx_i for new buffer
                                idx_i = 0;
                            }
                        }
                        
                        if idx_i < instance.stream_buffer.len() {
                            let (l1, r1) = get_sample(&instance.stream_buffer, idx_i, channels);
                            let (l2, r2) = if idx_i + channels < instance.stream_buffer.len() {
                                get_sample(&instance.stream_buffer, idx_i + channels, channels)
                            } else {
                                (l1, r1) // Can't easily interpolate across stream boundaries without state, fallback to nearest
                            };
                            
                            val_l = l1 + frac * (l2 - l1);
                            val_r = r1 + frac * (r2 - r1);
                            has_sample = true;
                        }
                    }
                } else if let Some(data) = &instance.data {
                    if idx_i < data.samples.len() {
                        let (l1, r1) = get_sample(&data.samples, idx_i, channels);
                        let mut next_idx = idx_i + channels;
                        if next_idx >= data.samples.len() && instance.is_loop {
                            next_idx = 0; // Wrap around for interpolation
                        }
                        
                        let (l2, r2) = get_sample(&data.samples, next_idx, channels);
                        
                        val_l = l1 + frac * (l2 - l1);
                        val_r = r1 + frac * (r2 - r1);
                        has_sample = true;
                    } else if instance.is_loop {
                        instance.cursor = 0;
                        idx_i = 0;
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
