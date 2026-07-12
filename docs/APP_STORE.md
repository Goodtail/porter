# Porter 배포 가이드 (Mac App Store · Developer ID)

Porter를 서명·공증·심사 제출 가능한 형태로 패키징하는 방법과,
채널별 제약을 정리한 문서입니다.

## 요약 — 어떤 채널로 배포할 것인가

| | Mac App Store | Developer ID (직접 배포) |
|---|---|---|
| App Sandbox | **필수** | 불필요 |
| Porter 로컬 스캔(lsof) | ❌ 샌드박스에서 차단 | ✅ |
| Porter 프로세스 종료(kill) | ❌ 타 프로세스 시그널 차단 | ✅ |
| SSH 원격 관리 | ❌ `~/.ssh` 접근·ssh 스폰 차단 | ✅ |
| 공증(notarization) | 불필요(심사로 대체) | 필수 |
| 스크립트 | `Scripts/release-appstore.sh` | `Scripts/release-notarized.sh` |

> **결론: 현재 아키텍처의 Porter는 Developer ID 배포가 유일하게 온전히
> 동작하는 채널입니다.** Mac App Store는 App Sandbox가 강제되는데, Porter의
> 핵심 기능 3가지가 모두 샌드박스 정책에 막힙니다:
>
> 1. **포트 스캔** — `/bin/zsh -c "lsof …"`로 전체 프로세스의 소켓을
>    열람하는데, 샌드박스 자식 프로세스는 자기 자신 외의 프로세스 정보를
>    볼 수 없습니다.
> 2. **프로세스 종료** — 샌드박스 앱은 자신이 스폰하지 않은 PID에
>    SIGTERM/SIGKILL을 보낼 수 없습니다.
> 3. **SSH** — `/usr/bin/ssh` 스폰 시 샌드박스가 상속되어 `~/.ssh/config`,
>    개인키 읽기가 거부됩니다.
>
> 그래도 MAS로 가려면 기능 축소(예: 원격 SSH 전용 모드를 libssh 내장
> 구현으로 대체)라는 아키텍처 변경이 선행돼야 합니다. 이 저장소에는
> 그날을 위해 MAS 파이프라인(`release-appstore.sh` + entitlements)도
> 준비되어 있습니다.

## 사전 준비 (공통)

1. **Apple Developer Program** 가입 (연 $99) — https://developer.apple.com
2. **번들 ID** — 기본값은 `com.goodtail.porter`로 확정되어 있습니다. 다른 ID가 필요하면
   도메인 기반(예: `com.yourdomain.porter`)으로 정해 모든 스크립트에
   `BUNDLE_ID=…`로 넘기세요. 한 번 배포하면 바꿀 수 없습니다.
3. **버전 정책** — `VERSION`(마케팅 버전, 예: 1.0.0)과
   `BUILD_NUMBER`(업로드마다 증가해야 하는 정수)를 스크립트 env로 관리합니다.

## 경로 A — Developer ID + 공증 (권장)

### 1회 설정

```sh
# 인증서: Xcode → Settings → Accounts → Manage Certificates
#         → "Developer ID Application" 생성
security find-identity -v -p codesigning   # 발급 확인

# 공증 자격 증명 저장 (비밀번호는 appleid.apple.com의 앱 암호)
xcrun notarytool store-credentials porter-notary \
  --apple-id you@example.com --team-id TEAMID1234 --password <app-specific-pw>
```

### 릴리스

```sh
DEVELOPER_ID="Developer ID Application: Your Name (TEAMID1234)" \
BUNDLE_ID=com.yourdomain.porter VERSION=1.0.0 BUILD_NUMBER=1 \
Scripts/release-notarized.sh
```

산출물: `dist/Porter-1.0.0.dmg` — 서명·공증·스테이플 완료, 웹사이트/GitHub
Releases/Homebrew cask 어디로든 배포 가능.

### 자동 업데이트 (Sparkle 2 + GitHub Releases)

앱에 Sparkle 2가 내장되어 있어, 설치된 앱이 실행 시 업데이트 피드
(`appcast.xml`, repo main 브랜치의 raw URL)를 확인하고 새 버전을
다운로드·검증·교체합니다. Sparkle 자체 UI는 한국어·일본어 포함 다국어가
프레임워크에 내장되어 있고, 앱 메뉴(Porter → 업데이트 확인…)로 수동 확인도
가능합니다.

**1회 설정** (공증 설정에 더해):

```sh
swift build                                          # Sparkle 도구 받기
.build/artifacts/sparkle/Sparkle/bin/generate_keys   # EdDSA 키쌍 → 로그인 키체인
export SPARKLE_ED_PUBLIC_KEY="<출력된 공개키>"          # 앱 Info.plist에 들어감
gh auth login                                        # GitHub CLI 인증
```

> ⚠️ `generate_keys`의 개인키는 로그인 키체인에 저장됩니다. 이 키를 잃으면
> 기존 사용자에게 업데이트를 배포할 수 없으니 `generate_keys -x`로 백업하세요.

**릴리스 (전 과정 자동)**:

```sh
DEVELOPER_ID="Developer ID Application: Your Name (TEAMID1234)" \
SPARKLE_ED_PUBLIC_KEY="..." VERSION=1.0.0 BUILD_NUMBER=2 \
Scripts/release-github.sh
```

공증된 DMG 생성 → EdDSA 서명 + `appcast.xml` 재생성 → GitHub Release 업로드 →
appcast를 main에 push까지 한 번에 처리합니다. `BUILD_NUMBER`는 릴리스마다
증가해야 Sparkle이 새 버전으로 인식합니다.

## 경로 B — Mac App Store

### 1회 설정

1. developer.apple.com → Identifiers에서 번들 ID 등록 (App Sandbox 체크)
2. 인증서 2종 발급: **Apple Distribution**, **Mac Installer Distribution**
3. Profiles → 새 프로비저닝 프로파일: 타입 **Mac App Store**, 위 번들 ID로
   생성 후 `.provisionprofile` 다운로드
4. App Store Connect → 새 macOS 앱 생성 (이름 Porter, 기본 언어, 번들 ID,
   SKU 지정)

### 패키징·업로드

```sh
APP_SIGN_IDENTITY="Apple Distribution: Your Name (TEAMID1234)" \
PKG_SIGN_IDENTITY="3rd Party Mac Developer Installer: Your Name (TEAMID1234)" \
PROVISIONING_PROFILE=~/Downloads/Porter_MAS.provisionprofile \
BUNDLE_ID=com.yourdomain.porter VERSION=1.0.0 BUILD_NUMBER=1 \
Scripts/release-appstore.sh
```

산출물 `dist/Porter-1.0.0.pkg`를 **Transporter** 앱(Mac App Store에서 무료
설치)으로 업로드 → App Store Connect에서 빌드 선택 → 심사 제출.

### App Store Connect 메타데이터 체크리스트

- [ ] 앱 이름·부제 (지역화: en / ko / ja — 앱 UI와 동일한 3개 언어)
- [ ] 설명·키워드·지원 URL·마케팅 URL (README의 3개 언어 버전 활용)
- [ ] 스크린샷 — 1280×800 / 1440×900 / 2560×1600 / 2880×1800 중 한 세트.
      `docs/screenshot-*.png` 원본을 요구 해상도로 재촬영 필요
      (Porter의 `--screenshot <출력폴더>` 데모 모드 활용 가능)
- [ ] 앱 개인정보 — Porter는 **수집하는 데이터 없음** (분석·추적·계정 없음.
      SSH 비밀번호는 메모리에만 유지, 이력은 로컬 파일)
- [ ] 수출 규정(암호화) — `ITSAppUsesNonExemptEncryption=false`가 Info.plist에
      이미 선언됨 (자체 암호화 구현 없음, SSH는 시스템 바이너리에 위임)
- [ ] 카테고리 — 개발자 도구 (`LSApplicationCategoryType`에 선언됨)
- [ ] 저작권 — `COPYRIGHT` env로 실명 반영 권장
- [ ] 심사 노트 — 데모 모드 실행법(`Porter --demo`)과 앱 성격(로컬 개발
      서버 관리 도구) 설명 첨부

## 지역화(Localization) 구조

- 소스 문자열은 한국어이며, `Sources/Porter/L10n.swift`의 `L()` 헬퍼가
  `Sources/Porter/Resources/{ko,en,ja}.lproj/Localizable.strings`에서
  조회합니다. 지원 외 언어는 영어로 폴백합니다(`defaultLocalization: "en"`).
- 새 UI 문자열을 추가할 때: 코드에서 `L("한국어 문자열")`로 감싸고, 세
  `.strings` 파일에 같은 키를 추가하세요. 문자열 보간은 `Int → %lld`,
  `String → %@` 형식 지정자로 키에 나타납니다.
- 언어별 확인 — 반드시 `.app` 번들로 실행해야 합니다. bare 바이너리
  (`swift run`)는 번들 ID가 없어 `-AppleLanguages` 오버라이드가 무시되고
  개발 언어(en)로 고정됩니다:
  ```sh
  Scripts/make-app.sh
  dist/Porter.app/Contents/MacOS/Porter --demo -AppleLanguages "(en)"   # 영어
  dist/Porter.app/Contents/MacOS/Porter --demo -AppleLanguages "(ja)"   # 일본어
  ```
- 앱 번들의 `CFBundleLocalizations` + `.lproj` 스텁은 `make-app.sh`가
  생성하며, 시스템 설정 → 언어별 앱 설정에서 Porter가 노출되게 합니다.

## 자주 걸리는 심사·공증 이슈

- **공증 실패 "The signature does not include a secure timestamp"** —
  `release-notarized.sh`가 `--timestamp`를 이미 포함. 수동 서명 시 주의.
- **MAS 심사에서 ATS(`NSAllowsArbitraryLoads`) 소명 요구** — 파비콘을
  로컬/사설망 dev 서버(http)에서 가져오는 용도라고 심사 노트에 기재.
- **`CFBundleVersion` 중복** — 업로드마다 `BUILD_NUMBER`를 올릴 것.
- **ad-hoc 서명 배포 금지** — `make-app.sh` 단독 산출물은 개발용입니다.
