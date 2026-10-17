#!/bin/sh
# Signs build/Unplug-<version>.dmg with the Sparkle private key (SPARKLE_PRIVATE_KEY)
# and writes build/appcast.xml, the update feed the app checks. Run after build-dmg.sh.
set -eu
cd "$(dirname "$0")/.."

: "${SPARKLE_PRIVATE_KEY:?set SPARKLE_PRIVATE_KEY to the key exported by Sparkle's generate_keys -x}"
VERSION="$(tr -d '[:space:]' < VERSION)"
DMG="build/Unplug-$VERSION.dmg"
PLIST=build/Unplug.app/Contents/Info.plist
BUILD="$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$PLIST")"
PUBLIC_KEY="$(/usr/libexec/PlistBuddy -c "Print :SUPublicEDKey" "$PLIST" 2>/dev/null || true)"
[ -n "$PUBLIC_KEY" ] || { echo "Resources/sparkle-public-key.txt is missing, so the app can't verify updates." >&2; exit 1; }

SIGN_UPDATE="$(find .build/artifacts -type f -name sign_update | head -1)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
(umask 077 && printf '%s' "$SPARKLE_PRIVATE_KEY" > "$TMP/key")
ATTRIBUTES="$("$SIGN_UPDATE" --ed-key-file "$TMP/key" "$DMG")" # sparkle:edSignature="..." length="..."

# Make sure the private key matches the public key inside the app, otherwise
# every installed copy would reject the update.
SIGNATURE="$(printf '%s' "$ATTRIBUTES" | sed -E 's/.*edSignature="([^"]+)".*/\1/')"
OPENSSL="$(brew --prefix openssl@3)/bin/openssl"
{ printf '\060\052\060\005\006\003\053\145\160\003\041\000'; printf '%s' "$PUBLIC_KEY" | base64 -D; } > "$TMP/public.der"
printf '%s' "$SIGNATURE" | base64 -D > "$TMP/signature"
"$OPENSSL" pkeyutl -verify -pubin -keyform DER -inkey "$TMP/public.der" -rawin -in "$DMG" -sigfile "$TMP/signature"

URL="https://github.com/mihaiflorinpopa/unplug/releases/download/v$VERSION/Unplug-$VERSION.dmg"
DATE="$(LC_ALL=C date -u '+%a, %d %b %Y %H:%M:%S +0000')"
cat > build/appcast.xml <<XML
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Unplug</title>
    <item>
      <title>Unplug $VERSION</title>
      <pubDate>$DATE</pubDate>
      <link>https://github.com/mihaiflorinpopa/unplug/releases/tag/v$VERSION</link>
      <sparkle:version>$BUILD</sparkle:version>
      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>13.0</sparkle:minimumSystemVersion>
      <enclosure url="$URL" $ATTRIBUTES type="application/octet-stream"/>
    </item>
  </channel>
</rss>
XML
echo "Wrote build/appcast.xml for $VERSION ($BUILD)"
