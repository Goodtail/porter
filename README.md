<p align="center">
  <img src="Assets/icon-1024.png" width="128" alt="Porter icon">
</p>

<h1 align="center">Porter</h1>

<p align="center"><b>Goodtail Open Source · 00</b></p>

<p align="center">
  A native macOS process &amp; port manager for developers —<br>
  monitor and safely control dev servers on your Mac <b>and over SSH</b>, in one window.
</p>

<p align="center">
  <b>English</b> · <a href="docs/README.ko.md">한국어</a> · <a href="docs/README.ja.md">日本語</a>
</p>

<p align="center">
  <a href="https://goodtail.app/s/porter">Product page</a> ·
  <a href="https://github.com/Goodtail/porter/releases/latest">Download</a> ·
  <a href="https://github.com/Goodtail/porter/issues">Issues</a>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/macOS-14%2B-000000?logo=apple&logoColor=white" alt="macOS 14+">
  <img src="https://img.shields.io/badge/Swift-6-F05138?logo=swift&logoColor=white" alt="Swift 6">
  <img src="https://img.shields.io/badge/UI-SwiftUI-0A84FF" alt="SwiftUI">
  <a href="https://github.com/Goodtail/porter/releases/latest"><img src="https://img.shields.io/github/v/release/Goodtail/porter?label=download&color=3FDCA4" alt="Download latest release"></a>
  <img src="https://img.shields.io/badge/license-MIT-blue" alt="MIT License">
  <img src="https://img.shields.io/badge/PRs-welcome-3FDCA4" alt="PRs welcome">
</p>

![Porter overview](docs/screenshot-overview.png)

If your day includes `lsof -i :3000` → `ps aux | grep` → `kill -9` → check again —
on your Mac *and* on the GPU box you SSH into — Porter collapses that whole loop
into a couple of clicks. Remote machines get **exactly the same UX as localhost**.

## Features

- **Port scanner** — every listening TCP port on the selected target (local or SSH),
  with process name, PID, user and bind address. Polls every 3s locally / 6s remotely
- **Menu bar quick panel** — Porter lives in the menu bar: glance at listening ports
  and kill them in one click, even with the main window closed. Launch at login and
  menu bar behavior are configurable in Settings (⌘,)
- **Dev-port intelligence** — well-known ports get labels: 3000 (Next.js), 5173 (Vite),
  8000 (Django/FastAPI), 8888 (Jupyter), 11434 (Ollama), 5432 (PostgreSQL), …
- **Project identity** — Porter reads each process's working directory
  (`package.json`, `pyproject.toml`, `go.mod`, `Cargo.toml`, …) and tells you what
  the service actually is: `Next.js · acme-web`, `NestJS · pind-api`. Over SSH this
  costs a single batched round-trip for all processes
- **Category sections** — the list groups into FRONTEND · BACKEND · DATABASE ·
  AI/ML · OTHER (toggleable)
- **Open in browser** — one click opens `http://localhost:3000`. When Tailscale is
  detected on the machine (local or remote), a tailnet URL is offered too — a dev
  server on your GPU box is one click away from any device
- **"Is this port free?"** — type a port number in the search box; Porter either shows
  you the offender or tells you the port is free to use
- **Process inspector** — full command line, working directory (both copyable),
  CPU/MEM, start time, plus auto-detected open log files with a tail preview
- **Live log streaming** — follow any detected log file in real time (`tail -F`,
  local or over SSH). Processes restarted through Porter get their output
  captured to `~/.porter/logs/` — instantly streamable even if they used to log
  only to a terminal
- **Run history** — every kill/restart snapshots the full command, working
  directory, port and target *before* the process dies. The clock button lists
  them; one click relaunches — no more digging for "what was that command again?"
- **Favicons in the list** — a URL column shows each service's address with the
  favicon fetched from the running service itself (`/favicon.ico`, falling back
  to the homepage's `<link rel=icon>`); click to open
- **Move to another port** — the restart sheet has a PORT field: Porter rewrites
  `--port 3000` / `-p 3000` / `PORT=3000` in the command (or prepends `PORT=`),
  shows you the result, and relaunches — "3000 is taken, run it on 3001" is now
  one button

![Porter detail panel](docs/screenshot-detail.png)

- **Safe kill** — the confirmation sheet always shows *what* dies *where*
  (target, PID, port, full command). SIGTERM first, liveness check, and SIGKILL is
  only offered after SIGTERM fails. Root/system processes need an extra checkbox
- **Restart** — kill, then relaunch the same command in its recorded working
  directory (editable before running)
- **SSH-native** — hosts from `~/.ssh/config` appear automatically; your existing
  keys/agent are used as-is. If the server wants a password, Porter asks in-app
  (kept in memory; Keychain storage is opt-in) and reuses the authenticated
  connection via ControlMaster. No agent to install — `lsof`/`ss`/`ps` is all a
  remote needs
- **Push-based exit detection** — displayed local PIDs are watched with kqueue,
  so a dying dev server updates the UI instantly, regardless of the poll interval
- **Activity feed** — a chronological record of every scan, kill and restart.
  Always answers "wait, what did I just kill?"

## Right in your menu bar

<img src="docs/screenshot-menubar.png" width="380" alt="Porter menu bar quick panel">

The full picture without switching windows: click the Porter icon in the menu
bar to see every listening port on any target — and kill a runaway dev server
in one click. Close the main window and Porter keeps watch in the background.

## Install

### Homebrew

```bash
brew install --cask goodtail/tap/porter
```

### Install script

```bash
curl -fsSL https://raw.githubusercontent.com/Goodtail/porter/main/Scripts/install.sh | sh
```

### Manual download

Grab the DMG from **[Releases](https://github.com/Goodtail/porter/releases/latest)**
and drag Porter into Applications. Sparkle support is built in; the signed update
feed will be enabled with a future notarized release.

> Pre-1.0 builds are not notarized yet, so macOS warns on first launch. The
> install script clears the quarantine flag for you; with Homebrew add
> `--no-quarantine`, or allow Porter under System Settings → Privacy & Security.

### Build from source

Requires macOS 14+ and Xcode Command Line Tools (Swift 6).

```bash
git clone https://github.com/Goodtail/porter.git && cd porter

# run directly
swift run

# or build a distributable app bundle (dist/Porter.app, ad-hoc signed)
./Scripts/make-app.sh
```

### Headless CLI scan

The same scan engine, without the GUI:

```bash
.build/release/Porter --scan              # scan this Mac
.build/release/Porter --scan gpu-server   # scan a host from ~/.ssh/config
```

### Demo mode

`swift run Porter --demo` fills the UI with curated fake data — useful for
exploring the UI or taking screenshots without exposing your real processes.

## How it works

```
Sidebar (targets) │ Port list │ Inspector        ← SwiftUI, dark-only, 3-pane
                 AppState (@MainActor)
        ┌───────── Scan/Control Engine ─────────┐
        │ Scanner : script builder + parsers     │  Local and remote share every
        │ Runner  : LocalRunner (zsh)            │  code path — only the runner
        │           SSHRunner (system ssh)       │  is swapped.
        └────────────────────────────────────────┘
```

- Port scan: `lsof -nP -iTCP -sTCP:LISTEN -F…` (machine-parseable mode — process
  names with spaces are safe). Linux servers without lsof fall back to `ss -ltnp`
- Detail fetch: ps + lsof (cwd, logs) batched into **one marker-delimited script,
  one round-trip** — SSH latency is paid once
- Refresh strategy: snapshot polling (the only portable way to list sockets) is
  augmented with kqueue `NOTE_EXIT` push events for local PIDs, paused while the
  window is occluded, and rate-differentiated (local 3s / remote 6s)
- Passwords are fed to ssh through an `SSH_ASKPASS` helper — environment variable
  only, never on a command line or on disk. Key-only servers
  (`Permission denied (publickey)`) are never prompted for a password

## Safety model

- Kill confirmations always display target, process, PID, port and full command —
  the anti-"killed the wrong PID" guard
- SIGKILL is a second step, only surfaced after SIGTERM verifiably failed
- Heuristic protection: root-owned processes, system paths (`/System`,
  `/usr/libexec`, …) and low PIDs get a warning badge and an explicit
  acknowledgement checkbox
- Porter never stores passwords unless you opt into Keychain persistence

## Development

```bash
swift test          # parser & auth unit tests
./Scripts/make-icons.sh   # regenerate icon assets from the flat-design script
swift run Porter --screenshot docs   # regenerate README screenshots (demo data)
```

The app currently ships in English, Korean, and Japanese. Contributions are
welcome — open an issue with a reproducible case or send a focused pull request.

## Roadmap

- Signed and notarized releases with an active Sparkle update feed
- tmux session visibility and Docker container awareness
- Accessibility and localization polish

See [PRD.md](PRD.md) (Korean) for the full product spec.

## License

[MIT](LICENSE)

Porter is the first public open-source project from [Goodtail](https://github.com/Goodtail).
