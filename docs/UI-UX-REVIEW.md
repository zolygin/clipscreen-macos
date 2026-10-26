# Clip 0.2 — UI/UX implementation review

Date: 2026-10-25. Scope: screenshot audit, native AppKit implementation, English UI, material clipping and theme adaptation.

## Task model and diagnosis

A Mac user needs to recognize and paste an earlier clipboard item with ⌥⌘V and Return, without losing the destination or having to scan a noisy list. The user verified that copying/pasting worked in 0.1; this update preserves that flow.

Observed in the supplied screenshot and confirmed in source:

1. **Backdrop corners escaped the foreground rounding.** `NSVisualEffectView` only had a CALayer corner radius; its separately composited material had no alpha mask. The screenshot shows light square pixels outside the rounded surface. Fix: explicitly mask the standard material, use the native corner radius on glass, keep the window and wrapper transparent, and clip foreground content separately.
2. **Weak grouping within rows.** Text and metadata were anchored to opposite ends of an 82 pt row. Fix: center a text group with a 5 pt internal gap inside a 76 pt row. Thumbnail slots are 48 pt; body text uses regular weight.
3. **Content overflow and intrusive tooltips.** Long previews could paint past their bounds, and the full-content tooltip covered the heading. Fix: two-line truncation, bounded text layers, and no full-content hover tooltip. Full clipboard payloads remain intact.
4. **App-owned copy was Russian.** Headers, menus, generated labels, relative time, errors and accessibility descriptions were translated to English. Copied text and external application names retain their original language. Historical image records display an English generic title without rewriting saved content.

Predicted benefit: clearer scanning and a quieter hierarchy. This is design judgment, not a measured usability improvement.

## Concrete constraints and rationale

| Role | Implemented value |
| --- | --- |
| Default panel | 430 × 590 pt; limited to the current screen's visible frame |
| Panel corners | 18 pt, including material clipping |
| Primary content inset | 16 pt |
| Row | 76 pt, 4 pt separation, 10 pt selection radius |
| Thumbnail | 48 × 48 pt, aspect ratio preserved |
| Image-to-text / title-to-metadata | 12 pt / 5 pt |
| Typography | System 17 semibold title; 13 regular content; 11 regular metadata |
| Preview | At most two lines, truncated; full original payload retained |
| Color | Native label/secondary-label, accent, and window-background roles |
| Footer | 46 pt normally; 76 pt when a permission action is available |
| Information order | Heading → search → optional status → history → keyboard help |

Intentional exceptions: list container inset is 8 pt to leave room for rounded selection and internal row padding; header top padding is 20 pt; search uses 14 pt native control typography. No custom animation was introduced.

## Files changed

- `Sources/Clipscreen/PanelSurface.swift`: shared visual constants, standard material mask, macOS 26 glass container, opaque accessibility fallback, theme updates and rounded selection.
- `Sources/Clipscreen/HistoryPanel.swift`: compact text grouping, bounded previews, footer, English content, loading state, search over display labels, keyboard handler and accessible hints.
- `Sources/Clipscreen/History.swift`, `HistoryModel.swift`, `Pasteboard.swift`: English generated/error labels, legacy image presentation, loading status, whitespace labels. Payload persistence and retention semantics are unchanged.
- `Sources/Clipscreen/AppDelegate.swift`, `PasteController.swift`: English menus, permission/recovery copy and app-owned errors. Open History uses a native menu key equivalent.
- `Resources/Info.plist`: English development/supported language; version 0.2.0 (2).
- `Tests/ClipTests.swift`, `Tests/PanelPreview.swift`, `scripts/check-ui.sh`: localization regression checks, keyboard checks and view scenarios.
- `scripts/build-app.sh`: optional absolute output bundle path, allowing an updated build without overwriting the running app.
- `.impeccable.md`, `README.md`: confirmed design rules and current build instructions.

## States and accessibility

The panel preserves search focus, native search editing, IME composition, selection across refresh, arrows, Return, Escape and Command-Delete. When a button holds keyboard focus, history shortcuts no longer intercept its ordinary activation keys. The existing guard against repeated paste activation is unchanged.

English labels cover buttons, menus, status, errors, empty results and relative timestamps. Decorative thumbnails do not receive a separate accessibility element; each row exposes the content summary and keyboard help. Native controls retain their platform focus treatment.

Liquid Glass is used on macOS 26. Standard material is retained on older systems. Reduce Transparency uses an opaque system-colored surface; appearance changes update its color. The single-material rule avoids stacking two blur effects. No system settings or permissions are changed automatically.

## Checks performed

- All application sources pass Swift type checking against the macOS 13 deployment target and macOS 26 SDK.
- **20 storage/clipboard/localization tests pass.** Named temporary pasteboards are used; the user's system clipboard is untouched.
- Isolated keyboard checks pass for arrows, bounds, Return, Command-Delete, refresh retention and empty history.
- **14 native view scenarios pass:** standard light/dark, glass light/dark, opaque light/dark, empty, permission, manual paste, error, loading, filtered, no matches, and 320 pt width.
- Each render asserts transparent outermost corner pixels and a content area filling the panel. English search finds image records saved with the earlier Russian label.
- All 14 renders were visually inspected against reference modules 01–07: hierarchy, alignment, grouping, density, material layers, light/dark colors and typography. The first glass render exposed a shrinking container; explicit layout constraints fixed it and all scenarios were rerun.
- Property-list and shell syntax validation pass. Local debug build/signature verification is recorded with the delivered bundle.

Previews are in `.build/previews/`. They contain synthetic fixtures, including deliberately multilingual clipboard content.

## Filled-in implementation QA

Legend: checked = verified in the described scope or explicitly not applicable; unchecked = remaining manual verification, not claimed as passed.

### Architecture

- [x] Existing AppKit controls and data flow retained; repeated appearance values extracted to `ClipStyle`.
- [x] New variants describe standard, automatic glass and opaque material roles.
- [x] Repository, capture and paste architecture retained; no database migration or history deletion.
- [x] No invented product data or marketing claims; previews use clearly identified test fixtures.

### Component behavior

- [x] Native control focus/pressed/disabled behavior retained; selected, loading and error states explicitly defined. Rows have no hover-only actions.
- [x] Displayed selection and table selection agree in isolated tests.
- [x] Existing `isChoosing` guard prevents repeated processing activation; inspected, unchanged.
- [x] Optimistic mutation is not introduced; existing storage commit/rollback tests pass.

### Forms

- [x] Search has a persistent accessibility label and native search-field semantics.
- [x] Native editing and paste commands retained; no authentication/autofill/password fields exist.
- [x] Unicode clipboard content remains unchanged in tests; IME marked text bypasses history navigation interception.
- [x] Search text and selected item survive recoverable refresh; application errors appear outside the field.
- [x] OTP, address/payment formats and composite form fields: not applicable.

### Accessibility

- [x] Isolated history keyboard flow passes; actionable controls keep English labels and native roles.
- [x] Default search focus and source-app restoration code retained; user verified restoration in the previous version.
- [x] Existing native destructive dialog retains a safe Cancel default and explicit consequences.
- [x] Decorative preview views are excluded as separate accessibility elements; row summaries/help are provided.
- [x] Selection has both fill and an outline, as well as native selected semantics. No motion is required.
- [ ] Full updated-app Tab/Shift-Tab, focus-ring and VoiceOver pass has not been run.
- [ ] OS text-size/Zoom and increased-contrast modes require manual device testing. Compact rows intentionally truncate previews rather than scale down content.

### Responsive behavior

- [x] 320 pt and 430 pt panel widths rendered; larger displays intentionally retain a compact fixed-width panel.
- [x] Long code, URLs, filenames and multilingual text are included in renders. Interface language is English; full RTL interface localization is outside this version.
- [x] Panel placement uses the screen visible frame; desktop software keyboard/mobile safe areas are not applicable.
- [x] Footer has reserved layout space and does not overlay scrollable content or errors.
- [x] Image aspect ratio is preserved; missing thumbnails use the existing symbol fallback.
- [x] Fixed row/thumbnail geometry prevents asynchronous media from shifting content.

### States and recovery

- [x] Loading, empty, no matches, read permission, manual paste and error states are rendered; offline is not applicable to this local app.
- [x] Existing recoverable read/paste behavior and serial persistence remain; disk-failure tests pass.
- [x] No clipboard payload translation or user-history mutation for this redesign.
- [x] Clear History explicitly states permanent removal; current system clipboard remains available.
- [x] Escape/Cancel code retained. No new deletion workflow or undo claim is introduced.

### Visual fidelity

- [x] Literal spacing/type/shape constraints above match the implementation; exceptions are documented.
- [x] Actual native renders reviewed, not only source code.
- [x] Backdrop masking and glass geometry received a fresh render-based correction pass.

### Verification

- [x] Formatting/whitespace inspected; no repository formatter is configured.
- [x] Swift type checking passes.
- [x] 20 unit/integration tests and isolated keyboard checks pass.
- [x] 14 visual/layout scenarios pass, including alpha checks at all four corners.
- [x] Real-device evidence is documented: user supplied the original macOS screenshot and confirmed the previous paste behavior; new checks run as native AppKit test views on this Mac.
- [ ] Live compositor appearance, shadow, native glass over a real desktop, and updated-app paste with granted permissions remain to be confirmed after restarting into 0.2.
- [x] These manual limits are reported rather than treated as automated passes.

## Remaining assumptions and rollout

The render harness cannot establish the exact appearance of a live behind-window blur or WindowServer shadow. The material mask and native glass corner API address the observed implementation error, while a post-restart visual check remains useful. Full VoiceOver/text enlargement behavior is also not claimed as tested.

The new bundle is `.build/updated/Clip.app`. Quit the currently running Clip through its menu before opening this bundle, so the original process can flush pending history writes. Both versions use the same persistent history directory. The old bundle is retained; this update does not force-stop the running process or erase its data.

## Primary references

- Apple: [NSVisualEffectView](https://developer.apple.com/documentation/appkit/nsvisualeffectview), specifically `maskImage`, whose alpha channel masks the material itself. The installed SDK also documents how this differs from subview clipping.
- Apple: [NSGlassEffectView](https://developer.apple.com/documentation/appkit/nsglasseffectview), including `contentView` and `cornerRadius` on macOS 26.
- Applied skill: `ui-ux-product-design`, references 01–07 and 13, and its implementation QA checklist. Predictions about readability are design hypotheses until tested with users.
