import AppKit

enum AnnotationTool: Int, CaseIterable {
    case pen
    case arrow
    case line
    case rect
    case filledRect
    case highlighter
    case text

    var icon: LucideIcon {
        switch self {
        case .pen: return .penLine
        case .arrow: return .arrowUpRight
        case .line: return .slash
        case .rect: return .square
        case .filledRect: return .squareFilled
        case .text: return .type
        case .highlighter: return .highlighter
        }
    }

    var title: String {
        switch self {
        case .pen: return "Pencil"
        case .arrow: return "Arrow"
        case .line: return "Line"
        case .rect: return "Rectangle Outline"
        case .filledRect: return "Filled Rectangle"
        case .text: return "Text"
        case .highlighter: return "Highlighter"
        }
    }

    var usesLineWidth: Bool { self != .filledRect && self != .text }
    var defaultLineWidth: CGFloat { self == .highlighter ? 20 : 3.5 }
    var lineWidths: [CGFloat] { self == .highlighter ? [8, 12, 20, 28, 40] : [1, 2, 3.5, 6, 10, 16] }
}

enum AnnotationFont: Int, CaseIterable {
    case system, serif, monospaced, rounded, helveticaNeue, avenirNext, georgia, menlo

    static var available: [AnnotationFont] { allCases.filter { $0.isAvailable } }
    var isAvailable: Bool { postScriptName.map { NSFont(name: $0, size: 13) != nil } ?? true }
    private var postScriptName: String? {
        switch self {
        case .helveticaNeue: return "HelveticaNeue"
        case .avenirNext: return "AvenirNext-Regular"
        case .georgia: return "Georgia"
        case .menlo: return "Menlo-Regular"
        default: return nil
        }
    }

    var title: String {
        switch self {
        case .system: return "System"
        case .serif: return "Serif"
        case .monospaced: return "Monospaced"
        case .rounded: return "Rounded"
        case .helveticaNeue: return "Helvetica Neue"
        case .avenirNext: return "Avenir Next"
        case .georgia: return "Georgia"
        case .menlo: return "Menlo"
        }
    }

    func font(size: CGFloat) -> NSFont {
        let base = NSFont.systemFont(ofSize: size)
        if let name = postScriptName { return NSFont(name: name, size: size) ?? base }
        let design: NSFontDescriptor.SystemDesign
        switch self {
        case .system: return base
        case .serif: design = .serif
        case .monospaced: design = .monospaced
        case .rounded: design = .rounded
        default: return base
        }
        return base.fontDescriptor.withDesign(design).flatMap { NSFont(descriptor: $0, size: size) } ?? base
    }
}

struct AnnotationTextStyle: Equatable {
    static let sizes: [CGFloat] = [12, 16, 20, 24, 32, 48, 64, 96]
    var font: AnnotationFont = .system
    var size: CGFloat = 24
}

struct AnnotationItem {
    let tool: AnnotationTool
    var startPoint: CGPoint
    var endPoint: CGPoint
    var points: [CGPoint]
    var color: NSColor
    var lineWidth: CGFloat
    var text: String = ""
    var textStyle = AnnotationTextStyle()
    var textMaxWidth: CGFloat = 400
}

enum AnnotationRenderer {
    static func attributedText(for item: AnnotationItem) -> NSAttributedString {
        NSAttributedString(string: item.text, attributes: [.font: item.textStyle.font.font(size: item.textStyle.size),
                                                          .foregroundColor: item.color])
    }

    /// Text anchors use the top-left corner in the image's bottom-up coordinate system.
    static func textRect(for item: AnnotationItem) -> CGRect {
        let measured = attributedText(for: item).boundingRect(
            with: NSSize(width: max(1, item.textMaxWidth), height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading])
        let height = max(item.textStyle.size * 1.25, ceil(measured.height))
        return CGRect(x: item.startPoint.x, y: item.startPoint.y - height,
                      width: min(item.textMaxWidth, max(item.textStyle.size, ceil(measured.width))), height: height)
    }

    static func contains(_ point: CGPoint, in item: AnnotationItem, tolerance: CGFloat) -> Bool {
        if item.tool == .text { return textRect(for: item).insetBy(dx: -tolerance, dy: -tolerance).contains(point) }
        let path = CGMutablePath()
        if item.tool == .rect || item.tool == .filledRect {
            let rect = CGRect(x: min(item.startPoint.x, item.endPoint.x), y: min(item.startPoint.y, item.endPoint.y),
                              width: max(1, abs(item.endPoint.x - item.startPoint.x)),
                              height: max(1, abs(item.endPoint.y - item.startPoint.y)))
            path.addRoundedRect(in: rect, cornerWidth: 3, cornerHeight: 3)
            if item.tool == .filledRect { return path.contains(point) }
        } else {
            let points = (item.tool == .pen || item.tool == .highlighter) && item.points.count > 1
                ? item.points : [item.startPoint, item.endPoint]
            path.addLines(between: points)
            if item.tool == .arrow {
                let angle = atan2(item.endPoint.y - item.startPoint.y, item.endPoint.x - item.startPoint.x)
                let length = max(14, item.lineWidth * 4)
                let head = CGMutablePath()
                head.move(to: item.endPoint)
                for direction: CGFloat in [-1, 1] {
                    head.addLine(to: CGPoint(x: item.endPoint.x - length * cos(angle + direction * .pi / 6),
                                            y: item.endPoint.y - length * sin(angle + direction * .pi / 6)))
                }
                head.closeSubpath()
                if head.contains(point) { return true }
                path.addPath(head)
            }
        }
        return path.copy(strokingWithWidth: item.lineWidth + tolerance * 2, lineCap: .round, lineJoin: .round, miterLimit: 10)
            .contains(point)
    }

    static func snapPoint(from start: CGPoint, to current: CGPoint) -> CGPoint {
        let dx = current.x - start.x
        let dy = current.y - start.y
        let distance = hypot(dx, dy)
        guard distance > 0 else { return current }
        let angle = atan2(dy, dx)
        let step = CGFloat.pi / 4.0
        let snappedAngle = (angle / step).rounded() * step
        return CGPoint(
            x: start.x + distance * cos(snappedAngle),
            y: start.y + distance * sin(snappedAngle)
        )
    }

    static func render(item: AnnotationItem, in context: CGContext) {
        context.saveGState()
        let color = item.color

        switch item.tool {
        case .text:
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
            attributedText(for: item).draw(with: textRect(for: item), options: [.usesLineFragmentOrigin, .usesFontLeading])
            NSGraphicsContext.restoreGraphicsState()

        case .pen:
            context.setStrokeColor(color.cgColor)
            context.setLineWidth(item.lineWidth)
            context.setLineCap(.round)
            context.setLineJoin(.round)
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
            context.setLineWidth(item.lineWidth)
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
        let headAngle = CGFloat.pi / 6

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
}
