#!/bin/bash
# Builds DropShelf.app. Requires only the Swift toolchain from Command Line
# Tools — no Xcode, no xcodebuild, no third-party dependencies.
#
#   ./build.sh              native architecture only (fast, for development)
#   UNIVERSAL=1 ./build.sh  arm64 + x86_64 (for sharing with other Macs)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
CONFIG="${CONFIG:-release}"
UNIVERSAL="${UNIVERSAL:-0}"
APP="$ROOT/build/DropShelf.app"

ARCH_FLAGS=()
if [ "$UNIVERSAL" = "1" ]; then
  ARCH_FLAGS=(--arch arm64 --arch x86_64)
  echo "==> Compiling ($CONFIG, universal arm64 + x86_64)"
else
  echo "==> Compiling ($CONFIG, native)"
fi

swift build -c "$CONFIG" --package-path "$ROOT" "${ARCH_FLAGS[@]}"
BIN_DIR="$(swift build -c "$CONFIG" --package-path "$ROOT" "${ARCH_FLAGS[@]}" --show-bin-path)"
BINARY="$BIN_DIR/DropShelf"

echo "==> Assembling bundle"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BINARY" "$APP/Contents/MacOS/DropShelf"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

echo "==> Rendering app icon"
ICONSET="$ROOT/build/AppIcon.iconset"
rm -rf "$ICONSET"
if swift "$ROOT/Tools/make-icon.swift" "$ICONSET" >/dev/null 2>&1 \
   && iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns" 2>/dev/null; then
  echo "    AppIcon.icns created"
else
  echo "    skipped (icon rendering unavailable; the app uses the generic icon)"
fi
rm -rf "$ICONSET"

echo "==> Signing (ad-hoc)"
# An ad-hoc signature with a stable identifier lets macOS remember the
# Accessibility grant between launches. Re-signing after a rebuild changes the
# code hash, so the grant has to be re-approved after each build.
codesign --force --sign - \
         --identifier local.dropshelf.app \
         --timestamp=none \
         "$APP" >/dev/null

echo
echo "Built: $APP"
echo "Arch:  $(lipo -archs "$APP/Contents/MacOS/DropShelf")"
echo "Run:   open \"$APP\""
echo
echo "First launch: grant Accessibility access when prompted (System Settings ▸"
echo "Privacy & Security ▸ Accessibility) for shake / modifier-key activation,"
echo "hover shortcuts and the notch target. Everything else works without it."
