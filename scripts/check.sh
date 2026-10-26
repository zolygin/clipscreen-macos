#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CHECK_DIR="$PROJECT_DIR/.build/checks"
mkdir -p "$CHECK_DIR" "$PROJECT_DIR/.build/module-cache"
SWIFT_COMPILER="$(xcrun --find swiftc)"
ARCH="$(uname -m)"
SDK_PATH="$(xcrun --show-sdk-path)"
FLAGS=(-swift-version 5 -sdk "$SDK_PATH" -target "$ARCH-apple-macosx13.0" -module-cache-path "$PROJECT_DIR/.build/module-cache")
"$SWIFT_COMPILER" -typecheck "${FLAGS[@]}" "$PROJECT_DIR"/Sources/Clipscreen/*.swift
"$SWIFT_COMPILER" "${FLAGS[@]}" \
    "$PROJECT_DIR/Sources/Clipscreen/History.swift" "$PROJECT_DIR/Sources/Clipscreen/Pasteboard.swift" \
    "$PROJECT_DIR/Tests/ClipTests.swift" -o "$CHECK_DIR/ClipTests"
"$CHECK_DIR/ClipTests"
plutil -lint "$PROJECT_DIR/Resources/Info.plist"
bash -n "$PROJECT_DIR/scripts/build-app.sh"
