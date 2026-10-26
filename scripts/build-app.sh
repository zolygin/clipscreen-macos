#!/bin/bash
# Creates a full local DEBUG app. Run only when explicitly requested by the user.
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="${1:-$PROJECT_DIR/.build/Clipscreen.app}"
if [[ "$APP_DIR" != /* || "$APP_DIR" != *.app ]]; then
    printf 'Output must be an absolute path ending in .app\n' >&2
    exit 1
fi
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources" "$PROJECT_DIR/.build/module-cache"
cp "$PROJECT_DIR/Resources/Info.plist" "$APP_DIR/Contents/Info.plist"
cp -R "$PROJECT_DIR/Resources/Lucide" "$APP_DIR/Contents/Resources/"
SWIFT_COMPILER="$(xcrun --find swiftc)"
ARCH="$(uname -m)"
SDK_PATH="$(xcrun --show-sdk-path)"
"$SWIFT_COMPILER" -swift-version 5 -Onone -g -sdk "$SDK_PATH" -target "$ARCH-apple-macosx13.0" \
    -module-cache-path "$PROJECT_DIR/.build/module-cache" \
    "$PROJECT_DIR"/Sources/Clipscreen/*.swift -o "$APP_DIR/Contents/MacOS/Clipscreen"
codesign --force --sign - --identifier local.kirill.clip -r='designated => identifier "local.kirill.clip"' "$APP_DIR"
codesign --verify --strict "$APP_DIR"
printf 'Created development app: %s\n' "$APP_DIR"
