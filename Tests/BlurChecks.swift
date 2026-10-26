import AppKit

/// Synthetic pixels and native events only; no user screenshots or clipboard.
enum BlurChecks {
    static func run(directory: URL) throws -> Int {
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 960, pixelsHigh: 600,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        bitmap.size = NSSize(width: 480, height: 300)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        for row in 0..<75 {
            for column in 0..<120 {
                ((row + column) % 2 == 0 ? NSColor.white : NSColor.black).setFill()
                NSRect(x: column * 4, y: row * 4, width: 4, height: 4).fill()
            }
        }
        NSColor.white.setFill(); NSRect(x: 85, y: 135, width: 310, height: 60).fill()
        ("Account: 1234 5678" as NSString).draw(at: NSPoint(x: 105, y: 153),
            withAttributes: [.font: NSFont.systemFont(ofSize: 24), .foregroundColor: NSColor.black])
        NSColor.systemOrange.setFill(); NSRect(x: 0, y: 270, width: 30, height: 30).fill()
        NSColor.systemBlue.setFill(); NSRect(x: 450, y: 0, width: 30, height: 30).fill()
        NSGraphicsContext.restoreGraphicsState()
        let image = NSImage(size: bitmap.size)
        image.addRepresentation(bitmap)
        let controller = ScreenshotEditorWindowController(image: image)
        let window = controller.window!
        window.setContentSize(NSSize(width: 960, height: 520))
        let content = window.contentView!
        content.layoutSubtreeIfNeeded(); content.layoutSubtreeIfNeeded()
        let toolbar = PanelPreview.descendants(content).compactMap { $0 as? ScreenshotEditorToolbar }.first!
        let canvas = PanelPreview.descendants(content).compactMap { $0 as? AnnotationCanvasView }.first!
        let fillButton = PanelPreview.descendants(toolbar).compactMap { $0 as? AnnotationToolButton }
            .first { $0.tag == AnnotationTool.filledRect.rawValue }!
        let menu = toolbar.makeWidthMenu(for: .filledRect)
        menu.performActionForItem(at: menu.items.firstIndex { $0.title == "Blur Area" }!)
        precondition(canvas.activeTool == .filledRect && canvas.activeFillMode == .blur && toolbar.fillMode == .blur)
        precondition(fillButton.accessibilityLabel() == "Blur Area" && fillButton.state == .on)
        precondition(toolbar.makeWidthMenu(for: .filledRect).items.last?.state == .on)
        let chosen = toolbar.makeWidthMenu(for: .filledRect)
        chosen.performActionForItem(at: 0)
        precondition(canvas.activeFillMode == .solid && fillButton.accessibilityLabel() == "Solid Fill")
        print("PASS rectangle context mode actions, checked state, dynamic icon/label and controller wiring")

        func event(_ type: NSEvent.EventType, _ point: CGPoint) -> NSEvent {
            let rect = canvas.imageRect
            let scale = rect.width / image.size.width
            let location = canvas.convert(NSPoint(x: rect.minX + point.x * scale, y: rect.minY + point.y * scale), to: nil)
            return NSEvent.mouseEvent(with: type, location: location, modifierFlags: [], timestamp: 0,
                windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        }
        func draw(_ tool: AnnotationTool, from start: CGPoint, to end: CGPoint) {
            canvas.activeTool = tool
            canvas.activeLineWidth = 6
            canvas.mouseDown(with: event(.leftMouseDown, start))
            canvas.mouseDragged(with: event(.leftMouseDragged, end))
            canvas.mouseUp(with: event(.leftMouseUp, end))
        }
        func pixel(_ output: NSBitmapImageRep, _ point: CGPoint) -> NSColor {
            let x = Int(point.x * 2), y = output.pixelsHigh - 1 - Int(point.y * 2)
            return output.colorAt(x: x, y: y)!.usingColorSpace(.sRGB)!
        }
        func export() -> NSBitmapImageRep { canvas.renderAnnotatedImage().representations.first as! NSBitmapImageRep }
        canvas.activeColor = .systemRed
        draw(.line, from: CGPoint(x: 95, y: 100), to: CGPoint(x: 385, y: 100))
        let before = export()
        toolbar.selectFillMode(.blur)
        // Reverse dragging must produce the same selected region.
        canvas.mouseDown(with: event(.leftMouseDown, CGPoint(x: 400, y: 230)))
        canvas.mouseDragged(with: event(.leftMouseDragged, CGPoint(x: 80, y: 70)))
        let preview = canvas.bitmapImageRepForCachingDisplay(in: canvas.bounds)!
        canvas.cacheDisplay(in: canvas.bounds, to: preview)
        try preview.representation(using: .png, properties: [:])!.write(to: directory.appendingPathComponent("blur-live-preview.png"))
        canvas.mouseUp(with: event(.leftMouseUp, CGPoint(x: 80, y: 70)))
        let blurred = export()
        precondition(blurred.pixelsWide == 960 && blurred.pixelsHigh == 600)
        for point in [CGPoint(x: 240, y: 100), CGPoint(x: 200, y: 210), CGPoint(x: 240, y: 170)] {
            let rect = canvas.imageRect
            let scale = rect.width / image.size.width
            let x = Int((rect.minX + point.x * scale) * CGFloat(preview.pixelsWide) / canvas.bounds.width)
            let y = preview.pixelsHigh - 1 - Int((rect.minY + point.y * scale) * CGFloat(preview.pixelsHigh) / canvas.bounds.height)
            let live = preview.colorAt(x: x, y: y)!.usingColorSpace(.sRGB)!
            let saved = pixel(blurred, point)
            precondition(abs(live.redComponent - saved.redComponent) < 0.05
                && abs(live.greenComponent - saved.greenComponent) < 0.05
                && abs(live.blueComponent - saved.blueComponent) < 0.05,
                "The in-progress Blur preview must match export at \(point): live=\(live), saved=\(saved), source=\(preview.colorSpaceName.rawValue)/\(blurred.colorSpaceName.rawValue), bitmap=\(preview.pixelsWide)x\(preview.pixelsHigh), canvas=\(canvas.bounds), image=\(canvas.imageRect)")
        }
        precondition(canvas.items[1].fillMode == .blur && canvas.items[1].startPoint.x > canvas.items[1].endPoint.x)
        for point in [CGPoint(x: 10, y: 290), CGPoint(x: 465, y: 15), CGPoint(x: 40, y: 140), CGPoint(x: 430, y: 200)] {
            let a = pixel(before, point), b = pixel(blurred, point)
            precondition(abs(a.redComponent - b.redComponent) < 0.02
                && abs(a.greenComponent - b.greenComponent) < 0.02 && abs(a.blueComponent - b.blueComponent) < 0.02,
                "Blur must preserve orientation and pixels outside the selected area")
        }
        let redBefore = pixel(before, CGPoint(x: 240, y: 100))
        let redAfter = pixel(blurred, CGPoint(x: 240, y: 100))
        precondition(redBefore.redComponent - redBefore.greenComponent > 0.5
            && abs(redAfter.redComponent - redAfter.greenComponent) < 0.2,
            "Blur must include earlier annotations, not only the base screenshot")
        let smoothA = pixel(blurred, CGPoint(x: 200, y: 210))
        let smoothB = pixel(blurred, CGPoint(x: 204, y: 210))
        let sharpA = pixel(before, CGPoint(x: 200, y: 210))
        let sharpB = pixel(before, CGPoint(x: 204, y: 210))
        precondition(abs(sharpA.redComponent - sharpB.redComponent) > 0.8
            && abs(smoothA.redComponent - smoothB.redComponent) < 0.08,
            "Gaussian blur must remove the selected region's high-frequency detail")
        precondition(smoothA.alphaComponent > 0.99)
        try blurred.representation(using: .png, properties: [:])!.write(to: directory.appendingPathComponent("blur-export-retina.png"))
        print("PASS real blur/export pixels, earlier annotation coverage, reverse drag, exact region and Retina dimensions")

        let context = canvas.widthMenu(at: CGPoint(x: 240, y: 180))!
        precondition(context.items.last?.state == .on)
        context.performActionForItem(at: 0)
        precondition(canvas.items[1].fillMode == .solid)
        let solid = pixel(export(), CGPoint(x: 240, y: 180))
        precondition(solid.redComponent - solid.greenComponent > 0.5)
        canvas.undo(); precondition(canvas.items[1].fillMode == .blur)
        canvas.redo(); precondition(canvas.items[1].fillMode == .solid)
        canvas.undo()
        canvas.activeColor = .systemBlue
        draw(.line, from: CGPoint(x: 95, y: 120), to: CGPoint(x: 385, y: 120))
        let blue = pixel(export(), CGPoint(x: 240, y: 120))
        precondition(blue.blueComponent - blue.redComponent > 0.5,
                     "Annotations drawn after Blur must remain above it")
        canvas.undo(); canvas.undo()
        precondition(canvas.items.count == 1)
        precondition(pixel(export(), CGPoint(x: 240, y: 100)).redComponent - pixel(export(), CGPoint(x: 240, y: 100)).greenComponent > 0.5)
        canvas.redo(); precondition(canvas.items.count == 2 && canvas.items[1].fillMode == .blur)
        print("PASS existing rectangle mode edits, compositing order and drawing/edit Undo/Redo")

        // Check that idle redraw and area dragging reuse prepared images.
        let render = AnnotationImageRenderer(baseImage: image)
        let one = render.render(canvas.items)
        precondition(render.render(canvas.items) === one, "Unchanged composites should be cached")
        precondition(render.blurredBackdrop(for: canvas.items) === render.blurredBackdrop(for: canvas.items),
                     "Dragging a Blur region must reuse its prepared backdrop")
        let fallback = AnnotationItem(tool: .filledRect, startPoint: .zero, endPoint: CGPoint(x: 30, y: 30),
            points: [], color: .red, lineWidth: 0, fillMode: .blur)
        let failClosed = NSImage(size: NSSize(width: 30, height: 30), flipped: false) { _ in
            AnnotationRenderer.render(item: fallback, in: NSGraphicsContext.current!.cgContext)
            return true
        }
        let covered = NSBitmapImageRep(data: failClosed.tiffRepresentation!)!
            .colorAt(x: 15, y: 15)!.usingColorSpace(.sRGB)!
        precondition(covered.redComponent < 0.01 && covered.alphaComponent > 0.99,
                     "Missing blur output must cover the region instead of revealing the source")
        print("PASS compositor/backdrop cache and opaque filter-failure fallback")

        var count = 2
        for theme: NSAppearance.Name in [.aqua, .darkAqua] {
            window.appearance = NSAppearance(named: theme)
            toolbar.selectFillMode(.blur)
            for width: CGFloat in [620, 960] {
                window.setContentSize(NSSize(width: width, height: 520))
                content.layoutSubtreeIfNeeded(); content.layoutSubtreeIfNeeded()
                let frame = content.bitmapImageRepForCachingDisplay(in: content.bounds)!
                content.cacheDisplay(in: content.bounds, to: frame)
                let name = "editor-blur-\(theme == .aqua ? "light" : "dark")-\(Int(width))"
                try frame.representation(using: .png, properties: [:])!.write(to: directory.appendingPathComponent(name + ".png"))
                count += 1
            }
        }
        let available = AnnotationFont.available
        let catalogBase = NSImage(size: NSSize(width: 640, height: CGFloat(available.count) * 70 + 40), flipped: false) { rect in
            NSColor.white.setFill(); rect.fill(); return true
        }
        let catalog = available.enumerated().map { index, font in
            AnnotationItem(tool: .text, startPoint: CGPoint(x: 25, y: catalogBase.size.height - 25 - CGFloat(index) * 70),
                endPoint: .zero, points: [], color: .black, lineWidth: 0,
                text: "\(font.title) · Привет, Mac", textStyle: AnnotationTextStyle(font: font, size: 26), textMaxWidth: 590)
        }
        let fonts = AnnotationImageRenderer(baseImage: catalogBase).render(catalog)
        try (fonts.representations.first as! NSBitmapImageRep).representation(using: .png, properties: [:])!
            .write(to: directory.appendingPathComponent("annotation-font-catalog.png"))
        window.appearance = NSAppearance(named: .aqua)
        toolbar.onSelectTool?(.text)
        toolbar.selectTextStyle(AnnotationTextStyle(font: .helveticaNeue, size: 24))
        content.layoutSubtreeIfNeeded(); content.layoutSubtreeIfNeeded()
        let fontControl = PanelPreview.descendants(toolbar).compactMap { $0 as? NSPopUpButton }
            .first { $0.accessibilityLabel() == "Text font" }!
        precondition(fontControl.selectedItem?.title == "Helvetica Neue")
        let toolbarImage = toolbar.bitmapImageRepForCachingDisplay(in: toolbar.bounds)!
        toolbar.cacheDisplay(in: toolbar.bounds, to: toolbarImage)
        try toolbarImage.representation(using: .png, properties: [:])!
            .write(to: directory.appendingPathComponent("editor-font-helvetica-light.png"))
        print("PASS expanded font catalog rendered with Cyrillic; Blur light/dark controls at narrow/wide sizes")
        return count + 2
    }
}
