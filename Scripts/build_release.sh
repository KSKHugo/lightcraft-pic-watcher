#!/bin/bash
# Builds the disk image to offer for download: universal app (Apple Silicon and Intel),
# signed with a "Developer ID Application" certificate, notarized by Apple and stapled,
# so it opens on any Mac with a double click and no Gatekeeper override.
#
# Needs, on the building Mac only (nothing of it lands in this repository):
#   - a "Developer ID Application" certificate in the keychain
#   - notarization credentials stored once as a keychain profile:
#       xcrun notarytool store-credentials lightcraft-notarize \
#           --apple-id <apple-id> --team-id <team-id>
#     (with an app-specific password from appleid.apple.com, never the Apple ID password)
#
# Environment overrides: DEVELOPER_ID (certificate SHA-1), NOTARY_PROFILE (profile name).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="LightCraft Pic Watcher"
APP_DIR="$ROOT/dist/$APP_NAME.app"
RELEASE_DIR="$ROOT/dist/release"

VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$ROOT/AppPackaging/Info.plist")"
BUILD="$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$ROOT/AppPackaging/Info.plist")"
DMG_PATH="$RELEASE_DIR/LightCraft-Pic-Watcher-$VERSION.dmg"

# Of several Developer ID certificates (a renewed one next to the old one carries the same
# name, which codesign refuses as ambiguous), the one valid the longest, by its SHA-1.
newest_developer_id() {
  local hash end
  # Only identities with a private key can sign, so the candidates come from find-identity.
  for hash in $(security find-identity -v -p codesigning | grep '"Developer ID Application' | awk '{ print $2 }'); do
    end="$(security find-certificate -a -Z -p -c "Developer ID Application" \
      | awk -v h="$hash" '/^SHA-1 hash:/ { on = ($3 == h) } on && /BEGIN CERTIFICATE/ { p = 1 } p { print } /END CERTIFICATE/ { p = 0 }' \
      | openssl x509 -noout -enddate | cut -d= -f2)"
    echo "$(LC_ALL=C date -j -f "%b %e %T %Y %Z" "$end" +%s 2>/dev/null || echo 0) $hash"
  done | sort -rn | head -1 | awk '{ print $2 }'
}

DEVELOPER_ID="${DEVELOPER_ID:-$(newest_developer_id)}"
if [ -z "$DEVELOPER_ID" ]; then
  echo "No \"Developer ID Application\" certificate in the keychain. A download build needs one." >&2
  exit 1
fi

# The profile is just a keychain label for the same Apple ID credentials, so one stored for
# another app of the same team works as well.
if [ -z "${NOTARY_PROFILE:-}" ]; then
  for candidate in lightcraft-notarize hybrid-notarize; do
    if xcrun notarytool history --keychain-profile "$candidate" >/dev/null 2>&1; then
      NOTARY_PROFILE="$candidate"
      break
    fi
  done
fi
if [ -z "${NOTARY_PROFILE:-}" ]; then
  echo "No notarization credentials found. Store them once (see the top of this script)." >&2
  exit 1
fi

UNIVERSAL=1 "$ROOT/Scripts/build_app.sh"

echo "==> Code signing (Developer ID $DEVELOPER_ID)"
# Hardened runtime and a secure timestamp are both required for notarization.
codesign --force --options runtime --timestamp --sign "$DEVELOPER_ID" "$APP_DIR"
codesign --verify --strict --deep "$APP_DIR"
lipo -archs "$APP_DIR/Contents/MacOS/LightCraftPicWatcher" | sed 's/^/    Architectures: /'

echo "==> Building the disk image"
mkdir -p "$RELEASE_DIR"
STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT
cp -R "$APP_DIR" "$STAGING/"
# The usual drag-to-install gesture: the app and a shortcut to /Applications side by side.
ln -s /Applications "$STAGING/Programme"
rm -f "$DMG_PATH"
hdiutil create -volname "$APP_NAME $VERSION" -srcfolder "$STAGING" -ov -format UDZO "$DMG_PATH" >/dev/null

# Gatekeeper checks the container a download arrives in too, so the image is signed as well.
codesign --force --timestamp --sign "$DEVELOPER_ID" "$DMG_PATH"

echo "==> Notarizing (waits for Apple, usually a few minutes)"
xcrun notarytool submit "$DMG_PATH" --keychain-profile "$NOTARY_PROFILE" --wait

# The ticket travels with the image, so it also opens on a Mac that is offline.
echo "==> Stapling the ticket"
xcrun stapler staple "$DMG_PATH"
xcrun stapler validate "$DMG_PATH"

echo "==> Checking it the way Gatekeeper will"
spctl -a -vvv -t open --context context:primary-signature "$DMG_PATH" 2>&1 | sed 's/^/    /'
MOUNT_POINT="$(hdiutil attach "$DMG_PATH" -nobrowse -readonly | grep -o '/Volumes/.*' | head -1)"
spctl -a -vvv -t exec "$MOUNT_POINT/$APP_NAME.app" 2>&1 | sed 's/^/    /'
hdiutil detach "$MOUNT_POINT" >/dev/null

(cd "$RELEASE_DIR" && shasum -a 256 "$(basename "$DMG_PATH")" > "$(basename "$DMG_PATH").sha256")

echo ""
echo "Ready for download: $DMG_PATH (version $VERSION, build $BUILD)"
echo "Checksum:           $DMG_PATH.sha256"
