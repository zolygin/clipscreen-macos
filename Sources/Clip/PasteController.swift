import AppKit
import ApplicationServices
import Carbon

final class PasteController {
    static var isTrusted: Bool { AXIsProcessTrusted() }

    static func requestPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    private var generation = 0
    func cancel() { generation += 1 }

    func paste(to target: NSRunningApplication?, completion: @escaping (String?) -> Void) {
        cancel()
        let token = generation
        guard let target, !target.isTerminated else {
            completion("Copied. Switch to an app and press ⌘V.")
            return
        }
        let activated = target.activate(options: [.activateIgnoringOtherApps])
        guard Self.isTrusted else {
            completion(nil) // The panel already advertised manual ⌘V before selection.
            return
        }
        guard activated else {
            completion("Could not return to the app. Your item is copied — press ⌘V to paste.")
            return
        }
        let expectedClipboardVersion = NSPasteboard.general.changeCount
        waitForFocus(target, token: token, clipboardVersion: expectedClipboardVersion,
                     attempts: 20, completion: completion)
    }

    private func waitForFocus(_ target: NSRunningApplication, token: Int, clipboardVersion: Int,
                              attempts: Int, completion: @escaping (String?) -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            guard let self, self.generation == token else { return }
            guard NSPasteboard.general.changeCount == clipboardVersion else {
                completion("The clipboard changed before pasting. Select the item again.")
                return
            }
            let front = NSWorkspace.shared.frontmostApplication
            let modifiers = CGEventSource.flagsState(.combinedSessionState)
            let held = modifiers.intersection([.maskCommand, .maskAlternate, .maskControl, .maskShift])
            if front?.processIdentifier == target.processIdentifier && held.isEmpty && !target.isTerminated {
                guard Self.isTrusted,
                      let source = CGEventSource(stateID: .privateState),
                      let down = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true),
                      let up = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false) else {
                    completion("Automatic paste is unavailable. Your item is copied — press ⌘V.")
                    return
                }
                down.flags = .maskCommand
                up.flags = .maskCommand
                // Address the original process so a focus change cannot paste into another app.
                down.postToPid(target.processIdentifier)
                up.postToPid(target.processIdentifier)
                completion(nil)
            } else if attempts > 0 {
                self.waitForFocus(target, token: token, clipboardVersion: clipboardVersion,
                                  attempts: attempts - 1, completion: completion)
            } else {
                completion("Copied, but the app did not regain focus. Click the destination and press ⌘V.")
            }
        }
    }
}
