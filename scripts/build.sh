#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release --product MakerGlance "$@"
BIN_DIR="$(swift build -c release --show-bin-path "$@")"
APP="$PWD/dist/MakerGlance.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/MakerGlance" "$APP/Contents/MacOS/MakerGlance"
# Remove local debug symbols (and compiler machine paths) before re-signing.
strip -S -x "$APP/Contents/MacOS/MakerGlance"
cp Resources/Info.plist "$APP/Contents/Info.plist"
swift scripts/Icon.swift "$APP/Contents/Resources/MakerGlance.icns"
codesign --force --sign - --identifier com.t0nyz0.MakerPulse "$APP"
codesign --verify --deep --strict "$APP"
echo "Built: $APP"
