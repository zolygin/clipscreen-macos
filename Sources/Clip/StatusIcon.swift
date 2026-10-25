import AppKit

enum StatusIcon {
    static func clipboard(paused: Bool = false) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: true) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            ctx.saveGState()

            // Scale standard Lucide 24x24 viewBox into 15x15 centered in 18x18
            let scale: CGFloat = 15.0 / 24.0
            ctx.translateBy(x: 1.5, y: 1.5)
            ctx.scaleBy(x: scale, y: scale)

            ctx.setLineCap(.round)
            ctx.setLineJoin(.round)
            ctx.setLineWidth(2.0)
            NSColor.black.setStroke()

            // Lucide Clip: rect width="8" height="4" x="8" y="2" rx="1" ry="1"
            let clipRect = CGRect(x: 8, y: 2, width: 8, height: 4)
            let clipPath = CGPath(roundedRect: clipRect, cornerWidth: 1, cornerHeight: 1, transform: nil)
            ctx.addPath(clipPath)
            ctx.strokePath()

            // Lucide Board: M16 4h2a2 2 0 0 1 2 2v14a2 2 0 0 1-2 2H6a2 2 0 0 1-2-2V6a2 2 0 0 1 2-2h2
            let boardPath = CGMutablePath()
            boardPath.move(to: CGPoint(x: 16, y: 4))
            boardPath.addLine(to: CGPoint(x: 18, y: 4))
            boardPath.addArc(tangent1End: CGPoint(x: 20, y: 4), tangent2End: CGPoint(x: 20, y: 6), radius: 2)
            boardPath.addLine(to: CGPoint(x: 20, y: 20))
            boardPath.addArc(tangent1End: CGPoint(x: 20, y: 22), tangent2End: CGPoint(x: 18, y: 22), radius: 2)
            boardPath.addLine(to: CGPoint(x: 6, y: 22))
            boardPath.addArc(tangent1End: CGPoint(x: 4, y: 22), tangent2End: CGPoint(x: 4, y: 20), radius: 2)
            boardPath.addLine(to: CGPoint(x: 4, y: 6))
            boardPath.addArc(tangent1End: CGPoint(x: 4, y: 4), tangent2End: CGPoint(x: 6, y: 4), radius: 2)
            boardPath.addLine(to: CGPoint(x: 8, y: 4))
            ctx.addPath(boardPath)
            ctx.strokePath()

            if paused {
                // Subtle pause bars centered inside clipboard
                ctx.setLineWidth(2.2)
                ctx.beginPath()
                ctx.move(to: CGPoint(x: 10, y: 10))
                ctx.addLine(to: CGPoint(x: 10, y: 16))
                ctx.move(to: CGPoint(x: 14, y: 10))
                ctx.addLine(to: CGPoint(x: 14, y: 16))
                ctx.strokePath()
            }

            ctx.restoreGState()
            return true
        }
        image.isTemplate = true
        return image
    }
}
