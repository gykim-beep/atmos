# 6. TASKS (단계별 작업 마일스톤)

*   **Phase 1. 기반 공사 및 FFI 브릿지 (Week 1)**
    *   [ ] `flutter create` 구동 및 `macos/Runner/DebugProfile.entitlements` 권한 추가 (오디오 파일 피커 버그 방지용).
    *   [ ] `flutter_rust_bridge` 하네스 세팅 및 `rust_core` 프로젝트 스캐폴딩.
    *   [ ] `config.json.tmp` -> 원자적 쓰기(Atomic Write) `Rename` 시스템 콜 로직 구현.
*   **Phase 2. 백엔드 오디오 엔진 코어 (Week 2)**
    *   [ ] `cpal` Output Stream 빌드. 0% I/O 및 0% Allocation 객체 풀 구조 확립.
    *   [ ] SIMD 병렬 믹싱 구조 및 `tanh` 소프트 클리핑 출력 이식.
    *   [ ] 선행(Pre) 리샘플러 및 디스크 스트리밍용 Double FBO 버퍼 개발 (`Acquire`/`Release` 오더링).
*   **Phase 3. Gating 로직 및 OSC 네트워크 (Week 3)**
    *   [ ] UDP/유무선 통합 OSC 비동기 데몬 및 시리얼 포트 파서 구축. 250ms 슬라이딩 디바운서 구현.
    *   [ ] `GlobalEngineState` 기반 Active/Locked/Cleared 인터록 상태 머신 통합.
    *   [ ] 스마트 더킹(150ms 하강, 300ms 상승) 연산 루프 통합.
*   **Phase 4. Flutter UI/UX 픽셀 퍼펙트 퍼블리싱 (Week 4)**
    *   [ ] 글로벌 헤더 오버플로우 방지 및 환경설정 다이얼로그(720x560) 구축.
    *   [ ] Glassmorphism(Sigma 20.0) 룸 잠금 배지 및 Hover 150ms 마이크로 인터랙션 구현.
    *   [ ] `CustomPainter` 기반 무부하 GC-Free 네온 VU 미터 그로잉 드로잉 파이프라인 개발.
*   **Phase 5. 시스템 통합 연동 (Week 5)**
    *   [ ] `Riverpod` 전역 상태 통합 및 16.6ms Batching 적용하여 통신 오버헤드 최소화.
    *   [ ] 핫플러그(장치 분리) 에러 핸들링 및 "정말 삭제하시겠습니까?" 컨펌 UI 플로우 통합.
*   **Phase 6. 오프라인 4단계 검증 및 스트레스 마일스톤 (Week 6)**
    *   [ ] **1. GUI 렌더링 락 검증**: `flutter run -d macos` 구동 후 60fps 네온 렌더링 GC 락 점검.
    *   [ ] **2. OSC 모의 시뮬레이터 검증**: 127.0.0.1 Python 핑 스크립트로 250ms 디바운서 필터링 확인.
    *   [ ] **3. 스마트 더킹 청음 검증**: 더킹 파라미터 작동 및 300ms 페이드아웃 팝 노이즈 차단 확인.
    *   [ ] **4. 리소스 및 48시간 스트레스 한계 테스트**: Activity Monitor로 SIMD 연산 점유율 파악 및 초당 100개 무작위 가짜 패킷 48시간 주입 시 링버퍼 언더런/OOM 0회 달성 확인.
