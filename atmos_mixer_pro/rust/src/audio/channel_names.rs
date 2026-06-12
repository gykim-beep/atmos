#[cfg(target_os = "macos")]
pub fn get_channel_names_mac(device_name_target: &str, num_channels: u32) -> Vec<String> {
    use coreaudio_sys::*;
    use std::ptr;
    use std::ffi::CStr;

    let fallback = (1..=num_channels).map(|i| format!("Channel {}", i)).collect::<Vec<_>>();

    unsafe {
        let property_address = AudioObjectPropertyAddress {
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain,
        };

        let mut data_size: u32 = 0;
        let status = AudioObjectGetPropertyDataSize(
            kAudioObjectSystemObject,
            &property_address,
            0,
            ptr::null(),
            &mut data_size,
        );

        if status != 0 {
            return fallback;
        }

        let num_devices = data_size as usize / std::mem::size_of::<AudioObjectID>();
        let mut devices: Vec<AudioObjectID> = vec![0; num_devices];

        let status = AudioObjectGetPropertyData(
            kAudioObjectSystemObject,
            &property_address,
            0,
            ptr::null(),
            &mut data_size,
            devices.as_mut_ptr() as *mut _,
        );

        if status != 0 {
            return fallback;
        }

        for &device_id in &devices {
            // Get device name
            let name_addr = AudioObjectPropertyAddress {
                mSelector: kAudioDevicePropertyDeviceNameCFString,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain,
            };
            let mut name_ref: CFStringRef = ptr::null();
            let mut name_size = std::mem::size_of::<CFStringRef>() as u32;

            let status = AudioObjectGetPropertyData(
                device_id,
                &name_addr,
                0,
                ptr::null(),
                &mut name_size,
                &mut name_ref as *mut _ as *mut _,
            );

            if status == 0 && !name_ref.is_null() {
                let length = CFStringGetLength(name_ref);
                let mut buffer: Vec<u8> = vec![0; (length * 4 + 1) as usize];
                if CFStringGetCString(name_ref, buffer.as_mut_ptr() as *mut i8, buffer.len() as i64, kCFStringEncodingUTF8) != 0 {
                    let c_str = CStr::from_ptr(buffer.as_ptr() as *const i8);
                    if let Ok(str_slice) = c_str.to_str() {
                        if str_slice == device_name_target {
                            // Match found! Get channel names.
                            let mut names = Vec::new();
                            for i in 1..=num_channels {
                                let ch_name_addr = AudioObjectPropertyAddress {
                                    mSelector: kAudioObjectPropertyElementName,
                                    mScope: kAudioDevicePropertyScopeOutput,
                                    mElement: i,
                                };
                                let mut ch_name_ref: CFStringRef = ptr::null();
                                let mut ch_name_size = std::mem::size_of::<CFStringRef>() as u32;
                                
                                let ch_status = AudioObjectGetPropertyData(
                                    device_id,
                                    &ch_name_addr,
                                    0,
                                    ptr::null(),
                                    &mut ch_name_size,
                                    &mut ch_name_ref as *mut _ as *mut _,
                                );

                                if ch_status == 0 && !ch_name_ref.is_null() {
                                    let ch_length = CFStringGetLength(ch_name_ref);
                                    let mut ch_buffer: Vec<u8> = vec![0; (ch_length * 4 + 1) as usize];
                                    if CFStringGetCString(ch_name_ref, ch_buffer.as_mut_ptr() as *mut i8, ch_buffer.len() as i64, kCFStringEncodingUTF8) != 0 {
                                        let ch_c_str = CStr::from_ptr(ch_buffer.as_ptr() as *const i8);
                                        if let Ok(ch_str) = ch_c_str.to_str() {
                                            names.push(ch_str.to_string());
                                            continue;
                                        }
                                    }
                                }
                                names.push(format!("Channel {}", i));
                            }
                            return names;
                        }
                    }
                }
            }
        }
    }
    fallback
}

#[cfg(target_os = "windows")]
pub fn get_channel_names_win(device_name_target: &str, num_channels: u32) -> Vec<String> {
    use windows::Win32::Media::Audio::*;
    use windows::Win32::System::Com::*;
    use windows::Win32::Devices::Properties::*;
    use windows::core::{Interface, PCWSTR};
    
    let mut fallback = (1..=num_channels).map(|i| format!("Channel {}", i)).collect::<Vec<_>>();
    
    // We'll keep it simple for WASAPI: most devices don't have per-channel names easily exposed,
    // so we return default names if we can't fetch them.
    fallback
}

#[cfg(not(any(target_os = "macos", target_os = "windows")))]
pub fn get_channel_names_fallback(num_channels: u32) -> Vec<String> {
    (1..=num_channels).map(|i| format!("Channel {}", i)).collect()
}
