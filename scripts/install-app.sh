#!/usr/bin/env bash
# Installs or updates workNrelax from the latest GitHub release.
# Works without this repo — safe to run via:
#   curl -fsSL https://raw.githubusercontent.com/Royr9/WorknRelax/main/scripts/install-app.sh | bash
set -euo pipefail

REPO="Royr9/WorknRelax"
APP_NAME="workNrelax"
ZIP_URL="https://github.com/$REPO/releases/latest/download/$APP_NAME.zip"
INSTALL_DIR="/Applications"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

echo "Downloading latest release…"
curl -fsSL "$ZIP_URL" -o "$TMP_DIR/$APP_NAME.zip"
ditto -x -k "$TMP_DIR/$APP_NAME.zip" "$TMP_DIR"

if [[ ! -d "$TMP_DIR/$APP_NAME.app" ]]; then
    echo "Error: downloaded archive did not contain $APP_NAME.app" >&2
    exit 1
fi

if [[ ! -w "$INSTALL_DIR" ]]; then
    echo "No write access to $INSTALL_DIR — installing to ~/Applications instead."
    INSTALL_DIR="$HOME/Applications"
    mkdir -p "$INSTALL_DIR"
fi
DEST="$INSTALL_DIR/$APP_NAME.app"

pkill -x "$APP_NAME" 2>/dev/null || true
sleep 1

rm -rf "$DEST"
ditto "$TMP_DIR/$APP_NAME.app" "$DEST"

echo "Installed $DEST — launching…"
open "$DEST"
