#!/usr/bin/env bash
set -euo pipefail
# Usage: ./scripts/set-version.sh 1.2.0
VERSION="${1:-}"
if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Usage: $0 <major.minor.patch>   e.g. $0 1.2.0" >&2
  exit 1
fi
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PLIST="$ROOT/xShot/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$PLIST"
BUILD="${VERSION//./}"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD" "$PLIST"
echo "Version set to $VERSION (build $BUILD)"
