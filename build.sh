#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

PROJECT="SimpleLauncher.xcodeproj"
SCHEME="SimpleLauncher"
CONFIG="${1:-Debug}"
DERIVED_DATA="$ROOT/build/DerivedData"

echo "Building SimpleLauncher ($CONFIG)…"
xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration "$CONFIG" \
  -derivedDataPath "$DERIVED_DATA" \
  build

APP="$DERIVED_DATA/Build/Products/$CONFIG/SimpleLauncher.app"
echo
echo "Build succeeded:"
echo "  $APP"
echo
echo "Run with:"
echo "  open \"$APP\""
