import AppKit

final class ScreenshotEditorWindow: NSWindow {
    var onUndo: (() -> Void)?
    var onRedo: (() -> Void)?
    var onCopy: (() -> Void)?
    var onSave: (() -> Void)?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags == [.command], event.charactersIgnoringModifiers == "w" {
            performClose(nil)
            return true
        }
        if let canvas = firstResponder as? AnnotationCanvasView, canvas.activeTool == .text,
           flags.isEmpty, event.keyCode == 36 {
            canvas.keyDown(with: event)
            return true
        }
        if let editor = firstResponder as? AnnotationTextView,
           !(flags == [.command] && event.charactersIgnoringModifiers == "s") {
            // Return belongs to the text field, never to the default screenshot Copy button.
            if !flags.contains(.command) { return false }
            return editor.performKeyEquivalent(with: event)
        }
        if flags == [.command], event.charactersIgnoringModifiers == "z" {
            onUndo?()
            return true
        }
        if flags.contains(.command) && flags.contains(.shift) &&
           event.charactersIgnoringModifiers?.lowercased() == "z" {
            onRedo?()
            return true
        }
        if flags == [.command], event.charactersIgnoringModifiers == "c" {
            onCopy?()
            return true
        }
        if flags == [.command], event.charactersIgnoringModifiers == "s" {
            onSave?()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    override func cancelOperation(_ sender: Any?) { performClose(sender) }
}

/// Activation is asynchronous, especially while screencapture restores its source
/// app. Keep one bounded handoff for the newest editor, never a focus watchdog.
final class ScreenshotEditorPresenter {
    private let notifications: NotificationCenter
    private let activate: () -> Void
    private let isApplicationActive: () -> Bool
    private let schedule: (TimeInterval, DispatchWorkItem) -> Void
    private var generation = 0
    private var activeObserver: NSObjectProtocol?
    private var closeObserver: NSObjectProtocol?
    private var retries: [DispatchWorkItem] = []

    init(notifications: NotificationCenter = .default,
         activate: @escaping () -> Void = { NSApp.activate(ignoringOtherApps: true) },
         isApplicationActive: @escaping () -> Bool = { NSApp.isActive },
         schedule: @escaping (TimeInterval, DispatchWorkItem) -> Void = { delay, work in
             DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
         }) {
        self.notifications = notifications
        self.activate = activate
        self.isApplicationActive = isApplicationActive
        self.schedule = schedule
    }

    func present(_ window: NSWindow) {
        cancel()
        let request = generation
        activeObserver = notifications.addObserver(forName: NSApplication.didBecomeActiveNotification,
                                                   object: nil, queue: .main) { [weak self, weak window] _ in
            guard let self, let window, self.generation == request, window.isVisible,
                  !window.isMiniaturized else { return }
            // Activation can complete after makeKeyAndOrderFront returned.
            self.raise(window)
        }
        closeObserver = notifications.addObserver(forName: NSWindow.willCloseNotification,
                                                  object: window, queue: .main) { [weak self] _ in self?.cancel() }
        if window.isMiniaturized { window.deminiaturize(nil) }
        // Make the window available before asking the accessory app to activate.
        window.orderFrontRegardless()
        activate()
        window.makeKeyAndOrderFront(nil)
        for (index, delay) in [0.15, 0.4, 0.8].enumerated() {
            let work = DispatchWorkItem { [weak self, weak window] in
                guard let self, let window, self.generation == request else { return }
                guard window.isVisible, !window.isMiniaturized else { self.cancel(); return }
                if self.isApplicationActive() && window.isKeyWindow { self.cancel(); return }
                self.raise(window)
                self.activate()
                window.makeKeyAndOrderFront(nil)
                if index == 2 { self.cancel() }
            }
            retries.append(work)
            schedule(delay, work)
        }
    }

    private func raise(_ window: NSWindow) {
        window.orderFrontRegardless()
        window.makeKeyAndOrderFront(nil)
    }

    func cancel() {
        generation += 1
        retries.forEach { $0.cancel() }
        retries.removeAll()
        if let activeObserver { notifications.removeObserver(activeObserver) }
        if let closeObserver { notifications.removeObserver(closeObserver) }
        activeObserver = nil
        closeObserver = nil
    }

    deinit {
        retries.forEach { $0.cancel() }
        if let activeObserver { notifications.removeObserver(activeObserver) }
        if let closeObserver { notifications.removeObserver(closeObserver) }
    }
}
