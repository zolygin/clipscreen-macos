# Whole-annotation eraser

## Task and literal implementation constraints

A screenshot editor user needs to remove one unwanted annotation without undoing later work. Eraser removes the topmost annotation hit by one click; dragging does not erase other objects. No partial raster erasure, animation, confirmation dialog or width setting.

- Reuse the 28 × 28 pt drawing-tool targets with 2 pt gaps, 16 pt original Lucide 0.468.0 eraser icon, active/hover/pressed treatment and system color tokens.
- Use 6 pt gaps inside the style group and a 124 × 26 pt font picker. This intentionally replaces the previous 30 pt tool targets/4 pt gaps, 8 pt style gaps and 128 pt font picker: the added tool otherwise pushes Text onto a second row at 960 pt.
- Place Eraser after Highlighter in the drawing-tools group; Text keeps its current position next to color controls.
- Keep the current 44/80 pt adaptive toolbar heights and verify 620–1440 pt layouts, including Text at 960 pt.
- Hit tolerance is 6 screen points, converted to image coordinates as for annotation context menus. Test actual stroke/shape/text bounds, not a bounding box for hollow shapes.
- Delete one item and record one existing Undo snapshot. Empty/background clicks preserve undo/redo. Export recomposes from the unmodified screenshot and surviving annotations.
- Native keyboard activation and accessible selected state on the toolbar button; existing text editing shortcuts remain unchanged.

## Implementation

- `AnnotationTool`/`LucideIcon` add Eraser, with the unchanged upstream SVG and ISC attribution.
- `ScreenshotEditorToolbar` supplies the button, selected state, tooltip and accessibility help, without a width/context menu for this tool.
- `AnnotationCanvasView` reuses `AnnotationRenderer.contains`, walks annotations front to back and removes the first hit. One click records one existing Undo snapshot; an empty click records nothing. Eraser never becomes a painted annotation. Switching tools commits an open text edit and clears any unfinished drawing preview.
- The existing renderer recomposes surviving annotations from the original screenshot, including cached blur backdrops. No source pixels are changed.
- `Tests/EraserChecks.swift` is included in the offscreen renderer. The existing tool-count assertion now includes all non-text tools; unbuffered test output preserves diagnostics after an assertion failure.

## Filled implementation QA

- [x] Architecture: existing canvas event flow, annotation geometry, snapshot history, renderer, toolbar buttons, system colors and Lucide resources reused. No new dependency or product claim.
- [x] Behavior/states: selected/hover/pressed button states reuse `ClipIconButton`; labels and selected accessibility value are synchronized. Empty/outside clicks are no-ops. There is no async pending state or duplicate-processing path.
- [x] Forms: N/A to the eraser. Existing text entry commits when switching tools; all font and text-editing regressions pass.
- [x] Accessibility: native button action, meaningful label/help and selected value verified. Pointer hit tolerance remains six screen points at different image scales; targets are 28 pt. Essential behavior does not rely on animation/color alone.
- [x] Responsive: narrow, normal and wide toolbars checked in light/dark appearances; all eight installed font choices at 96 pt remain inside the toolbar. Text stays on one row from 960 pt. Tool targets and spacing were intentionally tightened to meet that constraint.
- [x] Recovery: Undo/Redo restores/deletes the full object, retains its order and metadata, and a new deletion discards an old redo branch. Clicking background preserves redo. Later unrelated annotations remain intact; dragging does not erase more items.
- [x] Export: each annotation type and blur can be deleted; exported pixels then match the original image byte for byte. The blur fixture uses visible stripes and verifies that blur changes the original before erasure restores it.
- [x] Visual fidelity: actual offscreen renders inspected: `editor-eraser-light-620`, `editor-eraser-dark-960`, `editor-text-light-960`, `editor-text-dark-620`. Compared against hierarchy, grouping, spacing, consistency, icon affordance, color and typography principles (ui-ux-product-design references 01–07). No overlap, clipping or unexpected extra row was observed in the inspected variants.
- [x] Verification: `bash scripts/check-ui.sh` passed 73 native view scenarios and interaction/export regressions; `bash scripts/check.sh` passed full-source type checking, 25 isolated tests and plist/shell validation; `git diff --check` passed. Source formatting follows the existing four-space Swift style; no separate formatter is configured for this change.
- [ ] Manual installed-app testing, VoiceOver and physical keyboard traversal remain for the maintainer. The application was not built or launched; test windows stayed offscreen, without real clipboard access or activation.

## Limits

Eraser removes the topmost visible annotation hit by one click. It removes complete annotations created in the current editor; it does not remove content flattened into an imported image. It intentionally does not erase continuously while dragging or expose a brush width. The published 0.5.0 installer is unchanged; a new app build is needed to use this feature.

