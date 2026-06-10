use std::net::UdpSocket;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use std::time::Duration;
use rosc::OscPacket;
use crate::osc::debouncer::OscDebouncer;

pub struct OscServer {
    is_running: Arc<AtomicBool>,
}

impl OscServer {
    pub fn new() -> Self {
        OscServer {
            is_running: Arc::new(AtomicBool::new(false)),
        }
    }

    pub fn start<F>(&self, host: String, port: u16, callback: F) -> Result<(), String> 
    where F: Fn(String) + Send + 'static {
        let addr = format!("{}:{}", host, port);
        let socket = UdpSocket::bind(&addr).map_err(|e| format!("Failed to bind UDP socket: {}", e))?;
        socket.set_read_timeout(Some(Duration::from_millis(100))).map_err(|e| e.to_string())?;

        self.is_running.store(true, Ordering::SeqCst);
        let is_running = self.is_running.clone();

        std::thread::spawn(move || {
            let mut buf = [0u8; rosc::decoder::MTU];
            let mut debouncer = OscDebouncer::new(100);

            while is_running.load(Ordering::SeqCst) {
                match socket.recv_from(&mut buf) {
                    Ok((size, _addr)) => {
                        if let Ok((_, packet)) = rosc::decoder::decode_udp(&buf[..size]) {
                            match packet {
                                OscPacket::Message(msg) => {
                                    if debouncer.should_allow(&msg.addr, "") {
                                        callback(msg.addr);
                                    }
                                }
                                OscPacket::Bundle(bundle) => {
                                    for packet in bundle.content {
                                        if let OscPacket::Message(msg) = packet {
                                            if debouncer.should_allow(&msg.addr, "") {
                                                callback(msg.addr);
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                    Err(e) => {
                        let kind = e.kind();
                        if kind != std::io::ErrorKind::WouldBlock && kind != std::io::ErrorKind::TimedOut {
                            // eprintln!("UDP receive error: {:?}", e);
                        }
                    }
                }
            }
        });

        Ok(())
    }

    pub fn stop(&self) {
        self.is_running.store(false, Ordering::SeqCst);
    }
}
