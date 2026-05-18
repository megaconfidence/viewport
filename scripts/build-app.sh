#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="Viewport"
EXECUTABLE_NAME="Viewport"
APP_DIR="$ROOT_DIR/.build/$APP_NAME.app"
BINARY_PATH="$ROOT_DIR/.build/release/$EXECUTABLE_NAME"
VERSION="$(tr -d '[:space:]' < "$ROOT_DIR/VERSION")"

swift build --package-path "$ROOT_DIR" -c release --product "$EXECUTABLE_NAME"

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"

cp "$BINARY_PATH" "$APP_DIR/Contents/MacOS/$EXECUTABLE_NAME"
cp "$ROOT_DIR/Resources/Info.plist" "$APP_DIR/Contents/Info.plist"
cp "$ROOT_DIR/Resources/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"
printf 'APPL????' > "$APP_DIR/Contents/PkgInfo"

# Stamp the version from the VERSION file so the About panel stays in sync.
plutil -replace CFBundleShortVersionString -string "$VERSION" "$APP_DIR/Contents/Info.plist"
plutil -replace CFBundleVersion -string "$VERSION" "$APP_DIR/Contents/Info.plist"

if command -v codesign >/dev/null 2>&1; then
    codesign --force --deep --sign - "$APP_DIR" >/dev/null
fi

printf 'Built %s (v%s)\n' "$APP_DIR" "$VERSION"
