# Clip — Codebase Architecture & Summary

Clip is a lightweight, native macOS clipboard manager and screenshot annotation utility inspired by Windows clipboard history (`Win+V`) and Snipping Tool, designed with Apple Human Interface Guidelines and AppKit.

---

## 1. Global Shortcuts

| Shortcut | Action | Scope | Description |
| :--- | :--- | :--- | :--- |
| **`⌥⌘V`** (`Option + Command + V`) | **Open Clipboard History** | System-wide Global HotKey | Opens the 100-item clipboard history floating panel. |
| **`⌥⌘4`** (`Option + Command + 4`) | **Capture Screen Area & Edit** | System-wide Global HotKey | Triggers interactive screen capture and opens the annotation editor. |
| **`Return`** | **Paste Item / Copy & Close** | In-app | In history panel: pastes item to target app.<br>In screenshot editor: copies annotated image and closes. |
| **`Right-Click`** | **Edit Image** | History Panel | Right-clicking any image entry opens it directly in the annotation editor. |
| **`⌘Z`** | **Undo** | Screenshot Editor | Reverts the last drawn annotation. |
| **`⇧⌘Z`** | **Redo** | Screenshot Editor | Restores the previously undone annotation. |
| **`⌘S`** | **Save…** | Screenshot Editor | Exports annotated screenshot to PNG on disk. |
| **`Esc`** | **Close** | Both panels | Closes the panel/editor window without terminating Clip. |

> **Why `⌥⌘4`?**  
> macOS reserves `⌘⇧4` for its native screencapture utility. Using `⌥⌘4` provides a natural, memorable companion to `⌥⌘V` without colliding with system shortcuts.

---

## 2. File Organization & Architecture

The main modules are listed below (older line counts are approximate):

### Core Application
- **`Sources/Clip/main.swift`** (6 lines)  
  Application entry point initializing `NSApplication` with `AppDelegate`.
- **`Sources/Clip/AppDelegate.swift`** (344 lines)  
  Coordinates system integration, status item menu, global hotkeys, permission onboarding, and panel transitions.
- **`Sources/Clip/HotKey.swift`** (45 lines)  
  Carbon `EventHotKey` manager registering both `⌥⌘V` (history) and `⌥⌘4` (screenshot).
- **`Sources/Clip/StatusIcon.swift`**
  Uses original bundled Lucide clipboard/pause template images for the menu bar.
- **`Sources/Clip/LucideIcon.swift`**
  Shared loader for original SVG assets in `Resources/Lucide`, plus consistent icon-button sizing, a single surface for hover/press/active states, and an outlined active state.

### Clipboard Engine
- **`Sources/Clip/History.swift`** (176 lines)  
  Pure data layer: `ClipEntry`, `ClipPayload`, atomic index serialization, LRU eviction (100 items), and disk cleanup.
- **`Sources/Clip/HistoryModel.swift`** (79 lines)  
  Thread-safe in-memory cache and background persistence queue.
- **`Sources/Clip/Pasteboard.swift`** (154 lines)  
  NSPasteboard polling, change detection, filtering transient/password manager types, and data serialization.
- **`Sources/Clip/PasteController.swift`** (73 lines)  
  Accessibility-driven synthetic paste (`⌘V`) into the previous frontmost application.

### UI & History Window
- **`Sources/Clip/HistoryPanel.swift`** (472 lines)  
  Floating HUD panel with search field, scrollable entries, keyboard navigation (`↑`/`↓`), and right-click actions.
- **`Sources/Clip/PanelSurface.swift`** (143 lines)  
  Visual styling, vibrant translucent background, border shadows, and rounded glass effects.

### Screenshot & Annotation Editor (Modularized < 200 lines each)
- **`Sources/Clip/AnnotationTypes.swift`** (157 lines)  
  `AnnotationTool` enum, `AnnotationItem` data model, and high-performance Quartz 2D renderers (Pen, Arrow, Line, Rectangle, Filled Rectangle, Highlighter).
- **`Sources/Clip/AnnotationCanvasView.swift`** (173 lines)  
  Interactive drawing view, aspect-fit image scaling (100% visible, no clipping), mouse drag tracking, and independent Undo/Redo stacks.
- **`Sources/Clip/ScreenshotEditorToolbar.swift`** (175 lines)  
  Adaptive 44/80 pt toolbar placed strictly below the native titlebar with tool buttons, color chips, per-tool stroke widths, persistent rainbow custom-color button and native color panel, and action handlers.
- **`Sources/Clip/ScreenshotEditorWindow.swift`** (30 lines)  
  Custom `NSWindow` intercepting keyboard equivalents (`⌘Z`, `⇧⌘Z`, `⌘C`, `⌘S`).
- **`Sources/Clip/ScreenshotEditor.swift`** (140 lines)  
  `ScreenshotEditorWindowController` coordinating standard window titlebar (dedicated to dragging and 🔴 🟡 🟢), canvas, and export actions.
- **`Sources/Clip/ColorCircleButton.swift`** (41 lines)  
  Custom palette color circle buttons with active selection rings.

---

## 3. Verification & Build Commands

Following the repository's strict verification policy:

1. **Lightweight Typecheck & Unit Tests**:
   ```bash
   bash scripts/check.sh
   ```
   Runs 22 isolated unit tests without touching system clipboard or launching full apps.

2. **UI & Theme Scenario Tests**:
   ```bash
   bash scripts/check-ui.sh
   ```
   Renders and verifies 42 native visual scenarios, right-edge Pin alignment, keyboard pin/filter actions, and 120 resize updates with one geometry commit.

3. **Development App Build**:
   ```bash
   bash scripts/build-app.sh
   ```
   Builds `.build/Clip.app` with stable ad-hoc signing (`local.kirill.clip`) to preserve macOS Accessibility TCC permissions across builds.

### Editor controls
`StrokeWidthMenu.swift` shares width presets across tool, visible dropdown and annotation context menus. `CustomColorButton.swift` draws the permanent rainbow-plus control. The canvas hit-tests the topmost annotation and uses undo/redo snapshots for reversible width edits. `Tests/AnnotationChecks.swift` checks menus, actual editor wiring/reflow, exported pixels and light/dark toolbars at 620–1000 pt.
