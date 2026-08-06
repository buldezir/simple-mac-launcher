#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

PROJECT="SimpleLauncher.xcodeproj"
SCHEME="SimpleLauncher"
DERIVED_DATA="$ROOT/build/DerivedData"

case "${1:-Debug}" in
  [Rr]elease) CONFIG="Release" ;;
  [Dd]ebug) CONFIG="Debug" ;;
  *) CONFIG="$1" ;;
esac

echo "Building SimpleLauncher ($CONFIG, arm64)..."
xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration "$CONFIG" \
  -derivedDataPath "$DERIVED_DATA" \
  -arch arm64 \
  ARCHS=arm64 \
  ONLY_ACTIVE_ARCH=YES \
  EXCLUDED_ARCHS=x86_64 \
  build

APP="$DERIVED_DATA/Build/Products/$CONFIG/SimpleLauncher.app"
echo
echo "Build succeeded:"
echo "  $APP"

if [[ "$CONFIG" == "Release" ]]; then
  DEST="/Applications/SimpleLauncher.app"
  echo
  echo "Installing to ${DEST}..."
  rm -rf "$DEST"
  mv "$APP" "$DEST"
  echo
  echo "Run with:"
  echo "  open \"$DEST\""
else
  echo
  echo "Run with:"
  echo "  open \"$APP\""
fi
