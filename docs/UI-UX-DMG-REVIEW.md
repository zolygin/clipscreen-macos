# DMG installation review

## Task and diagnosis

A Mac user opening the download needs to recognize that Clipscreen should be copied to Applications. Previously, packaging supplied two items without an arranged installation view or instruction. The change preserves Finder's native copy model.

## Constraints and implementation

- Content 640 × 400 pt, neutral #F5F5F7, 1×/2× TIFF.
- Real 112 pt app/Applications icons centered at (170, 210)/(470, 210).
- Arrow between icons, 3 pt stroke #767680; no continuous motion.
- Centered 24 pt title, 16 pt action instruction, 13 pt follow-up; system font.
- Toolbar/statusbar/sidebar hidden; arrangement disabled so targets stay put.
- App signing precedes packaging; layout, close/unmount and UDZO conversion precede DMG signing/notarization.

Files: `scripts/dmg.mjs`, `scripts/dmg-layout.applescript`, `scripts/render-dmg.swift`, `scripts/dist.mjs`, `Resources/Installer/*`, `Tests/DistTests.mjs`, distribution documentation.

## Filled implementation QA

- [x] Architecture: existing Node-only command runner, signing order, lock, error redaction and output publication retained. No new npm dependencies or installer runtime.
- [x] Components/states: native Finder icons remain real files/shortcut, with native selection, focus, copy progress and errors; decorative background is not a fake control.
- [x] Forms: not applicable; no fields, passwords or new user input.
- [x] Accessibility design: meaning uses wording, direction and labeled native items; no color-only cue or required animation. Native copy/paste is available. Installation instruction also exists as document text.
- [x] Layout: fixed desktop DMG view, generous gaps and Retina representation. Production app icon is not baked into the background; a future icon needs no layout change.
- [x] Recovery: private unique mount path, close before detach, forced-detach fallback for this private volume, no conversion/signing/upload if layout or detach fails. Existing outputs remain intact.
- [x] Visual fidelity: offscreen 1× and 2× artwork inspected; composition preview rendered with native icons. Aligned icons, arrow and readable instruction follow references 01–07 of ui-ux-product-design.
- [x] Verification: Node syntax checks, isolated mocked distribution/failure tests, Swift artwork execution and AppleScript compilation. No full application/release build or Finder automation executed for verification.
- [ ] Live Finder opening, VoiceOver, keyboard copy and real signed DMG install: require a maintainer run of `npm run dist` and manual check. Not claimed as tested.

## Assumptions and limits

Finder backgrounds are static. Native drag/copy feedback supplies motion. Finder window chrome/labels can vary across macOS versions. On first build, Terminal → Finder automation may require permission; end users installing the DMG do not need it. The user selected the graphite tile with two overlapping cards and a blue clipboard tab. `Resources/AppIcon.png` has transparent exterior corners; `Resources/Clipscreen.icns` is wired into development/release resources and the volume icon. Native status-bar Lucide artwork remains separate.
