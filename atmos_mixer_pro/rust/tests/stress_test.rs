use rust_lib_atmos_mixer_pro::api::simple::*;
use rust_lib_atmos_mixer_pro::core::state::GLOBAL_STATE;
use rust_lib_atmos_mixer_pro::common::commands::AudioCommand;
use std::thread;
use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::Arc;
use std::time::Duration;

#[test]
fn test_room_clear_spam_no_duplicate() {
    println!("Starting room clear spam stress test...");
    
    // Clear global state first
    api_stop_all().unwrap();
    
    let play_count = Arc::new(AtomicUsize::new(0));
    
    // Dummy command receiver consumer
    let rx = GLOBAL_STATE.command_receiver.clone();
    let play_count_clone = play_count.clone();
    thread::spawn(move || {
        while let Ok(cmd) = rx.recv() {
            if let AudioCommand::PlayTrack { track_id_str, .. } = cmd {
                if track_id_str == "next_bgm_track" {
                    play_count_clone.fetch_add(1, Ordering::SeqCst);
                }
            }
        }
    });

    // Simulate OSC listener loop processing 10 "clear room" messages back-to-back very quickly
    // In actual app, OSC listener is a single thread reading from socket.
    for _ in 0..10 {
        // Simulating the exact logic from listener.rs when ClearRoom is received
        let next_track_id = "next_bgm_track".to_string();
        
        let playing = GLOBAL_STATE.playing_track_ids.read().unwrap();
        let is_playing = playing.values().any(|id| id == &next_track_id);
        drop(playing);
        
        if !is_playing {
            let instance_id = std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap()
                .as_nanos() as u64;
            GLOBAL_STATE.add_playing_track(instance_id, next_track_id.clone());
            let _ = GLOBAL_STATE.command_sender.try_send(AudioCommand::PlayTrack {
                instance_id,
                room_id: rust_lib_atmos_mixer_pro::common::utils::hash_id("next_room"),
                track_id: rust_lib_atmos_mixer_pro::common::utils::hash_id(&next_track_id),
                track_id_str: next_track_id,
                data: None,
                stream_receiver: None,
                stream_sample_rate: 44100,
                stream_channels: 2,
                is_loop: true,
                volume: 1.0,
                output_channel: 0,
                output_stereo: true,
            });
        }
    }
    
    // Give consumer a little time
    thread::sleep(Duration::from_millis(50));
    
    let count = play_count.load(Ordering::SeqCst);
    println!("BGM Play Track count after 10 clear room spams: {}", count);
    assert_eq!(count, 1, "Duplicate BGM playback detected! Expected 1, got {}", count);
    println!("Room clear spam stress test PASSED.");
}

#[test]
fn test_system_reset_theme_start_glitch() {
    println!("Starting system reset vs theme start glitch stress test...");
    
    let rx = GLOBAL_STATE.command_receiver.clone();
    thread::spawn(move || {
        while let Ok(_) = rx.recv() {} // drain commands
    });

    let num_iterations = 1000;
    
    let t1 = thread::spawn(move || {
        for i in 0..num_iterations {
            // Theme Start simulation: Set active room + Play Track
            let _ = api_set_active_room(Some("room_1".to_string()));
            // In real scenario, it plays bgm
            let instance_id = i as u64;
            GLOBAL_STATE.add_playing_track(instance_id, "theme_bgm".to_string());
            let _ = GLOBAL_STATE.command_sender.try_send(AudioCommand::PlayTrack {
                instance_id,
                room_id: rust_lib_atmos_mixer_pro::common::utils::hash_id("room_1"),
                track_id: rust_lib_atmos_mixer_pro::common::utils::hash_id("theme_bgm"),
                track_id_str: "theme_bgm".to_string(),
                data: None,
                stream_receiver: None,
                stream_sample_rate: 44100,
                stream_channels: 2,
                is_loop: true,
                volume: 1.0,
                output_channel: 0,
                output_stereo: true,
            });
        }
    });

    let t2 = thread::spawn(move || {
        for _ in 0..num_iterations {
            // System Reset simulation
            let _ = api_stop_all();
        }
    });

    t1.join().unwrap();
    t2.join().unwrap();
    
    println!("System reset vs theme start glitch stress test PASSED.");
}
