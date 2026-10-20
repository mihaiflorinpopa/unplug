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
# Privacy manifest, where Apple expects it in a Mac app.
cp Resources/PrivacyInfo.xcprivacy "$APP/Contents/Resources/"
# Shown by the standard About panel.
cp Resources/Credits.rtf "$APP/Contents/Resources/"

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

# macOS 26 and later show the Icon Composer version (Liquid Glass) from Assets.car,
# named by CFBundleIconName. macOS 14 and 15 keep using AppIcon.icns above.
# Absolute paths: actool runs as a service that may keep an old working directory.
ACTOOL_OUT="$PWD/build/actool"
rm -rf "$ACTOOL_OUT"
mkdir -p "$ACTOOL_OUT"
xcrun actool "$PWD/Resources/icon/Unplug.icon" --compile "$ACTOOL_OUT" --platform macosx \
    --minimum-deployment-target 14.0 --app-icon Unplug \
    --output-partial-info-plist "$ACTOOL_OUT/partial.plist" >/dev/null
cp "$ACTOOL_OUT/Assets.car" "$APP/Contents/Resources/"
rm -rf "$ACTOOL_OUT"

# Help Book for the Help menu. Its search uses the Spotlight index hiutil builds.
cp -R Resources/Unplug.help "$APP/Contents/Resources/"
HELP="$APP/Contents/Resources/Unplug.help/Contents/Resources/en.lproj"
hiutil -I corespotlight -Caf "$HELP/search.cshelpindex" "$HELP"
cp "$BIN/UnplugApp" "$APP/Contents/MacOS/Unplug"
# Helpers/, not MacOS/: "unplug" and "Unplug" collide on case-insensitive volumes.
cp "$BIN/unplug" "$APP/Contents/Helpers/unplug"

# Sparkle (auto-updates) is a binary framework the app loads from Frameworks/.
mkdir -p "$APP/Contents/Frameworks"
SPARKLE="$BIN/Sparkle.framework"
if [ ! -d "$SPARKLE" ]; then
    SPARKLE="$(find .build/artifacts -type d -path '*Sparkle.xcframework/macos-*/Sparkle.framework' | head -1)"
fi
ditto "$SPARKLE" "$APP/Contents/Frameworks/Sparkle.framework"

# Updates are verified with this public key. Without it the updater stays off.
if [ -s Resources/sparkle-public-key.txt ]; then
    /usr/libexec/PlistBuddy -c "Add :SUPublicEDKey string $(tr -d '[:space:]' < Resources/sparkle-public-key.txt)" \
        "$APP/Contents/Info.plist"
fi

# Ad-hoc signature so macOS will launch a locally built app.
codesign --force --deep --sign - "$APP"

echo "Built $APP $VERSION ($BUILD)"
echo "CLI: $APP/Contents/Helpers/unplug (symlink it onto your PATH to use it directly)"
