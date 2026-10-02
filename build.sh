#!/bin/bash
# Builds Anchor.app into ./build. Pass --install to also copy it to ~/Applications.
set -euo pipefail
cd "$(dirname "$0")"

APP="build/Anchor.app"

echo "→ Compiling (release)…"
swift build -c release
BIN="$(swift build -c release --show-bin-path)/Anchor"

if [ ! -f Support/AppIcon.icns ]; then
  echo "→ Drawing icon…"
  swift Tools/make_icon.swift build/AppIcon.iconset
  iconutil -c icns build/AppIcon.iconset -o Support/AppIcon.icns
fi

echo "→ Assembling app bundle…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Anchor"
cp Support/Info.plist "$APP/Contents/Info.plist"
cp Support/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$APP" >/dev/null

if [ "${1:-}" = "--install" ]; then
  mkdir -p "$HOME/Applications"
  rm -rf "$HOME/Applications/Anchor.app"
  cp -R "$APP" "$HOME/Applications/"
  echo "✓ Installed to ~/Applications/Anchor.app"
else
  echo "✓ Built $APP"
fi
