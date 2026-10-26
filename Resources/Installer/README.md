# DMG installation artwork

`background.tiff` contains 640 × 400 (1×) and 1280 × 800 (2×) representations. Finder overlays two real 112 pt icons at (170, 210) and (470, 210); names remain native Finder text. The icon positions and window settings are saved by `scripts/dmg-layout.applescript`.

The artwork uses macOS system text: 24 pt semibold title, 16 pt instruction, 13 pt follow-up. Background #F5F5F7, heading #242426, supporting text #51515A, 3 pt arrow #767680. The instruction is repeated in the distribution documentation; native Finder copy/paste also works without dragging.

Regenerate artwork without building the application or opening Finder:

```sh
xcrun swift scripts/render-dmg.swift /tmp/clipscreen-installer-art
cp /tmp/clipscreen-installer-art/background.tiff Resources/Installer/background.tiff
```

Add `--preview` to the Swift command to render a composition with the selected app icon and the system Applications icon for inspection. Preview pixels are not shipped. The production app icon is supplied by the `.app`, not baked into this background.
