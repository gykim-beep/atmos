# Atmos Mixer Pro — Flutter + Rust 하이브리드 아키텍처 도입 계획

방탈출 및 전시 공간용 초저지연 공간 음향 연출 프로그램 **Atmos Mixer Pro**의 안전성과 세련된 UI를 동시에 잡기 위한 **Flutter (Frontend UI) + Rust (Audio/OSC Engine)** 하이브리드 아키텍처 구축 계획입니다.

이 계획은 인터넷이 되지 않는 완전 오프라인 환경에서도 테스트, 실행, 디버깅이 가능하도록 로컬 최적화 구조를 지향합니다.

---

## 1. 권장 기술 스택 및 프레임워크 세팅

### 🖥️ Frontend (Flutter Desktop)
- **역할**: 전반적인 사용자 인터페이스(Faders, VU Meters, Routing Canvas), 프리셋 파일 로드/저장 관리, 사용자 입력 수신.
- **핵심 패키지 추천**:
  - `flutter_riverpod` (또는 `provider`): 복잡한 채널 상태 및 볼륨 제어를 실시간으로 일관되게 동기화하는 모던 상태 관리 라이브러리.
  - `window_manager`: 방탈출 전용 키오스크/PC 환경에 필수적인 창 크기 고정, 타이틀 바 숨김, 전체 화면 모드 등을 제어하는 데스크톱 전용 라이브러리.
  - `file_picker`: 사운드 파일(*.wav, *.mp3) 선택용 OS 네이티브 대화상자 호출.

### 🦀 Backend Engine (Rust Core)
- **역할**: 가비지 컬렉션(GC) 없는 실시간 초저지연 오디오 버퍼 렌더링, UDP OSC 네트워크 백그라운드 수신 및 디바운싱, 배타적 룸 제어.
- **핵심 크레이트(Crate) 추천**:
  - `cpal` (Cross-Platform Audio Library): Windows(ASIO) 및 macOS(Core Audio) 드라이버를 직접 스캔하고, 선점형으로 오디오 디바이스 스트림을 가동하는 초저지연 오디오 최적화 크레이트.
  - `rodio`: `cpal` 기반의 고수준 재생 라이브러리로, BGM 루프 재생, 볼륨 페이드 인/아웃(0.3초), 효과음(SFX) 믹싱 및 덕킹(Ducking) 처리를 직관적이고 효율적으로 처리.
  - `rosc`: 바이트 단위 UDP 오디오 트리거 패킷을 극도로 빠르게 파싱하는 전용 OSC 크레이트.
  - `crossbeam-channel`: UI 스레드, OSC 수신 스레드, 오디오 스레드 간에 락(Lock) 없이 안전하고 빠르게 메시지를 송수신하기 위한 초고속 채널.

### 🌉 연동 레이어 (Bridge Layer)
- **도구**: `flutter_rust_bridge` (v2)
  - Flutter(Dart)와 Rust 사이를 이어주는 가교 역할을 합니다.
  - Rust에 일반 함수(`pub fn play_bgm(room_id: i32)`)를 작성하면, 빌드 시 자동으로 Dart 쪽 호출 코드가 생성되어 UI에서 일반 Flutter 함수처럼 호출할 수 있습니다.
  - 복잡한 C++ FFI(Foreign Function Interface) 보일러플레이트 코드를 직접 짤 필요가 없어 개발 생산성이 대폭 향상됩니다.

---

## 2. 제안하는 폴더 구조 (Project Directory Structure)

새로운 프로젝트는 `/Users/dev/.gemini/antigravity/scratch/atmos-mixer-pro` 하위에 생성되며, Rust 엔진이 Flutter 내부에 깔끔하게 서브디렉터리로 포함되는 현대적인 모노레포 구조를 가집니다.

```text
atmos-mixer-pro/
├── README.md
├── pubspec.yaml                # Flutter 의존성 정의
├── lib/                        # Flutter (Dart) 소스코드
│   ├── main.dart               # 앱 실행 진입점
│   ├── src/
│   │   ├── rust/               # Rust 자동 생성 Dart 브릿지 파일들
│   │   ├── ui/                 # UI 화면 및 위젯 (Faders, Room Panels)
│   │   └── state/              # Riverpod 볼륨 및 오디오 상태 관리
│   └── rust_api.dart           # Rust Core 호출 래퍼 인터페이스
├── rust/                       # Rust Core 백엔드 소스코드
│   ├── Cargo.toml              # Rust 의존성 정의 (cpal, rodio, rosc 등)
│   ├── build.rs                # flutter_rust_bridge 빌드 스크립트
│   └── src/
│       ├── lib.rs              # Flutter에 노출할 API 진입점
│       ├── audio_engine.rs     # cpal/rodio 기반 멀티채널 사운드 시스템
│       ├── osc_server.rs       # UDP 소켓 기반 OSC 수신기 및 디바운서
│       └── config.rs           # config.json 기반 설정 로드/싱글턴 관리
└── config.json                 # 프로그램 공통 설정 파일 (Single Source of Truth)
```

---

## 3. 상세 마이그레이션 아키텍처 흐름

기존 Python 기반의 아키텍처 규칙(Harness Rules)을 하이브리드 세팅에 맞게 완벽하게 재구성합니다.

### 1) 오디오 렌더링 스레드 분리
- **Python**: 메인 스레드와 오디오 루프가 다른 라이브러리 스레드로 돌았으나 GIL(Global Interpreter Lock)의 영향을 미세하게 받았습니다.
- **Rust**: OS Native 스레드를 직접 생성하여 완벽하게 CPU 독립적으로 구동하며, UI 반응 속도가 저하되거나 렉이 걸려도 오디오 버퍼가 비어 소리가 튀는 현상(Buffer Underrun)을 원천 방지합니다.

### 2) OSC 실시간 수신 및 무결성 검증
- **Rust 백그라운드 스레드**에서 `std::net::UdpSocket`을 무한 대기(Blocking) 형태로 구동합니다.
- 패킷이 수신되면 `rosc` 크레이트를 통해 즉시 구조를 해석하고, Rust 내부의 메모리 캐시를 이용해 디바운싱(Debouncing, 최소 트리거 간격 필터링)을 0.1ms 이내에 완료합니다.
- 유효한 신호만 Flutter UI 스레드와 오디오 렌더링 스레드로 전파합니다.

---

## 4. 사용자 검토 필요 사안 (User Review Required)

> [!IMPORTANT]
> **Windows/macOS 멀티 OS 배포 시 고려사항**
> - **ASIO 드라이버 개발 세팅**: Windows 환경에서 실제 ASIO 드라이버를 스캔하려면 Steinberg SDK 헤더 파일이 빌드 타임에 필요할 수 있습니다. 1단계로 macOS의 Core Audio 및 일반 Windows WASAPI/DirectSound 기반 멀티채널을 먼저 구축한 뒤, ASIO 특화 프로토콜을 점진적으로 붙여 나가는 방식을 권장합니다.
> - **개발 언어 전환**: 파이썬 코드를 Rust와 Dart로 완전 재작성해야 합니다. 비즈니스 로직(Debouncing, Gate 제어)은 Rust로 가고 UI는 Dart로 분할되므로, 코딩 작업을 긴밀히 설계하며 진행해야 합니다.

---

## 5. 오픈 질문 (Open Questions)

> [!NOTE]
> 1. 현재 Python 프로젝트에서 사용 중인 핵심 파이썬 패키지(예: `pyaudio`, `mido`, `python-osc` 등)의 상세한 세부 사양을 참고할 수 있을까요? (만약 코드가 준비되어 있다면, 분석 후 마이그레이션 로직을 짜 드립니다.)
> 2. 이번 작업을 위해 `/Users/dev/.gemini/antigravity/scratch/atmos-mixer-pro` 폴더에 Flutter 데스크톱 템플릿 환경을 먼저 세팅해 드려도 괜찮을까요?

---

## 6. 검증 계획 (Verification Plan)

### 로컬 오프라인 테스트 방법
1. **Flutter 로컬 구동**: `flutter run -d macos` 명령어를 사용해 독립형 Native 데스크톱 윈도우가 가볍게 구동되는지 확인합니다.
2. **OSC 모의 시뮬레이터**: 로컬 루프백(`127.0.0.1:포트`) 주소로 Python 스크립트나 간단한 OSC 전송 툴을 사용해 패킷을 전송했을 때, Rust 오디오 엔진이 딜레이 없이 소리를 부드럽게 페이드인/아웃 시키는지 확인합니다.
3. **리소스 모니터링**: macOS 활성 상태 보기(Activity Monitor)를 통해 기존 customtkinter(Python) 대비 CPU와 RAM 점유율이 획기적으로 낮아졌는지 점검합니다.
