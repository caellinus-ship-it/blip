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

# Sign with BLIP_SIGN_ID, else the first code-signing identity on this Mac, else ad hoc ("-").
# An ad hoc signature changes with every build, so macOS asks for Blip's permissions again each time.
SIGN_ID="${BLIP_SIGN_ID:-$(security find-identity -v -p codesigning | awk '$2 ~ /^[0-9A-F]{40}$/ {print $2; exit}')}"
if [[ -z "$SIGN_ID" ]]; then
  echo "No code-signing identity found; signing ad hoc." >&2
  SIGN_ID="-"
fi
codesign --force --sign "$SIGN_ID" "$APP"

pkill -x Blip || true
while pgrep -x Blip >/dev/null; do sleep 0.1; done
mkdir -p ~/Applications
rm -rf ~/Applications/Blip.app
cp -R "$APP" ~/Applications/Blip.app

if [[ "${1:-}" != "--no-open" ]]; then
  open ~/Applications/Blip.app
fi
