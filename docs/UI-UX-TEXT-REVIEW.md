# Screenshot text annotations — 2026-10-26

## Diagnosis and task

A screenshot author needs to add a readable label without exporting to another editor. The existing editor has drawing tools and colors, but no text model, input surface or font controls. The main risks are accidental screenshot Copy while typing, lost drafts, a toolbar that overflows, and export that differs from the canvas.

## Concrete constraints set before implementation

Reuse original Lucide `type.svg`, 16 pt icon / 30 pt button, 14 pt toolbar edges, 4 pt within palette/tool groups, 8 pt between groups. Place Text beside Color, separate from the six drawing tools. Native text options: 118 × 26 pt font picker, 76 × 26 pt size picker, 6 pt gap, visible only in Text mode. System, serif and monospaced Apple font designs; default 24 pt, presets 12/16/20/24/32/48/64/96. The initial implementation used 80 pt below 780 pt or in Text mode, otherwise 44 pt. The follow-up below replaces the forced Text row with content-based fitting. Preserve dynamic system colors, selected outlines, existing Save/Copy and original-resolution export. The breakpoint increased from 720 to 780 pt to accommodate Text; Text mode keeps a second row at wide sizes to avoid squeezing its controls.

## Files changed and rationale

- `AnnotationTypes.swift`: text payload and font style; shared measurement, drawing and hit bounds in image coordinates.
- `AnnotationCanvasView.swift`: transparent native plain-text input, multiline Unicode, commit/cancel, selected-object style/color changes, dragging/deletion and reversible snapshots. Each text editor owns its typing undo manager.
- `ScreenshotEditorToolbar.swift`: Text next to Color and contextual font/size controls. No separate stroke-width dropdown was reintroduced.
- `ScreenshotEditor.swift`: synchronize defaults, selection and live editing; commit before Save/Copy.
- `ScreenshotEditorWindow.swift`: Return/newline and text Copy/Paste/Undo stay in the input; Command-Return applies. Keyboard Return on the text canvas starts input. Command-S saves and Command-W closes as before.
- `StrokeWidthMenu.swift`: Text never advertises an outline-width setting.
- `Tests/AnnotationChecks.swift`: real native text input/events, editor wiring, export pixels and reflow assertions; synthetic preview fixtures only.
- README, design context, architecture summary and Info.plist: document the feature and identify the development build as 0.4.0 (4).

## Interaction and state model

Select Text, then click the image (or press Return while the canvas is focused). Return inserts a line; Command-Return or a click away applies. Escape discards this edit and restores the existing label's style/color selection. In Text mode, click an existing label to select, drag to move, double-click or use its Edit Text context menu to edit. Delete removes a selected label; applying empty text deletes it. Whitespace-only new labels are ignored. Font/size/color edits affect the active draft or selected label, otherwise they set the next label's defaults. Added labels, edits, movement and deletion use document Undo/Redo. Normal text shortcuts use a separate typing history while input is active.

Text wraps at the image's remaining width. Long input remains in a scrolling native viewport and survives resizing. Text outside the image is clipped to the image on canvas/export; this is not an automatic shrink-to-fit feature. The native color panel remains a separate window as requested previously.

## Checks performed

`bash scripts/check.sh`: Swift type checking, 22 isolated history/pasteboard tests, plist and shell syntax. `bash scripts/check-ui.sh`: 53 visual/export scenarios plus behavioral assertions, including 620/680/779/780/1000 pt ordinary toolbar reflow, 620/780/1000/1440 pt text reflow in both themes, no overlapping controls, all font/size choices, actual insertion and newline, Unicode/emoji, cancel/commit, text selection/movement/color/deletion, document and typing Undo/Redo, keyboard routing, live-draft export and original 1280 × 720 pixels for a 2x screenshot. Existing 120 panel-resize updates and 22 history tests still pass.

Actual rendered text controls, PNG exports and a long-input viewport were inspected using skill references 01–07. Observed: controls fit, font choices render distinctly, the same line content appears in export, and the rainbow color action remains recognizable. The first input implementation had an opaque theme background; it was corrected to transparent so black text remains visible on a light screenshot in dark mode. Offscreen black space outside the image is the uncached window background, not exported pixels.

## Filled implementation QA

### Architecture

- [x] Existing Lucide asset, AppKit controls, system colors and annotation snapshots reused.
- [x] Semantic Text tool/style model; no external dependency, network or marketing claims.
- [x] Selection/default/draft data flow is synchronized through controller callbacks.

### Component behavior

- [x] Default, selected, hover/pressed and disabled states reuse existing controls. Native font popups show current values; Undo/Redo availability follows snapshots.
- [x] Drafts apply once; copy/save commit before rendering. Invalid sizes preserve the previous value.
- [x] Async processing/optimistic updates are not introduced; loading states are not applicable to local text input.

### Forms

- [x] Font/size remain visible while Text is active; native popups and text input have persistent accessible labels/help.
- [x] Plain-text input supports native selection, copy/paste, newlines and multilingual content. Password managers, autofill and OTP are not applicable.
- [x] Text survives resizing and style changes; empty text has explicit no-op/delete semantics.

### Accessibility

- [x] Keyboard activation, canvas Return, newlines, apply/cancel and local Undo/Redo tested with native events.
- [x] Focus enters text input and returns to canvas on commit/cancel; changing font restores input focus. No new modal.
- [x] Font, size, annotation input and Text selected state expose names/values/help. Selection has an outline and programmatic state; no motion is introduced.
- [x] Decorative Lucide glyph is part of the labeled button.
- [ ] Live VoiceOver/Tab traversal, macOS Zoom and increased-contrast settings remain manual; no claim of complete assistive-technology validation.

### Responsive behavior

- [x] Narrow, breakpoint, wide and 1440 pt text layouts checked in both themes with longest font label and 96 pt option.
- [x] Toolbar reserves its real height; input stays within canvas after narrow resizing. Image aspect ratio/pixel resolution preserved.
- [x] Cyrillic/Latin/emoji and long text checked. Native text input handles writing direction; full localized/RTL toolbar layout is outside the English UI scope.
- [x] Desktop safe areas/software keyboards are not applicable. No sticky overlay covers toolbar actions.

### States and recovery

- [x] New/selected/editing/empty text states are explicit. Escape restores prior content/style. Cancelled/blank drafts do not leave invisible objects.
- [x] Changes and deletion support Undo/Redo. Normal typing Undo cannot remove document objects.
- [x] No new network/loading/permission flow. Existing editor close and color-panel ownership are retained.

### Visual fidelity

- [x] Literal sizing/spacing, Apple font choices, 780 pt breakpoint and contextual second row match the implementation.
- [x] Actual light/dark/native renders and original-resolution PNG reviewed against references 01–07.
- [x] Transparent input is an intentional correction from the first render; there is no opaque input fill hiding the screenshot.

### Verification and remaining scope

The authorized development rebuild completed at `.build/Clipscreen.app`, version 0.4.0 (4). Strict code-signature verification passed. The app was left for the user to launch from Terminal; no release/DMG build or live UI control was performed.

- [x] Swift type checking, native behavior assertions, 22 tests and 53 rendered/export scenarios pass. Whitespace checked; no formatter is configured.
- [x] Synthetic fixtures and isolated pasteboards only. User's live application and clipboard were not operated.
- [x] Remaining scope recorded: real interactive menu/focus walkthrough, VoiceOver, other macOS versions and compositor performance have not been manually tested. Font point sizes refer to image coordinates, so their screen size varies with zoom.

## Follow-up: keep Text in a single row when it fits — 2026-10-26

Observed: the user supplied a screenshot with ample horizontal space, yet Text forced an 80 pt/two-row toolbar. This was caused by an explicit `selectedTool == .text` layout condition. This also moved the screenshot whenever Text was selected.

Changed: `ScreenshotEditorToolbar.swift` measures natural widths of visible controls, not the size of an already constrained stack. The layout preserves 14 pt outer insets, 8 pt group gaps, 30 pt tools, 118/76 pt font controls and a minimum 8 pt spacer. Above the existing 780 pt floor, it uses a 44 pt single row whenever everything fits; otherwise it reserves 80 pt and moves the style group together. Text selection alone never forces a second row. Row frames are assigned during reflow, so the current row contents cannot impose a stale Auto Layout minimum width on the editor window. The controller still reserves toolbar height above the canvas with its existing constraint. The existing 620 pt editor minimum is explicit; the root content view starts at the actual content size and resizes with the window.

Verification adds repeated tool/font switches at 960 pt with no height callbacks and identical canvas/header frames, narrow/wide resizing, visible font controls, exact requested window widths, and no control overlap. Text renders are checked at 620/780/900/960/1000/1440 pt in both themes.

Filled implementation QA for this change:

- [x] Architecture: reuse the same controls, font data, colors and controller height callback; remove redundant tool state. No new product claims or dependencies.
- [x] Behavior: font values and Text selection stay visible; ordinary drawing tools keep their existing layout rules. No loading, asynchronous or optimistic state is introduced.
- [x] Forms: native font/size selectors, labels, input and editing recovery are preserved. No new validation, autofill or OTP flow.
- [x] Accessibility: existing native names, values, keyboard routing and focus restoration retained. No icon-only or hover-only setting added.
- [x] Responsive: wide Text stays in one row; narrow layout keeps both font controls attached and visible. Changing tools/fonts at a fitting width does not move the screenshot.
- [x] Recovery: text drafts and Undo/Redo behavior remain covered by the native interaction/export checks. No destructive action added.
- [x] Visual fidelity: review actual light/dark native renders; preserve stated sizes/gaps and allow wrapping only when controls require it.
- [ ] Manual scope: VoiceOver, live menu tracking, other macOS versions and compositor timing are not exercised by offscreen renders.

- [x] Verification: 57 native visual/export scenarios and new geometry/visibility assertions pass; actual 960 pt light and 1000 pt dark one-row renders and the 620 pt two-row render inspected. Existing 22 isolated tests and Swift type checking pass. No formatter is configured; whitespace is checked.

Development build 0.4.1 (5) completed at `.build/Clipscreen.app`; strict code-signature verification passed. The app is left for the user to launch, without controlling their live UI.
