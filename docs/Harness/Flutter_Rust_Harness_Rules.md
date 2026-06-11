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
    *   **오디오 엔진 (Rust)**: `cpal` (크로스 플랫폼 오디오 I/O), `rodio` (또는 `symphonia` 오디오 디코딩), `rubato` (리샘플링 필요 시)
    *   **OSC 통신 (Rust)**: `rosc` (또는 `tokio` 기반의 비동기 UDP 처리)
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
    *   Flutter UI는 FFI(`flutter_rust_bridge`)를 통해 Rust로부터 상태(State)를 넘겨받아(구독하여) 렌더링만 수행하며, 설정 변경 시 직접 파일을 수정하지 않고 Rust 코어에 변경 명령을 내린다.

## 5. 스레드 철의 장막 (Strict Thread Separation) 🟢
*   **원칙**: 렌더링, 오디오 믹싱, 네트워크 통신 스레드는 철저히 분리되어야 하며, 서로 블로킹(Blocking)해서는 안 된다.
*   **적용**:
    *   **UI 스레드 (Flutter)**: 메인 Isolate에서 60fps 이상의 부드러운 UI 렌더링과 사용자 이벤트 처리만 전담한다.
    *   **오디오 스레드 (Rust)**: 운영체제(C 레벨)와 맞닿아 있는 실시간 콜백 스레드로 동작한다. 오디오 믹싱과 라우팅만 수행하며, 데이터 경합 방지를 위해 Rust의 안전한 동시성 모델(`Arc<Mutex<T>>` 또는 Lock-free 자료구조)을 강제한다.
    *   **OSC 스레드 (Rust)**: 아두이노 UDP 신호 수신은 별도의 비동기 태스크(예: `tokio`)나 데몬 스레드에서 처리되어 메인 오디오 콜백에 영향을 주지 않아야 한다.

## 6. 모듈 독립성 (Module Independence) 🟢
*   **원칙**: 너에게 지시된 역할의 파일(UI면 Dart, 코어면 Rust)만 정확히 수정하라.
*   **적용**: 프론트엔드와 백엔드의 역할이 언어 레벨에서 분리된 만큼, UI 수정 지시를 받았을 때 불필요하게 Rust 코어를 건드리거나 그 반대의 행동을 엄격히 금지한다.

## 7. 자율 통제 (Self-Healing & Debugging) 🟢
*   **원칙**: 컴파일, 빌드 또는 실행 중 에러 발생 시 **최대 3번까지만 스스로 원인을 분석하고 디버깅**하라. 
*   **적용**: 특히 Rust의 엄격한 Borrow Checker 에러나 Flutter의 위젯 트리 에러에 직면했을 때, 3번의 자율 시도 후에도 해결되지 않으면 즉시 진행 상황과 에러 로그를 한국어로 보고하고 디렉터의 지시를 기다려라.

## 8. UX/UI 및 핵심 기능 명세 절대 준수 (Design & Feature Parity) 🔵 (NEW)
*   **원칙**: 새롭게 갱신된 `Atmos_Mixer_Pro_UXUI_and_Features_Specs.md` 문서 및 `implementation_plan.md`의 내용을 100% 동일하게 구현하라.
*   **적용**:
    *   **UI/UX**: 글로벌 헤더, 룸 패널 형태, 다크 모드 색상 코드(`#0E0E1C`, `#08080F` 등), 하단 시스템 로그 패널, 트랙패드 부드러운 스크롤링 등은 Flutter에서 위젯으로 완벽히 재현해야 한다.
    *   **Audio/Core**: 스마트 더킹(Smart Ducking), 소프트 페이드(Soft Fade), 배타적 룸 제어(Exclusive Gating), 디바운싱(Debouncing) 기능은 반드시 **Rust Core**에 내재화되어야 하며, UI 프레임 드롭의 영향을 받지 않아야 한다.
