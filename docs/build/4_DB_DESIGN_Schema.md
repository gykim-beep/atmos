# 4. DB DESIGN (데이터 및 로컬 스토리지 설계)

## 1. 단일 진실 공급원 (Single Source of Truth)
본 프로그램은 RDBMS나 NoSQL을 사용하지 않으며, 단일 JSON 설정 파일로 모든 상태를 영속화합니다. 상태 변경 시 Flutter의 메모리 상태를 우선 갱신하고, 백그라운드나 명시적 '저장' 시 디스크 파일에 일괄 덮어씁니다.

## 2. 저장 정책 및 안정성
*   **원자적 쓰기 (Atomic Write)**: `config.json` 저장 중 데스크톱 전원 차단으로 인한 JSON 파일 증발/손상을 원천 차단하기 위해, 데이터를 임시 파일 `config.json.tmp`에 먼저 쓴 후 OS 수준의 `Rename(Atomic Swap)` 시스템 콜을 사용하여 100% 안전하게 덮어쓰는 로직 필수 적용.

## 3. JSON 스키마 명세
```json
{
  "schema_version": "1.0.0",
  "system_settings": {
    "osc_listen_port": 8000,
    "target_device_name": "ASIO Fireface USB",
    "buffer_size": 128,
    "sample_rate": 48000
  },
  "rooms": [
    {
      "room_id": "r-1234-abcd",
      "name": "1. 취조실", 
      "theme_color": "#2E7D32", 
      "master_volume": 1.0,
      "clear_osc_address": "/room1/clear",
      "tracks": [
        {
          "track_id": "t-5678-efgh",
          "name": "금고 덜컹거림",
          "file_path": "/Users/admin/Music/safe.wav",
          "volume": 0.8,
          "fade_in_sec": 0.1,
          "fade_out_sec": 0.3,
          "is_loop": false,
          "output_channel_idx": 3,
          "trigger_osc_address": "/room1/safe/open",
          "stop_osc_address": "/room1/safe/close"
        }
      ]
    }
  ]
}
```
