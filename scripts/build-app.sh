#!/bin/sh
# Builds Unplug.app (menu bar app with the `unplug` CLI inside) into ./build.
set -eu
cd "$(dirname "$0")/.."

swift build -c release --arch arm64 --arch x86_64
BIN="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)"

APP=build/Unplug.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Helpers"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp "$BIN/UnplugApp" "$APP/Contents/MacOS/Unplug"
# Helpers/, not MacOS/: "unplug" and "Unplug" collide on case-insensitive volumes.
cp "$BIN/unplug" "$APP/Contents/Helpers/unplug"

# Ad-hoc signature so macOS will launch a locally built app.
codesign --force --deep --sign - "$APP"

echo "Built $APP"
echo "CLI: $APP/Contents/Helpers/unplug (symlink it onto your PATH to use it directly)"
