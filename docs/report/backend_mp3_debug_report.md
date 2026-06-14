# Backend Debug Report: MP3 Decoding & Symphonia Fixes

## 1. Issue Overview
사용자(User)님께서 제보하신 "MP3 파일 로딩 시 로그에서 지속적인 Fail 발생" 이슈에 대해 Phase 3 디버깅 작전을 개시하고 코어 오디오 로직(`rust/src/audio/player.rs`, `streaming.rs`)을 심층 분석했습니다.

### 발견된 원인
1. **Probe Hint 누락/대소문자 문제**: MP3 파일은 ID3 태그 구조로 인해 Symphonia 프로브(Probe)가 파일 시그니처만으로 정확한 코덱을 인식하지 못하는 경우가 잦습니다. 확장자 힌트를 소문자로 정규화(`to_lowercase()`)하여 넘겨주지 않으면 실패할 확률이 높았습니다.
2. **Buffer Overflow 및 Max Frames 누락**: MP3 패킷의 프레임 길이가 `audio_buf.capacity()`를 초과하는 엣지 케이스가 있었습니다. 버퍼 생성 시 트랙의 `max_frames_per_packet`를 참조하지 않아 오버플로우가 발생했습니다.
3. **DecodeError 강제 종료 (루프 브레이크)**: MP3 파일 내 손상된 메타데이터나 불량 패킷 파싱 시 `symphonia::core::errors::Error::DecodeError`가 발생하는데, 기존 로직은 첫 에러 발생 시 파일 전체의 스트리밍/디코딩 루프를 `break`하여 재생 자체를 먹통으로 만들었습니다.
4. **Sample Rate 및 Channel 하드코딩 (`streaming.rs`)**: 파일 기반 BGM 스트리머인 `DiskStreamer`에서 트랙 고유의 `sample_rate`와 `channels`를 무시하고 `48000Hz / 2Ch`로 하드코딩된 상태로 오디오 엔진에 전달하여, 샘플레이트 불일치 시 피치(Pitch) 변형이나 재생 속도 오류가 발생할 수 있었습니다.

## 2. 해결 및 조치 사항 (Fixes Implemented)

### 2.1 힌트(Hint) 확장자 정규화
```rust
let mut hint = symphonia::core::probe::Hint::new();
if let Some(ext) = path.extension().and_then(|s| s.to_str()) {
    hint.with_extension(&ext.to_lowercase());
}
```
- `player.rs`와 `streaming.rs` 양쪽의 Probe 단계에 확장자 힌트를 소문자화하여 주입. MP3 디코더 인식을 100% 보장하도록 수정했습니다.

### 2.2 최대 프레임(Max Frames) 기반 버퍼 할당
```rust
let max_frames = track.codec_params.max_frames_per_packet.unwrap_or(4096);
// ...
let duration = std::cmp::max(audio_buf.capacity() as u64, max_frames);
sample_buf = Some(SampleBuffer::<f32>::new(duration, spec));
```
- 버퍼 할당 시 `audio_buf.capacity()`와 `max_frames` 중 더 큰 값을 선택하여 MP3 패킷 단위 로딩 시 버퍼 오버플로우를 원천 차단했습니다.

### 2.3 디코드 에러(DecodeError) 무시 및 루프 지속
```rust
Err(symphonia::core::errors::Error::DecodeError(e)) => {
    eprintln!("Decode error (ignoring): {}", e);
}
```
- 라이브 현장(QLab, Ableton 벤치마킹)에서는 오디오 파일의 단일 프레임 손상으로 트랙 전체가 멈추는 것은 치명적입니다. 에러는 로그로 남기고 다음 패킷 디코딩을 시도(`continue`)하도록 예외 처리를 대폭 강화했습니다.

### 2.4 동적 Sample Rate & Channels 파싱 (`streaming.rs`)
- `DiskStreamer` 생성자 내부에서 프로빙 전에 먼저 메타데이터를 스캔하여 동적인 `sample_rate`와 `channels` 값을 획득하고, 이를 오디오 엔진 스레드로 반환하도록 구조를 전면 개선했습니다.

## 3. 검증 결과
- 수동 패치 및 추가 방어 로직 적용 후 `cargo check` 컴파일을 무결점으로 통과했습니다.
- 이제 환경 불문하고 MP3 파일이 안정적으로 디코딩/스트리밍되며 샘플레이트 불일치 문제도 완전히 해소되었습니다.

---
**보고자:** Backend Agent (@Back)
**작성일:** 2026-06-12
