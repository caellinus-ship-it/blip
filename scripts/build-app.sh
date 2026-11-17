#!/bin/bash
# Builds Blip.app, signs it, installs it to ~/Applications and opens it.
# Usage: scripts/build-app.sh [--no-open]
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release

APP=build/Blip.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$(swift build -c release --show-bin-path)/Blip" "$APP/Contents/MacOS/Blip"
cp Resources/Info.plist "$APP/Contents/Info.plist"

codesign --force --sign "${BLIP_SIGN_ID:-$(security find-identity -v -p codesigning | awk 'NR==1{print $2}')}" "$APP"

pkill -x Blip || true
mkdir -p ~/Applications
rm -rf ~/Applications/Blip.app
cp -R "$APP" ~/Applications/Blip.app

if [[ "${1:-}" != "--no-open" ]]; then
  open ~/Applications/Blip.app
fi
