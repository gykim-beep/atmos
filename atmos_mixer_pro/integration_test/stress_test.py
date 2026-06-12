import argparse
import time
import random
import threading
from pythonosc import udp_client

def send_osc_barrage(client, num_messages, delay_ms):
    tracks = ["/track/1/play", "/track/2/play", "/track/3/play", "/track/1/stop", "/track/2/stop", "/track/all/stop"]
    
    print(f"Starting stress test: {num_messages} messages with {delay_ms}ms delay between each.")
    
    start_time = time.time()
    for i in range(num_messages):
        msg = random.choice(tracks)
        client.send_message(msg, 1.0)
        time.sleep(delay_ms / 1000.0)
        
        if i > 0 and i % 500 == 0:
            print(f"Sent {i} messages...")
            
    end_time = time.time()
    print(f"Finished sending {num_messages} messages in {end_time - start_time:.2f} seconds.")

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Atmos Mixer Pro Stress Tester")
    parser.add_argument("--ip", default="127.0.0.1", help="The ip of the OSC server")
    parser.add_argument("--port", type=int, default=8000, help="The port the OSC server is listening on")
    parser.add_argument("--count", type=int, default=2000, help="Number of messages to send")
    parser.add_argument("--delay", type=float, default=2.0, help="Delay between messages in milliseconds")
    
    args = parser.parse_args()
    
    client = udp_client.SimpleUDPClient(args.ip, args.port)
    
    # We can use multiple threads to increase concurrent stress
    threads = []
    for _ in range(3):
        t = threading.Thread(target=send_osc_barrage, args=(client, args.count, args.delay))
        threads.append(t)
        t.start()
        
    for t in threads:
        t.join()
        
    print("Stress test completed.")
