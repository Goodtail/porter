# Homebrew cask draft for Porter — 첫 릴리스 후에 제출용.
#
# 채워야 할 것:
#   1. sha256:  shasum -a 256 dist/Porter-<VERSION>.dmg
#   2. zap의 Preferences plist 경로를 최종 번들 ID로 교체
#
# 배포 방법 (둘 중 하나):
#   A. 개인 tap (즉시 가능):
#      blick9/homebrew-tap 저장소를 만들고 이 파일을 Casks/porter.rb로 push
#      → 사용자는 `brew install --cask blick9/tap/porter`
#   B. homebrew-cask 본진 제출 (인지도 기준 충족 시):
#      https://github.com/Homebrew/homebrew-cask 에 PR
#      → 사용자는 `brew install --cask porter`
cask "porter" do
  version "1.0.0"
  sha256 "REPLACE_WITH_SHA256_OF_RELEASE_DMG"

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

  zap trash: [
    "~/.porter",
    "~/Library/Preferences/REPLACE.WITH.FINAL.BUNDLE.ID.plist",
  ]
end
