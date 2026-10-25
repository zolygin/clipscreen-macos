#!/bin/bash
# Isolated native view rendering only; never creates or runs Clip.app.
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CHECK_DIR="$PROJECT_DIR/.build/checks"
mkdir -p "$CHECK_DIR" "$PROJECT_DIR/.build/module-cache" "$PROJECT_DIR/.build/previews"
cp -R "$PROJECT_DIR/Resources/Lucide" "$CHECK_DIR/"
xcrun swiftc -swift-version 5 -target "$(uname -m)-apple-macosx13.0" \
    -module-cache-path "$PROJECT_DIR/.build/module-cache" \
    "$PROJECT_DIR/Sources/Clip/History.swift" \
    "$PROJECT_DIR/Sources/Clip/PasteController.swift" \
    "$PROJECT_DIR/Sources/Clip/HistoryPanel.swift" \
    "$PROJECT_DIR/Sources/Clip/PanelSurface.swift" \
    "$PROJECT_DIR/Sources/Clip/LucideIcon.swift" \
    "$PROJECT_DIR/Sources/Clip/StatusIcon.swift" \
    "$PROJECT_DIR/Sources/Clip/AnnotationTypes.swift" \
    "$PROJECT_DIR/Sources/Clip/ColorCircleButton.swift" \
    "$PROJECT_DIR/Sources/Clip/CustomColorButton.swift" \
    "$PROJECT_DIR/Sources/Clip/StrokeWidthMenu.swift" \
    "$PROJECT_DIR/Sources/Clip/AnnotationCanvasView.swift" \
    "$PROJECT_DIR/Sources/Clip/ScreenshotEditor.swift" \
    "$PROJECT_DIR/Sources/Clip/ScreenshotEditorWindow.swift" \
    "$PROJECT_DIR/Sources/Clip/ScreenshotEditorToolbar.swift" \
    "$PROJECT_DIR/Tests/AnnotationChecks.swift" \
    "$PROJECT_DIR/Tests/PanelPreview.swift" -o "$CHECK_DIR/PanelPreview"
"$CHECK_DIR/PanelPreview" "$PROJECT_DIR/.build/previews"
