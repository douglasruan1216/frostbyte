#!/bin/bash
# Builds FrostByte and assembles a runnable .app bundle.
# Compiles directly with swiftc (no Xcode, no SwiftPM required).
set -euo pipefail

APP_NAME="FrostByte"
ROOT="$(cd "$(dirname "$0")" && pwd)"
APP="$ROOT/$APP_NAME.app"
SDK="$(xcrun --show-sdk-path)"
DEPLOY_TARGET="arm64-apple-macosx13.0"

echo "▸ Compiling with swiftc…"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

swiftc -O \
    -parse-as-library \
    -target "$DEPLOY_TARGET" \
    -sdk "$SDK" \
    $(find "$ROOT/Sources" -name '*.swift') \
    -o "$APP/Contents/MacOS/$APP_NAME"

echo "▸ Installing Info.plist…"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"

echo "▸ Code signing (ad-hoc — no special permissions needed)…"
codesign --force --deep --sign - "$APP"

echo "✓ Built $APP"
echo "  Launch it with:  open \"$APP\""
