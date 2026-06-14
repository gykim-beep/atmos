# 무한 검증 루프 - 결함 및 재발 방지 규칙 로그 (Testing Rules Log)

본 문서는 `[@sub]` 에이전트가 무한 검증 루프 과정에서 테스트 실패 시 도출한 '결함 원인(Why)'과 '재발 방지 규칙(Rule)'을 누적하여 기록하는 문서입니다. 코딩 및 리팩토링 시 이 규칙들을 반드시 숙지하고 준수해야 합니다.

---

## 🔴 Rule 1: Stack 내부 가변 크기 위젯(Column/Expanded) 렌더링 제약

*   **발생 시점**: 메인화면 트랙 미노출 (Tracks not showing) 버그 발생 시
*   **재발 방지 규칙 (Rule)**: `Stack` 내부에서 `Expanded`나 `Flexible` 등 가변 크기 위젯을 포함하는 `Column`을 사용할 때는, 반드시 `Positioned.fill`을 사용하여 `Column`(또는 그 상위의 `IgnorePointer` 등)이 `Stack`의 전체 크기에 맞춰 명시적인 꽉 찬 제약(tight constraints)을 받도록 감싸야 합니다.
*   **생성 이유 및 근본 원인 (Why)**: `lib/features/dashboard/widgets/room_card.dart` 등에서 `RoomCard` 위젯이 `Stack`의 자식으로 `Column`을 가지고, 그 내부에 `Expanded`가 배치될 경우, `Stack`은 위치가 지정되지 않은 자식에게 '느슨한 제약(loose constraints)'을 부여합니다. 이로 인해 `Column`이 자체 높이를 확정할 수 없어, 자식인 `Expanded`가 0의 높이를 갖게 되며 렌더링에 실패하기 때문입니다.

---

## 🔴 Rule 2: UI/UX 디자인 토큰 일치화 (Design Parity)

*   **발생 시점**: UI 불일치 (UI mismatches) 결함 발생 시
*   **재발 방지 규칙 (Rule)**: UI/UX 설계 문서(예: `docs/init/5_SCREENS_UXUI_Design.md` 또는 `docs/build/5_SCREENS_UXUI_Design.md`)가 갱신될 경우, `colors.dart`를 비롯한 핵심 디자인 토큰 코드를 16진수 ARGB 값 수준으로 즉시 동기화해야 합니다. 디자인 문서에 명시된 블러 수치(Sigma 20.0 등)와 같은 UI 렌더링 파라미터도 하드코딩된 과거 값을 찾아 1픽셀, 1소수점 단위까지 설계 문서와 정확히 일치시켜야 합니다.
*   **생성 이유 및 근본 원인 (Why)**: 설계 문서에는 전역 배경색 `#0xFF0A0C16`, 잠금 뱃지의 오버레이 블러(sigma) 값 20.0 등 새로운 옵시디언 다크 테마 토큰이 명시되어 있었으나, 실제 코드(`colors.dart`)는 과거 버전의 색상(`#0xFF0E0E1C`)과 하드코딩된 블러 값(5.0)을 유지하고 있어 설계와 구현체 간의 심각한 시각적 괴리가 발생했기 때문입니다.

---

## 🔴 Rule 3: `symphonia` MP3 로드 포맷 프로빙 및 버퍼 할당 안정성

*   **발생 시점**: MP3 로드 실패 및 런타임 패닉 (MP3 load failures) 발생 시
*   **재발 방지 규칙 (Rule)**: 오디오 파일 로드(디코딩) 로직 구현 시 반드시 다음 두 가지를 준수합니다.
    1.  `path.extension()`으로 추출한 파일 확장자 문자열은 반드시 소문자(`.to_lowercase()`)로 정규화하여 `Hint::with_extension()`에 주입해야 합니다.
    2.  `SampleBuffer` 생성 시 첫 번째 패킷 크기(`audio_buf.capacity()`)가 아닌, 코덱 파라미터의 최대 프레임 크기(`track.codec_params.max_frames_per_packet.unwrap_or(4096)`)를 우선 기준으로 삼아 충분한 버퍼 공간을 안전하게 할당해야 합니다.
*   **생성 이유 및 근본 원인 (Why)**: 대문자 확장자(예: `.MP3`)가 소문자 정규화 없이 프로빙 힌트로 들어가면 포맷 감지에 실패할 수 있습니다. 또한, 가변 프레임(VBR)을 가질 수 있는 MP3 파일의 특성상 첫 패킷 크기만을 기준으로 버퍼를 할당하면, 이후 도착하는 더 큰 프레임 패킷을 디코딩할 때 할당된 용량을 초과하여 런타임 패닉이 발생하기 때문입니다.
