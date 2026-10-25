import AppKit

final class AnnotationCanvasView: NSView {
    let baseImage: NSImage
    private(set) var items: [AnnotationItem] = []
    private(set) var redoItems: [AnnotationItem] = []
    private var currentItem: AnnotationItem?

    var activeTool: AnnotationTool = .pen
    var activeColor: NSColor = .systemRed
    var activeLineWidth: CGFloat = 3.5

    var onHistoryChange: ((_ canUndo: Bool, _ canRedo: Bool) -> Void)?

    init(image: NSImage) {
        self.baseImage = image
        super.init(frame: .zero)
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    var canUndo: Bool { !items.isEmpty }
    var canRedo: Bool { !redoItems.isEmpty }

    func undo() {
        guard let item = items.popLast() else { return }
        redoItems.append(item)
        needsDisplay = true
        onHistoryChange?(canUndo, canRedo)
    }

    func redo() {
        guard let item = redoItems.popLast() else { return }
        items.append(item)
        needsDisplay = true
        onHistoryChange?(canUndo, canRedo)
    }

    func clear() {
        items.removeAll()
        redoItems.removeAll()
        needsDisplay = true
        onHistoryChange?(false, false)
    }

    var imageRect: NSRect {
        let pad: CGFloat = 20
        let avail = NSRect(x: pad, y: pad, width: max(10, bounds.width - pad * 2), height: max(10, bounds.height - pad * 2))
        let size = baseImage.size
        guard size.width > 0, size.height > 0 else { return avail }
        let scale = min(avail.width / size.width, avail.height / size.height)
        let w = size.width * scale, h = size.height * scale
        return NSRect(x: avail.midX - w / 2, y: avail.midY - h / 2, width: w, height: h)
    }

    private func toImagePoint(_ windowPoint: NSPoint) -> CGPoint? {
        let pt = convert(windowPoint, from: nil), rect = imageRect
        guard rect.width > 0, rect.height > 0 else { return nil }
        let relX = (min(max(pt.x, rect.minX), rect.maxX) - rect.minX) / rect.width
        let relY = (min(max(pt.y, rect.minY), rect.maxY) - rect.minY) / rect.height
        return CGPoint(x: relX * baseImage.size.width, y: relY * baseImage.size.height)
    }

    override func mouseDown(with event: NSEvent) {
        guard let pt = toImagePoint(event.locationInWindow) else { return }
        currentItem = AnnotationItem(tool: activeTool, startPoint: pt, endPoint: pt,
                                     points: [pt], color: activeColor, lineWidth: activeLineWidth)
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard var item = currentItem, let rawPt = toImagePoint(event.locationInWindow) else { return }
        let isShift = event.modifierFlags.contains(.shift)
        let pt = isShift ? AnnotationRenderer.snapPoint(from: item.startPoint, to: rawPt) : rawPt
        item.endPoint = pt
        if item.tool == .highlighter || item.tool == .pen {
            if isShift {
                item.points = [item.startPoint, pt]
            } else {
                item.points.append(pt)
            }
        }
        currentItem = item
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard var item = currentItem, let rawPt = toImagePoint(event.locationInWindow) else { return }
        let isShift = event.modifierFlags.contains(.shift)
        let pt = isShift ? AnnotationRenderer.snapPoint(from: item.startPoint, to: rawPt) : rawPt
        item.endPoint = pt
        if item.tool == .highlighter || item.tool == .pen {
            if isShift {
                item.points = [item.startPoint, pt]
            } else {
                item.points.append(pt)
            }
        }
        items.append(item)
        redoItems.removeAll()
        currentItem = nil
        needsDisplay = true
        onHistoryChange?(canUndo, canRedo)
    }

    override func flagsChanged(with event: NSEvent) {
        super.flagsChanged(with: event)
        guard var item = currentItem,
              let windowPoint = window?.mouseLocationOutsideOfEventStream,
              let rawPt = toImagePoint(windowPoint) else { return }
        let isShift = event.modifierFlags.contains(.shift)
        let pt = isShift ? AnnotationRenderer.snapPoint(from: item.startPoint, to: rawPt) : rawPt
        item.endPoint = pt
        if item.tool == .highlighter || item.tool == .pen {
            if isShift {
                item.points = [item.startPoint, pt]
            }
        }
        currentItem = item
        needsDisplay = true
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
            AnnotationRenderer.render(item: item, in: context)
        }
        context.restoreGState()
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
            AnnotationRenderer.render(item: item, in: cg)
        }

        NSGraphicsContext.restoreGraphicsState()

        let result = NSImage(size: baseImage.size)
        result.addRepresentation(rep)
        return result
    }
}
