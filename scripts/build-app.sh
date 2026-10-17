#!/bin/sh
# Builds Unplug.app (menu bar app with the `unplug` CLI inside) into ./build.
set -eu
cd "$(dirname "$0")/.."

swift build -c release --arch arm64 --arch x86_64
BIN="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)"

APP=build/Unplug.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Helpers" "$APP/Contents/Resources"
cp Resources/Info.plist "$APP/Contents/Info.plist"

# Version: VERSION is the single source of truth; the build number is the
# commit count, so every build from main is unique and increasing.
VERSION="$(tr -d '[:space:]' < VERSION)"
BUILD="$(git rev-list --count HEAD 2>/dev/null || echo 1)"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD" "$APP/Contents/Info.plist"

# App icon: Resources/icon/icon-1024.png is rendered from icon.svg.
ICONSET=build/AppIcon.iconset
rm -rf "$ICONSET"
mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
    sips -z $size $size Resources/icon/icon-1024.png --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    double=$((size * 2))
    sips -z $double $double Resources/icon/icon-1024.png --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf "$ICONSET"
cp "$BIN/UnplugApp" "$APP/Contents/MacOS/Unplug"
# Helpers/, not MacOS/: "unplug" and "Unplug" collide on case-insensitive volumes.
cp "$BIN/unplug" "$APP/Contents/Helpers/unplug"

# Ad-hoc signature so macOS will launch a locally built app.
codesign --force --deep --sign - "$APP"

echo "Built $APP $VERSION ($BUILD)"
echo "CLI: $APP/Contents/Helpers/unplug (symlink it onto your PATH to use it directly)"
