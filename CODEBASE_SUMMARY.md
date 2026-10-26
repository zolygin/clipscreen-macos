# Clipscreen — Codebase Architecture & Summary

Clipscreen is a lightweight, native macOS clipboard manager and screenshot annotation utility inspired by Windows clipboard history (`Win+V`) and Snipping Tool, designed with Apple Human Interface Guidelines and AppKit.

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
| **`Esc`** | **Close** | Both panels | Closes the panel/editor window without terminating Clipscreen. |

> **Why `⌥⌘4`?**
> macOS reserves `⌘⇧4` for its native screencapture utility. Using `⌥⌘4` provides a natural, memorable companion to `⌥⌘V` without colliding with system shortcuts.

---

## 2. File Organization & Architecture

The main modules are listed below (older line counts are approximate):

### Core Application
- **`Sources/Clipscreen/main.swift`** (6 lines)
  Application entry point initializing `NSApplication` with `AppDelegate`.
- **`Sources/Clipscreen/AppDelegate.swift`** (344 lines)
  Coordinates system integration, status item menu, global hotkeys, permission onboarding, and panel transitions.
- **`Sources/Clipscreen/HotKey.swift`** (45 lines)
  Carbon `EventHotKey` manager registering both `⌥⌘V` (history) and `⌥⌘4` (screenshot).
- **`Sources/Clipscreen/StatusIcon.swift`**
  Uses original bundled Lucide clipboard/pause template images for the menu bar.
- **`Sources/Clipscreen/LucideIcon.swift`**
  Shared loader for original SVG assets in `Resources/Lucide`, plus consistent icon-button sizing, a single surface for hover/press/active states, and an outlined active state.

### Clipboard Engine
- **`Sources/Clipscreen/History.swift`** (176 lines)
  Pure data layer: `ClipEntry`, `ClipPayload`, atomic index serialization, LRU eviction (100 items), and disk cleanup.
- **`Sources/Clipscreen/HistoryModel.swift`** (79 lines)
  Thread-safe in-memory cache and background persistence queue.
- **`Sources/Clipscreen/Pasteboard.swift`** (154 lines)
  NSPasteboard polling, change detection, filtering transient/password manager types, and data serialization.
- **`Sources/Clipscreen/PasteController.swift`** (73 lines)
  Accessibility-driven synthetic paste (`⌘V`) into the previous frontmost application.

### UI & History Window
- **`Sources/Clipscreen/HistoryPanel.swift`** (472 lines)
  Floating HUD panel with search field, scrollable entries, keyboard navigation (`↑`/`↓`), and right-click actions.
- **`Sources/Clipscreen/PanelSurface.swift`** (143 lines)
  Visual styling, vibrant translucent background, border shadows, and rounded glass effects.

### Screenshot & Annotation Editor
- **`Sources/Clipscreen/AnnotationTypes.swift`**
  `AnnotationTool` enum, `AnnotationItem` data model, and high-performance Quartz 2D renderers (Pen, Arrow, Line, Rectangle, Filled Rectangle, Highlighter, Text), with system font styles and shared text bounds.
- **`Sources/Clipscreen/AnnotationCanvasView.swift`**
  Interactive drawing view, aspect-fit image scaling (100% visible, no clipping), mouse drag tracking, inline plain-text editing, text selection/movement and independent document/typing Undo/Redo stacks.
- **`Sources/Clipscreen/ScreenshotEditorToolbar.swift`**
  Adaptive 44/80 pt toolbar placed strictly below the native titlebar with tool buttons, color chips, per-tool stroke widths, persistent rainbow custom-color button and native color panel, contextual font/size popups, and action handlers.
- **`Sources/Clipscreen/ScreenshotEditorWindow.swift`** (30 lines)
  Custom `NSWindow` intercepting keyboard equivalents (`⌘Z`, `⇧⌘Z`, `⌘C`, `⌘S`).
- **`Sources/Clipscreen/ScreenshotEditor.swift`** (140 lines)
  `ScreenshotEditorWindowController` coordinating standard window titlebar (dedicated to dragging and 🔴 🟡 🟢), canvas, and export actions.
- **`Sources/Clipscreen/ColorCircleButton.swift`** (41 lines)
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
   Renders and verifies 65 native visual/export scenarios, right-edge Pin alignment, keyboard pin/filter actions, and 120 resize updates with one geometry commit.

3. **Development App Build**:
   ```bash
   bash scripts/build-app.sh
   ```
   Builds `.build/Clipscreen.app` with stable ad-hoc signing (`local.kirill.clip`) to preserve macOS Accessibility TCC permissions across builds.

### Editor controls
`StrokeWidthMenu.swift` shares width presets across tool and annotation context menus, without a separate toolbar dropdown. `CustomColorButton.swift` draws the permanent rainbow-plus control. The canvas hit-tests the topmost annotation and uses undo/redo snapshots for reversible width edits. `Tests/AnnotationChecks.swift` checks menus, actual editor wiring/reflow, exported pixels and light/dark toolbars at 620–1000 pt.

### Text editing
The original Lucide Text action lives beside Color. Text mode keeps a 44 pt row when all visible controls fit, otherwise reserves 80 pt, and shows system/serif/monospaced designs with 12–96 pt presets. `AnnotationItem` stores text, color, font, size and wrapping width in image coordinates. `AnnotationRenderer` shares text drawing/bounds between canvas, hit testing and original-resolution export. `AnnotationTextView` uses its own undo manager and consumes normal typing shortcuts; the screenshot window preserves Command-S/Command-W without treating text Copy or Return as screenshot export. Native offscreen tests cover actual insertion, multiline Unicode, cancel, style/color edits, movement, deletion, Undo/Redo, 2x export and adaptive text controls.

### Screenshot foreground handoff
`ScreenshotEditorPresenter` in `ScreenshotEditorWindow.swift` orders the ready window before requesting activation, finishes key-window focus after the activation notification and bounds retries to 0.15/0.4/0.8 seconds. One AppDelegate presenter handles every editor entry point and invalidates old work before a new capture. A capture-in-progress flag prevents overlapping interactive capture processes. Isolated tests intercept activation/ordering and cover late focus, denial, close/hide/minimize and newer-window precedence without showing any window.

### Fonts and rectangle effects
`AnnotationFont` offers four system designs plus installed Helvetica Neue, Avenir Next, Georgia and Menlo. A 128 pt picker shows available choices and full family names while retaining a single row at 960 pt. `RectangleFillMode` stores Solid Fill/Blur Area independently for each rectangle. `RectangleFillMenu` is shared by the toolbar and existing-object context menu; mode edits use normal annotation snapshots. `AnnotationImageRenderer` composes at the original pixel size, filters prior content through Core Image, caches the last composite/blur backdrop and tags output sRGB. Canvas previews reuse the prepared texture while dragging. Tests cover native mode callbacks, filter pixels/regions, image order, preview/PNG consistency, Retina dimensions, Undo/Redo and all installed fonts.
