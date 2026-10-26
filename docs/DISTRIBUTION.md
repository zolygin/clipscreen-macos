# Building and distributing Clipscreen

## One-command signed distribution

```bash
npm run dist
```

This creates an optimized **Universal 2** app (Apple Silicon and Intel), signs it with Developer ID Application, creates and signs a DMG, submits that DMG to Apple, waits for **Accepted**, staples its ticket, and verifies the final container before writing:

```text
release/Clipscreen-0.5.0-universal.dmg
release/Clipscreen-0.5.0-universal.dmg.sha256
release/Clipscreen-0.5.0-universal.release.json
```

The version/build come from `Resources/Info.plist`; filenames change with the version. The JSON records architectures, source revision, signer, notarization submission ID and checksum. A modified source checkout is marked `+modified`. Only a completed, verified run replaces the generated local DMG; it does not alter an already-published release.

`npm run dist` never tags, commits, pushes or publishes to GitHub/Supabase. Publication is a separate maintainer action.

### Requirements

- A Mac with Xcode 26 or a compatible newer macOS SDK, including `swiftc`, `lipo`, `notarytool` and `stapler`.
- Node.js 22 or later and npm. No `npm install` is needed: the wrapper uses Node built-ins only. The distributed app remains native Swift/AppKit and contains no Node/Electron runtime.
- A valid **Developer ID Application** certificate and its private key in Keychain.
- Apple notarization credentials configured by one of the methods below.
- Permission for the invoking terminal to control Finder (macOS may ask once during DMG layout).
- Network access for timestamp signing, notarization, ticket download and Gatekeeper assessment.

The app still targets macOS 13.0+. Building with a deployment target is not a runtime compatibility test on every supported Mac.

### Read-only readiness check

```bash
npm run dist:check
```

This checks the SDK/tools, source metadata, a matching valid Developer ID Application identity and the presence of the selected authentication configuration. It does not compile, sign, create a DMG, validate credentials remotely or upload anything. A Keychain-profile name is configuration, not proof that Apple will accept its credentials.

### Installation window

The DMG opens in Finder with Clipscreen on the left, the Applications shortcut on the right, an arrow and “Drag Clipscreen to Applications”. The arrow/background are static; Finder provides the actual drag, copy progress and keyboard interactions. After copying, open the app from Applications.

During `npm run dist`, Finder briefly opens the private staging volume to save its icon positions, background and window settings. On the first run, allow the invoking terminal to control Finder. If denied, enable it in **System Settings → Privacy & Security → Automation** and retry. No such automation permission is required to install or use the distributed app.

Layout failure, a missing `.DS_Store` or failure to unmount prevents signing/upload of a new DMG; existing release artifacts remain untouched. The staging volume is unmounted even when Finder configuration fails. Background artwork and regeneration instructions live in `Resources/Installer/README.md`.

### Authentication: same variables as Dictāta

The script supports the same Apple ID method used by Dictāta/electron-builder:

```dotenv
APPLE_ID=developer@example.com
APPLE_TEAM_ID=YOURTEAMID
APPLE_APP_SPECIFIC_PASSWORD=your-app-specific-password
```

`APPLE_ID_PASSWORD` is accepted as the password alias used by the Dictāta helper. If Team ID is omitted, the signer’s team is used. Alternatively, set `APPLE_KEYCHAIN_PROFILE` (or `CLIPSCREEN_NOTARY_PROFILE`) to an existing `notarytool` Keychain profile.

For a fresh setup, copy `.env.release.example` to `.env.release.local` and configure one authentication method. To create a Keychain profile interactively, run:

```bash
xcrun notarytool store-credentials "Clipscreen Notary"
```

That credential-setup command can validate the credentials with Apple. Run it locally and enter the requested values there; passwords do not belong in chat or Git.

Environment/configuration precedence is:

1. Variables already set in the invoking shell.
2. This project's `.env.release.local`.
3. Files explicitly listed in the ignored `.release.local.json`, in listed order.
4. This project's `.env.desktop`, then `.env`.

Only the Apple signing keys and supported identity/profile overrides are imported from dotenv files. The file content is parsed as data, never executed as shell code. Unrelated provider keys from another project are not imported.

For this maintainer's existing Dictāta setup, the local file can contain only references:

```json
{
  "credentialsFiles": [
    "../dictata/.env.desktop",
    "../dictata/.env"
  ]
}
```

This machine-specific file is ignored by Git and contains no copied password. Another checkout can configure its own `.env.release.local` or Keychain profile without having Dictāta installed. Credential values are not printed in build logs or written into release metadata. The Apple ID method passes credentials only to Apple's notarization CLI; private signing keys remain in Keychain.

If several valid Developer ID Application certificates exist, set `CLIPSCREEN_SIGNING_IDENTITY` (or `CSC_NAME`) to the intended full certificate name, signer name with Team ID, or certificate hash. Automatic selection is permitted only when one matching identity remains. Apple Development and ad-hoc identities are not accepted for this workflow.

### Identity and compatibility

The default bundle ID comes from `Resources/Info.plist`: currently `local.kirill.clip`. It is retained for preference/login identity compatibility. History remains in `~/Library/Application Support/Clip/`. The release uses the ordinary Developer ID designated requirement, not the identifier-only ad-hoc requirement used by the debug builder.

`CLIPSCREEN_BUNDLE_ID` is an explicit override for a deliberate identity migration. Changing it can require preference/login migration; it is not changed automatically by this workflow.

### Pipeline and failure handling

1. Validate local prerequisites and acquire an exclusive release-job lock.
2. Create a new workspace under `.build/dist-runs/`; keep the existing development app untouched.
3. Copy Info.plist, the Clipscreen ICNS icon, Lucide SVGs/ISC license and the MIT license; record build provenance.
4. Compile optimized `arm64` and `x86_64` executables and merge them before signing.
5. Sign the completed app with Developer ID Application, Hardened Runtime and a secure timestamp; verify its signature.
6. Create a temporary writable DMG, mount it at a unique private path, and use Finder to save a 640 × 400 pt drag-to-Applications layout with a Retina background. Close/unmount it, convert to compressed UDZO, then sign and verify the final DMG.
7. Submit the outer DMG with `notarytool --wait`. Apple's service processes the nested app as part of that submission.
8. Require `Accepted`, staple and validate the DMG ticket, verify disk-image integrity/signature, and run Gatekeeper assessment.
9. Write the final DMG, SHA-256 sidecar and release manifest to `release/`; remove the successful temporary workspace.

A rejected/unfinished submission or a failed verification stops the run. Existing generated release files remain in place for these failures, and the failed workspace is retained with its notarization ID/status when available. No automatic re-upload loop runs. Inspect the retained workspace/status before submitting again. A lock rejects concurrent distribution jobs.

Both `.build/` and `release/`, local environment/configuration files, and private-key/certificate-export extensions are ignored by Git. No Electron-specific JIT or library-validation entitlements are copied from Dictāta.

## Development build and local installation

The separate development workflow remains:

```bash
bash scripts/build-app.sh
open .build/Clipscreen.app
```

It creates a host-architecture debug app using `-Onone -g` and an ad-hoc signature. It does not notarize or produce a public installer. Both build commands create complete apps and require an explicit user request when run by an agent under `AGENTS.md`.

For daily use, quit the earlier running copy, open the release DMG and drag `Clipscreen.app` to Applications. Run the installed copy before enabling login launch and granting system permissions. Terminal is not needed to launch an installed app.

## Verification status

The release wrapper has automated tests with every external build/signing/Apple command intercepted. They cover credential precedence, safe dotenv parsing, identity selection, read-only preflight, Universal 2 merge-before-sign ordering, Hardened Runtime/timestamps, one outer-DMG submission, ticket/checksum ordering, no GitHub publication, preserved development/previous release files, rejected notarization, stapling/Gatekeeper failures, redacted errors and job locking. Run:

```bash
npm run check:dist
```

On 2026-10-26, 11 isolated pipeline tests and a native `lipo` smoke test passed. The latter uses header-only Mach-O object fixtures, accepts both required architectures and rejects a missing slice without compiling an application. Real local preflight found the installed macOS 26.5 SDK, valid Developer ID Application identity and the existing Dictāta Apple ID environment. Release plist commands were also checked on a temporary plist, and both arm64/x86_64 compiler argument sets passed real Swift type-checking without emitting executables. **A real production build, signing operation and Apple submission were not run during this implementation.** These checks do not establish that a signed/notarized DMG has already been produced.

After the first real successful `npm run dist`, test the actual downloaded/quarantined DMG with normal Gatekeeper settings. Verify install/launch, clipboard and Accessibility permissions, screenshots, login launch and updates. Test the architectures/macOS versions promised in release notes. Then create the GitHub Release and attach the DMG/checksum from this run; do not replace a published tagged asset with different bytes under the same filename.

## Primary references

- Apple: [Developer ID distribution](https://developer.apple.com/developer-id/).
- Apple: [Creating distribution-signed code for macOS](https://developer.apple.com/documentation/xcode/creating-distribution-signed-code-for-the-mac).
- Apple: [Customizing the notarization workflow](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow).
- Apple: [Building a universal macOS binary](https://developer.apple.com/documentation/apple-silicon/building-a-universal-macos-binary).

### First distribution-run fix: lipo argument order

The first maintainer run compiled and merged both optimized slices, then stopped at the verification command because the executable path followed `-verify_arch`. That option consumes subsequent arguments as architecture names. The corrected command is `lipo <executable> -verify_arch arm64 x86_64`. It was checked with the real tool against both synthetic object headers and the already-produced Universal 2 executable. The fake lipo implementation now enforces the argument order too. Signing and notarization were not reached in that failed run; rerun `npm run dist` with the corrected script.
