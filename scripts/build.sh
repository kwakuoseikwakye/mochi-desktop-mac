#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

echo "Building Mochi for Mac (release)..."
swift build -c release --scratch-path "$ROOT/build/swift-build" --disable-sandbox
BIN="$(swift build -c release --scratch-path "$ROOT/build/swift-build" --disable-sandbox --show-bin-path)"

STAGE="$(mktemp -d "/tmp/mochi-app.XXXXXX")"
APP="$STAGE/Mochi.app"

mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/MochiMac" "$APP/Contents/MacOS/MochiMac"
cp "$ROOT/Info.plist" "$APP/Contents/Info.plist"
cp -R "$BIN/MochiMac_MochiMac.bundle" "$APP/Contents/Resources/"

echo "Signing application (ad-hoc)..."
codesign --force --sign - "$APP"

mkdir -p "$ROOT/dist"
rm -rf "$ROOT/dist/Mochi.app"
mv "$APP" "$ROOT/dist/Mochi.app"
rm -rf "$STAGE"

printf '\nBuilt successfully!\nApp: %s\nRun: open "%s"\n' "$ROOT/dist/Mochi.app" "$ROOT/dist/Mochi.app"
