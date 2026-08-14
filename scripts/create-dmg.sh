#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/dist/xShot.app"
if [[ ! -d "$APP" ]]; then
  echo "Missing $APP — run make first" >&2
  exit 1
fi
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
STAGE="$ROOT/build/dmg-stage"
DMG="$ROOT/dist/xShot-${VERSION}.dmg"
rm -rf "$STAGE"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/xShot.app"
ln -s /Applications "$STAGE/Applications"
rm -f "$DMG"
hdiutil create -volname "xShot ${VERSION}" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
echo "$DMG"
