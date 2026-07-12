# Homebrew cask for Porter — canonical copy.
# 배포 위치: Goodtail/homebrew-tap 저장소의 Casks/porter.rb 로 복사해 push하면
# `brew install --cask goodtail/tap/porter` 로 설치 가능.
# 새 릴리스마다 version과 sha256(shasum -a 256 dist/Porter-<VERSION>.dmg)을 갱신.
cask "porter" do
  version "0.1.0"
  sha256 "258cea35f9aa407ed7db98b5b18ed5db88b16afab3d0d42a32003743d3408994"

  url "https://github.com/Goodtail/porter/releases/download/v#{version}/Porter-#{version}.dmg"
  name "Porter"
  desc "Process and port manager for dev servers, local and over SSH"
  homepage "https://github.com/Goodtail/porter"

  livecheck do
    url :url
    strategy :github_latest
  end

  # Sparkle keeps the app current between cask releases.
  auto_updates true
  depends_on macos: :sonoma

  app "Porter.app"

  zap trash: [
    "~/.porter",
    "~/Library/Preferences/com.goodtail.mac.porter.plist",
  ]

  caveats <<~EOS
    Pre-1.0 builds of Porter are not notarized yet. If macOS blocks the first
    launch, reinstall with:
      brew reinstall --cask --no-quarantine porter
    or allow Porter under System Settings → Privacy & Security.
  EOS
end
