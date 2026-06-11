# Atmos Mixer Pro - 7대 핵심 설계 문서 (7 Pillars)

본 문서는 `implementation_plan.md` 및 `Atmos_Mixer_Pro_UXUI_and_Features_Specs.md`, `Flutter_Rust_Harness_Rules.md`를 기반으로 프로젝트의 기획부터 개발, 디자인, 작업 단위까지 7가지 핵심 카테고리로 세분화하여 정리한 요약 명세서입니다.

---

## 1. PRD (Product Requirements Document - 제품 요구사항 정의서)
- **제품명**: Atmos Mixer Pro (Phase 2)
- **타겟 유저**: 프리미엄 방탈출 및 테마파크 공간 음향 엔지니어
- **핵심 목표**: 다중 스피커(최대 24채널) 환경에서 완전 오프라인으로 작동하는 '초저지연 시퀀스 제어형 멀티채널 오디오 믹서' 구축.
- **주요 요구 기능**:
  - **오프라인 센서 연동**: 아두이노 센서와 로컬 네트워크(UDP) 통신(OSC)을 통한 즉각적인 오디오 재생.
  - **독점적 룸 제어 (Exclusive Gating)**: 플레이어 위치 기반으로 현재 방의 센서만 허용하고 나머지 방의 간섭을 물리적으로 차단. 자동 룸 전환(Interlock).
  - **스마트 오디오 믹싱**: 단발성 효과음(SFX) 재생 시 배경음(BGM)이 자동으로 줄어들고 복구되는 '스마트 더킹(Smart Ducking)', 재생/정지 시 '소프트 페이드(Soft Fade)'.
  - **전문가형 UI**: 어두운 환경에서 엔지니어의 눈을 보호하고 가독성을 높이는 다크 모드 및 하드웨어 매핑 UI.

## 2. TRD (Technical Requirements Document - 기술 요구사항 정의서)
- **아키텍처**: Flutter (Desktop UI) + Rust (Core Engine) 하이브리드 아키텍처.
- **통신 브릿지**: `flutter_rust_bridge` (v2)를 사용한 C++ FFI 보일러플레이트 제거.
- **스레드 모델 (철의 장막)**:
  - **UI 스레드**: Flutter 메인 스레드 (60fps 렌더링).
  - **OSC 수신 데몬 스레드**: Rust 비동기 수신 대기 (포트 8000).
  - **실시간 오디오 믹서 스레드**: Rust `cpal` 기반 최상위 우선순위 콜백.
- **오디오 코어 제약사항 (무장애 설계)**:
  - **Zero-Allocation & Lock-Free**: 오디오 콜백 루프 내 디스크 I/O 0%, 메모리 힙 할당 0%, 뮤텍스 블로킹 0% 엄수.
  - OOM(Out of Memory) 방지를 위한 SFX(RAM 완전 캐시)와 BGM(Disk-Streaming 이중 링버퍼) 이원화 구조.
  - 96kHz 리샘플링 대응 SIMD 가속 병렬 믹싱.

## 3. USER FLOW (사용자 흐름도)
1. **[초기 구동]**: 앱 실행 -> `config.json` 로드 -> 오디오 장치 스캔 및 로드 -> 룸 1번 독점 활성화 대기.
2. **[실시간 운영 플로우 (방탈출 진행)]**:
   - `룸 1` Active -> BGM 자동 재생 루프.
   - 플레이어가 물리 센서(예: 서랍) 작동 -> 아두이노가 OSC 신호 송신.
   - Rust 코어 신호 수신 (250ms 이내 중복 신호 디바운싱 무시).
   - SFX 재생 트리거 -> 즉시 BGM 볼륨 30%로 하강(스마트 더킹, 150ms).
   - SFX 종료 -> BGM 원래 볼륨 복구(300ms).
   - 미션 완료 -> '룸 클리어' OSC 신호 수신 -> `룸 1` Cleared -> `룸 2` Active 전환 (인터록) -> `룸 2` BGM 재생 시작.
3. **[환경 설정 플로우]**: 글로벌 헤더 `⚙️ 설정` 클릭 -> 팝업창에서 인터페이스 출력 포트 라우팅 및 아두이노 OSC 주소 텍스트 매핑 -> `저장` -> 백그라운드 엔진 재시작 및 동기화.

## 4. DB DESIGN (데이터베이스/로컬 스토리지 설계)
본 프로그램은 RDBMS나 NoSQL을 사용하지 않으며, **단일 진실 공급원(SSOT)** 원칙에 따라 하나의 JSON 설정 파일로 모든 상태를 영속화합니다.
- **저장 파일명**: `config.json`
- **핵심 스키마 (Config Schema)**:
  - `device_settings`: 연결된 하드웨어 ID, 버퍼 사이즈, 수신 포트 번호(기본 8000).
  - `rooms` (Array):
    - 속성: `room_id`, `name`, `theme_color`, `master_volume`.
    - `clear_osc_address` (해당 방 클리어 신호).
    - `tracks` (Array): 개별 오디오 소스 리스트
      - 속성: `track_id`, `file_path`, `name`, `volume`, `is_bgm_loop`, `output_channel` (물리 아웃풋 번호).
      - 트리거: `trigger_osc_address`, `stop_osc_address`.

## 5. Screens (화면 설계 및 UI/UX)
1. **글로벌 헤더 (Top, 90px)**:
   - 테마시작, 비상정지, 시스템 리셋, 룸 추가, 환경설정, 설정 저장/불러오기 버튼. 우측 하드웨어 스캔 및 정보 라벨.
2. **메인 대시보드 (Center)**: 가로 관성 스크롤 기반의 '룸 패널(Room Panel, 350px)' 뷰.
   - 비활성 룸은 상단 `🔒 잠금` 뱃지와 함께 Glassmorphism(반투명 유리) 오버레이로 클릭이 완전 차단됨.
3. **트랙 카드 (Track Card)**: 각 룸 내부에 위치하는 개별 오디오 제어 패널.
   - 수동 재생/정지 토글, 이름 수정 필드, 볼륨 슬라이더, 무한 루프 플래그 토글, 라우팅 출력 포트 확인 라벨.
4. **시스템 로그 (Bottom, 155px)**:
   - 타임스탬프와 함께 시스템 상태(에러, OSC 지연시간, 재생 기록 등)를 렌더링하는 해커 터미널 감성 콘솔 (`#000000` 배경, `#22DD88` 폰트).
5. **환경설정 팝업 (Modal, 720x560)**:
   - 오디오 출력 탭 (하드웨어 디바이스 선택 및 매핑).
   - OSC 아두이노 신호 탭 (주소 텍스트 매핑).

## 6. Tasks (단계별 작업 마일스톤)
- **Phase 1 (환경 세팅 및 브릿지)**: Flutter + Rust 프로젝트 스캐폴딩. `flutter_rust_bridge`를 활용한 FFI 파이프라인 개통 및 하네스 룰 세팅.
- **Phase 2 (Rust Core 개발)**:
  - `cpal`, `symphonia` 기반 RAM/Disk 이중화 오디오 캐시 시스템 구축.
  - SIMD 믹서, 스마트 더킹 알고리즘, Gating/디바운싱 시스템 통합.
- **Phase 3 (Flutter UI 퍼블리싱)**:
  - Riverpod 전역 상태 구조화 (Rust 상태 구독).
  - 글로벌 헤더, 룸 패널, 트랙 카드, 네온 VU 미터(CustomPainter) 퍼블리싱.
- **Phase 4 (통합 및 최적화)**: 프론트엔드 버튼 트리거와 백엔드 오디오 연산 결합. `config.json` 저장/불러오기 통합.
- **Phase 5 (QA 및 디버깅)**: 127.0.0.1 핑 테스트, 메모리 리소스(Activity Monitor) 프로파일링, 더킹 청음 테스트.

## 7. 코딩 컨벤션 (Coding Convention)
- **언어 원칙**: 코드 주석, 로그, UI 등 모든 소통 및 문서는 **100% 한국어** 사용 (하네스 룰).
- **Rust (Backend)**:
  - `cargo fmt` 포맷팅 및 `clippy` 린트 준수.
  - 오디오 스레드 내 힙 할당(`.clone()` 남발, `Box`, `Vec` 동적 추가 등) 철저 금지. 뮤텍스 락 대신 `Atomic` 및 `crossbeam-channel` 사용.
  - `std::path::PathBuf` 사용하여 맥/윈도우 OS 독립적 경로 처리.
- **Flutter (Frontend)**:
  - 비즈니스 로직은 Rust에 100% 위임하고, UI는 렌더링 및 `Riverpod` 구독만 수행 (단일 진실 공급원).
  - 로컬 파일 제어 시 `path_provider` 사용.
  - 60fps 렌더링 최적화를 위해 불필요한 `setState`를 지양.
