import AppKit

/// An isolated view-rendering harness. No app delegate, global shortcut,
/// clipboard monitor, accessibility request, or real clipboard access.
@main
struct PanelPreview {
    static func main() throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let image = NSImage(size: NSSize(width: 240, height: 160), flipped: false) { rect in
            NSColor(calibratedRed: 0.86, green: 0.88, blue: 0.80, alpha: 1).setFill()
            rect.fill()
            NSColor(calibratedRed: 0.35, green: 0.47, blue: 0.34, alpha: 1).setFill()
            NSBezierPath(ovalIn: NSRect(x: 30, y: 18, width: 150, height: 150)).fill()
            NSColor(calibratedRed: 0.94, green: 0.75, blue: 0.39, alpha: 1).setFill()
            NSBezierPath(ovalIn: NSRect(x: 128, y: 70, width: 70, height: 70)).fill()
            return true
        }
        let samples: [(ClipKind, String, String, String)] = [
            (.text, "Let's meet on Thursday at 11:30. I'll send the call link a little later.", "73 characters", "Notes"),
            (.image, "Изображение", "1440 × 960", "Preview"), // A record saved by v0.1.
            (.text, "const currentOption = data[Math.round(listOffsetRef.current / itemHeight)];", "75 characters", "Xcode"),
            (.text, "https://developer.apple.com/documentation/appkit/nsglasseffectview", "65 characters", "Safari"),
            (.files, "Cover.png, Presentation.pdf", "Files: 2", "Finder"),
            (.text, "Скопированный текст остаётся на языке оригинала. 日本語もそのまま。", "56 characters", "Notes")
        ]
        let entries = samples.enumerated().map { offset, value in
            ClipEntry(id: UUID(), copiedAt: Date().addingTimeInterval(Double(-offset * 120)), kind: value.0,
                      title: value.1, detail: value.2, searchText: value.1, source: value.3,
                      fingerprint: "fixture-\(offset)", byteCount: 10)
        }
        var pinnedEntries = entries
        pinnedEntries[0].isPinned = true
        pinnedEntries[1].isPinned = true
        let keyboard = HistoryPanel(materialMode: .standard, hasPastePermission: { true })
        keyboard.refresh(entries, message: nil)
        precondition(keyboard.selectedEntry?.id == entries[0].id)
        keyboard.handleHistoryKey(125)
        precondition(keyboard.selectedEntry?.id == entries[1].id)
        var chosen: UUID?
        keyboard.onChoose = { chosen = $0.id }
        keyboard.handleHistoryKey(36)
        precondition(chosen == entries[1].id, "Return must activate the selected item")
        var removed: UUID?
        keyboard.onDelete = { removed = $0.id }
        keyboard.handleHistoryKey(51, modifiers: .command)
        precondition(removed == entries[1].id, "Command-Delete must target the selection")
        keyboard.refresh(entries, message: "A recoverable error")
        precondition(keyboard.selectedEntry?.id == entries[1].id, "Refresh must preserve selection")
        keyboard.handleHistoryKey(126)
        keyboard.handleHistoryKey(126)
        precondition(keyboard.selectedEntry?.id == entries[0].id, "Up must stay in bounds")
        keyboard.refresh([], message: nil)
        chosen = nil
        keyboard.handleHistoryKey(125)
        keyboard.handleHistoryKey(36)
        precondition(chosen == nil, "Empty history must not activate an item")
        print("PASS keyboard selection, Return, removal, refresh, bounds and empty state")

        keyboard.refresh(pinnedEntries, message: nil)
        var pinTarget: UUID?
        keyboard.onTogglePin = { pinTarget = $0.id }
        keyboard.handleHistoryKey(35, modifiers: .command)
        precondition(pinTarget == keyboard.selectedEntry?.id, "Command-P must pin the selected item")
        keyboard.handleHistoryKey(35, modifiers: [.command, .shift])
        precondition(keyboard.selectedEntry?.isPinned == true, "Pinned filter must select a pinned item")
        keyboard.handleHistoryKey(35, modifiers: [.command, .shift])
        print("PASS pin shortcut and pinned filter")

        // Exercise the same drag path as mouse events, without moving the
        // system pointer, activating a window, or saving real preferences.
        let resizeWindow = keyboard.window!
        resizeWindow.setFrame(NSRect(x: 100, y: 200, width: 430, height: 590), display: false)
        let handle = descendants(resizeWindow.contentView!).compactMap { $0 as? ResizeHandleView }.first!
        var resizeCommits = 0
        handle.onResized = { _ in resizeCommits += 1 }
        handle.beginResize(at: NSPoint(x: 530, y: 200))
        precondition(!resizeWindow.isMovable && !handle.mouseDownCanMoveWindow)
        let initial = resizeWindow.frame
        for offset in 1...120 {
            handle.resize(to: NSPoint(x: 530 + CGFloat(offset), y: 200 - CGFloat(offset) / 2))
            resizeWindow.contentView!.layoutSubtreeIfNeeded()
            precondition(abs(resizeWindow.frame.minX - initial.minX) < 0.01)
            precondition(abs(resizeWindow.frame.maxY - initial.maxY) < 0.01, "Resize must preserve the top edge")
            precondition(resizeCommits == 0, "Do not persist geometry during a drag")
            verifyActionAlignment(resizeWindow.contentView!)
        }
        handle.endResize()
        precondition(resizeWindow.isMovable && resizeCommits == 1, "Commit once and restore window movement")
        handle.endResize()
        precondition(resizeCommits == 1)
        let testScreen = NSRect(x: 0, y: 0, width: 1440, height: 1000)
        let minimum = ResizeHandleView.resizedFrame(initial: initial, delta: NSPoint(x: -5000, y: 5000), screen: testScreen, scale: 2)
        precondition(minimum.size == ClipStyle.minPanelSize && minimum.maxY == initial.maxY)
        let maximum = ResizeHandleView.resizedFrame(initial: initial, delta: NSPoint(x: 5000, y: -5000), screen: testScreen, scale: 2)
        precondition(maximum.width == 850 && maximum.minY >= testScreen.minY + 16)
        let fractional = ResizeHandleView.resizedFrame(initial: initial, delta: NSPoint(x: 0.36, y: -0.36), screen: testScreen, scale: 2)
        precondition(fractional.width * 2 == (fractional.width * 2).rounded())
        print("PASS 120 resize updates: fixed top-left, aligned actions, pixel rounding, size limits and one commit")

        for icon in LucideIcon.allCases {
            let vector = icon.image()
            precondition(vector.isTemplate && vector.size == NSSize(width: 16, height: 16))
            precondition(vector.tiffRepresentation != nil, "Original Lucide SVG must render: \(icon)")
        }
        precondition(StatusIcon.clipboard().isTemplate && StatusIcon.clipboard(paused: true).isTemplate)
        print("PASS bundled Lucide assets and menu bar variants")

        var renderCount = 0
        func render(_ name: String, appearance: NSAppearance.Name = .aqua,
                    mode: PanelSurface.MaterialMode = .standard, data: [ClipEntry]? = nil,
                    message: String? = nil, readPermission: Bool = false, pastePermission: Bool = true,
                    loading: Bool = false, query: String? = nil, width: CGFloat = 430,
                    pinnedFilter: Bool = false, missingThumbnail: Bool = false,
                    hoverPin: Bool = false, pressPin: Bool = false, disablePin: Bool = false) throws {
            let panel = HistoryPanel(materialMode: mode, hasPastePermission: { pastePermission })
            panel.thumbnail = { $0.kind == .image && !missingThumbnail ? image : nil }
            let window = panel.window!
            window.appearance = NSAppearance(named: appearance)
            window.setContentSize(NSSize(width: width, height: 590))
            panel.refresh(data ?? entries, message: message, readPermissionNeeded: readPermission, isLoading: loading)
            if pinnedFilter { panel.handleHistoryKey(35, modifiers: [.command, .shift]) }
            let view = window.contentView!
            if let query {
                let search = descendants(view).compactMap { $0 as? NSSearchField }.first!
                search.stringValue = query
                panel.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: search))
            }
            view.layoutSubtreeIfNeeded()
            if hoverPin || pressPin || disablePin {
                let table = descendants(view).compactMap { $0 as? NSTableView }.first!
                let cell = table.view(atColumn: 0, row: 0, makeIfNecessary: true) as! ClipCell
                let pin = cell.subviews.compactMap { $0 as? ClipIconButton }
                    .first { $0.action == NSSelectorFromString("pinClicked") }!
                let frame = pin.frame
                if hoverPin {
                    let event = NSEvent.enterExitEvent(with: .mouseEntered, location: .zero, modifierFlags: [],
                                                       timestamp: 0, windowNumber: window.windowNumber, context: nil,
                                                       eventNumber: 0, trackingNumber: 0, userData: nil)!
                    pin.mouseEntered(with: event)
                }
                if pressPin { pin.highlight(true) }
                pin.isEnabled = !disablePin
                precondition(pin.frame == frame && pin.bounds.size == NSSize(width: 28, height: 28),
                             "Pin hit target must not change across interaction states")
                precondition(!pin.isBordered && pin.image?.size == NSSize(width: 16, height: 16),
                             "One custom surface, with no native bezel stacked over it")
            }
            window.displayIfNeeded()
            verifyActionAlignment(view)
            let surface = view as! PanelSurface
            precondition(abs(surface.body.bounds.width - width) < 1 && abs(surface.body.bounds.height - 590) < 1,
                         "Content does not fill the panel in \(name): \(surface.body.bounds)")
            let table = descendants(view).compactMap { $0 as? NSTableView }.first!
            let strings = descendants(view).compactMap { ($0 as? NSTextField)?.stringValue }
            if query == "image" { precondition(table.numberOfRows == 1, "Legacy images must be searchable in English") }
            if query == "unmatched-query" { precondition(table.numberOfRows == 0 && strings.contains("No matches")) }
            if loading { precondition(strings.contains("Loading history…")) }
            precondition(descendants(view).compactMap { $0 as? ClipCell }.allSatisfy { $0.toolTip == nil })
            guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { fatalError("No bitmap") }
            view.cacheDisplay(in: view.bounds, to: bitmap)
            for (x, y) in [(0, 0), (bitmap.pixelsWide - 1, 0), (0, bitmap.pixelsHigh - 1),
                           (bitmap.pixelsWide - 1, bitmap.pixelsHigh - 1)] {
                precondition(bitmap.colorAt(x: x, y: y)!.alphaComponent < 0.01, "Opaque corner in \(name)")
            }
            try bitmap.representation(using: .png, properties: [:])!.write(to: directory.appendingPathComponent(name + ".png"))
            print("PASS \(name): transparent corners, rendered native view")
            renderCount += 1
        }
        try render("panel-light")
        try render("panel-dark", appearance: .darkAqua)
        try render("panel-glass-light", mode: .automatic)
        try render("panel-glass-dark", appearance: .darkAqua, mode: .automatic)
        try render("panel-opaque-light", mode: .opaque)
        try render("panel-opaque-dark", appearance: .darkAqua, mode: .opaque)
        try render("panel-empty", data: [])
        try render("panel-permission", data: [], message: "Allow clipboard access to start saving your history.",
                   readPermission: true, pastePermission: false)
        try render("panel-manual-paste", pastePermission: false)
        try render("panel-error", message: "History storage is unavailable. Check disk space and folder permissions. (Error 513)")
        try render("panel-loading", data: [], loading: true)
        try render("panel-filtered", query: "image")
        try render("panel-no-matches", query: "unmatched-query")
        try render("panel-narrow", width: 320)
        try render("panel-minimum", width: 360)
        try render("panel-wide", width: 600)
        try render("panel-maximum", width: 850)
        try render("panel-pinned-light", data: pinnedEntries)
        try render("panel-pinned-dark", appearance: .darkAqua, data: pinnedEntries)
        try render("panel-favorites", data: pinnedEntries, pinnedFilter: true)
        try render("panel-no-favorites", pinnedFilter: true)
        try render("panel-missing-thumbnail", missingThumbnail: true)
        try render("panel-error-narrow", message: "History storage is unavailable. Check disk space and folder permissions. (Error 513)", width: 360)
        for appearance: NSAppearance.Name in [.aqua, .darkAqua] {
            let theme = appearance == .aqua ? "light" : "dark"
            try render("panel-pin-hover-\(theme)", appearance: appearance, hoverPin: true)
            try render("panel-pin-active-hover-\(theme)", appearance: appearance,
                       data: pinnedEntries, pinnedFilter: true, hoverPin: true)
            try render("panel-pin-pressed-\(theme)", appearance: appearance,
                       data: pinnedEntries, pinnedFilter: true, hoverPin: true, pressPin: true)
            try render("panel-pin-disabled-\(theme)", appearance: appearance, hoverPin: true, disablePin: true)
        }
        for appearance: NSAppearance.Name in [.aqua, .darkAqua] {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 780, height: 44),
                                  styleMask: [.borderless], backing: .buffered, defer: false)
            let toolbar = ScreenshotEditorToolbar()
            toolbar.frame = NSRect(origin: .zero, size: window.contentRect(forFrameRect: window.frame).size)
            toolbar.autoresizingMask = [.width, .height]
            window.contentView = toolbar
            window.appearance = NSAppearance(named: appearance)
            toolbar.updateToolSelection(activeTool: .filledRect)
            toolbar.updateColorSelection(activeColor: .systemRed)
            toolbar.layoutSubtreeIfNeeded()
            let bitmap = toolbar.bitmapImageRepForCachingDisplay(in: toolbar.bounds)!
            toolbar.cacheDisplay(in: toolbar.bounds, to: bitmap)
            let name = appearance == .aqua ? "editor-toolbar-light" : "editor-toolbar-dark"
            try bitmap.representation(using: .png, properties: [:])!.write(to: directory.appendingPathComponent(name + ".png"))
            renderCount += 1
            print("PASS \(name): original Lucide tool, undo and redo icons")
        }
        renderCount += try AnnotationChecks.run(directory: directory)
        print("\(renderCount) native view scenarios passed. No real clipboard data or permissions used.")
    }

    static func descendants(_ view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap(descendants)
    }

    static func verifyActionAlignment(_ view: NSView) {
        let surface = view as! PanelSurface
        precondition(surface.body.subviews.compactMap { $0 as? NSTextField }.contains { $0.stringValue == "Clipscreen" },
                     "The panel heading must use the single-word product name")
        let headerButtons = surface.body.subviews.compactMap { $0 as? ClipIconButton }
        precondition(headerButtons.count == 2, "Header must only contain capture and pinned filter")
        precondition(!surface.body.subviews.compactMap({ $0 as? NSTextField }).contains { $0.stringValue == "⌥⌘V" },
                     "Do not repeat the invocation shortcut inside the open history panel")
        let favorites = headerButtons.first { $0.action == NSSelectorFromString("toggleFavoritesFilter") }!
        precondition(abs(favorites.frame.maxX - (surface.body.bounds.width - 16)) < 1,
                     "Header Pin must be at the far right")
        precondition(headerButtons.allSatisfy { $0 === favorites || $0.frame.maxX < favorites.frame.minX })
        for cell in descendants(view).compactMap({ $0 as? ClipCell }) {
            let pin = cell.subviews.compactMap { $0 as? ClipIconButton }
                .first { $0.action == NSSelectorFromString("pinClicked") }!
            precondition(abs(pin.frame.maxX - (cell.bounds.width - 16)) < 1,
                         "Row Pin must be at the far right, including during resize")
            let edit = cell.subviews.compactMap { $0 as? ClipIconButton }
                .first { $0.action == NSSelectorFromString("editClicked") }!
            let actionStart = edit.isHidden ? pin.frame.minX : edit.frame.minX
            for field in descendants(cell).compactMap({ $0 as? NSTextField }) {
                let rect = cell.convert(field.bounds, from: field)
                // NSTextField includes a 2 pt alignment inset outside its stack.
                precondition(rect.maxX <= actionStart - 4, "Text must not overlap row actions")
            }
        }
    }
}
