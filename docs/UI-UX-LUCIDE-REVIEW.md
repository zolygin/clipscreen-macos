# Clip — Lucide, Pin alignment and resizing

Date: 2026-10-25. Mode: implementation using `ui-ux-product-design`, references 01–07 and 13. This review supplements the earlier `UI-UX-REVIEW.md`.

## Diagnosis and task model

A Mac user needs to recognize and paste a previous clipboard item, pin useful entries, and resize the history panel without shifting action targets or losing the destination app.

Observed in source and native renders:

- History and screenshot tools used SF Symbols; the menu bar used a hand-drawn approximation. The icon family was inconsistent.
- The row action stack stretched horizontally. Its trailing edge was aligned, but the actual Pin button stayed near the text. Inspecting rendered frames ruled out the initial hypothesis that the table column was too narrow.
- The resize handle could participate in background-window dragging, while `FloatingPanel.isMovable` ignored assignments. Every pointer update forced an immediate display and wrote two defaults values.
- The three-line resize indicator occupied almost the entire handle.
- A first render showed insufficient distinction between active and inactive pins/filter. The final version adds an outlined active surface.
- The pinned-group separator was drawn after the first pinned entry. It now precedes the group and is absent in the pinned-only view.

The resize changes remove identifiable sources of unnecessary work and competing movement. Their effect on perceived smoothness is a hypothesis until tested by dragging the live window; automated geometry tests do not establish frame rate.

## Literal constraints and rationale

| Role | Value |
| --- | --- |
| Icon source | Unmodified Lucide 0.468.0 SVG paths, 24 × 24 view box, 2-unit rounded stroke |
| Action icons / hit targets | 16 pt / 28 × 28 pt |
| Header menu / native search / clear glyphs | 14 / 14 / 12 pt |
| Action spacing | 4 pt; text-to-action gap 8 pt before native text-field alignment insets |
| Header action order | Menu → capture → Pin; Pin trailing inset 16 pt |
| Row action order | Edit image when relevant → Pin; Pin trailing inset 16 pt |
| Active state | Accent fill at 0.12 alpha, 1 pt outline at 0.5 alpha, 6 pt corners, accessible value |
| Preview fallback icons | 24 pt inside the existing 48 pt thumbnail slot |
| Resize indicator / target | Three 1 pt diagonal strokes, longest 12 pt / 22 × 22 pt target |
| Resize behavior | Fixed top-left anchor, backing-pixel rounding, no animation, one persistence commit at completion |
| Panel sizes | Default 430 × 590 pt; minimum 360 × 420 pt; maximum 850 × 1100 pt, custom drag also limited to available screen area |

Retained: 18 pt panel corners, 16 pt content insets, 76 pt rows with 4 pt separation, 48 pt thumbnails, two-line previews, 17/13/11 pt system type roles, semantic system colors, English interface, automatic appearance and material fallbacks. The 320 pt render is an additional stress case below the interactive minimum. Editor tool targets retain their existing 30 pt size.

## Files changed

- `Resources/Lucide/*`: original SVGs, ISC license and pinned source provenance.
- `Sources/Clip/LucideIcon.swift`: shared cached vector loader and icon button with native hover/press feedback and explicit active outline.
- `HistoryPanel.swift`: actual Pin edge anchoring, icon replacements, smaller menu/grip, isolated resize drag, end-only geometry persistence, keyboard pin/filter actions and accessible button state.
- `PanelSurface.swift`: pinned-group separator placement.
- `AnnotationTypes.swift`, `ScreenshotEditorToolbar.swift`, `StatusIcon.swift`: original Lucide tool and status icons. Paint bucket distinguishes filled rectangle from its outline.
- `scripts/build-app.sh`, `scripts/check-ui.sh`: package the same local SVG assets for the app and isolated renderer.
- `Tests/PanelPreview.swift`: regression checks and synthetic visual fixtures.
- README files, `.impeccable.md`, `CODEBASE_SUMMARY.md`: icon policy, shortcuts and verification guidance.

## Behavior, states and accessibility

Pinning and editing remain independent of row paste activation. `⌘P` acts on the selected entry; `⇧⌘P` toggles the pinned filter. Search, arrows, Return, Escape, deletion, source-app restoration and persistence retain their existing data flow. The model still publishes committed pin state; no new optimistic storage mutation is introduced.

Icon controls retain native button roles and hover/press behavior, with explicit English names and tooltips. Pins expose Pinned/Not pinned; the filter exposes On/Off. An outline accompanies accent color so active state does not depend solely on hue. Row content no longer hides its action children behind a single accessibility element. Decorative previews remain excluded. No animation is introduced.

## Checks performed

- `bash scripts/check.sh`: all source type checking, 22 storage/clipboard/localization tests, plist validation and shell syntax pass. Named pasteboards are isolated from the user's current clipboard. Pasteboard tests require access to the system service outside the restricted sandbox.
- `bash scripts/check-ui.sh`: 25 native renders pass, including transparent-corner checks and actual action/text frame checks. Widths: 320, 360, 430, 600 and 850 pt. States: light/dark, glass, opaque, pinned/filter, loading, empty, no matches, permissions, manual paste, errors and missing thumbnail, plus light/dark editor toolbars.
- 120 sequential resize updates preserve the left/top edges, keep action alignment, and do not invoke the completion callback until release. Tests cover min/max limits, pixel rounding and restoring window movement.
- All vendored icon cases decode and render through AppKit as template images; menu bar variants are covered.
- Actual renders were inspected against references 01–07. This exposed and corrected the stretched action stack and the weak selected-filter treatment. Native cell-frame assertions prevent a recurrence that source inspection alone missed.
- `git diff --check` passes. No formatter is configured.

Preview artifacts are in `.build/previews/` and use synthetic content. No production/release/archive build is part of this work. A full local development build and launch were explicitly requested after the implementation began.

## Filled implementation QA checklist

Checked items are verified in the scope described, or explicitly not applicable. Unchecked items are remaining manual checks, not reported as passes.

### Architecture

- [x] Existing style tokens, AppKit components and model/persistence flow reused.
- [x] Shared icon button expresses action/active roles rather than individual icon styling.
- [x] UI follows committed model state; original clipboard payloads and retention are unchanged.
- [x] No product claims or fabricated user data added; fixtures are synthetic.

### Component behavior

- [x] Default, native hover/pressed, active/selected and disabled tool states are defined; existing loading/error states are rendered.
- [x] Pin/filter/tool programmatic values and visible states agree.
- [x] Existing processing guard prevents repeated paste activation; no asynchronous new action introduced.
- [x] No new optimistic mutation; existing storage reconciliation retained.

### Forms

- [x] Search keeps a persistent accessible label and native editing/paste semantics.
- [x] Unicode and mixed-script content retained; IME bypass remains intact.
- [x] Recoverable refresh preserves input/selection; errors stay outside the field.
- [x] Password/autofill, international address/payment formats, validation fields and OTP: not applicable.

### Accessibility

- [x] Isolated keyboard history, activation, deletion, pin and filter tests pass.
- [x] Existing search/source-app focus handling retained; icon controls have English accessible names and state.
- [x] Native modal behavior retained; no new modal introduced.
- [x] Decorative thumbnails excluded; row actions remain exposed as children.
- [x] Active state uses outline/fill and accessible value; no motion required.
- [ ] Full live VoiceOver and focus-order walkthrough has not been performed.
- [ ] macOS Zoom, larger text, increased contrast and reduced-motion system settings have not been manually exercised; fixed-height previews still truncate rather than shrink text.

### Responsive behavior

- [x] Narrow, default, wide and maximum widths rendered; continuous resizing checks actual Pin position.
- [x] Long text, URLs, filenames, Cyrillic and Japanese samples included. Interface remains English; full RTL localization is outside scope.
- [x] Desktop visible-frame limits considered; mobile safe areas/software keyboard are not applicable.
- [x] Footer and error banner have reserved space and do not overlay rows.
- [x] Image aspect ratio and missing-image fallback rendered.
- [x] Fixed row/media geometry and direct action anchors prevent unintended action-position shifts in automated checks.

### States and recovery

- [x] Loading, empty, pinned-empty, filtered, permission, error and manual-paste states rendered; offline is not applicable.
- [x] Existing safe retry and storage failure handling retained; integration tests pass.
- [x] Search and selection survive recoverable refresh; clipboard data is preserved.
- [x] Existing delete/clear scope and safe Cancel default retained.
- [x] Escape/Cancel retained; no new undo claims or destructive behavior.

### Visual fidelity

- [x] Literal dimensions above match the final code; editor target and 320 pt stress-case exceptions documented.
- [x] Actual native output inspected using the original hierarchy, alignment, density, icon, color and typography references.
- [x] A render-driven correction pass fixed action expansion and made active states visible.

### Verification

- [x] Formatting/whitespace checked; no configured formatter.
- [x] Swift type checking passes.
- [x] Unit/integration and isolated interaction tests pass.
- [x] 25 visual scenarios and 120 resize updates pass.
- [x] Real-device scope documented: AppKit renderer runs on this Mac; live compositor behavior requires separate confirmation.
- [x] Remaining assumptions and manual risks explicitly reported below.

## Remaining assumptions and risks

Offscreen renders do not prove WindowServer frame pacing, blur over a live desktop, permission prompts, or VoiceOver navigation. No performance measurement or user study is claimed. Original SVG loading was exercised on the current macOS; the macOS 13 deployment target is type-checked, without a separate macOS 13 machine run. Runtime resources are included by the build script; direct manual `swiftc` app builds must copy `Resources/Lucide` too.

The requested development bundle is `.build/lucide/Clip.app`. The previous app must quit gracefully before launching it, allowing the existing `applicationWillTerminate` hook to flush history. Earlier bundles and stored history are retained.
