import AppKit

final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override var isMovable: Bool {
        get { true }
        set { }
    }
}

final class HistoryPanel: NSWindowController, NSWindowDelegate, NSTableViewDataSource,
                          NSTableViewDelegate, NSSearchFieldDelegate {
    var onChoose: ((ClipEntry) -> Void)?
    var onDelete: ((ClipEntry) -> Void)?
    var onMenu: ((NSView) -> Void)?
    var onAccess: (() -> Void)?
    var onCaptureScreen: (() -> Void)?
    var onDismiss: (() -> Void)?
    var thumbnail: ((ClipEntry) -> NSImage?)?
    private var userPosition: NSPoint?
    private let search = NSSearchField()
    private let table = NSTableView()
    private let count = NSTextField(labelWithString: "0 / 100")
    private let hint = NSTextField(labelWithString: "")
    private let banner = NSTextField(wrappingLabelWithString: "")
    private let emptyTitle = NSTextField(labelWithString: "Your clipboard, a little longer")
    private let emptyDetail = NSTextField(wrappingLabelWithString: "Copy text or an image with ⌘C.\nYour last 100 items will appear here.")
    private let access = NSButton(title: "Enable Auto-Paste", target: nil, action: nil)
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
                                  styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.title = "Clip — Clipboard history"
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
        let height = min(ClipStyle.panelSize.height, frame.height - 32)
        let width = min(ClipStyle.panelSize.width, frame.width - 32)
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
        count.stringValue = "\(entries.count) / 100"
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

        let title = NSTextField(labelWithString: "Clipboard")
        title.font = ClipStyle.titleFont
        let shortcut = NSTextField(labelWithString: "⌥⌘V")
        shortcut.font = .systemFont(ofSize: 13, weight: .medium)
        shortcut.textColor = .secondaryLabelColor

        let capture = NSButton(image: NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: "Capture Area (⇧⌘4)")!,
                               target: self, action: #selector(triggerCaptureScreen))
        capture.isBordered = false
        capture.bezelStyle = .inline
        capture.toolTip = "Capture screen area to clipboard (⇧⌘4)"
        capture.focusRingType = .none
        capture.refusesFirstResponder = true

        let menu = NSButton(image: NSImage(systemSymbolName: "ellipsis", accessibilityDescription: "Clip menu")!,
                            target: self, action: #selector(openMenu(_:)))
        menu.isBordered = false
        menu.bezelStyle = .inline
        menu.toolTip = "Recording, login and history settings"
        menu.focusRingType = .none
        menu.refusesFirstResponder = true

        search.placeholderString = "Search history"
        search.font = .systemFont(ofSize: 14)
        search.controlSize = .regular
        search.focusRingType = .none
        search.cell?.focusRingType = .none
        search.delegate = self
        search.sendsSearchStringImmediately = true
        search.setAccessibilityLabel("Search clipboard history")
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
        table.addTableColumn(column)
        table.delegate = self
        table.dataSource = self
        table.target = self
        table.action = #selector(clickedRow)
        table.setAccessibilityLabel("Clipboard history")
        scroll.documentView = table

        let divider = NSBox()
        divider.boxType = .separator
        count.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        count.textColor = .secondaryLabelColor
        hint.font = .systemFont(ofSize: 11)
        hint.textColor = .secondaryLabelColor
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

        for view in [title, shortcut, capture, menu, search, banner, scroll, divider, count, hint, access, emptyTitle, emptyDetail] {
            view.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(view)
        }
        bannerHeight = banner.heightAnchor.constraint(equalToConstant: 0)
        footerHeight = divider.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -46)
        NSLayoutConstraint.activate([
            title.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: ClipStyle.inset),
            title.topAnchor.constraint(equalTo: root.topAnchor, constant: 20),
            menu.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -17),
            menu.centerYAnchor.constraint(equalTo: title.centerYAnchor),
            menu.widthAnchor.constraint(equalToConstant: 28), menu.heightAnchor.constraint(equalToConstant: 28),
            capture.trailingAnchor.constraint(equalTo: menu.leadingAnchor, constant: -4),
            capture.centerYAnchor.constraint(equalTo: title.centerYAnchor),
            capture.widthAnchor.constraint(equalToConstant: 28), capture.heightAnchor.constraint(equalToConstant: 28),
            shortcut.trailingAnchor.constraint(equalTo: capture.leadingAnchor, constant: -10),
            shortcut.centerYAnchor.constraint(equalTo: title.centerYAnchor),
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
            count.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -16),
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

    private func updateAccess() {
        let trusted = hasPastePermission()
        hint.stringValue = trusted ? "↑↓ Select    ↩ Paste    esc Close" : "↩ Copy    then ⌘V to paste"
        access.title = readPermissionNeeded ? "Enable History…" : "Enable Auto-Paste…"
        access.isHidden = trusted && !readPermissionNeeded
        footerHeight.constant = access.isHidden ? -46 : -76
    }

    private func refilter() {
        let selected = selectedEntry?.id
        let query = search.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        filtered = query.isEmpty ? entries : entries.filter {
            $0.searchText.localizedStandardContains(query) || $0.displayTitle.localizedStandardContains(query)
                || $0.source.localizedStandardContains(query)
        }
        table.reloadData()
        if !filtered.isEmpty {
            let row = filtered.firstIndex { $0.id == selected } ?? 0
            table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            table.scrollRowToVisible(row)
        }
        emptyTitle.isHidden = !filtered.isEmpty
        emptyDetail.isHidden = !filtered.isEmpty
        emptyTitle.stringValue = isLoading ? "Loading history…" : query.isEmpty ? "Your clipboard, a little longer" : "No matches"
        emptyDetail.stringValue = isLoading ? "Your saved items will appear shortly." : query.isEmpty
            ? "Copy text or an image with ⌘C.\nYour last 100 items will appear here."
            : "Try another word or app name."
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
        cell.configure(entry, image: thumbnail?(entry))
        return cell
    }
    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? { ClipRowView() }
    func windowDidResignKey(_ notification: Notification) { dismiss() }
    func windowDidBecomeKey(_ notification: Notification) { updateAccess() }
    @objc private func clickedRow() {
        guard table.clickedRow >= 0, let entry = selectedEntry else { return }
        onChoose?(entry)
    }
    @objc private func openMenu(_ sender: NSButton) { onMenu?(sender) }
    @objc private func triggerCaptureScreen() { onCaptureScreen?() }
    @objc private func requestAccess() {
        if readPermissionNeeded { onAccess?() } else { PasteController.requestPermission() }
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
    private let preview = NSImageView()
    private let title = NSTextField(wrappingLabelWithString: "")
    private let detail = NSTextField(labelWithString: "")

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
        for view in [preview, textGroup] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            preview.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            preview.centerYAnchor.constraint(equalTo: centerYAnchor),
            preview.widthAnchor.constraint(equalToConstant: ClipStyle.thumbnailSize),
            preview.heightAnchor.constraint(equalToConstant: ClipStyle.thumbnailSize),
            textGroup.leadingAnchor.constraint(equalTo: preview.trailingAnchor, constant: 12),
            textGroup.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            textGroup.centerYAnchor.constraint(equalTo: centerYAnchor),
            title.widthAnchor.constraint(equalTo: textGroup.widthAnchor),
            title.heightAnchor.constraint(lessThanOrEqualToConstant: 34),
            detail.widthAnchor.constraint(equalTo: textGroup.widthAnchor)
        ])
    }
    convenience init() { self.init(frame: .zero) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(_ entry: ClipEntry, image: NSImage?) {
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
            let symbol = entry.kind == .files ? "doc.on.doc" : entry.kind == .image ? "photo" : "text.alignleft"
            preview.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(pointSize: 23, weight: .regular))
            preview.contentTintColor = .secondaryLabelColor
        }
        toolTip = nil // Do not obscure the panel with clipboard contents on hover.
        setAccessibilityElement(true)
        setAccessibilityLabel("\(entry.displayTitle), \(detail.stringValue)")
        setAccessibilityHelp("Press Return to use this item. Press Command-Delete to remove it from history.")
    }
}
