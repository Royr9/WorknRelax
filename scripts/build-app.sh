#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="workNrelax"
BUILD_CONFIG="release"
APP_DIR="$ROOT_DIR/dist/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"

swift build -c "$BUILD_CONFIG" --package-path "$ROOT_DIR"
BIN_DIR="$(swift build -c "$BUILD_CONFIG" --package-path "$ROOT_DIR" --show-bin-path)"

rm -rf "$APP_DIR"
mkdir -p "$CONTENTS_DIR/MacOS"
mkdir -p "$CONTENTS_DIR/Resources"

cp "$BIN_DIR/$APP_NAME" "$CONTENTS_DIR/MacOS/$APP_NAME"
cp "$ROOT_DIR/Info.plist" "$CONTENTS_DIR/Info.plist"

codesign --force --deep --sign - "$APP_DIR" 2>/dev/null || true

echo "Built $APP_DIR"
echo "Run it with: open \"$APP_DIR\""
