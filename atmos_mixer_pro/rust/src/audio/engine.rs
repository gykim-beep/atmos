use cpal::traits::{DeviceTrait, HostTrait, StreamTrait};
use cpal::{Stream, StreamConfig, OutputCallbackInfo, SampleFormat};
use crossbeam_channel::Receiver;
use crate::audio::mixer::AudioMixer;
use crate::common::commands::AudioCommand;

pub struct AudioEngine {
    stream: Option<Stream>,
}

impl Default for AudioEngine {
    fn default() -> Self {
        Self::new()
    }
}

impl AudioEngine {
    pub fn new() -> Self {
        Self {
            stream: None,
        }
    }

    pub fn start(&mut self, device_name: Option<String>, cmd_receiver: Receiver<AudioCommand>) {
        let host = cpal::default_host();
        let device = if let Some(name) = device_name {
            host.output_devices().unwrap().find(|d| d.name().unwrap_or_default() == name).unwrap_or(host.default_output_device().unwrap())
        } else {
            host.default_output_device().unwrap()
        };

        println!("Using output device: {}", device.name().unwrap_or_default());

        let mut supported_configs_range = device.supported_output_configs().unwrap();
        let supported_config = supported_configs_range.next().unwrap().with_max_sample_rate();
        let sample_format = supported_config.sample_format();
        let config: StreamConfig = supported_config.into();

        println!("Stream config: {:?}", config);

        let (gc_tx, gc_rx) = crossbeam_channel::bounded::<crate::audio::player::SoundInstance>(256);
        std::thread::spawn(move || {
            while let Ok(dropped) = gc_rx.recv() {
                // Instance is dropped here in a background thread, preventing GC in audio thread.
                crate::core::state::GLOBAL_STATE.remove_playing_track(dropped.instance_id);
            }
        });

        let mut mixer = AudioMixer::new(config.sample_rate.0, gc_tx);

        let err_fn = |err| eprintln!("an error occurred on stream: {}", err);

        let stream = match sample_format {
            SampleFormat::F32 => {
                device.build_output_stream(
                    &config,
                    move |data: &mut [f32], _: &OutputCallbackInfo| {
                        Self::process_commands(&mut mixer, &cmd_receiver);
                        mixer.process(data, config.channels as usize);
                    },
                    err_fn,
                    None
                )
            },
            _ => panic!("Unsupported format"),
        }.unwrap();

        stream.play().unwrap();
        self.stream = Some(stream);
    }

    fn process_commands(mixer: &mut AudioMixer, rx: &Receiver<AudioCommand>) {
        // Lock-free pop from command queue
        while let Ok(cmd) = rx.try_recv() {
            match cmd {
                AudioCommand::PlayTrack { instance_id, room_id, track_id, track_id_str, data, stream_receiver, stream_sample_rate, stream_channels, is_loop, volume, output_channel, output_stereo } => {
                    let mut instance = crate::audio::player::SoundInstance::new(
                        instance_id,
                        track_id,
                        room_id,
                        track_id_str,
                        data,
                        stream_receiver,
                        stream_sample_rate,
                        stream_channels,
                        is_loop,
                        volume,
                        output_channel,
                        output_stereo,
                    );
                    instance.volume = volume;
                    if let Some(slot) = mixer.instances.iter_mut().find(|s| s.is_none()) {
                        if let Some(old) = slot.replace(instance) {
                            let _ = mixer.gc_sender.try_send(old);
                        }
                    } else {
                        eprintln!("Mixer object pool full!");
                    }
                }
                AudioCommand::StopTrack { room_id, track_id } => {
                    for inst in mixer.instances.iter_mut().flatten() {
                        if inst.room_id == room_id && inst.id == track_id {
                            inst.is_stopping = true;
                        }
                    }
                }
                AudioCommand::StopAll => {
                    for inst in mixer.instances.iter_mut().flatten() {
                        inst.is_stopping = true;
                    }
                }
                AudioCommand::ClearRoom { room_id } => {
                    for inst in mixer.instances.iter_mut().flatten() {
                        if inst.room_id == room_id {
                            inst.is_stopping = true;
                        }
                    }
                }
                AudioCommand::SetTrackVolume { room_id, track_id, volume } => {
                    for inst in mixer.instances.iter_mut().flatten() {
                        if inst.room_id == room_id && inst.id == track_id {
                            inst.volume = volume;
                        }
                    }
                }
                _ => {}
            }
        }
    }
}
