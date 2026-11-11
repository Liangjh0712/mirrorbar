#!/bin/zsh
# Build Mirrorbar.app and install it to ~/Applications.
set -euo pipefail

cd "${0:A:h}/.."
swift build -c release --arch arm64
BIN="$(swift build -c release --arch arm64 --show-bin-path)"

APP=build/Mirrorbar.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/Mirrorbar" "$APP/Contents/MacOS/Mirrorbar"
cp Resources/Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"

if [[ "${1:-}" == "--install" ]]; then
  pkill -x Mirrorbar 2>/dev/null && sleep 1 || true
  mkdir -p ~/Applications
  rm -rf ~/Applications/Mirrorbar.app
  cp -R "$APP" ~/Applications/
  open ~/Applications/Mirrorbar.app
  echo "installed ~/Applications/Mirrorbar.app"
else
  echo "built $APP"
fi
