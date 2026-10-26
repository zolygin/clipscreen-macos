import AppKit

final class ResizeHandleView: NSView {
    var onResized: ((NSSize) -> Void)?
    private var initialMouseLocation: NSPoint = .zero
    private var initialWindowFrame: NSRect = .zero
    private var resizeScreenFrame: NSRect = .zero
    private var resizeScale: CGFloat = 1
    private var wasMovable = true
    private var isDragging = false
    private var isHovered = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var mouseDownCanMoveWindow: Bool { false }

    private static let resizeCursor: NSCursor = {
        let size = NSSize(width: 17, height: 17)
        let image = NSImage(size: size, flipped: false) { _ in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            context.setLineCap(.round)
            context.setLineJoin(.round)
            let path = NSBezierPath()
            path.move(to: NSPoint(x: 3.5, y: 13.5))
            path.line(to: NSPoint(x: 13.5, y: 3.5))
            path.move(to: NSPoint(x: 3.5, y: 8.5))
            path.line(to: NSPoint(x: 3.5, y: 13.5))
            path.line(to: NSPoint(x: 8.5, y: 13.5))
            path.move(to: NSPoint(x: 8.5, y: 3.5))
            path.line(to: NSPoint(x: 13.5, y: 3.5))
            path.line(to: NSPoint(x: 13.5, y: 8.5))
            NSColor.black.withAlphaComponent(0.6).setStroke()
            path.lineWidth = 3
            path.stroke()
            NSColor.white.setStroke()
            path.lineWidth = 1.5
            path.stroke()
            return true
        }
        return NSCursor(image: image, hotSpot: NSPoint(x: 8.5, y: 8.5))
    }()

    override func resetCursorRects() {
        discardCursorRects()
        addCursorRect(bounds, cursor: Self.resizeCursor)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach { removeTrackingArea($0) }
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInActiveApp], owner: self, userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let color = isDragging ? NSColor.controlAccentColor
            : (isHovered ? NSColor.secondaryLabelColor : NSColor.tertiaryLabelColor.withAlphaComponent(0.6))
        color.setStroke()
        let path = NSBezierPath()
        path.lineWidth = 1
        path.lineCapStyle = .round
        let w = bounds.width
        for length: CGFloat in [4, 8, 12] {
            path.move(to: NSPoint(x: w - 5, y: 5 + length))
            path.line(to: NSPoint(x: w - 5 - length, y: 5))
        }
        path.stroke()
    }

    override func mouseDown(with event: NSEvent) {
        beginResize(at: NSEvent.mouseLocation)
    }

    func beginResize(at point: NSPoint) {
        guard let window else { return }
        isDragging = true
        initialMouseLocation = point
        initialWindowFrame = window.frame
        resizeScreenFrame = (window.screen ?? NSScreen.main)?.visibleFrame ?? window.frame
        resizeScale = window.backingScaleFactor
        wasMovable = window.isMovable
        window.isMovable = false
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        resize(to: NSEvent.mouseLocation)
    }

    func resize(to point: NSPoint) {
        guard isDragging, let window else { return }
        let frame = Self.resizedFrame(initial: initialWindowFrame,
                                     delta: NSPoint(x: point.x - initialMouseLocation.x,
                                                    y: point.y - initialMouseLocation.y),
                                     screen: resizeScreenFrame, scale: resizeScale)
        guard window.frame != frame else { return }
        // Let AppKit coalesce drawing with its normal display cycle. Forcing a
        // display and defaults writes for every pointer event stalls resizing.
        window.setFrame(frame, display: false, animate: false)
    }

    override func mouseUp(with event: NSEvent) {
        endResize()
    }

    func endResize() {
        guard isDragging else { return }
        isDragging = false
        needsDisplay = true
        if let window {
            window.isMovable = wasMovable
            onResized?(window.frame.size)
        }
    }

    static func resizedFrame(initial: NSRect, delta: NSPoint, screen: NSRect, scale: CGFloat) -> NSRect {
        let maxWidth = max(ClipStyle.minPanelSize.width, min(850, screen.maxX - initial.minX - 16))
        let maxHeight = max(ClipStyle.minPanelSize.height, min(1100, initial.maxY - screen.minY - 16))
        let pixelScale = max(1, scale)
        let width = min(maxWidth, max(ClipStyle.minPanelSize.width,
                                     ((initial.width + delta.x) * pixelScale).rounded() / pixelScale))
        let height = min(maxHeight, max(ClipStyle.minPanelSize.height,
                                       ((initial.height - delta.y) * pixelScale).rounded() / pixelScale))
        return NSRect(x: initial.minX, y: initial.maxY - height, width: width, height: height)
    }
}

final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

final class ClipTableView: NSTableView {
    var onRightClickRow: ((Int) -> Void)?
    var onContextMenu: ((Int) -> NSMenu?)?

    override func menu(for event: NSEvent) -> NSMenu? {
        let point = convert(event.locationInWindow, from: nil)
        let row = self.row(at: point)
        guard row >= 0 else { return nil }
        self.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        if let menu = onContextMenu?(row) { return menu }
        onRightClickRow?(row)
        return nil
    }
}

final class HistoryPanel: NSWindowController, NSWindowDelegate, NSTableViewDataSource,
                          NSTableViewDelegate, NSSearchFieldDelegate {
    var onChoose: ((ClipEntry) -> Void)?
    var onDelete: ((ClipEntry) -> Void)?
    var onTogglePin: ((ClipEntry) -> Void)?
    var onAccess: (() -> Void)?
    var onCaptureScreen: (() -> Void)?
    var onEditImage: ((ClipEntry) -> Void)?
    var onDismiss: (() -> Void)?
    var thumbnail: ((ClipEntry) -> NSImage?)?
    private var userPosition: NSPoint?
    private let search = NSSearchField()
    private let table = ClipTableView()
    private let count = NSTextField(labelWithString: "0 / 100")
    private let hint = NSTextField(labelWithString: "")
    private let banner = NSTextField(wrappingLabelWithString: "")
    private let emptyTitle = NSTextField(labelWithString: "Your clipboard, a little longer")
    private let emptyDetail = NSTextField(wrappingLabelWithString: "Copy text or an image with ⌘C.\nYour last 100 items will appear here.")
    private let access = NSButton(title: "Enable Auto-Paste", target: nil, action: nil)
    private let favoritesButton = ClipIconButton(.pin, label: "Show pinned items (⇧⌘P)", target: nil, action: nil)
    private let resizeHandle = ResizeHandleView()
    private var showOnlyPinned = false
    private var entries: [ClipEntry] = []
    private var filtered: [ClipEntry] = []
    private var localMonitor: Any?
    private var outsideMonitor: Any?
    private var bannerHeight: NSLayoutConstraint!
    private var footerHeight: NSLayoutConstraint!
    private var isLoading = false
    private var readPermissionNeeded = false
    private let hasPastePermission: () -> Bool
    var isOpen: Bool { window?.isVisible == true }

    init(materialMode: PanelSurface.MaterialMode = .automatic,
         hasPastePermission: @escaping () -> Bool = { PasteController.isTrusted }) {
        self.hasPastePermission = hasPastePermission
        let panel = FloatingPanel(contentRect: NSRect(origin: .zero, size: ClipStyle.panelSize),
                                  styleMask: [.borderless, .resizable, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.minSize = ClipStyle.minPanelSize
        panel.maxSize = NSSize(width: 850, height: 1100)
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.isMovable = true
        panel.title = "Clipscreen"
        panel.isReleasedWhenClosed = false
        super.init(window: panel)
        panel.delegate = self
        NotificationCenter.default.addObserver(self, selector: #selector(windowMoved),
                                               name: NSWindow.didMoveNotification, object: panel)
        NotificationCenter.default.addObserver(self, selector: #selector(appDidBecomeActive),
                                               name: NSApplication.didBecomeActiveNotification, object: nil)
        buildContent(panel, materialMode: materialMode)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func show() {
        guard let window else { return }
        search.stringValue = ""
        refilter()
        updateAccess()
        positionWindow(window)
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(search)
        installMonitors()
    }

    private func positionWindow(_ window: NSWindow) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        guard let frame = screen?.visibleFrame else { return }
        let savedWidth = UserDefaults.standard.double(forKey: "clip.panelWidth")
        let savedHeight = UserDefaults.standard.double(forKey: "clip.panelHeight")
        let defaultWidth = ClipStyle.panelSize.width
        let defaultHeight = ClipStyle.panelSize.height
        let targetWidth = savedWidth >= ClipStyle.minPanelSize.width ? CGFloat(savedWidth) : defaultWidth
        let targetHeight = savedHeight >= ClipStyle.minPanelSize.height ? CGFloat(savedHeight) : defaultHeight
        let width = min(targetWidth, frame.width - 32)
        let height = min(targetHeight, frame.height - 32)
        if let userPosition {
            let proposed = NSRect(origin: userPosition, size: NSSize(width: width, height: height))
            let isVisible = NSScreen.screens.contains { $0.visibleFrame.intersects(proposed) }
            if isVisible {
                window.setFrame(proposed, display: false)
                return
            }
        }
        window.setFrame(NSRect(x: frame.midX - width / 2,
                               y: frame.maxY - height - max(16, (frame.height - height) * 0.30),
                               width: width, height: height), display: false)
    }

    @objc private func windowMoved() {
        guard isOpen, let window else { return }
        userPosition = window.frame.origin
    }

    @objc private func appDidBecomeActive() {
        updateAccess()
    }

    func dismiss() {
        guard isOpen else { return }
        removeMonitors()
        window?.orderOut(nil)
        onDismiss?()
    }

    func refresh(_ entries: [ClipEntry], message: String?, readPermissionNeeded: Bool = false, isLoading: Bool = false) {
        self.isLoading = isLoading
        self.entries = entries
        self.readPermissionNeeded = readPermissionNeeded
        let pinnedCount = entries.filter { $0.isPinned }.count
        if pinnedCount > 0 {
            count.stringValue = "\(entries.count) / 100 (\(pinnedCount) pinned)"
        } else {
            count.stringValue = "\(entries.count) / 100"
        }
        banner.stringValue = message ?? ""
        banner.isHidden = message == nil
        let width = max(240, (window?.frame.width ?? ClipStyle.panelSize.width) - 40)
        let height = (message ?? "").boundingRect(with: NSSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: banner.font!]).height
        bannerHeight.constant = message == nil ? 0 : max(32, ceil(height) + 6)
        refilter()
        updateAccess()
    }

    private func buildContent(_ panel: NSPanel, materialMode: PanelSurface.MaterialMode) {
        let surface = PanelSurface(mode: materialMode)
        panel.contentView = surface
        let root = surface.body

        let title = NSTextField(labelWithString: "Clipscreen")
        title.font = ClipStyle.titleFont

        favoritesButton.refusesFirstResponder = true
        favoritesButton.target = self
        favoritesButton.action = #selector(toggleFavoritesFilter)
        favoritesButton.contentTintColor = .secondaryLabelColor

        let capture = ClipIconButton(.scan, label: "Capture screen area (⌥⌘4)",
                                     target: self, action: #selector(triggerCaptureScreen))
        capture.refusesFirstResponder = true

        search.placeholderString = "Search history"
        search.font = .systemFont(ofSize: 14)
        search.controlSize = .regular
        search.focusRingType = .none
        search.cell?.focusRingType = .none
        search.delegate = self
        search.sendsSearchStringImmediately = true
        search.setAccessibilityLabel("Search clipboard history")
        if let cell = search.cell as? NSSearchFieldCell {
            cell.searchButtonCell?.image = LucideIcon.search.image(size: 14)
            cell.cancelButtonCell?.image = LucideIcon.x.image(size: 12)
        }
        banner.font = .systemFont(ofSize: 12)
        banner.textColor = .secondaryLabelColor
        banner.maximumNumberOfLines = 0
        banner.isHidden = true

        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        scroll.focusRingType = .none
        table.headerView = nil
        table.backgroundColor = .clear
        table.selectionHighlightStyle = .regular
        table.style = .plain
        table.rowHeight = ClipStyle.rowHeight
        table.intercellSpacing = NSSize(width: 0, height: 4)
        table.usesAlternatingRowBackgroundColors = false
        table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        table.allowsEmptySelection = false
        table.focusRingType = .none
        let column = NSTableColumn(identifier: .init("clip"))
        column.resizingMask = .autoresizingMask
        column.minWidth = 0
        column.maxWidth = .greatestFiniteMagnitude
        table.addTableColumn(column)
        table.delegate = self
        table.dataSource = self
        table.target = self
        table.action = #selector(clickedRow)
        table.onContextMenu = { [weak self] row in
            guard let self, self.filtered.indices.contains(row) else { return nil }
            let entry = self.filtered[row]
            let menu = NSMenu()
            if entry.kind == .image {
                let edit = NSMenuItem(title: "Edit Image…", action: #selector(self.contextEditImage(_:)), keyEquivalent: "")
                edit.target = self
                edit.representedObject = entry
                menu.addItem(edit)
                menu.addItem(.separator())
            }
            let pasteTitle = self.hasPastePermission() ? "Paste" : "Copy to Clipboard"
            let paste = NSMenuItem(title: pasteTitle, action: #selector(self.contextChoose(_:)), keyEquivalent: "")
            paste.target = self
            paste.representedObject = entry
            menu.addItem(paste)
            let pinTitle = entry.isPinned ? "Unpin from Favorites" : "Pin to Favorites"
            let pin = NSMenuItem(title: pinTitle, action: #selector(self.contextTogglePin(_:)), keyEquivalent: "")
            pin.target = self
            pin.representedObject = entry
            menu.addItem(pin)
            menu.addItem(.separator())
            let delete = NSMenuItem(title: "Delete", action: #selector(self.contextDelete(_:)), keyEquivalent: "")
            delete.target = self
            delete.representedObject = entry
            menu.addItem(delete)
            return menu
        }
        table.setAccessibilityLabel("Clipboard history")
        scroll.documentView = table

        let divider = NSBox()
        divider.boxType = .separator
        count.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        count.textColor = .secondaryLabelColor
        hint.font = .systemFont(ofSize: 11)
        hint.textColor = .secondaryLabelColor
        hint.lineBreakMode = .byTruncatingTail
        hint.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        access.font = .systemFont(ofSize: 11)
        access.bezelStyle = .rounded
        access.controlSize = .small
        access.focusRingType = .none
        access.target = self
        access.action = #selector(requestAccess)
        access.setContentCompressionResistancePriority(.required, for: .horizontal)
        emptyTitle.font = .systemFont(ofSize: 15, weight: .medium)
        emptyTitle.alignment = .center
        emptyDetail.font = .systemFont(ofSize: 13)
        emptyDetail.textColor = .secondaryLabelColor
        emptyDetail.alignment = .center

        resizeHandle.onResized = { [weak self] _ in self?.saveWindowGeometry() }

        for view in [title, favoritesButton, capture, search, banner, scroll, divider, count, hint, access, emptyTitle, emptyDetail, resizeHandle] {
            view.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(view)
        }
        bannerHeight = banner.heightAnchor.constraint(equalToConstant: 0)
        footerHeight = divider.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -46)
        NSLayoutConstraint.activate([
            title.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: ClipStyle.inset),
            title.topAnchor.constraint(equalTo: root.topAnchor, constant: 20),
            favoritesButton.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -ClipStyle.inset),
            capture.trailingAnchor.constraint(equalTo: favoritesButton.leadingAnchor, constant: -4),
            capture.centerYAnchor.constraint(equalTo: title.centerYAnchor),
            capture.widthAnchor.constraint(equalToConstant: 28), capture.heightAnchor.constraint(equalToConstant: 28),
            favoritesButton.centerYAnchor.constraint(equalTo: title.centerYAnchor),
            favoritesButton.widthAnchor.constraint(equalToConstant: 28), favoritesButton.heightAnchor.constraint(equalToConstant: 28),
            search.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16),
            search.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -16),
            search.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 16),
            search.heightAnchor.constraint(equalToConstant: 32),
            banner.topAnchor.constraint(equalTo: search.bottomAnchor, constant: 8),
            banner.leadingAnchor.constraint(equalTo: search.leadingAnchor, constant: 4),
            banner.trailingAnchor.constraint(equalTo: search.trailingAnchor, constant: -4), bannerHeight,
            scroll.topAnchor.constraint(equalTo: banner.bottomAnchor, constant: 6),
            scroll.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 8),
            scroll.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -8),
            scroll.bottomAnchor.constraint(equalTo: divider.topAnchor, constant: -8),
            divider.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            divider.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            footerHeight,
            hint.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: ClipStyle.inset),
            hint.topAnchor.constraint(equalTo: divider.bottomAnchor, constant: 15),
            hint.trailingAnchor.constraint(lessThanOrEqualTo: count.leadingAnchor, constant: -10),
            resizeHandle.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -4),
            resizeHandle.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -4),
            resizeHandle.widthAnchor.constraint(equalToConstant: 22),
            resizeHandle.heightAnchor.constraint(equalToConstant: 22),
            count.trailingAnchor.constraint(equalTo: resizeHandle.leadingAnchor, constant: -6),
            count.centerYAnchor.constraint(equalTo: hint.centerYAnchor),
            access.leadingAnchor.constraint(equalTo: hint.leadingAnchor),
            access.topAnchor.constraint(equalTo: hint.bottomAnchor, constant: 8),
            emptyTitle.centerXAnchor.constraint(equalTo: scroll.centerXAnchor),
            emptyTitle.centerYAnchor.constraint(equalTo: scroll.centerYAnchor, constant: -20),
            emptyDetail.topAnchor.constraint(equalTo: emptyTitle.bottomAnchor, constant: 10),
            emptyDetail.centerXAnchor.constraint(equalTo: scroll.centerXAnchor),
            emptyDetail.widthAnchor.constraint(equalTo: scroll.widthAnchor, constant: -40)
        ])
    }

    private func updateHint() {
        guard !filtered.isEmpty, let selected = selectedEntry else {
            hint.stringValue = "esc Close"
            return
        }
        let trusted = hasPastePermission()
        let action = trusted ? "Click / ↩ Paste" : "Click / ↩ Copy (⌘V to paste)"
        if selected.kind == .image {
            hint.stringValue = "\(action)    Right-click Edit    esc Close"
        } else {
            hint.stringValue = "\(action)    esc Close"
        }
    }

    private func updateAccess() {
        let trusted = hasPastePermission()
        updateHint()
        access.title = readPermissionNeeded ? "Enable History…" : "Enable Auto-Paste…"
        access.isHidden = trusted && !readPermissionNeeded
        footerHeight.constant = access.isHidden ? -46 : -76
    }

    @objc private func toggleFavoritesFilter() {
        showOnlyPinned.toggle()
        favoritesButton.setActive(showOnlyPinned)
        favoritesButton.setAccessibilityValue(showOnlyPinned ? "On" : "Off")
        favoritesButton.toolTip = showOnlyPinned ? "Show all history (⇧⌘P)" : "Show pinned items (⇧⌘P)"
        refilter()
    }

    private func refilter() {
        let selected = selectedEntry?.id
        let query = search.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let matches = query.isEmpty ? entries : entries.filter {
            $0.searchText.localizedStandardContains(query) || $0.displayTitle.localizedStandardContains(query)
                || $0.source.localizedStandardContains(query)
        }
        if showOnlyPinned {
            filtered = matches.filter { $0.isPinned }
        } else {
            let unpinned = matches.filter { !$0.isPinned }
            let pinned = matches.filter { $0.isPinned }
            filtered = unpinned + pinned
        }
        table.reloadData()
        if !filtered.isEmpty {
            let row = filtered.firstIndex { $0.id == selected } ?? 0
            table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            table.scrollRowToVisible(row)
        }
        emptyTitle.isHidden = !filtered.isEmpty
        emptyDetail.isHidden = !filtered.isEmpty
        if showOnlyPinned && filtered.isEmpty && !entries.isEmpty {
            emptyTitle.stringValue = "No Favorites Yet"
            emptyDetail.stringValue = "Click the pin icon on any item to save it here."
        } else {
            emptyTitle.stringValue = isLoading ? "Loading history…" : query.isEmpty ? "Your clipboard, a little longer" : "No matches"
            emptyDetail.stringValue = isLoading ? "Your saved items will appear shortly." : query.isEmpty
                ? "Copy text or an image with ⌘C.\nYour last 100 items will appear here."
                : "Try another word or app name."
        }
        updateHint()
    }

    var selectedEntry: ClipEntry? {
        let row = table.selectedRow
        return filtered.indices.contains(row) ? filtered[row] : nil
    }

    func controlTextDidChange(_ obj: Notification) { refilter() }
    func numberOfRows(in tableView: NSTableView) -> Int { filtered.count }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let entry = filtered[row]
        let cell = ClipCell()
        cell.configure(entry, image: thumbnail?(entry), onTogglePin: { [weak self] in
            self?.onTogglePin?(entry)
        }, onEditImage: { [weak self] in
            self?.onEditImage?(entry)
        })
        return cell
    }
    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        let rowView = ClipRowView()
        if row < filtered.count {
            let entry = filtered[row]
            let isFirstPinned = entry.isPinned && row > 0 && !filtered[row - 1].isPinned
            rowView.isFirstPinned = isFirstPinned
        }
        return rowView
    }
    func tableViewSelectionDidChange(_ notification: Notification) { updateHint() }
    func windowDidResignKey(_ notification: Notification) { dismiss() }
    func windowDidBecomeKey(_ notification: Notification) { updateAccess() }
    func windowDidEndLiveResize(_ notification: Notification) { saveWindowGeometry() }

    private func saveWindowGeometry() {
        guard let window else { return }
        UserDefaults.standard.set(Double(window.frame.width), forKey: "clip.panelWidth")
        UserDefaults.standard.set(Double(window.frame.height), forKey: "clip.panelHeight")
        userPosition = window.frame.origin
    }
    @objc private func clickedRow() {
        guard table.clickedRow >= 0, let entry = selectedEntry else { return }
        onChoose?(entry)
    }
    @objc private func triggerCaptureScreen() { onCaptureScreen?() }
    @objc private func requestAccess() {
        if readPermissionNeeded { onAccess?() } else { PasteController.requestPermission() }
    }

    @objc private func contextChoose(_ sender: NSMenuItem) {
        guard let entry = sender.representedObject as? ClipEntry else { return }
        onChoose?(entry)
    }
    @objc private func contextEditImage(_ sender: NSMenuItem) {
        guard let entry = sender.representedObject as? ClipEntry else { return }
        onEditImage?(entry)
    }
    @objc private func contextTogglePin(_ sender: NSMenuItem) {
        guard let entry = sender.representedObject as? ClipEntry else { return }
        onTogglePin?(entry)
    }
    @objc private func contextDelete(_ sender: NSMenuItem) {
        guard let entry = sender.representedObject as? ClipEntry else { return }
        onDelete?(entry)
    }

    private func installMonitors() {
        removeMonitors()
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard let self, self.isOpen, event.window === self.window else { return event }
            if let editor = self.window?.firstResponder as? NSTextView, editor.hasMarkedText() {
                return event // Let input methods finish composition before handling navigation/Return.
            }
            if event.keyCode == 48 { // Tab key: navigate list instead of drawing focus ring
                self.handleTab(shift: event.modifierFlags.contains(.shift))
                return nil
            }
            if event.keyCode != 53, self.window?.firstResponder is NSButton { return event }
            return self.handleHistoryKey(event.keyCode, modifiers: event.modifierFlags) ? nil : event
        }
        outsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.dismiss()
        }
    }

    private func handleTab(shift: Bool) {
        guard !filtered.isEmpty else { return }
        let step = shift ? -1 : 1
        let row = min(max(table.selectedRow + step, 0), filtered.count - 1)
        table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        table.scrollRowToVisible(row)
    }

    /// Kept separate from event monitoring so keyboard behavior can be tested
    /// without sending keys to the user's desktop or touching their clipboard.
    @discardableResult
    func handleHistoryKey(_ keyCode: UInt16, modifiers: NSEvent.ModifierFlags = []) -> Bool {
        switch keyCode {
        case 35 where modifiers.contains(.command): // P
            if modifiers.contains(.shift) { toggleFavoritesFilter() }
            else if let entry = selectedEntry { onTogglePin?(entry) }
            return true
        case 53: dismiss(); return true
        case 36, 76:
            if let entry = selectedEntry { onChoose?(entry) }
            return true
        case 125, 126:
            guard !filtered.isEmpty else { return true }
            let step = keyCode == 125 ? 1 : -1
            let row = min(max(table.selectedRow + step, 0), filtered.count - 1)
            table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            table.scrollRowToVisible(row)
            return true
        case 51 where modifiers.contains(.command):
            if let entry = selectedEntry { onDelete?(entry) }
            return true
        default: return false
        }
    }

    private func removeMonitors() {
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        if let outsideMonitor { NSEvent.removeMonitor(outsideMonitor) }
        localMonitor = nil
        outsideMonitor = nil
    }
}

final class ClipCell: NSTableCellView {
    var onTogglePin: (() -> Void)?
    var onEditImage: (() -> Void)?
    private let preview = NSImageView()
    private let title = NSTextField(wrappingLabelWithString: "")
    private let detail = NSTextField(labelWithString: "")
    private let pinButton = ClipIconButton(.pin, label: "Pin to favorites (⌘P)", target: nil, action: nil)
    private let editButton = ClipIconButton(.pencil, label: "Edit image", target: nil, action: nil)
    private var textTrailing: NSLayoutConstraint!

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = true
        preview.imageScaling = .scaleProportionallyUpOrDown
        preview.wantsLayer = true
        preview.layer?.cornerRadius = 6
        preview.layer?.masksToBounds = true
        preview.setAccessibilityElement(false)
        title.font = ClipStyle.bodyFont
        title.maximumNumberOfLines = 2
        title.lineBreakMode = .byWordWrapping
        title.cell?.wraps = true
        title.cell?.isScrollable = false
        title.cell?.truncatesLastVisibleLine = true
        title.wantsLayer = true
        title.layer?.masksToBounds = true
        title.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        detail.font = ClipStyle.captionFont
        detail.textColor = .secondaryLabelColor
        detail.lineBreakMode = .byTruncatingTail
        let textGroup = NSStackView(views: [title, detail])
        textGroup.orientation = .vertical
        textGroup.alignment = .leading
        textGroup.spacing = 5

        pinButton.target = self
        pinButton.action = #selector(pinClicked)
        pinButton.refusesFirstResponder = true

        editButton.target = self
        editButton.action = #selector(editClicked)
        editButton.refusesFirstResponder = true
        editButton.contentTintColor = .secondaryLabelColor
        editButton.toolTip = "Edit image in Annotation Editor"

        for view in [preview, textGroup, editButton, pinButton] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        textTrailing = textGroup.trailingAnchor.constraint(equalTo: pinButton.leadingAnchor, constant: -8)
        NSLayoutConstraint.activate([
            preview.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            preview.centerYAnchor.constraint(equalTo: centerYAnchor),
            preview.widthAnchor.constraint(equalToConstant: ClipStyle.thumbnailSize),
            preview.heightAnchor.constraint(equalToConstant: ClipStyle.thumbnailSize),
            pinButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            pinButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            editButton.trailingAnchor.constraint(equalTo: pinButton.leadingAnchor, constant: -4),
            editButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            pinButton.widthAnchor.constraint(equalToConstant: 28),
            pinButton.heightAnchor.constraint(equalToConstant: 28),
            editButton.widthAnchor.constraint(equalToConstant: 28),
            editButton.heightAnchor.constraint(equalToConstant: 28),
            textGroup.leadingAnchor.constraint(equalTo: preview.trailingAnchor, constant: 12),
            textTrailing,
            textGroup.centerYAnchor.constraint(equalTo: centerYAnchor),
            title.widthAnchor.constraint(equalTo: textGroup.widthAnchor),
            title.heightAnchor.constraint(lessThanOrEqualToConstant: 34),
            detail.widthAnchor.constraint(equalTo: textGroup.widthAnchor)
        ])
    }
    convenience init() { self.init(frame: .zero) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    @objc private func pinClicked() { onTogglePin?() }
    @objc private func editClicked() { onEditImage?() }

    func configure(_ entry: ClipEntry, image: NSImage?, onTogglePin: (() -> Void)? = nil, onEditImage: (() -> Void)? = nil) {
        self.onTogglePin = onTogglePin
        self.onEditImage = onEditImage
        editButton.isHidden = entry.kind != .image
        textTrailing.constant = entry.kind == .image ? -40 : -8
        pinButton.setActive(entry.isPinned)
        let pinLabel = entry.isPinned ? "Unpin from favorites (⌘P)" : "Pin to favorites (⌘P)"
        pinButton.toolTip = pinLabel
        pinButton.setAccessibilityLabel(pinLabel)
        pinButton.setAccessibilityValue(entry.isPinned ? "Pinned" : "Not pinned")
        title.stringValue = entry.displayTitle
        let time = RelativeDateTimeFormatter()
        time.locale = Locale(identifier: "en_US")
        time.unitsStyle = .short
        let relativeTime = abs(entry.copiedAt.timeIntervalSinceNow) < 60 ? "Just now"
            : time.localizedString(for: entry.copiedAt, relativeTo: Date())
        detail.stringValue = [entry.kind == .image ? entry.displayImageDetail : nil, entry.source.isEmpty ? nil : entry.source,
                              relativeTime]
            .compactMap { $0 }.joined(separator: " · ")
        if let image {
            preview.imageScaling = .scaleProportionallyUpOrDown
            preview.image = image
            preview.contentTintColor = nil
        } else {
            preview.imageScaling = .scaleNone
            let icon: LucideIcon = entry.kind == .files ? .files : entry.kind == .image ? .image : .type
            preview.image = icon.image(size: 24)
            preview.contentTintColor = .secondaryLabelColor
        }
        toolTip = nil // Do not obscure the panel with clipboard contents on hover.
        setAccessibilityElement(false) // Keep the two action buttons reachable by VoiceOver.
        setAccessibilityLabel("\(entry.displayTitle), \(detail.stringValue)")
        setAccessibilityHelp("Press Return to use this item. Press Command-Delete to remove it from history.")
    }
}
