-- Invoked only by an explicitly requested distribution build.
-- argv is a private, unique mount point, never a disk name shared with another DMG.
on run argv
    set volumeFolder to POSIX file (item 1 of argv) as alias
    tell application "Finder"
        open volumeFolder
        tell container window of volumeFolder
            set current view to icon view
            set toolbar visible to false
            set statusbar visible to false
            set bounds to {200, 160, 840, 588}
            set sidebar width to 0
            set viewOptions to icon view options
            set arrangement of viewOptions to not arranged
            set icon size of viewOptions to 112
            set text size of viewOptions to 14
            set background picture of viewOptions to file ".background:background.tiff" of volumeFolder
        end tell
        set position of item "Clipscreen.app" of volumeFolder to {170, 210}
        set position of item "Applications" of volumeFolder to {470, 210}
        set extension hidden of item "Clipscreen.app" of volumeFolder to true
        set comment of item "Clipscreen.app" of volumeFolder to "To install, copy Clipscreen to Applications."
        update volumeFolder without registering applications
        delay 1
        close container window of volumeFolder
    end tell
end run
