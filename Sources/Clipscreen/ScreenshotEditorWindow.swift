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
