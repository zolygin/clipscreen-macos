import AppKit

final class ColorCircleButton: NSButton {
    let color: NSColor
    var isSelected: Bool = false {
        didSet {
            state = isSelected ? .on : .off
            setAccessibilityValue(isSelected ? "Selected" : "Not selected")
            needsDisplay = true
        }
    }

    init(color: NSColor, label: String, target: AnyObject?, action: Selector) {
        self.color = color
        super.init(frame: .zero)
        self.target = target
        self.action = action
        isBordered = false
        bezelStyle = .inline
        title = ""
        toolTip = label
        setAccessibilityLabel(label)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func draw(_ dirtyRect: NSRect) {
        let circleRect = bounds.insetBy(dx: 3, dy: 3)
        let path = NSBezierPath(ovalIn: circleRect)
        color.setFill()
        path.fill()

        if color == .white {
            NSColor.separatorColor.setStroke()
            path.lineWidth = 1
            path.stroke()
        }

        if isSelected {
            let ringRect = bounds.insetBy(dx: 1, dy: 1)
            let ring = NSBezierPath(ovalIn: ringRect)
            NSColor.controlAccentColor.setStroke()
            ring.lineWidth = 2
            ring.stroke()
        }
    }
}
