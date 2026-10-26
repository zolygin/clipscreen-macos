#!/bin/bash
# Isolated native view rendering only; never creates or runs Clip.app.
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CHECK_DIR="$PROJECT_DIR/.build/checks"
mkdir -p "$CHECK_DIR" "$PROJECT_DIR/.build/module-cache" "$PROJECT_DIR/.build/previews"
cp -R "$PROJECT_DIR/Resources/Lucide" "$CHECK_DIR/"
xcrun swiftc -swift-version 5 -target "$(uname -m)-apple-macosx13.0" \
    -module-cache-path "$PROJECT_DIR/.build/module-cache" \
    "$PROJECT_DIR/Sources/Clipscreen/History.swift" \
    "$PROJECT_DIR/Sources/Clipscreen/PasteController.swift" \
    "$PROJECT_DIR/Sources/Clipscreen/HistoryPanel.swift" \
    "$PROJECT_DIR/Sources/Clipscreen/PanelSurface.swift" \
    "$PROJECT_DIR/Sources/Clipscreen/LucideIcon.swift" \
    "$PROJECT_DIR/Sources/Clipscreen/StatusIcon.swift" \
    "$PROJECT_DIR/Sources/Clipscreen/AnnotationTypes.swift" \
    "$PROJECT_DIR/Sources/Clipscreen/ColorCircleButton.swift" \
    "$PROJECT_DIR/Sources/Clipscreen/CustomColorButton.swift" \
    "$PROJECT_DIR/Sources/Clipscreen/StrokeWidthMenu.swift" \
    "$PROJECT_DIR/Sources/Clipscreen/AnnotationCanvasView.swift" \
    "$PROJECT_DIR/Sources/Clipscreen/ScreenshotEditor.swift" \
    "$PROJECT_DIR/Sources/Clipscreen/ScreenshotEditorWindow.swift" \
    "$PROJECT_DIR/Sources/Clipscreen/ScreenshotEditorToolbar.swift" \
    "$PROJECT_DIR/Tests/BlurChecks.swift" \
    "$PROJECT_DIR/Tests/AnnotationChecks.swift" \
    "$PROJECT_DIR/Tests/PanelPreview.swift" -o "$CHECK_DIR/PanelPreview"
"$CHECK_DIR/PanelPreview" "$PROJECT_DIR/.build/previews"
