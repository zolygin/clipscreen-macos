// Offscreen artwork renderer only. Does not build or launch Clipscreen.
// Usage: xcrun swift scripts/render-dmg.swift <output-directory>
import AppKit

let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
let width = 640, height = 400
let preview = CommandLine.arguments.contains("--preview")
func color(_ value: UInt32) -> NSColor {
    NSColor(srgbRed: CGFloat((value >> 16) & 255) / 255,
            green: CGFloat((value >> 8) & 255) / 255,
            blue: CGFloat(value & 255) / 255, alpha: 1)
}
func text(_ string: String, y: CGFloat, size: CGFloat, weight: NSFont.Weight, ink: UInt32) {
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center
    (string as NSString).draw(in: NSRect(x: 32, y: y, width: 576, height: 36), withAttributes: [
        .font: NSFont.systemFont(ofSize: size, weight: weight),
        .foregroundColor: color(ink), .paragraphStyle: paragraph
    ])
}
let artwork = NSImage(size: NSSize(width: width, height: height))
for scale in [1, 2] {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width * scale, pixelsHigh: height * scale,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let context = NSGraphicsContext.current!.cgContext
    context.scaleBy(x: CGFloat(scale), y: CGFloat(scale))
    context.translateBy(x: 0, y: CGFloat(height))
    context.scaleBy(x: 1, y: -1)
    color(0xF5F5F7).setFill()
    NSRect(x: 0, y: 0, width: width, height: height).fill()
    // Draw text in a flipped AppKit context so glyphs remain upright.
    let flipped = NSGraphicsContext(cgContext: context, flipped: true)
    NSGraphicsContext.current = flipped
    text("Install Clipscreen", y: 38, size: 24, weight: .semibold, ink: 0x242426)
    text("Drag Clipscreen to Applications", y: 78, size: 16, weight: .regular, ink: 0x51515A)
    color(0x767680).setStroke()
    let arrow = NSBezierPath()
    arrow.lineWidth = 3
    arrow.lineCapStyle = .round
    arrow.lineJoinStyle = .round
    arrow.move(to: NSPoint(x: 282, y: 210))
    arrow.line(to: NSPoint(x: 358, y: 210))
    arrow.move(to: NSPoint(x: 344, y: 196))
    arrow.line(to: NSPoint(x: 358, y: 210))
    arrow.line(to: NSPoint(x: 344, y: 224))
    arrow.stroke()
    text("Then open Clipscreen from Applications.", y: 340, size: 13, weight: .regular, ink: 0x51515A)
    if preview {
        let project = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        for (name, x, file) in [
            ("Clipscreen", CGFloat(170), project.appendingPathComponent(".build/Clipscreen.app").path),
            ("Applications", CGFloat(470), "/Applications")
        ] {
            let icon = name == "Clipscreen"
                ? NSImage(contentsOf: project.appendingPathComponent("Resources/Clipscreen.icns"))!
                : NSWorkspace.shared.icon(forFile: file)
            icon.draw(in: NSRect(x: x - 56, y: 154, width: 112, height: 112),
                from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center
            (name as NSString).draw(in: NSRect(x: x - 100, y: 278, width: 200, height: 24), withAttributes: [
                .font: NSFont.systemFont(ofSize: 14), .foregroundColor: color(0x242426), .paragraphStyle: paragraph
            ])
        }
    }
    NSGraphicsContext.restoreGraphicsState()
    // Verify the arrow occupies the same logical position at both pixel scales.
    let sample = rep.colorAt(x: 300 * scale, y: 210 * scale)!.usingColorSpace(.sRGB)!
    guard abs(sample.redComponent - 118.0 / 255.0) < 0.02,
          abs(sample.greenComponent - 118.0 / 255.0) < 0.02,
          abs(sample.blueComponent - 128.0 / 255.0) < 0.02 else {
        throw NSError(domain: "ClipscreenArtwork", code: 1, userInfo: [
            NSLocalizedDescriptionKey: "Incorrect installer artwork scale at \(scale)x"
        ])
    }
    // Set logical size after drawing: setting it before creating the bitmap
    // context also scales its CTM, doubling the explicit Retina transform.
    rep.size = NSSize(width: width, height: height)
    artwork.addRepresentation(rep)
    try rep.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent("\(preview ? "installer-preview" : "background")-\(scale)x.png"))
}

if !preview {
    try artwork.tiffRepresentation(using: .lzw, factor: 1)!.write(to: output.appendingPathComponent("background.tiff"))
}
