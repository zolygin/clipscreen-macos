# Screenshot Editor — stroke widths and custom color

Date: 2026-10-25. Implementation review using `ui-ux-product-design`, references 01–07, 08, 10 and 13.

## Diagnosis

A user needs to annotate a screenshot with a chosen stroke thickness and color while preserving finished work and keeping export actions accessible.

Observed: the canvas accepted a line-width property but the toolbar exposed no control. The custom-color well became a solid square matching the selected color, visually blending with the preset swatches. All controls occupied one row despite the editor allowing a 620 pt minimum width. The filled-rectangle tool works and is retained; its existing Lucide icon is retained, with a tooltip explaining that dragging covers an area.

Design judgment: a persistent rainbow-plus button should make arbitrary color choice easier to recognize. This has been visually inspected, without a user study. Thickness editing is available from a visible control and right-click menus, rather than relying exclusively on a hidden gesture.

## Concrete constraints and interaction

| Role | Implementation |
| --- | --- |
| Tool targets | 30 × 30 pt, original 16 pt Lucide icons, 4 pt group gaps |
| Width control | 62 × 28 pt, current numeric value in pt, native dropdown |
| Pencil / arrow / line / rectangle widths | 1, 2, 3.5, 6, 10, 16 pt; default 3.5 |
| Highlighter widths | 8, 12, 20, 28, 40 pt; default 20 |
| Filled rectangle | Retained as solid fill; width disabled with an explanation because there is no outline |
| Color presets | Existing six colors; 24 pt targets; visible Color group label |
| Custom color | 30 pt target, permanent 22 pt rainbow ring, plus in opaque system-colored center |
| Selected color | 2 pt selection ring; named accessible state; custom color exposes its hex value |
| Row grouping | 14 pt outer insets, 8 pt between groups |
| Wide toolbar | 44 pt high at widths ≥780 pt; tools/width → colors → flexible space → undo/redo/export |
| Compact toolbar | 80 pt high below 780 pt; tools/width and undo/redo/export above, colors below |

Per-tool widths are remembered for the current editor session. Switching tools restores its own width. Width applies to subsequent drawing; right-clicking an existing annotation changes only that annotation. Overlapping annotations are hit-tested from topmost to bottommost using their stroke/shape geometry, with a 6 pt screen-space tolerance.

Right-clicking a tool shows that tool's preset widths and checked selection. Choosing a value also selects the tool. Right-clicking a filled rectangle explains the absence of an outline width. The visible width dropdown supports the same choices without requiring right-click.

The rainbow stays rainbow after color changes. Clicking it opens the standard macOS color panel; the existing preset buttons remain direct selections. Closing the editor closes its owned color panel and clears the callback target.

## Files changed

- `AnnotationTypes.swift`: per-tool presets/defaults, editable item width, geometric hit testing, actual highlighter stroke width.
- `AnnotationCanvasView.swift`: annotation context menu and reversible width edits; undo/redo snapshots cover drawing and width changes.
- `StrokeWidthMenu.swift`: shared numeric widths, sample strokes, selected state and solid-fill explanation.
- `ScreenshotEditorToolbar.swift`: visible width control, right-click tool menus, session memory, responsive grouping and standard color-panel lifecycle.
- `CustomColorButton.swift`, `ColorCircleButton.swift`: persistent rainbow-plus control and accessible preset states.
- `ScreenshotEditor.swift`: connects width/tool selection to the canvas and reserves adaptive toolbar height.
- `LucideIcon.swift`: allows tool-button subclassing while preserving the single-surface hover treatment.
- `Tests/AnnotationChecks.swift`, `Tests/PanelPreview.swift`, `scripts/check-ui.sh`: isolated behavior/export checks and rendered scenarios.

Earlier header/Pin changes remain in the same working tree and are documented separately in `UI-UX-LUCIDE-REVIEW.md`.

## State, accessibility and recovery

Native menu items expose numeric widths and checked state. Tool/color controls have English accessible names and selection state. The width dropdown is disabled for fill with explanatory help, preventing a misleading no-op. The custom color does not rely on rainbow hue alone: the plus, accessible name, group label and selected outline distinguish it from presets. Native button roles, focus behavior and dropdown keyboard operation are retained.

Undo/Redo now store annotation-state snapshots so changing a width can be undone without removing the figure. A new edit after Undo discards the obsolete redo branch. Menus do not alter data until a value is chosen. Base image data, clipboard persistence and save/copy flow are unchanged.

The highlighter previously clamped several small values to the same 20 pt minimum. It now uses the selected width directly, with a 20 pt default preserving the previous default appearance. Annotations are local to the current editor; there is no stored annotation-schema migration.

## Checks performed

- Source type checking and 22 existing storage/clipboard/localization tests pass; tests use isolated named pasteboards.
- 42 native rendered scenarios pass, including eight new light/dark toolbars at 620, 680, 780 and 1000 pt, and a real exported marker image.
- Menus are invoked through native action dispatch without opening a UI: per-tool memory, callbacks, checked selection, invalid-value rejection and fill explanation pass.
- Canvas events are delivered only to the isolated test canvas: contextual editing, topmost selection, empty hit, solid fill and Undo/Redo branching pass.
- Exported pixels differ between 8 pt and 40 pt highlighter strokes, proving that smaller width values are no longer clamped away.
- The actual editor controller is instantiated offscreen: its width callback reaches the actual canvas, switching tools restores the saved width, and repeated resizing reserves 44/80 pt correctly.
- Bounds checks ensure controls remain inside the toolbar and reflow does not duplicate tools, the dropdown or the custom-color button.
- Actual light/dark renders at all four widths were inspected against references 01–07. The permanent rainbow, grouping, selected states and export alignment remain visible.
- `git diff --check` passes; no formatter is configured.

The renderer does not move the user's pointer, show windows, open the color panel, use the real clipboard, or interact with the running app. Palette opening, color selection through the macOS panel and assistive navigation remain manual checks.

## Filled implementation QA checklist

### Architecture

- [x] Existing AppKit controls, Lucide assets and single-surface button treatment reused.
- [x] Shared width menu serves tool, visible control and annotation contexts.
- [x] Controller owns tool/color/width flow; canvas owns annotations and Undo/Redo.
- [x] No invented product facts or user data added; previews are synthetic.

### Component behavior

- [x] Default, selected, disabled, native menu focus and button-pressed states defined.
- [x] Checked widths, visible width, active tool, canvas width and color states synchronize in tests.
- [x] Repeated drawing remains event-driven; no asynchronous processing action introduced.
- [x] No optimistic persistence added; width edits are reversible and redo branches reconcile.

### Forms

- [x] Color and width controls have persistent programmatic labels; menus show values and samples.
- [x] Native dropdown and color panel semantics used; custom control retains a button role.
- [x] Paste/autofill/passwords, international data formats, field validation and OTP are not applicable to these preset controls.
- [x] Invalid width input is rejected without clearing a valid value; canceling menus preserves the work.

### Accessibility

- [x] Visible width dropdown provides an alternative to right-click; native menus/buttons retain keyboard activation.
- [x] Accessible names, selected values and disabled fill help are explicit; color presets expose names.
- [x] Decorative line samples/rainbow are part of their labeled controls, not extra elements.
- [x] Selection uses outline and programmatic state; no animation is required.
- [x] Existing modal focus/source-app handling is retained; no new custom modal introduced.
- [ ] Full VoiceOver, Tab/Shift-Tab and live color-panel focus walkthrough remains manual.
- [ ] macOS Zoom, larger text and increased-contrast settings have not been manually exercised.

### Responsive behavior

- [x] 620, 680, 780 and 1000 pt layouts tested in both themes.
- [x] Repeated actual-controller reflow tested across the breakpoint; toolbar height is reserved above the canvas.
- [x] Existing long/multilingual clipboard fixtures remain covered. UI language is English; full RTL localization is outside scope.
- [x] Desktop-only interface; mobile safe areas and software keyboard do not apply.
- [x] Toolbar does not cover the canvas or export actions; image fit/aspect ratio retained.
- [x] No unintended duplicate controls or overflow in adaptive layouts.

### States and recovery

- [x] Selected preset/custom color, selected tool, disabled fill width and unavailable undo/redo states covered.
- [x] Existing history loading/empty/permission/error renders still pass; offline is not applicable.
- [x] Canceling menus does not mutate drawings; invalid width leaves current state intact.
- [x] Width changes and drawing support Undo/Redo, including a new branch after Undo.
- [x] Existing destructive clipboard actions and editor cancel/save/copy scope retained.

### Visual fidelity

- [x] Stated target sizes, grouping, values and breakpoint match the implementation.
- [x] Actual native images at all four editor widths reviewed against references 01–07.
- [x] Intentional differences documented: highlighter range differs from outlines; fill has no width; compact toolbar uses two rows.

### Verification

- [x] Formatting/whitespace checked; no configured formatter.
- [x] Swift type checking passes.
- [x] Existing 22 unit/integration tests and new native menu/canvas/controller checks pass.
- [x] 42 visual/export scenarios pass, including pixel evidence for marker thickness.
- [x] Device scope documented: native offscreen AppKit on this Mac; no CUA/live-app testing.
- [x] Remaining manual limitations reported.

## Remaining assumptions

The standard macOS color panel has not been opened during automated checks, respecting the user's request to operate the app themselves. VoiceOver, live menu tracking and the picker close/reopen interaction still need a manual walkthrough. Offscreen tests do not prove compositor frame pacing. Per-tool values reset in a new editor session; no persistent preferences are claimed.

The development bundle for this iteration is `.build/editor/Clip.app`, built separately so the current app is not overwritten or quit automatically. Quit the current Clip through its menu bar menu before launching the new bundle from Terminal.
