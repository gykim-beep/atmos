# 5. SCREENS (화면 설계 및 UI/UX)

## 1. 디자인 시스템 토큰 (옵시디언 다크 테마)
*   **배경 (Deep Obsidian Space)**: `#0xFF0A0C16`
*   **액센트 (Cyanscent Aqua Glow)**: `#0xFF00FFCC` (재생, 미터)
*   **액센트 2 (Neon Magenta Rose)**: `#0xFFFF0055` (에러, 피크)
*   **액센트 3 (Button Blue)**: `#0xFF1565C0` -> Hover `#0xFF0D3E8A`
*   **액센트 4 (Danger Red)**: `#0xFFB71C1C` -> Hover `#0xFF7F0000`
*   **Glass Base (모듈 바탕)**: `0x1A1D30` (Backdrop Filter: Gaussian Blur Sig 20.0, 투명도 0x1A)

## 2. 글로벌 헤더 (Top Bar, 90px)
*   **타이틀**: `🎛 Atmos Mixer Pro — 시퀀스 제어형 멀티채널 오디오 믹서` (흰색 텍스트).
*   **레이아웃 배치**: 로고 및 타이틀 -> 중앙 제어부 버튼 5개(테마 시작, 비상 정지, 시스템 리셋, 룸 추가, 환경설정) -> 데이터 입출력 -> 디바이스 스캐너.
*   **디바이스 실시간 핫플러그 UI**: 디바이스 스캐너 구역은 OS 오디오 장치 변경 이벤트를 실시간 구독하여, 장비 플러그/언플러그 시 목록이 즉시 새로고침됨.
*   **OVERFLOW 에러 방어 설계**: 상단 제어 버튼 `Row` 내부에 `Wrap`을 사용하거나 `Expanded` + 가로 `SingleChildScrollView`를 적용하여 노란색 빗금 에러 원천 차단.

## 3. 룸 패널 대시보드 (Center)
*   가로 관성 스크롤 영역. 너비 `350px`, 라운딩 `10px`.
*   **룸 헤더**: `TextField` 직접 편집. 룸 색상 순환 배정.
*   **마이크로 인터랙션**: 버튼 Hover 시 150ms 선형 보간 트랜지션 타임 적용.
*   **잠금(Lock) 오버레이 UX**: `Active` 상태가 아닌 패널은 `BackdropFilter(sigmaX: 20.0, sigmaY: 20.0)`를 통한 반투명 유리막과 `🔒 잠금` 뱃지로 덮이며 클릭이 완벽히 차단(Disabled)됨.

## 4. 트랙 카드 (Track Card)
*   이름 직관적 수정(`TextField`). 수동 재생/정지 토글, 볼륨 슬라이더, `🔄 무한 루프` 토글 스위치, 출력 채널 라벨(`🔌 Output 3`) 배치.

## 5. 환경설정 팝업 다이얼로그 (Preferences Modal)
*   **크기**: 720x560 모달창.
*   **구성**: 오디오 디바이스 선택(드롭다운), 버퍼 사이즈(64~1024), 트랙-채널 물리적 매핑(12x24 그리드), OSC 수신 포트 및 트리거 주소 텍스트 매핑.

## 6. 시스템 로그 콘솔 (Bottom, 155px) 및 VU 미터
*   **실시간 시스템 로그**: 검정 바탕(`#000000`)에 밝은 초록(`#22DD88`) 타임스탬프 텍스트 렌더링.
*   **60fps GC-Free 네온 VU 미터 렌더링 최적화 (핵심)**: 60fps로 위젯을 재빌드(`setState`)하면 GC 부하가 생겨 프레임 드랍이 발생함. 이를 극복하기 위해 Rust의 `AtomicU32` 레벨값을 직접 폴링하여 `CustomPainter` 캔버스의 비디오 하드웨어 가속 레이어에 네온 그라데이션(`Cyan` -> `Yellow` -> `Red`)을 **위젯 트리 재빌드 없이 직접 무부하 드로잉(Direct Drawing)** 합니다.
