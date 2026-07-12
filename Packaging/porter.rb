# Homebrew cask for Porter — canonical copy.
# 배포 위치: blick9/homebrew-tap 저장소의 Casks/porter.rb 로 복사해 push하면
# `brew install --cask blick9/tap/porter` 로 설치 가능.
# 새 릴리스마다 version과 sha256(shasum -a 256 dist/Porter-<VERSION>.dmg)을 갱신.
cask "porter" do
  version "0.1.0"
  sha256 "2a33b6ec15af92bcee300896dd0e1c14b03ab4b09f6e36656aba5524b2c36471"

  url "https://github.com/blick9/porter/releases/download/v#{version}/Porter-#{version}.dmg"
  name "Porter"
  desc "Process and port manager for dev servers, local and over SSH"
  homepage "https://github.com/blick9/porter"

  livecheck do
    url :url
    strategy :github_latest
  end

  # Sparkle keeps the app current between cask releases.
  auto_updates true
  depends_on macos: ">= :sonoma"

  app "Porter.app"

  caveats <<~EOS
    Pre-1.0 builds of Porter are not notarized yet. If macOS blocks the first
    launch, reinstall with:
      brew reinstall --cask --no-quarantine porter
    or allow Porter under System Settings → Privacy & Security.
  EOS

  zap trash: [
    "~/.porter",
    "~/Library/Preferences/dev.porter.Porter.plist",
  ]
end
