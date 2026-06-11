# 7. 코딩 컨벤션 (Coding Convention)

## 1. 범용 커뮤니케이션 규칙
*   **100% 한국어**: 함수 위젯의 Docstring, 내부 주석, 에러 로그 메시지, 변수명 설명, 디버그용 `println!`까지 모든 텍스트는 100% 한국어로 작성합니다.
*   **권한 및 경로**: 파일 I/O는 macOS Sandbox 권한 에러를 피해 `path_provider`와 OS 다이얼로그를 활용하며, 경로는 항상 OS 독립적인 `std::path::PathBuf`로 취급합니다.

## 2. 디렉토리 및 모듈 구조 강제화 (Feature-First)
백엔드는 도메인 기반으로 분리하고, 프론트엔드는 기능 기반(Feature-First) 구조를 엄수합니다.

*   **Rust (`rust_core/src/`)**
    *   `lib.rs`: FFI 진입점
    *   `common/commands.rs`, `config.rs`: 전역 공통 모델
    *   `audio/mixer.rs`, `player.rs`, `streaming.rs`, `resampler.rs`: 오디오 실시간 연산 및 캐싱
    *   `osc/listener.rs`, `debouncer.rs`: OSC 수신 및 채터링 방지
    *   `core/state.rs`: 글로벌 라이프사이클 관리
*   **Flutter (`lib/`)**
    *   `core/theme/colors.dart`, `ffi/ffi_bridge.dart`, `state/global_state.dart`: 공통 기반
    *   `features/dashboard/`: `dashboard_screen.dart`, `channel_strip.dart`, `vu_meter.dart` 등 메인 UI
    *   `features/settings/`: `settings_screen.dart`, `preferences_modal.dart` 환경설정

## 3. Rust (Audio Core) 컨벤션
*   **할당 통제 (Lint)**: 오디오 콜백(`fn audio_callback`) 안에서는 `Vec::new()`, `format!()`, `.clone()` 등 메모리를 동적 할당하는 코드를 단 한 줄도 허용하지 않습니다.
*   **에러 타입 매핑 (AtmosError)**: 제네릭한 에러를 금지하고, `AtmosError`를 `NetworkError`, `AudioDeviceLost`, `FileIoError`, `BufferUnderrun` 등으로 세분화합니다. 각 에러는 Flutter UI의 붉은색/노란색 경고 배너로 1:1 매핑됩니다.
*   **락(Lock) 제어**: `Mutex` 사용을 지양하고 `crossbeam::atomic::AtomicCell` 또는 MPSC 채널 기반 소유권 이전을 사용합니다.

## 4. Flutter (UI) 및 FFI 컨벤션
*   **FFI 네이밍 컨벤션**: Rust-Flutter 간 통신 함수는 모두 `api_xxx()` 접두사를 가지며, Flutter 내 Riverpod 상태 관리자는 `xxx_provider`, `xxx_notifier`로 명명 규칙을 엄격 통일합니다.
*   **오버플로우(RenderFlex) 방어 원칙**: 고정 크기 위젯 다중 배치 시 무조건 가변 여백 위젯(`Expanded`, `Flexible`, `Wrap`)을 사용하여 우측 오버플로우 에러를 방지합니다.
*   **퍼포먼스 렌더링 방어**: 60fps로 갱신되는 위젯은 전체 화면 위젯 트리의 `setState`를 발생시키지 않고, `CustomPainter` 및 `RepaintBoundary` 단일 구역에서 해결합니다.
