import AppKit

/// Original Lucide SVGs, vendored in Resources/Lucide. No SF Symbols fallback.
enum LucideIcon: String, CaseIterable {
    case pin, scan, menu, pencil, files, image, type, square, highlighter, clipboard, pause, search, x
    case penLine = "pen-line"
    case arrowUpRight = "arrow-up-right"
    case slash
    case paintBucket = "paint-bucket"
    case undo = "undo-2"
    case redo = "redo-2"

    private static var originals: [LucideIcon: NSImage] = [:]

    func image(size: CGFloat = 16) -> NSImage {
        let original: NSImage
        if let cached = Self.originals[self] {
            original = cached
        } else {
            guard let url = Bundle.main.resourceURL?.appendingPathComponent("Lucide/\(rawValue).svg"),
                  let loaded = NSImage(contentsOf: url) else {
                preconditionFailure("Missing bundled Lucide icon: \(rawValue)")
            }
            Self.originals[self] = loaded
            original = loaded
        }
        let result = original.copy() as! NSImage
        result.size = NSSize(width: size, height: size)
        result.isTemplate = true
        return result
    }
}

/// A consistent hit target and native hover/press treatment for icon actions.
final class ClipIconButton: NSButton {
    private var isActive = false

    init(_ icon: LucideIcon, label: String, size: CGFloat = 16, target: AnyObject?, action: Selector?) {
        super.init(frame: .zero)
        image = icon.image(size: size)
        imagePosition = .imageOnly
        bezelStyle = .recessed
        isBordered = true
        showsBorderOnlyWhileMouseInside = true
        contentTintColor = .secondaryLabelColor
        toolTip = label
        setAccessibilityLabel(label)
        self.target = target
        self.action = action
        wantsLayer = true
        layer?.cornerRadius = 6
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func setActive(_ active: Bool) {
        isActive = active
        state = active ? .on : .off
        contentTintColor = active ? .controlAccentColor : .secondaryLabelColor
        updateActiveAppearance()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateActiveAppearance()
    }

    private func updateActiveAppearance() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = isActive ? NSColor.controlAccentColor.withAlphaComponent(0.12).cgColor : nil
            layer?.borderColor = isActive ? NSColor.controlAccentColor.withAlphaComponent(0.5).cgColor : nil
            layer?.borderWidth = isActive ? 1 : 0
        }
    }
}
