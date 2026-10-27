import AppKit
import ServiceManagement
import UniformTypeIdentifiers

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var model: HistoryModel!
    private let monitor = ClipboardMonitor()
    private let hotKey = GlobalHotKey()
    private let paste = PasteController()
    private let panel = HistoryPanel()
    private var target: NSRunningApplication?
    private var lastExternalApp: NSRunningApplication?
    private var workspaceObserver: NSObjectProtocol?
    private var monitorMessage: String?
    private var hotKeyMessage: String?
    private var actionMessage: String?
    private var isChoosing = false
    private var choiceGeneration = 0
    // Every open editor needs an owner until its window closes. A single slot
    // released earlier controllers while their windows could remain on screen.
    private var editorControllers: [ScreenshotEditorWindowController] = []
    private var editorSerial = 0
    private let editorPresenter = ScreenshotEditorPresenter()
    private var isCapturingScreen = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let bundleID = Bundle.main.bundleIdentifier,
           let existing = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .first(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }) {
            if existing.bundleURL?.standardizedFileURL != Bundle.main.bundleURL.standardizedFileURL {
                showAlert(title: "Another copy of Clipscreen is running",
                          message: "Quit the running copy through its menu bar menu, then open this build again.\n\nRunning copy:\n\(existing.bundleURL?.path ?? "Unknown location")\n\nThis copy:\n\(Bundle.main.bundleURL.path)")
            } else {
                existing.activate(options: [.activateAllWindows])
            }
            NSApp.terminate(nil)
            return
        }
        NSApp.setActivationPolicy(.accessory)
        installApplicationMenu()
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Clip", isDirectory: true) // Keep the original history location across the rename.
        model = HistoryModel(directory: directory)
        model.onChange = { [weak self] in self?.refresh() }
        monitor.onCapture = { [weak self] in self?.model.add($0) }
        monitor.onStatus = { [weak self] message in
            self?.monitorMessage = message
            self?.refresh()
        }
        panel.thumbnail = { [weak self] in self?.model.thumbnail($0) }
        panel.onChoose = { [weak self] in self?.choose($0) }
        panel.onDelete = { [weak self] in self?.model.remove($0.id) }
        panel.onTogglePin = { [weak self] in self?.model.togglePin($0.id) }
        panel.onCaptureScreen = { [weak self] in self?.captureScreen() }
        panel.onEditImage = { [weak self] in self?.editImageEntry($0) }
        panel.onAccess = { [weak self] in self?.enableReading() }
        panel.onDismiss = { [weak self] in
            self?.choiceGeneration += 1
            self?.isChoosing = false
        }
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = StatusIcon.clipboard()
            button.image?.isTemplate = true
            button.toolTip = "Clipscreen · Clipboard history · ⌥⌘V"
            button.target = self
            button.action = #selector(statusClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        lastExternalApp = NSWorkspace.shared.frontmostApplication
        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
            self?.lastExternalApp = app
        }
        hotKey.onPress = { [weak self] in self?.togglePanel() }
        hotKey.onCapturePress = { [weak self] in self?.captureScreen() }
        let result = hotKey.register()
        if result != noErr {
            hotKeyMessage = "⌥⌘V is unavailable (code \(result)). Free this shortcut in the other app, then restart Clipscreen."
        }
        monitor.start()
        monitor.poll()
        if !UserDefaults.standard.bool(forKey: "hasLaunched") || hotKeyMessage != nil {
            UserDefaults.standard.set(true, forKey: "hasLaunched")
            showPanel()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        editorPresenter.cancel()
        monitor.stop()
        paste.cancel()
        model?.flush()
        if let workspaceObserver { NSWorkspace.shared.notificationCenter.removeObserver(workspaceObserver) }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    private func refresh() {
        let paused = monitor.paused ? "History is paused. Choose Resume Recording in the menu to continue." : nil
        panel.refresh(model?.entries ?? [], message: model?.error ?? actionMessage ?? hotKeyMessage ?? paused ?? monitorMessage,
                      readPermissionNeeded: needsReadPermission, isLoading: model?.isLoading ?? true)
        statusItem?.button?.image = StatusIcon.clipboard(paused: monitor.paused)
        statusItem?.button?.image?.isTemplate = true
    }

    private var needsReadPermission: Bool {
        if #available(macOS 15.4, *) { return NSPasteboard.general.accessBehavior != .alwaysAllow }
        return false
    }

    private func showPanel() {
        paste.cancel()
        let front = NSWorkspace.shared.frontmostApplication
        target = front?.processIdentifier == ProcessInfo.processInfo.processIdentifier ? lastExternalApp : front
        actionMessage = nil
        refresh()
        panel.show()
    }

    @objc private func togglePanel() {
        if panel.isOpen { panel.dismiss() } else { showPanel() }
    }

    @objc private func statusClicked(_ sender: NSStatusBarButton) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            panel.dismiss()
            makeMenu().popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.minY), in: sender)
        } else { togglePanel() }
    }

    private func choose(_ entry: ClipEntry) {
        guard !isChoosing else { return }
        isChoosing = true
        choiceGeneration += 1
        let generation = choiceGeneration
        let destination = target
        model.load(entry) { [weak self] result in
            guard let self, self.panel.isOpen, generation == self.choiceGeneration else { return }
            self.isChoosing = false
            switch result {
            case .success(let payload):
                guard PasteboardCodec.restore(payload, to: .general) else {
                    self.actionMessage = "Could not copy this item. Please try again."
                    self.refresh()
                    return
                }
                self.monitor.ignoreCurrentChange()
                self.panel.dismiss()
                self.paste.paste(to: destination) { [weak self] message in
                    guard let self, let message else { return }
                    self.actionMessage = message
                    self.refresh()
                    self.panel.show()
                }
            case .failure:
                self.actionMessage = "Could not read this item. Press ⌘⌫ to remove it from history."
                self.refresh()
            }
        }
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "Development"
        let build = info["CFBundleVersion"] as? String ?? "?"
        let identity = NSMenuItem(title: "Clipscreen \(version) (\(build))", action: nil, keyEquivalent: "")
        identity.toolTip = [info["ClipscreenBuildDate"] as? String, info["ClipscreenSourceRevision"] as? String,
                            Bundle.main.bundleURL.path].compactMap { $0 }.joined(separator: "\n")
        menu.addItem(identity)
        menu.addItem(.separator())
        func item(_ title: String, _ action: Selector) -> NSMenuItem {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            menu.addItem(item)
            return item
        }
        let history = item("Open History", #selector(openHistory))
        history.keyEquivalent = "v"
        history.keyEquivalentModifierMask = [.command, .option]
        let capture = item("Capture Area to Clipboard", #selector(captureScreen))
        capture.keyEquivalent = "4"
        capture.keyEquivalentModifierMask = [.command, .option]
        menu.addItem(.separator())
        _ = item(monitor.paused ? "Resume Recording" : "Pause Recording", #selector(togglePause))
        let login = item("Launch at Login", #selector(toggleLogin))
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        _ = item("Allow Automatic Paste…", #selector(enablePasting))
        if needsReadPermission { _ = item("Allow Clipboard Access…", #selector(enableReading)) }
        menu.addItem(.separator())
        _ = item("Clear History…", #selector(clearHistory))
        menu.addItem(.separator())
        _ = item("Quit Clipscreen", #selector(quit))
        return menu
    }

    @objc private func openHistory() { showPanel() }
    @objc private func captureScreen() {
        guard !isCapturingScreen else { return }
        isCapturingScreen = true
        editorPresenter.cancel()
        panel.dismiss()
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("clip_capture_\(UUID().uuidString).png")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            task.arguments = ["-i", tempURL.path]
            task.terminationHandler = { proc in
                DispatchQueue.main.async {
                    defer { try? FileManager.default.removeItem(at: tempURL) }
                    self?.isCapturingScreen = false
                    guard proc.terminationStatus == 0,
                          let image = NSImage(contentsOf: tempURL) else {
                        return
                    }
                    self?.openEditor(with: image)
                }
            }
            do {
                try task.run()
            } catch {
                self?.isCapturingScreen = false
                try? FileManager.default.removeItem(at: tempURL)
                NSLog("Failed to run screencapture: \(error)")
            }
        }
    }

    private func openEditor(with image: NSImage) {
        let editor = ScreenshotEditorWindowController(image: image)
        editorSerial += 1
        editor.window?.title = "Clipscreen — Screenshot \(editorSerial)"
        editorControllers.append(editor)
        editor.onComplete = { [weak self, weak editor] annotatedImage in
            guard let self else { return }
            if let editor { self.editorControllers.removeAll { $0 === editor } }
            if let tiff = annotatedImage.tiffRepresentation,
               let rep = NSBitmapImageRep(data: tiff),
               let png = rep.representation(using: .png, properties: [:]) {
                let board = NSPasteboard.general
                board.clearContents()
                board.setData(png, forType: .png)
                board.setData(tiff, forType: .tiff)
                self.monitor.poll(userInitiated: true)
            }
        }
        editor.onCancel = { [weak self, weak editor] in
            if let editor { self?.editorControllers.removeAll { $0 === editor } }
        }
        if let window = editor.window { editorPresenter.present(window) }
    }

    private func editImageEntry(_ entry: ClipEntry) {
        guard entry.kind == .image else { return }
        model.load(entry) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                switch result {
                case .success(let payload):
                    guard let image = self.imageFromPayload(payload) else {
                        self.actionMessage = "Could not load this image for editing."
                        self.refresh()
                        return
                    }
                    self.panel.dismiss()
                    self.openEditor(with: image)
                case .failure:
                    self.actionMessage = "Could not load this image for editing."
                    self.refresh()
                }
            }
        }
    }

    private func imageFromPayload(_ payload: ClipPayload) -> NSImage? {
        for part in payload.parts {
            for rep in part.representations {
                if let ut = UTType(rep.type), ut.conforms(to: .image),
                   let image = NSImage(data: rep.data) {
                    return image
                }
            }
        }
        return nil
    }

    @objc private func togglePause() { monitor.paused.toggle(); refresh() }
    @objc private func enablePasting() { panel.dismiss(); PasteController.requestPermission() }
    @objc private func enableReading() {
        panel.dismiss()
        if #available(macOS 15.4, *), NSPasteboard.general.accessBehavior == .alwaysDeny {
            showAlert(title: "Allow Clipboard Access", message: "Open System Settings → Privacy & Security and allow Clipscreen to always read the clipboard.")
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security")!)
        } else {
            // Only this explicit user action may trigger macOS's pasteboard prompt.
            monitor.poll(userInitiated: true)
            if needsReadPermission {
                showAlert(title: "Always Allow Clipboard Access", message: "To save history in the background, allow Clipscreen to always read the clipboard in System Settings. One-time access only saves the current item.")
            }
        }
        refresh()
    }
    @objc private func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
            else {
                try SMAppService.mainApp.register()
                if SMAppService.mainApp.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
            }
        } catch {
            panel.dismiss()
            showAlert(title: "Could Not Change Login Setting", message: "Check Clipscreen in System Settings → General → Login Items. (Error \((error as NSError).code))")
        }
    }
    @objc private func clearHistory() {
        panel.dismiss()
        let alert = NSAlert()
        alert.messageText = "Clear history?"
        alert.informativeText = "This permanently removes unpinned items. Favorites will be kept. Your current clipboard remains available to paste with ⌘V."
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Clear History")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertSecondButtonReturn { model.clear() }
    }
    @objc private func quit() { NSApp.terminate(nil) }

    private func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    private func installApplicationMenu() {
        let menu = NSMenu()
        let app = NSMenuItem()
        let appMenu = NSMenu()
        let quit = NSMenuItem(title: "Quit Clipscreen", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        appMenu.addItem(quit)
        app.submenu = appMenu
        menu.addItem(app)
        let edit = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(NSMenuItem(title: "Undo", action: Selector(("undo:")), keyEquivalent: "z"))
        let redoItem = NSMenuItem(title: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(redoItem)
        editMenu.addItem(.separator())
        for (name, selector, key) in [("Cut", "cut:", "x"), ("Copy", "copy:", "c"),
                                      ("Paste", "paste:", "v"), ("Select All", "selectAll:", "a")] {
            editMenu.addItem(NSMenuItem(title: name, action: Selector(selector), keyEquivalent: key))
        }
        edit.submenu = editMenu
        menu.addItem(edit)
        NSApp.mainMenu = menu
        let windowItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(NSMenuItem(title: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"))
        windowMenu.addItem(.separator())
        windowMenu.addItem(NSMenuItem(title: "Bring All to Front", action: #selector(NSApplication.arrangeInFront(_:)), keyEquivalent: ""))
        windowItem.submenu = windowMenu
        menu.addItem(windowItem)
        NSApp.windowsMenu = windowMenu
    }
}
