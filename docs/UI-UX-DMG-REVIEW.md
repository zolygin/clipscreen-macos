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
- [x] Visual fidelity: offscreen 1× and 2× artwork inspected; composition preview rendered with native icons. The initial 2× preview exposed a double scale transform; moving the logical bitmap size assignment after drawing fixed it. The generator now checks the arrow pixel position/color at both scales. Aligned icons, arrow and readable instruction follow references 01–07 of ui-ux-product-design.
- [x] Verification: Node syntax checks, isolated mocked distribution/failure tests, Swift artwork execution and AppleScript compilation. The initial check was offscreen; after explicit maintainer authorization, native Finder/temporary-volume integration checks were also run. No full application/release build was executed for verification.
- [x] Native Finder script ran twice on a disposable volume, saving both item records and closing only owned windows.
- [ ] VoiceOver, keyboard copy and real signed DMG install: require a maintainer run of `npm run dist` and manual check. Not claimed as tested.

## Assumptions and limits

Finder backgrounds are static. Native drag/copy feedback supplies motion. Finder window chrome/labels can vary across macOS versions. On first build, Terminal → Finder automation may require permission; end users installing the DMG do not need it. The user selected the graphite tile with two overlapping cards and a blue clipboard tab. `Resources/AppIcon.png` has transparent exterior corners; `Resources/Clipscreen.icns` is wired into development/release resources and the volume icon. Native status-bar Lucide artwork remains separate.


## Finder alias regression

A maintainer build reported error -1728: a filesystem alias cannot supply Finder's `container window` property. The production script now creates a specific Finder window, sets its target from the private mount alias, and obtains the Finder container through that window. It closes its own window on success and error. No front-window or volume-name lookup is used.

The packaging error now adds an Automation hint only for actual Apple-event permission denial (-1743). Mocked regressions distinguish object lookup, unrelated layout failures and permission denial. AppleScript compilation is a syntax check, not proof of runtime behavior.

`npm run check:dmg-layout` is an explicit integration check for a maintainer terminal. It exercises the real script on a disposable HFS+ fixture twice and checks DS_Store/owned-window cleanup. After explicit maintainer authorization, the production Finder script passed twice on an actual temporary HFS+ volume. This also exposed and fixed a second runtime reference: icon view options must explicitly belong to the created window. No production rebuild or notarization was performed for this fix.


The native packaging check subsequently exposed that `bless --openfolder` is unsupported on Apple Silicon. That legacy command was removed. The actual `createInstallationDMG` function then passed twice with non-executable fixture apps: Finder metadata and both item records, owned-window cleanup, volume-icon flag, unmount, UDZO conversion and `hdiutil verify`. Temporary fixtures were removed. All 19 isolated distribution tests also passed; the test runner rejects reintroduction of `bless`.
