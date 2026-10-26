# Screenshot editor foreground handoff — 2026-10-26

## Diagnosis

The user reports that the screenshot editor sometimes remains behind another application after Option-Command-4 or the menu bar capture action. Both entry points call `AppDelegate.captureScreen()`, so they share the same completion path. Inspection found a single activation request before construction of the editor, followed immediately by `makeKeyAndOrderFront`. The local macOS 26 AppKit SDK documents app activation as asynchronous and not guaranteed. A race with the capture tool restoring the source application is a plausible cause; no live capture/WindowServer trace was collected.

## Constraints and changes

Keep the existing accessory/menu bar activation policy and one shared capture-completion path. The ready editor must be ordered before requesting activation. Once AppKit notifies that activation completed, make that editor key/front. Retry a missed handoff only within 0.15/0.4/0.8 seconds; stop when active/key, hidden, minimized, closed, superseded, or when another capture starts. Do not continuously reassert focus. Retain the normal editor window level, 44/80 pt toolbar, existing font/color controls, window geometry and artwork.

- `Sources/Clipscreen/ScreenshotEditorWindow.swift`: `ScreenshotEditorPresenter` owns one bounded presentation attempt, activation/close observers and generation-scoped delayed work. Shows the ready window regardless of background status, requests activation, and completes keyboard focus on the activation notification. Notifications and scheduling are injectable for isolated verification.
- `Sources/Clipscreen/AppDelegate.swift`: construct/retain/configure the editor before presenting through the common presenter. Cancel old requests before another capture or app termination. A capture-in-progress guard prevents overlapping interactive capture processes; reset it on success, cancellation or launch failure.
- `Sources/Clipscreen/ScreenshotEditor.swift`: request the active Space and fullscreen auxiliary behavior for the editor; normal window level retained.
- `Tests/AnnotationChecks.swift`: intercept all ordering/activation calls on hidden test windows, use an isolated notification center and virtual scheduled work. No real activation, capture process or live app control.
- `Resources/Info.plist`: development version 0.4.2 (6).

## Verification

`bash scripts/check.sh`: application type checking, 22 isolated history/pasteboard tests, plist/shell validation. `bash scripts/check-ui.sh`: 57 native visual/export scenarios and six focus-handoff check groups covering order before activation, asynchronous keyboard focus, simulated capture/source-app focus loss, bounded activation denial, close/hide/minimize cancellation, newer-editor precedence and explicit cancellation before capture. Editor collection behavior and normal level are asserted. Existing text/toolbar/window-lifecycle checks pass.

## Filled implementation QA

- [x] Architecture: one presenter shared by hotkey, menu and image-entry editing; existing controller ownership and AppKit APIs reused. No dependencies or product claims added.
- [x] Component behavior: ready/visible, awaiting activation, focused, cancelled and timed-out states covered. Concurrent capture is guarded. Retries are bounded and stale work is invalidated.
- [x] Forms: no new form; current text drafts, font/size/color values and native editing semantics remain covered by existing checks. Password/OTP/autofill rules do not apply.
- [x] Accessibility: restore a key window after activation; do not assign first responder over an existing text editor. Existing labels, keyboard shortcuts, close/Undo/Redo/text routing and focus restoration retained.
- [x] Responsive: no geometry/token changes; 620–1440 pt editor layouts and light/dark renders still pass. Existing panel resize and transparent/opaque/glass scenarios pass.
- [x] Recovery: cancellation/failure releases capture state; closing, hiding, minimizing or replacing an editor cancels deferred presentation. Existing image content and reversible annotation edits remain with their controller.
- [x] Visual fidelity: changes concern activation/order only; the existing visual scenarios still render with the same toolbar and canvas geometry. No motion or color-only state introduced.
- [x] Verification: isolated activation sequencing and cancellation checks pass alongside 22 tests and 57 visual/export scenarios. No formatter is configured; whitespace is checked.
- [ ] Manual limits: real macOS focus ordering after hotkey/menu capture, separate displays/Spaces/fullscreen/Stage Manager, VoiceOver and compositor timing need a user walkthrough. The injected checks verify the handoff logic, not OS permission to activate. No real screenshot was taken and no user window was operated.

Development app 0.4.2 (6) was rebuilt at `.build/Clipscreen.app`; strict signature verification passed. No release/DMG build or live application launch was performed.
