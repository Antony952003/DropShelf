#!/bin/bash
# Produces a universal DropShelf.app and zips it for sharing, using ditto so
# the bundle's symlinks, resource forks and ad-hoc signature survive the trip.
# (`zip` can mangle a .app; Finder's "Compress" and ditto do not.)
#
#   ./package-release.sh            -> build/DropShelf.zip
#   ./package-release.sh 1.1        -> build/DropShelf-1.1.zip
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
VERSION="${1:-}"
APP="$ROOT/build/DropShelf.app"

UNIVERSAL=1 "$ROOT/build.sh"

if [ -n "$VERSION" ]; then
  ZIP="$ROOT/build/DropShelf-$VERSION.zip"
else
  ZIP="$ROOT/build/DropShelf.zip"
fi

echo "==> Verifying signature"
codesign --verify --deep --strict "$APP"
echo "    signature OK"

echo "==> Zipping"
rm -f "$ZIP"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"

echo
echo "Package: $ZIP"
echo "Size:    $(du -h "$ZIP" | cut -f1)"
echo "Arch:    $(lipo -archs "$APP/Contents/MacOS/DropShelf")"
echo
echo "Attach this zip to a GitHub Release. Because it is ad-hoc signed rather"
echo "than notarised, whoever downloads it must clear the quarantine flag once:"
echo
echo "    xattr -dr com.apple.quarantine /Applications/DropShelf.app"
echo
echo "See INSTALL.md for the full instructions to pass on."
