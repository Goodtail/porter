<p align="center">
  <img src="../Assets/icon-1024.png" width="128" alt="Porter 아이콘">
</p>

<h1 align="center">Porter</h1>

<p align="center">
  개발자를 위한 macOS 네이티브 프로세스·포트 매니저 —<br>
  로컬 Mac과 <b>SSH 원격 서버</b>의 개발 서버를 한 창에서 모니터링하고 안전하게 제어합니다.
</p>

<p align="center">
  <a href="../README.md">English</a> · <b>한국어</b> · <a href="README.ja.md">日本語</a>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/macOS-14%2B-000000?logo=apple&logoColor=white" alt="macOS 14+">
  <img src="https://img.shields.io/badge/Swift-6-F05138?logo=swift&logoColor=white" alt="Swift 6">
  <img src="https://img.shields.io/badge/UI-SwiftUI-0A84FF" alt="SwiftUI">
  <img src="https://img.shields.io/badge/dependencies-zero-A78BFA" alt="의존성 없음">
  <img src="https://img.shields.io/badge/license-MIT-blue" alt="MIT 라이선스">
  <img src="https://img.shields.io/badge/PRs-welcome-3FDCA4" alt="PR 환영">
</p>

![Porter 개요](screenshot-overview.png)

`lsof -i :3000` → `ps aux | grep` → `kill -9` → 재확인… 이 조합을 로컬에서도,
SSH로 접속한 GPU 서버에서도 반복하고 있다면 — Porter는 그 전체 흐름을 클릭
몇 번으로 줄입니다. 원격 머신도 **localhost와 완전히 동일한 UX**로 다룹니다.

## 주요 기능

- **포트 스캔** — 선택한 타깃(로컬/SSH)의 LISTEN 중인 TCP 포트 전체를
  프로세스명·PID·사용자·바인드 주소와 함께 표시. 로컬 3초 / 원격 6초 폴링
- **개발 포트 인텔리전스** — 3000(Next.js), 5173(Vite), 8000(Django/FastAPI),
  8888(Jupyter), 11434(Ollama), 5432(PostgreSQL) 등 잘 알려진 포트에 라벨 표시
- **프로젝트 식별** — 각 프로세스의 작업 디렉토리에서 `package.json`,
  `pyproject.toml`, `go.mod`, `Cargo.toml` 등을 읽어 이 서비스가 실제로 무엇인지
  표시: `Next.js · acme-web`, `NestJS · pind-api`. SSH에서도 전체 프로세스를
  **배치 스크립트 1회 왕복**으로 처리
- **카테고리 섹션** — FRONTEND · BACKEND · DATABASE · AI/ML · OTHER로
  목록 자동 그룹핑 (토글 가능)
- **브라우저 바로가기** — 클릭 한 번으로 `http://localhost:3000` 열기.
  머신(로컬/원격)에서 Tailscale이 감지되면 tailnet URL도 함께 제공 —
  GPU 서버의 dev 서버를 어떤 기기에서든 한 번에 접속
- **"이 포트 비어있나?"** — 검색창에 포트 번호를 입력하면 점유 프로세스를
  찾아주거나, 비어 있으면 "사용 가능"을 명시
- **프로세스 인스펙터** — 전체 실행 명령어와 작업 디렉토리(복사 버튼),
  CPU/MEM, 시작 시각, 열려 있는 로그 파일 자동 감지 + tail 미리보기

![Porter 상세 패널](screenshot-detail.png)

- **안전한 Kill** — 확인 시트에 *무엇을 어디서* 죽이는지(타깃, PID, 포트, 전체
  명령어) 항상 표시. SIGTERM → 생존 확인 → 실패했을 때만 SIGKILL 노출.
  root/시스템 프로세스는 추가 체크박스 확인 필요
- **Restart** — 기록된 작업 디렉토리에서 같은 명령어로 재기동 (실행 전 수정 가능)
- **SSH 네이티브** — `~/.ssh/config`의 호스트 자동 인식, 기존 키/agent 그대로
  사용. 서버가 비밀번호를 요구하면 앱 내에서 물어보고(메모리 보관, Keychain
  저장은 opt-in) ControlMaster로 인증된 연결을 재사용. 원격에 에이전트 설치
  불필요 — `lsof`/`ss`/`ps`만 있으면 동작
- **푸시 기반 종료 감지** — 표시 중인 로컬 PID를 kqueue로 감시. dev 서버가
  죽는 순간 폴링 주기와 무관하게 UI 즉시 갱신
- **Activity Feed** — 모든 스캔/킬/재시작을 시간순 기록.
  "아까 내가 뭘 죽였지?"에 항상 답할 수 있음

## 설치

macOS 14+ 및 Xcode Command Line Tools(Swift 6) 필요.

```bash
git clone <this-repo> && cd process-manager

# 바로 실행
swift run

# 또는 배포 가능한 앱 번들 생성 (dist/Porter.app, ad-hoc 서명)
./Scripts/make-app.sh
```

### 헤드리스 CLI 스캔

GUI 없이 같은 스캔 엔진 사용:

```bash
.build/release/Porter --scan              # 로컬 스캔
.build/release/Porter --scan gpu-server   # ~/.ssh/config의 호스트 스캔
```

### 데모 모드

`swift run Porter --demo` — 실제 프로세스 노출 없이 큐레이션된 가짜 데이터로
UI를 둘러보거나 스크린샷을 찍을 때 유용합니다.

## 동작 원리

```
사이드바(타깃) │ 포트 리스트 │ 인스펙터        ← SwiftUI, 다크 전용 3-패널
                AppState (@MainActor)
        ┌───────── Scan/Control Engine ─────────┐
        │ Scanner : 스크립트 생성 + 파서          │  로컬/원격이 같은 코드 경로.
        │ Runner  : LocalRunner (zsh)            │  실행기만 교체됩니다.
        │           SSHRunner (시스템 ssh)        │
        └────────────────────────────────────────┘
```

- 포트 스캔: `lsof -nP -iTCP -sTCP:LISTEN -F…` (머신 파싱 모드 — 공백 포함
  프로세스명 안전). lsof 없는 Linux 서버는 `ss -ltnp` 자동 폴백
- 상세 조회: ps + lsof(cwd/로그)를 마커로 구분한 **단일 스크립트 1회 왕복** —
  SSH 레이턴시를 한 번만 지불
- 갱신 전략: 소켓 목록은 스냅샷 폴링(유일한 이식 가능한 방법)이 기본이되,
  로컬 PID는 kqueue `NOTE_EXIT` 푸시로 보강하고, 창이 가려지면 폴링을 멈추며,
  로컬 3초/원격 6초로 차등 적용
- 비밀번호는 `SSH_ASKPASS` 헬퍼를 통해 환경 변수로만 ssh에 전달 — 명령줄·디스크
  노출 없음. 키 전용 서버(`Permission denied (publickey)`)에는 물어보지 않음

## 안전 모델

- Kill 확인 시트에 타깃/프로세스/PID/포트/전체 명령어 항상 표시 —
  "엉뚱한 PID를 죽였다" 사고 방지
- SIGKILL은 SIGTERM 실패가 확인된 뒤에만 노출되는 2차 수단
- 휴리스틱 보호: root 소유, 시스템 경로(`/System`, `/usr/libexec` 등),
  낮은 PID는 경고 배지 + 명시적 확인 체크박스
- Keychain 저장을 선택하지 않는 한 비밀번호를 저장하지 않음

## 개발

```bash
swift test                             # 파서·인증 단위 테스트
./Scripts/make-icons.sh                # 플랫 아이콘 에셋 재생성
swift run Porter --screenshot docs     # README 스크린샷 재생성 (데모 데이터)
```

기여 환영합니다 — 이슈나 PR을 열어주세요.

## 로드맵

- v0.2 — 메뉴바 모드, 프로세스 그룹 재기동, 로그 스트리밍, 다국어 지원
- v0.3 — tmux 세션 뷰, Docker 컨테이너 인식, 공증(notarized) 릴리스

전체 제품 스펙은 [PRD.md](../PRD.md) 참고.

## 라이선스

[MIT](../LICENSE)
