# Clipscreen app icon

The maintainer selected concept 2: a graphite macOS tile with two white overlapping cards and a blue clipboard tab. The original surrounding pale canvas was removed; outside the dark rounded square is alpha transparency, not a light matte.

- `AppIcon.png`: 1024 × 1024 RGBA master.
- `Clipscreen.icns`: native sizes 16, 32, 128, 256 and 512 pt at 1×/2×, up to 1024 px.
- `Info.plist`: `CFBundleIconFile = Clipscreen.icns`.
- Development and release builders copy ICNS before signing; the installer uses it for its volume icon too.

Regenerate the ICNS without building the app:

```sh
node scripts/create-icon.mjs
```

This uses built-in macOS `sips`/`iconutil` only. The menu-bar and tool icons remain the existing Lucide assets.

## Artwork provenance and prompt

Created with the built-in imagegen tool, followed by standard pixel-size conversion and ICNS packaging. Final edit prompt:

> Use case: background-extraction. Edit the supplied Clipscreen app icon. Keep the chosen existing icon exactly: dark graphite rounded-square tile, two overlapping white cards and bright blue clipboard tab, same proportions, materials and colors. Remove ALL the pale white/light-gray exterior background and its pale halo. Crop/frame tightly so the dark rounded-square tile nearly fills the square canvas with only 2 percent transparent clearance per edge. Outside the dark tile must be genuinely transparent, including corners, with clean anti-aliased edges. Preserve the dark tile itself. No white border, no white matte, no added text, no redesign. Output one production macOS icon master PNG with real alpha transparency.
