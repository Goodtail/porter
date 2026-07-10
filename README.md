# Porter

> 로컬 Mac과 SSH 원격 서버의 개발 프로세스·포트를 한 화면에서 모니터링하고
> 안전하게 종료/재시작하는 macOS 네이티브 프로세스 매니저.

`lsof -i :3000` → `ps aux | grep` → `kill -9` → 재확인… 이 조합을 반복하고 있다면,
Porter는 그 전체 흐름을 클릭 몇 번으로 줄입니다. 메인 Mac에서 SSH로 원격 머신을
운영하는 개발자를 위해, **원격 프로세스도 로컬과 완전히 동일한 UX**로 다룹니다.

## 주요 기능

- **포트 스캔** — 선택한 타깃(로컬/SSH)의 LISTEN 중인 TCP 포트를 프로세스명·PID·사용자와 함께 표시. 5초 자동 새로고침
- **개발 포트 인텔리전스** — 3000(Next.js), 5173(Vite), 8000(Django/FastAPI), 8888(Jupyter), 11434(Ollama) 등 잘 알려진 포트에 라벨 표시
- **포트 충돌 사전 확인** — 검색창에 포트 번호를 입력하면 점유 프로세스를 찾거나, 비어 있으면 "사용 가능"을 명시
- **프로세스 상세** — 전체 실행 명령어, 작업 디렉토리(복사 버튼), CPU/MEM, 열려 있는 로그 파일 자동 감지 + tail 미리보기
- **안전한 제어** — Kill(SIGTERM) → 생존 확인 → Force Kill(SIGKILL) 단계적 제어. 확인 시트에 타깃/PID/명령어를 명시해 오조작 방지. root·시스템 프로세스는 보호 배지 + 추가 확인
- **Restart** — 기록된 작업 디렉토리에서 같은 명령어로 재기동 (명령어 수정 가능)
- **SSH 네이티브** — `~/.ssh/config`의 Host 자동 인식, 기존 키/agent 우선 사용. 키 인증이 거부되고 서버가 비밀번호를 받으면 **앱 내에서 비밀번호를 물어보고** (세션 메모리 보관, Keychain 저장은 opt-in) askpass 경유로 접속. ControlMaster로 인증 세션 재사용 — 폴링마다 재인증하지 않음. 원격에 에이전트 설치 불필요 — lsof/ss/ps만 있으면 동작
- **Activity Feed** — 모든 스캔/킬/재시작 이벤트를 시간순 기록. "아까 내가 뭘 죽였지?"에 항상 답할 수 있음

## 빌드 & 실행

요구사항: macOS 14+, Xcode Command Line Tools (Swift 6+)

```bash
swift build -c release
.build/release/Porter            # GUI 실행
```

개발 중에는:

```bash
swift run
```

### 헤드리스 스캔 (CLI)

GUI 없이 같은 스캔 엔진을 터미널에서 사용할 수 있습니다.

```bash
.build/release/Porter --scan              # 로컬 스캔
.build/release/Porter --scan gpu-server   # ~/.ssh/config의 호스트 스캔
```

## 아키텍처 한눈에

```
Sidebar(Targets) │ PortList │ DetailPanel     ← SwiftUI, 다크 전용 3-패널
                AppState (@MainActor)
        ┌─────── Scan/Control Engine ───────┐
        │ Scanner  : 스크립트 생성 + 파서    │   로컬/원격이 같은 코드 경로.
        │ Runner   : LocalRunner(zsh)       │   실행기만 교체된다.
        │            SSHRunner(ssh binary)  │
        └───────────────────────────────────┘
```

- 포트 스캔: `lsof -nP -iTCP -sTCP:LISTEN -F…` (머신 파싱 모드 — 공백 포함 프로세스명 안전). lsof가 없는 Linux 서버는 `ss -ltnp` 자동 폴백
- 상세 조회: ps + lsof(cwd/로그)를 마커로 구분한 **단일 스크립트 1회 왕복** — SSH 레이턴시 최소화
- Restart는 로컬에서 로그인 셸(zsh -l)로 실행되어 nvm/pyenv 등 사용자 PATH를 상속

### 갱신 전략 — 폴링 + 푸시 하이브리드

포트 **목록**은 스냅샷 API(lsof/ss)밖에 없어 폴링이 표준입니다(Activity Monitor도 동일).
Porter는 폴링 비용과 반응 지연을 다음으로 줄입니다:

- **kqueue 푸시 감지** — 화면에 표시된 로컬 PID는 `NOTE_EXIT`로 감시. 프로세스가
  죽는 순간(Porter 밖에서 kill해도) 폴링 주기와 무관하게 즉시 목록 갱신
- **가시성 인지** — 창이 다른 창에 가려지면 폴링 중단, 다시 보이는 순간 즉시 1회 스캔
- **차등 주기** — 로컬 3초(스냅샷 비용 ~수십 ms) / 원격 6초. 원격은 ControlMaster
  세션을 타므로 폴링당 비용은 이미 인증된 연결의 왕복 1회뿐
- 비밀번호 입력 중이거나 인증 실패로 막힌 타깃은 폴링을 보류해 서버를 두드리지 않음

## 안전장치

- Kill 전 확인 시트에 **무엇을 어디서** 죽이는지(타깃, 프로세스, PID, 포트, 전체 명령어) 항상 표시
- SIGKILL은 SIGTERM이 실패했을 때만 2차 수단으로 노출
- root 소유, `/System`·`/usr/libexec` 경로, 낮은 PID 프로세스는 경고 + 별도 체크박스 확인 요구
- SSH는 키/agent 인증 우선(BatchMode로 즉시 실패 감지). 서버가 비밀번호 인증을 받는 경우에만 앱 내 프롬프트 표시 — 비밀번호는 ssh 프로세스에 환경 변수로만 전달되고(명령줄·디스크 노출 없음), 기본은 세션 메모리 보관, Keychain 저장은 체크박스로 opt-in
- 키 전용 서버(`Permission denied (publickey)`)에는 비밀번호를 물어보지 않음 — 물어봐도 소용없기 때문

## 로드맵

- v0.2 — 메뉴바 상주 모드, 프로세스 그룹 일괄 재기동, 로그 스트리밍
- v0.3 — tmux 세션 뷰, Docker 컨테이너 인식, 서명된 앱 번들 배포

자세한 요구사항은 [PRD.md](PRD.md) 참고.
