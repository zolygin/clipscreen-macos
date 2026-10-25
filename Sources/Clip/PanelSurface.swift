import AppKit

enum ClipStyle {
    static let panelSize = NSSize(width: 430, height: 590)
    static let minPanelSize = NSSize(width: 360, height: 420)
    static let cornerRadius: CGFloat = 18
    static let inset: CGFloat = 16
    static let rowHeight: CGFloat = 76
    static let thumbnailSize: CGFloat = 48
    static let rowRadius: CGFloat = 10
    static let titleFont = NSFont.systemFont(ofSize: 17, weight: .semibold)
    static let bodyFont = NSFont.systemFont(ofSize: 13)
    static let captionFont = NSFont.systemFont(ofSize: 11)
}

/// The backdrop is composited separately from the view's ordinary CALayer.
/// maskImage clips that backdrop too; cornerRadius alone leaves square corners.
final class PanelSurface: NSView {
    enum MaterialMode { case automatic, standard, opaque }
    let body = NSView()
    private let standard = NSVisualEffectView()
    private var glass: NSView?
    private let mode: MaterialMode
    private var displayObserver: NSObjectProtocol?
    private var bodyConstraints: [NSLayoutConstraint] = []

    init(mode: MaterialMode = .automatic) {
        self.mode = mode
        super.init(frame: NSRect(origin: .zero, size: ClipStyle.panelSize))
        wantsLayer = true
        layer?.cornerRadius = ClipStyle.cornerRadius
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
        standard.material = .popover
        standard.blendingMode = .behindWindow
        standard.state = .active
        standard.maskImage = Self.roundedMask(radius: ClipStyle.cornerRadius)
        addSubview(standard)
        pin(standard)
        body.wantsLayer = true
        body.layer?.cornerRadius = ClipStyle.cornerRadius
        body.layer?.masksToBounds = true
        body.translatesAutoresizingMaskIntoConstraints = false
        if #available(macOS 26.0, *), mode == .automatic {
            let effect = NSGlassEffectView()
            effect.style = .regular
            effect.cornerRadius = ClipStyle.cornerRadius
            effect.contentView = body
            glass = effect
            addSubview(effect)
            pin(effect)
        } else {
            addSubview(body)
            bodyConstraints = pin(body)
        }
        updateMaterial()
        displayObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.updateMaterial() }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    deinit {
        if let displayObserver { NSWorkspace.shared.notificationCenter.removeObserver(displayObserver) }
    }

    private func updateMaterial() {
        let opaque = mode == .opaque || NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
        // Use a single material, never a glass layer over a second blur layer.
        let useGlass = glass != nil && !opaque
        standard.isHidden = useGlass || opaque
        if let glass {
            if useGlass {
                if #available(macOS 26.0, *), let effect = glass as? NSGlassEffectView,
                   effect.contentView !== body {
                    NSLayoutConstraint.deactivate(bodyConstraints)
                    bodyConstraints = []
                    body.removeFromSuperview()
                    effect.contentView = body
                }
            } else if body.superview !== self {
                if #available(macOS 26.0, *), let effect = glass as? NSGlassEffectView { effect.contentView = nil }
                addSubview(body)
                bodyConstraints = pin(body)
            }
            glass.isHidden = !useGlass
        }
        updateOpaqueBackground(opaque)
        window?.invalidateShadow()
    }

    override var isOpaque: Bool { false }
    override var mouseDownCanMoveWindow: Bool { true }

    @discardableResult
    private func pin(_ view: NSView) -> [NSLayoutConstraint] {
        view.translatesAutoresizingMaskIntoConstraints = false
        let constraints = [view.leadingAnchor.constraint(equalTo: leadingAnchor),
                           view.trailingAnchor.constraint(equalTo: trailingAnchor),
                           view.topAnchor.constraint(equalTo: topAnchor),
                           view.bottomAnchor.constraint(equalTo: bottomAnchor)]
        NSLayoutConstraint.activate(constraints)
        return constraints
    }

    private func updateOpaqueBackground(_ opaque: Bool) {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            body.layer?.backgroundColor = opaque ? NSColor.windowBackgroundColor.cgColor : nil
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateOpaqueBackground(mode == .opaque || NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency)
    }

    static func roundedMask(radius: CGFloat) -> NSImage {
        let size = NSSize(width: radius * 2 + 1, height: radius * 2 + 1)
        let image = NSImage(size: size, flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }
}

final class ClipRowView: NSTableRowView {
    var isFirstPinned = false
    override var interiorBackgroundStyle: NSView.BackgroundStyle { .normal }

    override func drawSelection(in dirtyRect: NSRect) {
        guard isSelected else { return }
        let rightMargin: CGFloat = 14
        let selectionRect = NSRect(x: 3, y: 2, width: max(0, bounds.width - 3 - rightMargin), height: bounds.height - 4)
        let shape = NSBezierPath(roundedRect: selectionRect,
                                 xRadius: ClipStyle.rowRadius, yRadius: ClipStyle.rowRadius)
        NSColor.controlAccentColor.withAlphaComponent(0.12).setFill()
        shape.fill()
        NSColor.controlAccentColor.withAlphaComponent(
            NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast ? 0.85 : 0.35).setStroke()
        shape.lineWidth = 1
        shape.stroke()
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if isFirstPinned {
            let line = NSBezierPath()
            line.move(to: NSPoint(x: 12, y: bounds.height - 1))
            line.line(to: NSPoint(x: bounds.width - 24, y: bounds.height - 1))
            NSColor.separatorColor.withAlphaComponent(0.5).setStroke()
            line.lineWidth = 1
            line.stroke()
        }
    }
}
