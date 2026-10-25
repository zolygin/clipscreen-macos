import AppKit

enum AnnotationTool: Int, CaseIterable {
    case pen
    case arrow
    case line
    case rect
    case filledRect
    case highlighter

    var symbolName: String {
        switch self {
        case .pen: return "pencil.tip"
        case .arrow: return "arrow.up.right"
        case .line: return "line.diagonal"
        case .rect: return "square"
        case .filledRect: return "square.fill"
        case .highlighter: return "highlighter"
        }
    }

    var title: String {
        switch self {
        case .pen: return "Pencil"
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

enum AnnotationRenderer {
    static func render(item: AnnotationItem, in context: CGContext) {
        context.saveGState()
        let color = item.color

        switch item.tool {
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
