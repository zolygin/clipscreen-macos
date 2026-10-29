import AppKit

/// Offscreen interaction and export checks; never shows or activates a window.
enum EraserChecks {
    static func run(directory: URL) throws -> Int {
        let image = NSImage(size: NSSize(width: 240, height: 160), flipped: false) { rect in
            NSColor.white.setFill(); rect.fill()
            NSColor.lightGray.setFill()
            for x in stride(from: 0, to: 240, by: 8) {
                NSRect(x: x, y: 0, width: 4, height: 160).fill()
            }
            return true
        }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 280, height: 200),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        let canvas = AnnotationCanvasView(image: image)
        window.contentView = canvas
        func event(_ type: NSEvent.EventType, _ point: CGPoint) -> NSEvent {
            let rect = canvas.imageRect
            let location = canvas.convert(NSPoint(x: rect.minX + point.x * rect.width / image.size.width,
                                                 y: rect.minY + point.y * rect.height / image.size.height), to: nil)
            return NSEvent.mouseEvent(with: type, location: location, modifierFlags: [], timestamp: 0,
                                     windowNumber: window.windowNumber, context: nil, eventNumber: 0,
                                     clickCount: 1, pressure: 1)!
        }
        func click(_ point: CGPoint) {
            canvas.mouseDown(with: event(.leftMouseDown, point))
            canvas.mouseUp(with: event(.leftMouseUp, point))
        }
        func draw(_ tool: AnnotationTool, from start: CGPoint, to end: CGPoint, mode: RectangleFillMode = .solid) {
            canvas.activeTool = tool
            canvas.activeFillMode = mode
            canvas.activeLineWidth = 1
            canvas.mouseDown(with: event(.leftMouseDown, start))
            canvas.mouseDragged(with: event(.leftMouseDragged, end))
            canvas.mouseUp(with: event(.leftMouseUp, end))
        }
        func pixels() -> Data {
            let bitmap = NSBitmapImageRep(data: canvas.renderAnnotatedImage().tiffRepresentation!)!
            return Data(bytes: bitmap.bitmapData!, count: bitmap.bytesPerRow * bitmap.pixelsHigh)
        }
        let original = pixels()
        for tool in AnnotationTool.allCases where tool != .eraser {
            canvas.clear()
            if tool == .text {
                canvas.beginText(at: CGPoint(x: 40, y: 120))
                canvas.textEditor!.insertText("Remove me", replacementRange: NSRange(location: NSNotFound, length: 0))
                canvas.finishTextEditing()
            } else {
                draw(tool, from: CGPoint(x: 40, y: 60), to: CGPoint(x: 180, y: 100))
            }
            let before = canvas.items
            precondition(before.count == 1)
            let hit: CGPoint
            if tool == .text {
                let rect = AnnotationRenderer.textRect(for: before[0]); hit = CGPoint(x: rect.midX, y: rect.midY)
            } else { hit = CGPoint(x: 110, y: tool == .rect ? 60 : 80) }
            canvas.activeTool = .eraser
            click(hit)
            precondition(canvas.items.isEmpty && canvas.canUndo, "Eraser must delete the entire \(tool.title)")
            precondition(pixels() == original, "Deleting an annotation must restore original exported pixels")
            canvas.undo(); precondition(canvas.items == before && canvas.canRedo)
            canvas.redo(); precondition(canvas.items.isEmpty)
        }
        draw(.filledRect, from: CGPoint(x: 40, y: 40), to: CGPoint(x: 200, y: 120), mode: .blur)
        let blur = canvas.items
        precondition(pixels() != original, "The blur fixture must visibly change exported pixels")
        canvas.activeTool = .eraser; click(CGPoint(x: 100, y: 80))
        precondition(canvas.items.isEmpty && pixels() == original)
        canvas.undo(); precondition(canvas.items == blur)
        canvas.redo(); precondition(canvas.items.isEmpty)
        print("PASS eraser: all annotation tools and blur, full-object deletion, Undo/Redo and original export pixels")

        draw(.line, from: CGPoint(x: 30, y: 80), to: CGPoint(x: 210, y: 80))
        canvas.activeColor = .systemBlue
        draw(.line, from: CGPoint(x: 30, y: 80), to: CGPoint(x: 210, y: 80))
        let overlap = canvas.items
        canvas.activeTool = .eraser; click(CGPoint(x: 100, y: 80))
        precondition(canvas.items == Array(overlap.dropLast()), "Only the topmost hit annotation may be removed")
        canvas.undo(); precondition(canvas.items == overlap)
        var updates = 0
        canvas.onHistoryChange = { _, _ in updates += 1 }
        click(CGPoint(x: 100, y: 20))
        click(CGPoint(x: -10, y: -10))
        precondition(canvas.items == overlap && canvas.canRedo && updates == 0,
                     "Empty/outside clicks must preserve both data and the redo branch")
        canvas.redo(); precondition(canvas.items == Array(overlap.dropLast()))
        canvas.undo(); precondition(canvas.items == overlap && canvas.canRedo)
        canvas.activeTool = .eraser; click(CGPoint(x: 100, y: 80))
        precondition(canvas.items == Array(overlap.dropLast()) && !canvas.canRedo,
                     "A new deletion must discard an old redo branch")
        click(CGPoint(x: 100, y: 80)); precondition(canvas.items.isEmpty)
        print("PASS eraser: topmost overlap, empty/outside clicks and history branching")

        draw(.line, from: CGPoint(x: 30, y: 50), to: CGPoint(x: 210, y: 50))
        draw(.line, from: CGPoint(x: 30, y: 110), to: CGPoint(x: 210, y: 110))
        let untouched = canvas.items[1]
        canvas.activeTool = .eraser
        canvas.mouseDown(with: event(.leftMouseDown, CGPoint(x: 100, y: 50)))
        canvas.mouseDragged(with: event(.leftMouseDragged, CGPoint(x: 100, y: 110)))
        canvas.mouseUp(with: event(.leftMouseUp, CGPoint(x: 100, y: 110)))
        precondition(canvas.items == [untouched], "Dragging Eraser must not delete other annotations or create an eraser item")
        canvas.undo(); precondition(canvas.items.count == 2, "One click must be exactly one Undo step")
        canvas.clear()
        draw(.line, from: CGPoint(x: 30, y: 80), to: CGPoint(x: 210, y: 80))
        draw(.rect, from: CGPoint(x: 40, y: 40), to: CGPoint(x: 200, y: 120))
        let outline = canvas.items[1]
        canvas.activeTool = .eraser; click(CGPoint(x: 100, y: 80))
        precondition(canvas.items == [outline], "A hollow rectangle's interior must not count as a hit on its outline")
        print("PASS eraser: click-only gesture, a single Undo step, and exact hollow-shape hit testing")

        for size in [NSSize(width: 140, height: 120), NSSize(width: 1000, height: 640)] {
            canvas.clear()
            window.setContentSize(size)
            draw(.line, from: CGPoint(x: 30, y: 80), to: CGPoint(x: 210, y: 80))
            let scale = canvas.imageRect.width / image.size.width
            canvas.activeTool = .eraser
            click(CGPoint(x: 100, y: 80 + 12 / scale))
            precondition(canvas.items.count == 1, "Hit tolerance must not grow with zoom")
            click(CGPoint(x: 100, y: 80 + 5 / scale))
            precondition(canvas.items.isEmpty, "Hit tolerance must stay usable on a scaled-down image")
        }
        print("PASS eraser: six-screen-point hit tolerance at small and large canvas scales")

        let controller = ScreenshotEditorWindowController(image: image)
        let editorWindow = controller.window!
        let content = editorWindow.contentView!
        let toolbar = PanelPreview.descendants(content).compactMap { $0 as? ScreenshotEditorToolbar }.first!
        let editorCanvas = PanelPreview.descendants(content).compactMap { $0 as? AnnotationCanvasView }.first!
        let eraser = PanelPreview.descendants(toolbar).compactMap { $0 as? AnnotationToolButton }
            .first { $0.tag == AnnotationTool.eraser.rawValue }!
        toolbar.onSelectTool?(.text)
        editorCanvas.beginText(at: CGPoint(x: 40, y: 120))
        editorCanvas.textEditor!.insertText("Keep this edit", replacementRange: NSRange(location: NSNotFound, length: 0))
        eraser.performClick(nil)
        precondition(editorCanvas.textEditor == nil && editorCanvas.items.first?.text == "Keep this edit")
        precondition(editorCanvas.activeTool == .eraser && eraser.state == .on && eraser.widthMenu == nil)
        precondition(eraser.accessibilityValue() as? String == "Selected")
        precondition(!AnnotationTool.eraser.usesLineWidth && toolbar.makeWidthMenu(for: .eraser).items.isEmpty)
        precondition(eraser.toolTip?.contains("click an annotation") == true)
        print("PASS eraser: actual toolbar action, text commit, selected/accessibility state, and no width menu")
        var count = 0
        for appearance: NSAppearance.Name in [.aqua, .darkAqua] {
            for width: CGFloat in [620, 780, 960, 1000] {
                editorWindow.appearance = NSAppearance(named: appearance)
                editorWindow.setContentSize(NSSize(width: width, height: 440))
                content.layoutSubtreeIfNeeded(); content.layoutSubtreeIfNeeded()
                precondition(toolbar.frame.height == (width < 780 ? 80 : 44))
                let bitmap = toolbar.bitmapImageRepForCachingDisplay(in: toolbar.bounds)!
                toolbar.cacheDisplay(in: toolbar.bounds, to: bitmap)
                let theme = appearance == .aqua ? "light" : "dark"
                try bitmap.representation(using: .png, properties: [:])!
                    .write(to: directory.appendingPathComponent("editor-eraser-\(theme)-\(Int(width)).png"))
                count += 1
            }
        }
        return count
    }
}
