# macOS 데스크톱 앱 빌드 트러블슈팅 리포트 (Flutter + Rust)

## 1. 개요
본 리포트는 `Atmos Mixer Pro` (Flutter + Rust 하이브리드 아키텍처) 데스크톱 애플리케이션을 macOS 환경에서 최초로 빌드 및 실행하는 과정에서 직면한 주요 장애 요소들과 이를 극복하기 위한 기술적 해결 과정을 기록한 문서입니다. 이 문서는 향후 다른 개발 환경 세팅이나 CI/CD 파이프라인 구축 시 유용한 참고 자료로 활용될 수 있습니다.

---

## 2. 주요 발생 문제 및 해결 과정

### 2.1. Xcode 및 `xcodebuild` 경로 인식 실패
*   **증상**: `xcrun: error: unable to find utility "xcodebuild", not a developer tool or in PATH`
*   **원인**: macOS 애플리케이션 빌드를 위해서는 Apple의 공식 컴파일러인 전체 버전의 Xcode가 필수적이나, 시스템에 설치되어 있지 않거나 Command Line Tools 환경 변수가 올바른 Xcode.app 경로를 가리키지 못했습니다. 또한, App Store의 버전 인식 버그("macOS 버전 26.2 이상 필요")로 인해 정상적인 다운로드가 불가능했습니다.
*   **해결 조치**: 
    1. Apple Developer 포털을 우회하여 Xcode 16 수동 다운로드 및 `응용 프로그램(Applications)` 폴더로 설치 진행.
    2. 터미널 명령어를 통해 강제로 라이선스 동의 처리 (`sudo xcodebuild -license accept`).
    3. `sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer` 명령어로 빌드 도구 경로를 시스템에 정상 매핑 완료.

### 2.2. CocoaPods 패키지 관리자 누락 및 설치 오류
*   **증상**: Flutter 플러그인(iOS/macOS)을 연결하기 위해 필요한 CocoaPods가 없어 빌드 스크립트 실행이 중단됨.
*   **원인**: Homebrew 환경에서 CocoaPods 및 의존성 패키지(Ruby 등)가 누락되어 있었습니다.
*   **해결 조치**: 백그라운드 환경에서 `brew install cocoapods` 명령어를 실행하여 Ruby 및 관련 인증서 체인 업데이트와 함께 CocoaPods를 안정적으로 설치 완료했습니다.

### 2.3. Rust `cpal` 라이브러리의 CoreAudio 링킹(Linking) 에러
*   **증상**: `Undefined symbols for architecture x86_64: _AudioComponentFindNext...`
*   **원인**: 백그라운드 오디오 처리를 담당하는 Rust 엔진이 macOS 사운드 카드에 접근하려 했으나, 플러그인 설정 파일(`podspec`)에 Apple의 기본 오디오 프레임워크(CoreAudio)에 대한 참조가 명시되어 있지 않아 링커(Linker) 에러가 대량 발생했습니다.
*   **해결 조치**: 
    - macOS용 Rust 빌드 설정 파일(`rust_builder/macos/rust_lib_atmos_mixer_pro.podspec`)을 직접 수정.
    - `OTHER_LDFLAGS` 항목에 `-framework CoreAudio -framework AudioUnit -framework AudioToolbox` 속성을 강제 주입하여 오디오 하드웨어 접근 권한을 해결했습니다.

### 2.4. Extended Attributes (보안 속성 찌꺼기) 충돌
*   **증상**: `resource fork, Finder information, or similar detritus not allowed`
*   **원인**: 프로젝트 폴더가 iCloud 동기화 또는 다운로드 과정을 거치면서 파일들에 보이지 않는 확장 속성(`com.apple.fileprovider` 등)이 부여되었으며, 애플의 빌드 무결성 검증 단계에서 이를 보안 위협으로 간주하여 빌드가 중단되었습니다.
*   **해결 조치**: 
    - `xattr -cr .` 명령어를 통해 프로젝트 내 모든 파일의 보안 속성(찌꺼기)을 일괄 삭제.
    - `find . -name ".DS_Store" -delete` 명령어로 시스템 숨김 파일 제거.
    - `flutter clean`으로 기존 오염된 빌드 캐시를 완벽히 초기화했습니다.

### 2.5. CodeSign(보안 서명) 에러 우회
*   **증상**: `Command CodeSign failed with a nonzero exit code`
*   **원인**: 로컬 개발 환경 특성상 Apple Developer 인증서가 세팅되지 않은 상태였으나, Xcode 프로젝트 설정이 서명을 강제하고 있어 최종 `.app` 번들링 단계에서 지속적으로 실패했습니다.
*   **해결 조치**: 
    - `sed` 명령어를 활용하여 `macos/Runner.xcodeproj/project.pbxproj` 파일 수정.
    - `CODE_SIGNING_ALLOWED = YES` 속성을 `NO`로 변경하고, `CODE_SIGN_IDENTITY` 값을 비워 서명 단계를 완전히 우회(Bypass)하도록 조치. 이를 통해 로컬 환경에서 에러 없이 실행 가능한 데스크톱 앱을 성공적으로 도출했습니다.

---

## 3. 결론 및 향후 권장 사항
일련의 트러블슈팅 과정을 통해 macOS 데스크톱 환경에서 Flutter와 Rust 하이브리드 아키텍처를 결합하기 위한 모든 기반 인프라 구축을 완수했습니다. 현재 프로젝트는 어떠한 에러도 발생하지 않는 매우 깨끗한 'Clean Slate' 상태입니다.

**향후 권장 사항**:
- 차후 코드를 수정하고 실행할 때는 별도의 추가 조치 없이 `flutter run -d macos` 명령어만으로 쾌적한 핫 리로드(Hot Reload) 및 빌드 환경을 누릴 수 있습니다.
- 이후 타 팀원(혹은 CI 머신)이 해당 프로젝트를 클론(Clone) 받아 사용할 때를 대비하여, 본 문서의 조치 사항(특히 2.3항의 podspec 프레임워크 설정)은 소스코드 관리(Git)에 영구적으로 반영되어야 합니다.
