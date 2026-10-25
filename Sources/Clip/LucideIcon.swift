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

/// One surface for hover, press and active state. A native button bezel would
/// add a second, shorter hover fill over the active outline.
class ClipIconButton: NSButton {
    private var isActive = false
    private var isHovered = false
    private var hoverTrackingArea: NSTrackingArea?

    init(_ icon: LucideIcon, label: String, size: CGFloat = 16, target: AnyObject?, action: Selector?) {
        super.init(frame: .zero)
        image = icon.image(size: size)
        imagePosition = .imageOnly
        bezelStyle = .inline
        isBordered = false
        contentTintColor = .secondaryLabelColor
        toolTip = label
        setAccessibilityLabel(label)
        self.target = target
        self.action = action
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func setActive(_ active: Bool) {
        isActive = active
        state = active ? .on : .off
        contentTintColor = active ? .controlAccentColor : .secondaryLabelColor
        needsDisplay = true
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverTrackingArea { removeTrackingArea(hoverTrackingArea) }
        let area = NSTrackingArea(rect: .zero,
                                  options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        hoverTrackingArea = area
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
        if isEnabled && (isActive || isHovered || isHighlighted) {
            let shape = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 6, yRadius: 6)
            let color: NSColor = isActive ? .controlAccentColor : .labelColor
            let alpha: CGFloat = isHighlighted ? 0.20 : isHovered ? 0.12 : 0.08
            color.withAlphaComponent(alpha).setFill()
            shape.fill()
            if isActive {
                color.withAlphaComponent(0.5).setStroke()
                shape.lineWidth = 1
                shape.stroke()
            }
        }
        super.draw(dirtyRect)
    }
}
