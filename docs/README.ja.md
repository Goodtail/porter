<p align="center">
  <img src="../Assets/icon-1024.png" width="128" alt="Porter アイコン">
</p>

<h1 align="center">Porter</h1>

<p align="center">
  開発者のための macOS ネイティブなプロセス&amp;ポートマネージャー —<br>
  ローカル Mac と <b>SSH リモートサーバー</b>の開発サーバーを、ひとつのウィンドウで監視・安全に制御。
</p>

<p align="center">
  <a href="../README.md">English</a> · <a href="README.ko.md">한국어</a> · <b>日本語</b>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/macOS-14%2B-000000?logo=apple&logoColor=white" alt="macOS 14+">
  <img src="https://img.shields.io/badge/Swift-6-F05138?logo=swift&logoColor=white" alt="Swift 6">
  <img src="https://img.shields.io/badge/UI-SwiftUI-0A84FF" alt="SwiftUI">
  <img src="https://img.shields.io/badge/dependencies-zero-A78BFA" alt="依存関係ゼロ">
  <img src="https://img.shields.io/badge/license-MIT-blue" alt="MIT ライセンス">
  <img src="https://img.shields.io/badge/PRs-welcome-3FDCA4" alt="PR 歓迎">
</p>

![Porter 概要](screenshot-overview.png)

`lsof -i :3000` → `ps aux | grep` → `kill -9` → 再確認…。この繰り返しを、
ローカルでも SSH 先の GPU サーバーでもやっているなら — Porter はその一連の
流れを数クリックに短縮します。リモートマシンも **localhost と完全に同じ UX**
で扱えます。

## 主な機能

- **ポートスキャン** — 選択したターゲット(ローカル/SSH)で LISTEN 中の TCP
  ポートを、プロセス名・PID・ユーザー・バインドアドレスと共に一覧表示。
  ローカル 3 秒 / リモート 6 秒でポーリング
- **開発ポートの自動ラベル** — 3000 (Next.js)、5173 (Vite)、8000 (Django/FastAPI)、
  8888 (Jupyter)、11434 (Ollama)、5432 (PostgreSQL) など既知のポートにラベル表示
- **「このポート空いてる?」** — 検索欄にポート番号を入力すると、占有プロセスを
  表示するか、空いていれば「使用可能」と明示
- **プロセスインスペクター** — 完全なコマンドライン、作業ディレクトリ(どちらも
  コピー可)、CPU/MEM、起動時刻、開いているログファイルの自動検出 + tail プレビュー

![Porter 詳細パネル](screenshot-detail.png)

- **安全な Kill** — 確認シートに*何を・どこで*終了するのか(ターゲット、PID、
  ポート、完全なコマンド)を常に表示。まず SIGTERM → 生存確認 → 失敗した場合
  のみ SIGKILL を提示。root/システムプロセスは追加のチェックボックス確認が必要
- **Restart** — 記録された作業ディレクトリで同じコマンドを再起動(実行前に編集可)
- **SSH ネイティブ** — `~/.ssh/config` のホストを自動認識し、既存の鍵/agent を
  そのまま使用。サーバーがパスワードを要求する場合はアプリ内でプロンプト表示
  (メモリ保持、Keychain 保存はオプトイン)し、ControlMaster で認証済み接続を
  再利用。リモートへのエージェント導入は不要 — `lsof`/`ss`/`ps` があれば動作
- **プッシュ型の終了検知** — 表示中のローカル PID を kqueue で監視。dev サーバー
  が落ちた瞬間、ポーリング間隔に関係なく UI を即時更新
- **アクティビティフィード** — すべてのスキャン/kill/再起動を時系列で記録。
  「さっき何を kill したっけ?」に常に答えられます

## インストール

macOS 14+ と Xcode Command Line Tools (Swift 6) が必要です。

```bash
git clone <this-repo> && cd process-manager

# そのまま実行
swift run

# または配布可能なアプリバンドルを作成 (dist/Porter.app、ad-hoc 署名)
./Scripts/make-app.sh
```

### ヘッドレス CLI スキャン

GUI なしで同じスキャンエンジンを使用:

```bash
.build/release/Porter --scan              # ローカルをスキャン
.build/release/Porter --scan gpu-server   # ~/.ssh/config のホストをスキャン
```

### デモモード

`swift run Porter --demo` — 実際のプロセスを晒すことなく、キュレーション
されたダミーデータで UI を試したりスクリーンショットを撮ったりできます。

## 仕組み

```
サイドバー(ターゲット) │ ポート一覧 │ インスペクター   ← SwiftUI、ダーク専用 3 ペイン
                    AppState (@MainActor)
        ┌───────── Scan/Control Engine ─────────┐
        │ Scanner : スクリプト生成 + パーサー      │  ローカルとリモートは同じ
        │ Runner  : LocalRunner (zsh)            │  コードパス。実行器だけを
        │           SSHRunner (システム ssh)      │  差し替えます。
        └────────────────────────────────────────┘
```

- ポートスキャン: `lsof -nP -iTCP -sTCP:LISTEN -F…`(機械可読モード — 空白を
  含むプロセス名も安全)。lsof のない Linux サーバーは `ss -ltnp` に自動フォールバック
- 詳細取得: ps + lsof(cwd/ログ)をマーカー区切りの**単一スクリプト・1 往復**に
  集約 — SSH レイテンシは一度だけ
- 更新戦略: ソケット一覧はスナップショットポーリング(唯一のポータブルな方法)を
  基本に、ローカル PID は kqueue `NOTE_EXIT` のプッシュで補強。ウィンドウが
  隠れている間はポーリングを停止し、ローカル 3 秒/リモート 6 秒で差別化
- パスワードは `SSH_ASKPASS` ヘルパー経由の環境変数としてのみ ssh に渡され、
  コマンドラインやディスクには残りません。鍵認証のみのサーバー
  (`Permission denied (publickey)`)にはプロンプトを表示しません

## 安全モデル

- Kill 確認シートにターゲット/プロセス/PID/ポート/完全なコマンドを常に表示 —
  「間違った PID を kill した」事故を防止
- SIGKILL は SIGTERM の失敗が確認された後にのみ表示される第二段階
- ヒューリスティック保護: root 所有、システムパス(`/System`、`/usr/libexec`
  など)、低い PID には警告バッジ + 明示的な確認チェックボックス
- Keychain 保存を選択しない限り、パスワードは保存されません

## 開発

```bash
swift test                             # パーサー・認証のユニットテスト
./Scripts/make-icons.sh                # フラットアイコンアセットの再生成
swift run Porter --screenshot docs     # README スクリーンショットの再生成(デモデータ)
```

現在の UI は韓国語ファーストです。ローカライズ(英語から)はロードマップに
含まれています。コントリビューション歓迎 — Issue や PR をお待ちしています。

## ロードマップ

- v0.2 — メニューバーモード、プロセスグループ再起動、ログストリーミング、多言語対応
- v0.3 — tmux セッションビュー、Docker コンテナ認識、公証(notarized)リリース

製品仕様の全文は [PRD.md](../PRD.md)(韓国語)を参照してください。

## ライセンス

[MIT](../LICENSE)
