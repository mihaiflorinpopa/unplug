#!/bin/sh
# Builds Unplug.app, then packages it as build/Unplug.dmg with an Applications
# shortcut so it installs by drag and drop.
set -eu
cd "$(dirname "$0")/.."

./scripts/build-app.sh

VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Resources/Info.plist)"
STAGING=build/dmg
DMG=build/Unplug-$VERSION.dmg

rm -rf "$STAGING" "$DMG"
mkdir -p "$STAGING"
cp -R build/Unplug.app "$STAGING/"
ln -s /Applications "$STAGING/Applications"

hdiutil create -volname "Unplug" -srcfolder "$STAGING" -fs HFS+ -format UDZO -ov "$DMG"
rm -rf "$STAGING"

echo "Built $DMG"
