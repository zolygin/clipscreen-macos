# Expanded screenshot fonts and rectangle blur — 2026-10-26

## Diagnosis and task

The user needs more annotation typefaces and a quick way to blur text within a rectangle. Existing controls offer three font designs and one solid rectangle operation. The requested workflow is a context menu on that same rectangle button, with solid fill remaining the default. Meaning must be discoverable through labels/state, and the new font list must not reintroduce a two-row header in a wide window.

## Literal constraints

Reuse original Lucide icons and the current AppKit toolbar. Keep 16 pt icons in 30 pt tool targets, 4 pt intra-group gaps, 8 pt group gaps, 14 pt outer insets, a 128 × 26 pt font and 76 × 26 pt size controls, and existing content-based 44/80 pt reflow. Add no extra toolbar slot or row for blur. Keep 12–96 pt text sizes. Fill/blur rectangles share the existing 3 pt corner geometry. Use a 24 image-point Gaussian radius, scaled by native pixel density; clip the result exactly to the rectangle. Preserve the screenshot's original pixel dimensions and consistent color management for preview/export.

## Files and rationale

- `AnnotationTypes.swift`: add Rounded, Helvetica Neue, Avenir Next, Georgia and Menlo. Named families use the installed macOS font and are offered only when available; no font files or network fonts are distributed. Add `RectangleFillMode`, equatable annotations and shared full-resolution `AnnotationImageRenderer` with Core Image Gaussian blur, ordered compositing, caches and explicit sRGB output.
- `StrokeWidthMenu.swift`: add `RectangleFillMenu` with checked Solid Fill/Blur Area actions for both the toolbar and an existing rectangle. No width setting for either area operation.
- `ScreenshotEditorToolbar.swift`: use a 128 pt font picker and keep the same tool count; update the rectangle's original Lucide glyph, label, selected value and keyboard-accessible context help by mode.
- `AnnotationCanvasView.swift`: create area annotations in the selected mode, edit existing modes reversibly and preview from a cached blur backdrop. Blend over earlier image content/annotations; later strokes remain above the blur. Reuse composition for original-resolution export and invalidate caches when appearance changes.
- `ScreenshotEditor.swift`: wire rectangle-mode selection to the canvas.
- `LucideIcon.swift`, `Resources/Lucide/square-dashed.svg`: unchanged official Lucide 0.468.0 asset (upstream Git blob `f0822a34f3f07d32de327bd36ce3229b53146c01`); existing ISC attribution retained. Dashes distinguish the area effect, while native menu text explicitly names it Blur Area. No red slash is used because the operation is represented by its menu label and state.
- `Tests/BlurChecks.swift`, `Tests/AnnotationChecks.swift`, `scripts/check-ui.sh`: synthetic pixel/event scenarios and expanded font coverage.
- Info.plist/docs: version 0.5.0 (7), workflow and maintainer QA.

## States and recovery

Each new editor starts with Solid Fill. Selecting Blur Area from the rectangle's right-click/Shift-F10/Show Menu menu selects that tool and changes its icon to a dashed square. The tooltip/accessibility label names the operation. Right-clicking an existing area changes only that annotation and supports Undo/Redo. Switching to another tool remembers the area's default for the editor session. Color applies to solid fill; blur samples the image beneath it. If a filter produces no image, the selected area is covered opaquely instead of exposing unfiltered source pixels. Gaussian blur is an image effect; this implementation does not claim irreversible removal or OCR resistance.

The font picker exposes eight distinct available choices on this Mac: System, Serif, Monospaced, Rounded, Helvetica Neue, Avenir Next, Georgia and Menlo. Font/size/color edits and text input keep the existing draft/selection/default semantics and Undo/Redo.

## Verification and visual review

Native tests use synthetic checkerboard/text/color patches, hidden windows and injected activation effects only. Tests verify actual high-frequency smoothing, unchanged pixels outside the region, reverse dragging, earlier/later annotation compositing, mode menu callbacks/checkmarks/controller wiring, existing-object mode edits, Undo/Redo, cache reuse, opaque filter-failure fallback and original 960 × 600 pixels from a 480 × 300 point image. Existing text checks exercise all eight fonts at narrow/wide layouts and 96 pt, plus Cyrillic/emoji. Tests also compare live blur samples with the PNG and render a full font catalog and the longest family name in the existing control.

A 132 pt font control regressed the 960 pt header, while the original 118 pt control clipped Helvetica Neue. The final 128 pt width fits that name while preserving the one-row layout at 960 pt. A pixel-level preview/export comparison also identified unprofiled Device RGB versus calibrated preview differences; output is explicitly tagged sRGB so the filter and saved image use consistent colors.

Actual native font-catalog, live blur, exported blur and narrow/wide light/dark controls are reviewed against skill references 01–07: the rectangle effect stays in its existing group, the mode has distinct glyph plus labeled menus, fonts are legible, and changing font/mode does not create a new wide-header row. Offscreen black space around the screenshot is the uncached window background; it is not exported image content.

## Filled implementation QA

### Architecture

- [x] Reuse AppKit controls, Lucide assets/licenses, system colors, annotation model and snapshot undo history.
- [x] Semantic fill mode stored per annotation; shared menu/renderer rather than duplicated toolbar/export behavior.
- [x] No downloaded fonts, runtime network dependency, fabricated data or unsupported product claims.

### Component behavior

- [x] Solid default, checked mode, dynamic glyph/label/help, selected tool and normal Undo/Redo availability are synchronized.
- [x] No standalone width or additional toolbar slot for either rectangle mode.
- [x] Mode changes act once; no async optimistic state. Prepared filter textures and unchanged composites are reused during preview.

### Forms and accessibility

- [x] Existing native font/size controls remain named and preserve current values. Unavailable named fonts are omitted; rendering has a system fallback.
- [x] Native text selection/paste/newlines/Unicode and input recovery remain covered by existing checks; password/OTP/autofill are not part of this task.
- [x] Right-click has Shift-F10 and accessibility Show Menu alternatives. Native menu items expose their names/checkmarks; glyph alone is not the only mode cue.
- [x] No new modal, focus trap, color-only meaning or animation. Text and close/apply shortcut routing retained.
- [ ] Full VoiceOver, live context-menu keyboard traversal, Zoom and high-contrast walkthrough remain manual.

### Responsive behavior

- [x] Existing 620–1440 pt font/control layouts and 960 pt stable one-row regression pass with the expanded list; no overlap or hidden font control.
- [x] Blur controls rendered at 620/960 pt in light/dark appearance; target sizes and grouping retained.
- [x] Latin/Cyrillic/emoji tested. English UI and native text direction remain; full RTL toolbar localization is outside scope. Desktop safe areas/software keyboards do not apply.
- [x] Original aspect ratio/native pixels preserved. Region clipping and orientation tested using asymmetric source colors.

### States and recovery

- [x] Fill/blur defaults and existing-area conversion support Undo/Redo; invalid stroke-width changes do not affect area modes.
- [x] Filter failure has an opaque fallback. No network, loading or new permission prompt is introduced.
- [x] Existing text draft/edit cancellation, independent window ownership and capture-focus checks remain covered.

### Visual fidelity

- [x] Literal sizes/gaps, corner geometry, 128 pt font-control width and adaptive row rules retained. Original SVG geometry verified by blob hash.
- [x] Actual rendered font/blur/export images reviewed against references 01–07.
- [x] Intentional changes documented: dashed square for Blur Area, eight installed typefaces, stronger region blur, sRGB composition and cached preview texture.

### Verification and remaining scope

- [x] Swift type checking, existing 22 isolated history tests and native annotation/context/presentation checks are used. No formatter configured; whitespace is checked.
- [x] Final visual/export run: 65 native scenarios pass, including live/export sRGB sample agreement and the full Helvetica Neue title at 960 pt. The actual final light/dark/Helvetica/blur/font-catalog renders were inspected. Build metadata is recorded below after compilation.
- [ ] Other macOS font installations, real interactive menu feel, large-image frame pacing, screen-reader behavior and screenshot capture/foreground ordering remain manual. No user's live app, clipboard or screenshot was operated.

Development build 0.5.0 (7) completed at `.build/Clipscreen.app`. Strict code-signature verification passed, and the bundled dashed-square SVG matches its upstream blob hash. No release/DMG build or live app launch was performed; the user can quit the previous copy and launch the new bundle from Terminal.
