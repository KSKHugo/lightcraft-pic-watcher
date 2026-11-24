#!/bin/bash
# Builds "LightCraft Pic Watcher.app" from the Swift package into dist/.
# Signed ad hoc for use on this Mac, with the hardened runtime. The app is not meant for
# the Mac App Store and therefore runs without the App Sandbox.
#
# UNIVERSAL=1 builds one binary for Apple Silicon and Intel (used by build_release.sh).
# See build_release.sh for the signed, notarized disk image to offer for download.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EXECUTABLE="LightCraftPicWatcher"
APP_DIR="$ROOT/dist/LightCraft Pic Watcher.app"
SCRATCH="$HOME/Library/Caches/LightCraftPicWatcher-build"

ARCH_FLAGS=()
if [ "${UNIVERSAL:-0}" = "1" ]; then
  ARCH_FLAGS=(--arch arm64 --arch x86_64)
fi

echo "==> Building (release${ARCH_FLAGS:+, universal})"
swift build --package-path "$ROOT" -c release --scratch-path "$SCRATCH" --product "$EXECUTABLE" ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"}
BIN_DIR="$(swift build --package-path "$ROOT" -c release --scratch-path "$SCRATCH" ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"} --show-bin-path)"

echo "==> Assembling the app"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$BIN_DIR/$EXECUTABLE" "$APP_DIR/Contents/MacOS/$EXECUTABLE"
cp "$ROOT/AppPackaging/Info.plist" "$APP_DIR/Contents/Info.plist"
# Drawn by Scripts/make_icon.swift; rerun that script after changing the icon.
cp "$ROOT/AppPackaging/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"
printf 'APPL????' > "$APP_DIR/Contents/PkgInfo"

echo "==> Code signing (ad hoc)"
codesign --force --options runtime --sign - "$APP_DIR"
codesign --verify --strict "$APP_DIR"

echo "Built: $APP_DIR"
