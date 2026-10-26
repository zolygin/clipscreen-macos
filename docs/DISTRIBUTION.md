# Building and distributing Clipscreen

This guide describes the current development build and the work needed for a public macOS release. The project does **not** yet include an automated, distribution-signed, notarized release pipeline. The commands below are manual instructions; documenting them does not mean those release steps have been executed or verified for Clipscreen.

## What the current build produces

From the repository root:

```bash
bash scripts/build-app.sh
```

The script:

1. Creates `.build/Clipscreen.app/Contents/MacOS` and `Contents/Resources`.
2. Copies `Info.plist` and the local Lucide resources into the bundle.
3. Compiles `Sources/Clipscreen/*.swift` directly with `swiftc`, using AppKit and the system frameworks. There is no package manager or Xcode project required by this script.
4. Targets the machine's current architecture (`arm64` or `x86_64`) and a macOS 13 deployment target.
5. Uses `-Onone -g` for a development executable.
6. Records the source revision and UTC build date in the generated Info.plist.
7. Applies an ad-hoc local signature with `codesign --sign -` and verifies that signature.

The compiler needs an SDK containing the macOS 26 APIs referenced by the source, even though availability checks select older runtime fallbacks. Use Xcode 26 or compatible Command Line Tools with the macOS 26 SDK. `-swift-version 5` selects a language mode; it does not remove this SDK requirement.

The output is already a regular macOS application bundle:

```text
Clipscreen.app/
  Contents/
    Info.plist
    MacOS/Clipscreen
    Resources/Lucide/...
```

It is intended for local development. An ad-hoc signature is not a Developer ID signature and does not establish a public developer identity for downloaded software.

## Install the local app for everyday use

1. Quit any running copy of Clipscreen through its menu bar menu, allowing pending history writes to finish.
2. In Finder, open the repository's `.build` directory. Hidden directories can be shown with Command-Shift-Period, or reached with Finder's Go to Folder command.
3. Drag `Clipscreen.app` to **Applications**.
4. Launch that installed copy from Applications, Spotlight or Finder. Terminal is no longer needed for launching it.
5. Grant clipboard access and Accessibility for automatic paste when requested. Screen-capture permissions may also be requested for screenshot functionality.
6. Enable Launch at Login through Clipscreen's menu bar menu if desired.

Use the installed copy before granting permissions or enabling login launch. A development-to-Developer-ID signing change may require reviewing permissions again. The history remains in the user's Application Support directory, outside the app bundle.

## Choose a distribution format

| Format | What the recipient does | Suitability for Clipscreen |
| --- | --- | --- |
| `.app` | Copies the application into Applications | The actual program; already produced locally |
| `.zip` | Extracts the app, then copies it into Applications | A simple download format; notarize/staple the app before creating the final ZIP |
| `.dmg` | Opens the disk image and drags the app to Applications | Recommended public download experience |
| `.pkg` | Runs the macOS Installer | Unnecessary for the current app, which does not install system services or privileged helpers |

A disk image is a container, not a compiler or a signing mechanism. Putting a local development app inside a DMG does not turn it into a distribution-signed or notarized app.

## Optional local preview DMG

These commands package an already-built development app to preview the drag-to-Applications experience. They do not produce a public-ready release. Run them from the repository root after making a fresh local build:

```bash
CLIP_DMG_STAGE="$(mktemp -d "$PWD/.build/dmg-preview.XXXXXX")"
ditto ".build/Clipscreen.app" "$CLIP_DMG_STAGE/Clipscreen.app"
ln -s /Applications "$CLIP_DMG_STAGE/Applications"
hdiutil create -volname "Clipscreen" -srcfolder "$CLIP_DMG_STAGE" \
  -format UDZO ".build/Clipscreen-preview.dmg"
```

The staging directory is new for each invocation. The output filename must not already exist; choose another name for another preview. The Applications item is a shortcut to the recipient's Applications folder, not a copy of that folder. Finder window decoration and icon positioning are optional later refinements.

## Public release workflow to implement

A release should follow this order:

```text
Release executable → Clipscreen.app → Developer ID signature → DMG
→ Developer ID signature on DMG → Apple notarization → stapled ticket
→ final download/install checks → GitHub Release
```

### 1. Establish a stable release identity

Choose and retain a permanent bundle identifier before the first public release. The current `local.kirill.clip` identifier and custom development signing requirement belong to the development workflow. A distribution workflow should use the appropriate Developer ID identity and its normal designated requirement, not simply copy the local `--sign -` / identifier-only requirement.

Developer ID signing requires an Apple Developer Program membership and a **Developer ID Application** certificate with its private key available to the signing process. The public source repository and local source builds do not require that membership. Keep certificate private keys, app-specific passwords and notarization credentials out of Git; use Keychain or appropriately scoped CI secrets.

### 2. Create the release app

The release workflow still needs to be implemented. It should:

- Compile an optimized executable rather than silently publishing the existing `-Onone -g` development output.
- Build either clearly labeled Apple Silicon/Intel downloads, or a Universal 2 executable. For Universal 2, compile both architectures and merge the executable slices with `lipo` **before signing**. A single app then contains both architectures.
- Set the intended app version and build number in `Info.plist`.
- Include the required Lucide resources and license, plus the project's MIT notice in the distributed bundle or accompanying materials.
- Sign the completed app with Developer ID Application, Hardened Runtime and a secure timestamp. Determine and test any genuinely required entitlements; do not add broad exceptions speculatively.
- Verify the final app signature and avoid modifying executable code or signed resources afterward.

The current `scripts/build-app.sh` performs only the development workflow described above; there is no `release.sh` command yet.

### 3. Package and sign the DMG

Create a fresh staging directory containing the signed `Clipscreen.app` and an Applications shortcut. Use `ditto` to preserve the bundle structure, and `hdiutil` to create a read-only compressed UDZO disk image. Sign the DMG itself with Developer ID Application and a secure timestamp, using its own signing identifier.

For a public download such as `Clipscreen-0.3.0-universal.dmg`, only use an architecture label that matches the executable actually inside the app.

### 4. Notarize and staple

Submit the signed DMG to Apple's automated notarization service. This uploads the release artifact to Apple; it is separate from publishing the source on GitHub or submitting an app for App Store review. If the final distribution is a DMG, notarize that outer container.

After a signed release DMG and a configured Keychain credential profile exist, the submission step looks like:

```bash
xcrun notarytool submit "Clipscreen-0.3.0-universal.dmg" \
  --keychain-profile "Clipscreen Notary" --wait
```

Continue only when the result is **Accepted**, and inspect the notarization log for errors or warnings. Then attach the issued ticket to the same DMG:

```bash
xcrun stapler staple "Clipscreen-0.3.0-universal.dmg"
xcrun stapler validate "Clipscreen-0.3.0-universal.dmg"
hdiutil verify "Clipscreen-0.3.0-universal.dmg"
```

The `Clipscreen Notary` profile is a placeholder for credentials configured by the maintainer, not something provided by this repository. Never put the actual password in this document or a committed script.

For ZIP distribution, the ZIP itself cannot be stapled. Notarize, staple the app, and create the final ZIP from that stapled app instead.

### 5. Test and publish the final artifact

Test the actual downloaded/quarantined DMG on a Mac with normal Gatekeeper settings, preferably separately from the development environment. Check installation, launch from Applications, light/dark appearance, clipboard permissions, automatic paste, screenshots, login launch, and updating an existing installation. Test the promised architectures and macOS versions; a successful deployment-target type check is not a runtime compatibility test.

Only then create a version tag and GitHub Release and attach the final DMG, release notes and checksum. Provide download/install instructions in both README languages. Do not silently replace a tagged artifact with different bytes under the same filename.

## Primary references

- Apple: [Packaging Mac software for distribution](https://developer.apple.com/documentation/xcode/packaging-mac-software-for-distribution).
- Apple: [Creating distribution-signed code for macOS](https://developer.apple.com/documentation/xcode/creating-distribution-signed-code-for-the-mac).
- Apple: [Notarizing macOS software before distribution](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution).
- Apple: [Customizing the notarization workflow](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow).
- Apple: [Building a universal macOS binary](https://developer.apple.com/documentation/apple-silicon/building-a-universal-macos-binary).
- Apple: [Developer Program enrollment](https://developer.apple.com/help/account/membership/program-enrollment).

## Development rename compatibility (0.3.0)

The product and executable are now Clipscreen, and the repository folder is `clipscreen-macos`. The canonical development bundle is `.build/Clipscreen.app`; older `.build/*/Clip.app` bundles are historical copies. The development bundle identifier, designated requirement, preference keys and existing `Application Support/Clip` storage stay unchanged to preserve history and settings. A future Developer ID release should handle any identifier migration explicitly. The status menu exposes version/build and a tooltip containing build date, source revision and the running app path.
