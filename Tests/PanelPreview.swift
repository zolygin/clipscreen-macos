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
        func render(_ name: String, appearance: NSAppearance.Name = .aqua,
                    mode: PanelSurface.MaterialMode = .standard, data: [ClipEntry]? = nil,
                    message: String? = nil, readPermission: Bool = false, pastePermission: Bool = true,
                    loading: Bool = false, query: String? = nil, width: CGFloat = 430) throws {
            let panel = HistoryPanel(materialMode: mode, hasPastePermission: { pastePermission })
            panel.thumbnail = { $0.kind == .image ? image : nil }
            let window = panel.window!
            window.appearance = NSAppearance(named: appearance)
            window.setContentSize(NSSize(width: width, height: 590))
            panel.refresh(data ?? entries, message: message, readPermissionNeeded: readPermission, isLoading: loading)
            let view = window.contentView!
            if let query {
                let search = descendants(view).compactMap { $0 as? NSSearchField }.first!
                search.stringValue = query
                panel.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: search))
            }
            view.layoutSubtreeIfNeeded()
            window.displayIfNeeded()
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
        print("14 native view scenarios passed. No real clipboard data or permissions used.")
    }

    static func descendants(_ view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap(descendants)
    }
}
