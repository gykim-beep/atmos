# Atmos Mixer Pro - Flutter + Rust 하이브리드 아키텍처 하네스 규칙 (Harness Rules)

본 문서는 'Atmos Mixer Pro'를 Python 환경에서 **Flutter(프론트엔드) + Rust(백엔드 코어)** 하이브리드 아키텍처로 마이그레이션 및 개편할 때 반드시 준수해야 하는 개발 철학과 기술적 제약 사항을 정의합니다.

---

## 1. 무조건적인 한국어 소통의 원칙 🟢
*   **원칙**: 디렉터와의 대화, 에러 분석, 코드 주석, 시스템 로그, UI 텍스트까지 모두 **100% 한국어로만 작성**하라.
*   **적용**: Flutter(Dart)의 위젯 설명이나 Rust의 내부 비즈니스 로직 주석도 예외 없이 한국어를 사용해야 한다.

## 2. 종속성 동결 (Strict Dependency Control) 🟡
*   **원칙**: 내 허락 없이 외부 크레이트(Rust Crate)나 패키지(Flutter Package)를 임의로 설치하거나 `pubspec.yaml` / `Cargo.toml`에 추가하지 마라.
*   **허용된 코어 스택 (화이트리스트)**:
    *   **통신 브릿지**: `flutter_rust_bridge` (Flutter와 Rust 간의 유일한 통신 채널)
    *   **오디오 엔진 (Rust)**: `cpal` (장치 제어), `symphonia` (무부하 디코딩). 
        * *주의: `rodio`와 `rubato`는 힙 할당 및 블로킹을 유발하므로 사용을 엄격히 금지한다.*
    *   **OSC 통신 (Rust)**: `rosc` (또는 `tokio` 기반의 비동기 UDP 처리)
    *   **안전성 (Rust)**: `crossbeam-channel` (락프리 통신)
    *   **UI (Flutter)**: 공식 `material` / `cupertino`, 상태 관리를 위한 `riverpod` (또는 `provider`)

## 3. 경로 독립성 (Path Independence) 🟡
*   **원칙**: Mac과 Windows 환경 어디에서든 오디오 에셋이나 설정 파일을 불러올 때 경로가 깨지지 않게 하라.
*   **적용**:
    *   **Rust 코어**: 문자열 조작 대신 반드시 `std::path::PathBuf`를 사용하여 파일 시스템에 접근하라.
    *   **Flutter UI**: 로컬 파일 시스템 경로나 앱 데이터 디렉토리에 접근할 때는 `path_provider` 패키지를 사용하여 OS 독립성을 보장하라.

## 4. 단일 진실 공급원 (Single Source of Truth) 🟢
*   **원칙**: 프로그램의 모든 설정값(오디오 라우팅, 방 세팅, OSC 매핑 등)은 오직 `config.json`에서만 읽고 써야 한다.
*   **적용**: 
    *   파일 I/O 및 파싱 로직은 오로지 **Rust 엔진**이 전담한다.
    *   **원자적 쓰기 (Atomic Write)**: PC 전원 차단 시 JSON 파괴를 막기 위해 반드시 `config.json.tmp` 생성 후 OS Rename 하는 방식을 강제한다.
    *   Flutter UI는 FFI(`flutter_rust_bridge`)를 통해 Rust로부터 상태(State)를 넘겨받아(구독하여) 렌더링만 수행하며, 설정 변경 시 직접 파일을 수정하지 않고 Rust 코어에 변경 명령을 내린다.

## 5. 스레드 철의 장막 (Strict Thread Separation) 🟢
*   **원칙**: 렌더링, 오디오 믹싱, 네트워크 통신 스레드는 철저히 분리되어야 하며, 서로 블로킹(Blocking)해서는 안 된다.
*   **적용**:
    *   **UI 스레드 (Flutter)**: 메인 Isolate에서 60fps 이상의 부드러운 UI 렌더링과 사용자 이벤트 처리만 전담한다.
    *   **오디오 스레드 (Rust - The "Zero" Rules)**: 실시간 오디오 콜백 스레드 내에서는 `Mutex` 잠금, 디스크 I/O, 메모리 힙 할당(`Vec::new` 등)을 **0%로 전면 금지**한다. 데이터 통신 및 동기화에는 오직 `Atomic` 변수와 `crossbeam-channel`만 허용된다.
    *   **OSC 스레드 (Rust)**: 아두이노 UDP 신호 수신은 별도의 비동기 태스크(예: `tokio`)나 데몬 스레드에서 처리되어 메인 오디오 콜백에 영향을 주지 않아야 한다.

## 6. 모듈 독립성 (Module Independence) 🟢
*   **원칙**: 너에게 지시된 역할의 파일(UI면 Dart, 코어면 Rust)만 정확히 수정하라.
*   **적용**: 프론트엔드와 백엔드의 역할이 언어 레벨에서 분리된 만큼, UI 수정 지시를 받았을 때 불필요하게 Rust 코어를 건드리거나 그 반대의 행동을 엄격히 금지한다.

## 7. 자율 통제 (Self-Healing & Debugging) 🟢
*   **원칙**: 컴파일, 빌드 또는 실행 중 에러 발생 시 **최대 3번까지만 스스로 원인을 분석하고 디버깅**하라. 
*   **적용**: 특히 Rust의 엄격한 Borrow Checker 에러나 Flutter의 위젯 트리 에러에 직면했을 때, 3번의 자율 시도 후에도 해결되지 않으면 즉시 진행 상황과 에러 로그를 한국어로 보고하고 디렉터의 지시를 기다려라.

## 8. UX/UI 및 핵심 기능 명세 절대 준수 (Design & Feature Parity) 🔵
*   **원칙**: 새롭게 정립된 `docs/build/` 경로 내 7개 핵심 설계 문서의 내용(3대 Zero 규칙, 원자적 쓰기 등)을 100% 동일하게 구현하라.
*   **적용**: 작업을 시작하기 전에 반드시 `docs/build/` 하위의 7개 문서를 모두 정독해야 하며, 명시된 디렉터리 구조(`feature-first`, `rust_core/src/audio`)를 임의로 변경하거나 위배해서는 안 된다.
*   **UI 최적화**: 60fps 프레임 드랍을 막기 위해 VU 미터는 반드시 `CustomPainter` 기반의 무부하 렌더링 규칙을 따라야 한다.

## 9. FFI 및 에러 핸들링 컨벤션 (FFI & Error Conventions) 🔴 (NEW)
*   **원칙**: Flutter와 Rust 간의 브릿지 인터페이스와 에러 처리는 명확하고 일관되게 규격화되어야 한다.
*   **적용**:
    *   **네이밍 강제**: Rust-Flutter 간 통신 함수는 모두 `api_xxx()` 접두사로 명명하라.
    *   **Batching 최적화**: 고빈도 상태(VU 레벨 등)는 UI 스레드 과부하를 막기 위해 16.6ms Batching으로 묶어 전송할 것.
    *   **에러 매핑**: 제네릭 에러(`anyhow`) 대신 세분화된 `AtmosError`를 정의하여 사용하고, Flutter 측에서 에러 타입에 따라 빨강/노랑 배너 등으로 시각적 매핑을 수행할 것.
