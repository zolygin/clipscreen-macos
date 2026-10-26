import AppKit

/// Shared by tool context menus and existing annotations.
final class StrokeWidthMenu: NSMenu {
    private let onSelect: (CGFloat) -> Void

    init(tool: AnnotationTool, width: CGFloat, onSelect: @escaping (CGFloat) -> Void) {
        self.onSelect = onSelect
        super.init(title: "Line width")
        let heading = NSMenuItem(title: tool == .text ? "Text" : "\(tool.title) · Line width", action: nil, keyEquivalent: "")
        heading.isEnabled = false
        addItem(heading)
        if !tool.usesLineWidth {
            let explanation = NSMenuItem(title: tool == .text ? "Choose font and size next to Color" : "Solid fill has no outline width", action: nil, keyEquivalent: "")
            explanation.isEnabled = false
            addItem(explanation)
            return
        }
        addItem(.separator())
        for value in tool.lineWidths {
            let item = NSMenuItem(title: Self.label(value), action: #selector(chooseWidth(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = NSNumber(value: Double(value))
            item.state = value == width ? .on : .off
            item.image = NSImage(size: NSSize(width: 32, height: 16), flipped: false) { rect in
                let path = NSBezierPath()
                path.move(to: NSPoint(x: 4, y: rect.midY))
                path.line(to: NSPoint(x: 28, y: rect.midY))
                path.lineWidth = min(12, value)
                path.lineCapStyle = .round
                NSColor.labelColor.setStroke()
                path.stroke()
                return true
            }
            item.image?.isTemplate = true
            addItem(item)
        }
    }

    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    static func label(_ width: CGFloat) -> String { String(format: "%g pt", Double(width)) }

    @objc private func chooseWidth(_ sender: NSMenuItem) {
        guard let number = sender.representedObject as? NSNumber else { return }
        onSelect(CGFloat(number.doubleValue))
    }
}
