#!/bin/bash
# Isolated native view rendering only; never creates or runs Clip.app.
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CHECK_DIR="$PROJECT_DIR/.build/checks"
mkdir -p "$CHECK_DIR" "$PROJECT_DIR/.build/module-cache" "$PROJECT_DIR/.build/previews"
xcrun swiftc -swift-version 5 -target "$(uname -m)-apple-macosx13.0" \
    -module-cache-path "$PROJECT_DIR/.build/module-cache" \
    "$PROJECT_DIR/Sources/Clip/History.swift" \
    "$PROJECT_DIR/Sources/Clip/PasteController.swift" \
    "$PROJECT_DIR/Sources/Clip/HistoryPanel.swift" \
    "$PROJECT_DIR/Sources/Clip/PanelSurface.swift" \
    "$PROJECT_DIR/Tests/PanelPreview.swift" -o "$CHECK_DIR/PanelPreview"
"$CHECK_DIR/PanelPreview" "$PROJECT_DIR/.build/previews"
