#!/usr/bin/env bash
# Publish the macOS agent self-contained, wrap it in TrackpadAgent.app and ad-hoc sign it.
# Usage: scripts/build-mac-agent.sh [arm64|x64|all]   (default: arm64)
# Output: dist/mac-agent-<arch>/ (raw publish) and dist/<arch>/TrackpadAgent.app
set -euo pipefail

ARCH="${1:-arm64}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUNDLE_ID="com.trackpad.agent"

build_one() {
  local arch="$1" rid="osx-$1"
  local pub="$ROOT/dist/mac-agent-$arch"
  local app="$ROOT/dist/$arch/TrackpadAgent.app"
  local macos="$app/Contents/MacOS"

  echo "==> Publishing $rid"
  rm -rf "$pub"
  (cd "$ROOT/agent" && dotnet publish Agent.Mac -c Release -r "$rid" --self-contained -o "$pub")

  echo "==> Bundling $app"
  rm -rf "$app"
  mkdir -p "$macos"
  cp -R "$pub"/. "$macos"/

  # CFBundleExecutable: opens Terminal and runs the real binary there, so the
  # Pairing_Code printed to the console is visible when launched from Finder.
  cat > "$macos/TrackpadAgent" <<'LAUNCHER'
#!/bin/bash
DIR="$(cd "$(dirname "$0")" && pwd)"
osascript - "$DIR/Agent.Mac" <<'OSA'
on run argv
  set cmd to quoted form of (item 1 of argv)
  tell application "Terminal"
    activate
    do script cmd
  end tell
end run
OSA
LAUNCHER
  chmod +x "$macos/TrackpadAgent" "$macos/Agent.Mac"

  cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleName</key><string>TrackpadAgent</string>
  <key>CFBundleDisplayName</key><string>Trackpad Agent</string>
  <key>CFBundleExecutable</key><string>TrackpadAgent</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>LSMinimumSystemVersion</key><string>11.0</string>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

  echo "==> Ad-hoc signing"
  codesign --force --deep -s - "$app"
  codesign --verify --deep --strict "$app"
  echo "Built: $app"
}

case "$ARCH" in
  arm64|x64) build_one "$ARCH" ;;
  all) build_one arm64; build_one x64 ;;
  *) echo "Usage: $0 [arm64|x64|all]" >&2; exit 2 ;;
esac
