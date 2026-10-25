import AppKit

/// The rainbow is a persistent affordance; it never turns into the active swatch.
final class CustomColorButton: NSButton {
    var selectedColor: NSColor? {
        didSet {
            state = selectedColor == nil ? .off : .on
            let rgb = selectedColor?.usingColorSpace(.sRGB)
            let hex = rgb.map { color in
                String(format: "#%02X%02X%02X", Int((color.redComponent * 255).rounded()),
                       Int((color.greenComponent * 255).rounded()), Int((color.blueComponent * 255).rounded()))
            }
            setAccessibilityValue(selectedColor == nil ? "Not selected" : "Selected, \(hex ?? "custom color")")
            toolTip = hex.map { "Custom color: \($0)" } ?? "Custom color…"
            needsDisplay = true
        }
    }

    init(target: AnyObject?, action: Selector) {
        super.init(frame: .zero)
        self.target = target
        self.action = action
        title = ""
        isBordered = false
        bezelStyle = .inline
        toolTip = "Custom color…"
        setAccessibilityLabel("Choose custom color")
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func draw(_ dirtyRect: NSRect) {
        let center = NSPoint(x: bounds.midX, y: bounds.midY)
        let radius = min(bounds.width, bounds.height) / 2 - 4
        for step in 0..<180 {
            let start = CGFloat(step) * 2
            let wedge = NSBezierPath()
            wedge.move(to: center)
            wedge.appendArc(withCenter: center, radius: radius, startAngle: start, endAngle: start + 2.5)
            wedge.close()
            NSColor(calibratedHue: CGFloat(step) / 180, saturation: 0.85, brightness: 1, alpha: 1).setFill()
            wedge.fill()
        }
        let inside = NSRect(x: center.x - radius + 4, y: center.y - radius + 4,
                            width: (radius - 4) * 2, height: (radius - 4) * 2)
        let centerShape = NSBezierPath(ovalIn: inside)
        NSColor.controlBackgroundColor.setFill()
        centerShape.fill()
        if isHighlighted {
            NSColor.labelColor.withAlphaComponent(0.12).setFill()
            centerShape.fill()
        }
        let plus = NSBezierPath()
        plus.move(to: NSPoint(x: center.x - 3.5, y: center.y))
        plus.line(to: NSPoint(x: center.x + 3.5, y: center.y))
        plus.move(to: NSPoint(x: center.x, y: center.y - 3.5))
        plus.line(to: NSPoint(x: center.x, y: center.y + 3.5))
        plus.lineWidth = 1.5
        plus.lineCapStyle = .round
        NSColor.labelColor.setStroke()
        plus.stroke()
        if selectedColor != nil {
            let ring = NSBezierPath(ovalIn: bounds.insetBy(dx: 1, dy: 1))
            NSColor.controlAccentColor.setStroke()
            ring.lineWidth = 2
            ring.stroke()
        }
    }

    override func drawFocusRingMask() { NSBezierPath(ovalIn: bounds).fill() }
}
