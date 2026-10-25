import AppKit

enum AnnotationTool: Int, CaseIterable {
    case arrow
    case line
    case rect
    case filledRect
    case highlighter

    var symbolName: String {
        switch self {
        case .arrow: return "arrow.up.right"
        case .line: return "line.diagonal"
        case .rect: return "square"
        case .filledRect: return "square.fill"
        case .highlighter: return "highlighter"
        }
    }

    var title: String {
        switch self {
        case .arrow: return "Arrow"
        case .line: return "Line"
        case .rect: return "Rectangle Outline"
        case .filledRect: return "Filled Rectangle"
        case .highlighter: return "Highlighter"
        }
    }
}

struct AnnotationItem {
    let tool: AnnotationTool
    var startPoint: CGPoint
    var endPoint: CGPoint
    var points: [CGPoint]
    let color: NSColor
    let lineWidth: CGFloat
}

final class AnnotationCanvasView: NSView {
    let baseImage: NSImage
    private(set) var items: [AnnotationItem] = []
    private var currentItem: AnnotationItem?

    var activeTool: AnnotationTool = .arrow
    var activeColor: NSColor = .systemRed
    var activeLineWidth: CGFloat = 3.5

    var onUndoChange: ((Bool) -> Void)?

    init(image: NSImage) {
        self.baseImage = image
        super.init(frame: .zero)
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    var canUndo: Bool { !items.isEmpty }

    func undo() {
        guard !items.isEmpty else { return }
        items.removeLast()
        needsDisplay = true
        onUndoChange?(canUndo)
    }

    func clear() {
        items.removeAll()
        needsDisplay = true
        onUndoChange?(false)
    }

    var imageRect: NSRect {
        let padding: CGFloat = 20
        let available = NSRect(x: padding, y: padding,
                               width: max(10, bounds.width - padding * 2),
                               height: max(10, bounds.height - padding * 2))
        let imgSize = baseImage.size
        guard imgSize.width > 0, imgSize.height > 0 else { return available }
        let scale = min(available.width / imgSize.width, available.height / imgSize.height)
        let w = imgSize.width * scale
        let h = imgSize.height * scale
        return NSRect(x: available.midX - w / 2, y: available.midY - h / 2, width: w, height: h)
    }

    private func toImagePoint(_ windowPoint: NSPoint) -> CGPoint? {
        let viewPoint = convert(windowPoint, from: nil)
        let rect = imageRect
        guard rect.width > 0, rect.height > 0 else { return nil }
        let clampedX = min(max(viewPoint.x, rect.minX), rect.maxX)
        let clampedY = min(max(viewPoint.y, rect.minY), rect.maxY)
        let relX = (clampedX - rect.minX) / rect.width
        let relY = (clampedY - rect.minY) / rect.height
        return CGPoint(x: relX * baseImage.size.width,
                       y: relY * baseImage.size.height)
    }

    override func mouseDown(with event: NSEvent) {
        guard let pt = toImagePoint(event.locationInWindow) else { return }
        currentItem = AnnotationItem(tool: activeTool, startPoint: pt, endPoint: pt,
                                     points: [pt], color: activeColor, lineWidth: activeLineWidth)
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard var item = currentItem, let pt = toImagePoint(event.locationInWindow) else { return }
        item.endPoint = pt
        if item.tool == .highlighter {
            item.points.append(pt)
        }
        currentItem = item
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard var item = currentItem, let pt = toImagePoint(event.locationInWindow) else { return }
        item.endPoint = pt
        if item.tool == .highlighter {
            item.points.append(pt)
        }
        items.append(item)
        currentItem = nil
        needsDisplay = true
        onUndoChange?(canUndo)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let rect = imageRect
        guard rect.width > 0, rect.height > 0,
              let context = NSGraphicsContext.current?.cgContext else { return }

        // Draw shadow under image
        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: -3), blur: 12,
                          color: NSColor.black.withAlphaComponent(0.20).cgColor)
        baseImage.draw(in: rect)
        context.restoreGState()

        // Draw subtle border around image
        let border = NSBezierPath(rect: rect)
        NSColor.separatorColor.withAlphaComponent(0.6).setStroke()
        border.lineWidth = 0.5
        border.stroke()

        // Render annotations transformed to the current imageRect
        context.saveGState()
        context.translateBy(x: rect.minX, y: rect.minY)
        let scaleX = rect.width / max(1, baseImage.size.width)
        let scaleY = rect.height / max(1, baseImage.size.height)
        context.scaleBy(x: scaleX, y: scaleY)

        let all = items + [currentItem].compactMap { $0 }
        for item in all {
            Self.render(item: item, in: context)
        }
        context.restoreGState()
    }

    static func render(item: AnnotationItem, in context: CGContext) {
        context.saveGState()
        let color = item.color

        switch item.tool {
        case .arrow:
            drawArrow(from: item.startPoint, to: item.endPoint, color: color,
                      lineWidth: item.lineWidth, in: context)

        case .line:
            context.setStrokeColor(color.cgColor)
            context.setLineWidth(item.lineWidth)
            context.setLineCap(.round)
            context.beginPath()
            context.move(to: item.startPoint)
            context.addLine(to: item.endPoint)
            context.strokePath()

        case .rect:
            let rect = CGRect(x: min(item.startPoint.x, item.endPoint.x),
                              y: min(item.startPoint.y, item.endPoint.y),
                              width: max(1, abs(item.endPoint.x - item.startPoint.x)),
                              height: max(1, abs(item.endPoint.y - item.startPoint.y)))
            context.setStrokeColor(color.cgColor)
            context.setLineWidth(item.lineWidth)
            let path = CGPath(roundedRect: rect, cornerWidth: 3, cornerHeight: 3, transform: nil)
            context.addPath(path)
            context.strokePath()

        case .filledRect:
            let rect = CGRect(x: min(item.startPoint.x, item.endPoint.x),
                              y: min(item.startPoint.y, item.endPoint.y),
                              width: max(1, abs(item.endPoint.x - item.startPoint.x)),
                              height: max(1, abs(item.endPoint.y - item.startPoint.y)))
            context.setFillColor(color.cgColor)
            let path = CGPath(roundedRect: rect, cornerWidth: 3, cornerHeight: 3, transform: nil)
            context.addPath(path)
            context.fillPath()

        case .highlighter:
            context.setStrokeColor(color.withAlphaComponent(0.38).cgColor)
            context.setLineWidth(max(20, item.lineWidth * 5.5))
            context.setLineCap(.round)
            context.setLineJoin(.round)
            context.setBlendMode(.multiply)
            if item.points.count > 1 {
                context.beginPath()
                context.addLines(between: item.points)
                context.strokePath()
            } else {
                context.beginPath()
                context.move(to: item.startPoint)
                context.addLine(to: item.endPoint)
                context.strokePath()
            }
        }
        context.restoreGState()
    }

    private static func drawArrow(from start: CGPoint, to end: CGPoint, color: NSColor,
                                  lineWidth: CGFloat, in context: CGContext) {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let length = hypot(dx, dy)
        guard length > 1 else { return }

        let angle = atan2(dy, dx)
        let headLength = max(14, lineWidth * 4)
        let headAngle = CGFloat.pi / 6 // 30 degrees

        let shaftEnd = CGPoint(x: end.x - headLength * 0.7 * cos(angle),
                               y: end.y - headLength * 0.7 * sin(angle))

        context.setStrokeColor(color.cgColor)
        context.setFillColor(color.cgColor)
        context.setLineWidth(lineWidth)
        context.setLineCap(.round)
        context.setLineJoin(.round)

        context.beginPath()
        context.move(to: start)
        context.addLine(to: shaftEnd)
        context.strokePath()

        let p1 = end
        let p2 = CGPoint(x: end.x - headLength * cos(angle - headAngle),
                         y: end.y - headLength * sin(angle - headAngle))
        let p3 = CGPoint(x: end.x - headLength * cos(angle + headAngle),
                         y: end.y - headLength * sin(angle + headAngle))

        context.beginPath()
        context.move(to: p1)
        context.addLine(to: p2)
        context.addLine(to: p3)
        context.closePath()
        context.fillPath()
    }

    func renderAnnotatedImage() -> NSImage {
        var pixelSize = baseImage.size
        for rep in baseImage.representations {
            if rep.pixelsWide > 0 && rep.pixelsHigh > 0 {
                pixelSize = NSSize(width: rep.pixelsWide, height: rep.pixelsHigh)
                break
            }
        }

        let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                                   pixelsWide: Int(pixelSize.width),
                                   pixelsHigh: Int(pixelSize.height),
                                   bitsPerSample: 8,
                                   samplesPerPixel: 4,
                                   hasAlpha: true,
                                   isPlanar: false,
                                   colorSpaceName: .deviceRGB,
                                   bytesPerRow: 0,
                                   bitsPerPixel: 0)!
        rep.size = baseImage.size

        NSGraphicsContext.saveGraphicsState()
        let ctx = NSGraphicsContext(bitmapImageRep: rep)!
        NSGraphicsContext.current = ctx
        let cg = ctx.cgContext

        baseImage.draw(in: NSRect(origin: .zero, size: baseImage.size))

        for item in items {
            Self.render(item: item, in: cg)
        }

        NSGraphicsContext.restoreGraphicsState()

        let result = NSImage(size: baseImage.size)
        result.addRepresentation(rep)
        return result
    }
}

final class ScreenshotEditorWindowController: NSWindowController, NSWindowDelegate {
    private let canvas: AnnotationCanvasView
    private let image: NSImage
    var onComplete: ((NSImage) -> Void)?
    var onCancel: (() -> Void)?

    private var toolButtons: [AnnotationTool: NSButton] = [:]
    private var colorButtons: [NSColor: NSButton] = [:]
    private var undoButton: NSButton!

    private let colors: [NSColor] = [
        .systemRed,
        .systemYellow,
        .systemGreen,
        .systemBlue,
        .black,
        .white
    ]

    init(image: NSImage) {
        self.image = image
        self.canvas = AnnotationCanvasView(image: image)

        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let maxW = screen.width * 0.85
        let maxH = screen.height * 0.85

        let toolbarMinWidth: CGFloat = 620
        let naturalW = max(toolbarMinWidth, min(image.size.width + 64, maxW))
        let naturalH = max(420, min(image.size.height + 120, maxH))

        let initialSize = NSSize(width: naturalW, height: naturalH)

        let window = NSWindow(contentRect: NSRect(origin: .zero, size: initialSize),
                              styleMask: [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.minSize = NSSize(width: 580, height: 380)
        window.title = "Clip Screenshot Editor"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
        window.delegate = self

        buildUI(window)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func buildUI(_ window: NSWindow) {
        let content = NSView()
        window.contentView = content

        let toolbar = buildToolbar()
        toolbar.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(toolbar)

        canvas.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(canvas)

        NSLayoutConstraint.activate([
            toolbar.topAnchor.constraint(equalTo: content.topAnchor, constant: 12),
            toolbar.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            toolbar.heightAnchor.constraint(equalToConstant: 44),
            toolbar.leadingAnchor.constraint(greaterThanOrEqualTo: content.leadingAnchor, constant: 16),
            toolbar.trailingAnchor.constraint(lessThanOrEqualTo: content.trailingAnchor, constant: -16),

            canvas.topAnchor.constraint(equalTo: toolbar.bottomAnchor, constant: 8),
            canvas.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            canvas.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            canvas.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -12)
        ])

        canvas.onUndoChange = { [weak self] canUndo in
            self?.undoButton.isEnabled = canUndo
        }

        updateToolSelection()
        updateColorSelection()
    }

    private func buildToolbar() -> NSView {
        let bar = NSVisualEffectView()
        bar.material = .headerView
        bar.blendingMode = .withinWindow
        bar.state = .active
        bar.wantsLayer = true
        bar.layer?.cornerRadius = 22
        bar.layer?.masksToBounds = true
        bar.layer?.borderWidth = 1
        bar.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.2).cgColor

        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 6
        stack.edgeInsets = NSEdgeInsets(top: 4, left: 10, bottom: 4, right: 10)
        stack.translatesAutoresizingMaskIntoConstraints = false
        bar.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: bar.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: bar.trailingAnchor),
            stack.topAnchor.constraint(equalTo: bar.topAnchor),
            stack.bottomAnchor.constraint(equalTo: bar.bottomAnchor)
        ])

        // Close button
        let close = NSButton(image: NSImage(systemSymbolName: "xmark", accessibilityDescription: "Close")!,
                             target: self, action: #selector(cancelAction))
        close.isBordered = false
        close.bezelStyle = .inline
        close.toolTip = "Discard screenshot (Esc)"
        close.widthAnchor.constraint(equalToConstant: 28).isActive = true
        close.heightAnchor.constraint(equalToConstant: 28).isActive = true
        stack.addArrangedSubview(close)

        stack.addArrangedSubview(makeSeparator())

        // Tool buttons
        for tool in AnnotationTool.allCases {
            let btn = NSButton(image: NSImage(systemSymbolName: tool.symbolName, accessibilityDescription: tool.title)!,
                               target: self, action: #selector(toolClicked(_:)))
            btn.tag = tool.rawValue
            btn.isBordered = false
            btn.bezelStyle = .inline
            btn.toolTip = tool.title
            btn.widthAnchor.constraint(equalToConstant: 30).isActive = true
            btn.heightAnchor.constraint(equalToConstant: 30).isActive = true
            toolButtons[tool] = btn
            stack.addArrangedSubview(btn)
        }

        stack.addArrangedSubview(makeSeparator())

        // Color circles
        for color in colors {
            let btn = ColorCircleButton(color: color, target: self, action: #selector(colorClicked(_:)))
            btn.widthAnchor.constraint(equalToConstant: 24).isActive = true
            btn.heightAnchor.constraint(equalToConstant: 24).isActive = true
            colorButtons[color] = btn
            stack.addArrangedSubview(btn)
        }

        stack.addArrangedSubview(makeSeparator())

        // Undo button
        undoButton = NSButton(image: NSImage(systemSymbolName: "arrow.uturn.backward", accessibilityDescription: "Undo")!,
                              target: self, action: #selector(undoAction))
        undoButton.isBordered = false
        undoButton.bezelStyle = .inline
        undoButton.toolTip = "Undo (⌘Z)"
        undoButton.isEnabled = false
        undoButton.widthAnchor.constraint(equalToConstant: 28).isActive = true
        undoButton.heightAnchor.constraint(equalToConstant: 28).isActive = true
        stack.addArrangedSubview(undoButton)

        stack.addArrangedSubview(makeSeparator())

        // Copy & Close button (Primary Action)
        let copyBtn = NSButton(title: "Copy", target: self, action: #selector(copyAction))
        copyBtn.bezelStyle = .rounded
        copyBtn.controlSize = .regular
        copyBtn.keyEquivalent = "\r"
        copyBtn.toolTip = "Copy to clipboard and close (Enter / ⌘C)"
        stack.addArrangedSubview(copyBtn)

        // Save button
        let saveBtn = NSButton(title: "Save…", target: self, action: #selector(saveAction))
        saveBtn.bezelStyle = .rounded
        saveBtn.controlSize = .regular
        saveBtn.toolTip = "Save to disk (⌘S)"
        stack.addArrangedSubview(saveBtn)

        return bar
    }

    private func makeSeparator() -> NSView {
        let v = NSBox()
        v.boxType = .separator
        v.widthAnchor.constraint(equalToConstant: 1).isActive = true
        v.heightAnchor.constraint(equalToConstant: 20).isActive = true
        return v
    }

    @objc private func toolClicked(_ sender: NSButton) {
        guard let tool = AnnotationTool(rawValue: sender.tag) else { return }
        canvas.activeTool = tool
        updateToolSelection()
    }

    @objc private func colorClicked(_ sender: ColorCircleButton) {
        canvas.activeColor = sender.color
        updateColorSelection()
    }

    private func updateToolSelection() {
        for (tool, btn) in toolButtons {
            let isSelected = tool == canvas.activeTool
            btn.contentTintColor = isSelected ? .controlAccentColor : .secondaryLabelColor
            btn.wantsLayer = true
            btn.layer?.cornerRadius = 6
            btn.layer?.backgroundColor = isSelected ? NSColor.controlAccentColor.withAlphaComponent(0.15).cgColor : nil
        }
    }

    private func updateColorSelection() {
        for (color, btn) in colorButtons {
            if let circle = btn as? ColorCircleButton {
                circle.isSelected = (color == canvas.activeColor)
            }
        }
    }

    @objc private func undoAction() {
        canvas.undo()
    }

    @objc private func copyAction() {
        let annotated = canvas.renderAnnotatedImage()
        onComplete?(annotated)
        window?.close()
    }

    @objc private func saveAction() {
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.png]
        savePanel.nameFieldStringValue = "Screenshot \(DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .medium)).png"
        savePanel.beginSheetModal(for: window!) { [weak self] response in
            guard response == .OK, let url = savePanel.url, let self else { return }
            let annotated = self.canvas.renderAnnotatedImage()
            if let tiff = annotated.tiffRepresentation,
               let rep = NSBitmapImageRep(data: tiff),
               let png = rep.representation(using: .png, properties: [:]) {
                try? png.write(to: url)
            }
        }
    }

    @objc private func cancelAction() {
        onCancel?()
        window?.close()
    }

    func windowWillClose(_ notification: Notification) {
        onCancel?()
    }
}

final class ColorCircleButton: NSButton {
    let color: NSColor
    var isSelected: Bool = false {
        didSet { needsDisplay = true }
    }

    init(color: NSColor, target: AnyObject?, action: Selector) {
        self.color = color
        super.init(frame: .zero)
        self.target = target
        self.action = action
        isBordered = false
        bezelStyle = .inline
        title = ""
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
