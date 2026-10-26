import AppKit

/// Native event handlers and menus, exercised without showing a window or palette.
enum AnnotationChecks {
    static func run(directory: URL) throws -> Int {
        let outline = NSBitmapImageRep(data: AnnotationTool.rect.icon.image().tiffRepresentation!)!
        let filled = NSBitmapImageRep(data: AnnotationTool.filledRect.icon.image().tiffRepresentation!)!
        precondition(outline.pixelsWide == filled.pixelsWide && outline.pixelsHigh == filled.pixelsHigh)
        precondition(outline.colorAt(x: outline.pixelsWide / 2, y: outline.pixelsHigh / 2)!.alphaComponent < 0.01)
        precondition(filled.colorAt(x: filled.pixelsWide / 2, y: filled.pixelsHigh / 2)!.alphaComponent > 0.99,
                     "Filled Rectangle needs a filled square icon, not a bucket")
        print("PASS matching outline/filled square icons: empty and opaque centers")
        let image = NSImage(size: NSSize(width: 240, height: 160), flipped: false) { rect in
            NSColor.white.setFill()
            rect.fill()
            return true
        }
        let toolbar = ScreenshotEditorToolbar()
        var selected: AnnotationTool?
        var width: CGFloat?
        toolbar.onSelectTool = { selected = $0 }
        toolbar.onSelectLineWidth = { width = $0 }
        for tool in AnnotationTool.allCases {
            let menu = toolbar.makeWidthMenu(for: tool)
            if tool.usesLineWidth {
                let value = tool.lineWidths.last!
                let index = menu.items.firstIndex { ($0.representedObject as? NSNumber)?.doubleValue == Double(value) }!
                menu.performActionForItem(at: index)
                precondition(selected == tool && width == value && toolbar.lineWidth(for: tool) == value)
                let updated = toolbar.makeWidthMenu(for: tool)
                precondition(updated.items.filter { $0.state == .on }.count == 1)
            } else {
                precondition(menu.items.allSatisfy { $0.action == nil }, "Fill must not advertise a no-op width")
            }
        }
        precondition(toolbar.lineWidth(for: .pen) == 16 && toolbar.lineWidth(for: .highlighter) == 40)
        toolbar.selectLineWidth(.nan, for: .pen)
        precondition(toolbar.lineWidth(for: .pen) == 16, "Invalid width must preserve the selection")
        print("PASS tool width menus: callbacks, per-tool memory, checked state, marker range and solid fill")

        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 280, height: 200),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        let canvas = AnnotationCanvasView(image: image)
        window.contentView = canvas
        func event(_ type: NSEvent.EventType, _ point: CGPoint) -> NSEvent {
            let location = canvas.convert(NSPoint(x: point.x + 20, y: point.y + 20), to: nil)
            return NSEvent.mouseEvent(with: type, location: location, modifierFlags: [], timestamp: 0,
                                     windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        }
        func draw(_ tool: AnnotationTool, _ lineWidth: CGFloat, _ start: CGPoint, _ end: CGPoint) {
            canvas.activeTool = tool
            canvas.activeLineWidth = lineWidth
            canvas.mouseDown(with: event(.leftMouseDown, start))
            canvas.mouseDragged(with: event(.leftMouseDragged, end))
            canvas.mouseUp(with: event(.leftMouseUp, end))
        }
        draw(.line, 2, CGPoint(x: 30, y: 40), CGPoint(x: 200, y: 40))
        precondition(canvas.items.count == 1 && canvas.items[0].lineWidth == 2)
        let menu = canvas.widthMenu(at: CGPoint(x: 100, y: 40))!
        menu.performActionForItem(at: menu.items.firstIndex { $0.title == "10 pt" }!)
        precondition(canvas.items[0].lineWidth == 10)
        canvas.undo()
        precondition(canvas.items[0].lineWidth == 2 && canvas.canRedo)
        canvas.redo()
        precondition(canvas.items[0].lineWidth == 10)
        draw(.arrow, 3.5, CGPoint(x: 30, y: 120), CGPoint(x: 200, y: 120))
        canvas.undo()
        canvas.setLineWidth(6, at: 0)
        precondition(!canvas.canRedo, "An edit after Undo must discard the old redo branch")
        canvas.undo()
        precondition(canvas.items[0].lineWidth == 10)
        canvas.undo()
        precondition(canvas.items[0].lineWidth == 2)
        canvas.undo()
        precondition(canvas.items.isEmpty)
        canvas.redo()
        precondition(canvas.items.count == 1 && canvas.items[0].lineWidth == 2)
        draw(.line, 3.5, CGPoint(x: 30, y: 40), CGPoint(x: 200, y: 40))
        let topMenu = canvas.widthMenu(at: CGPoint(x: 100, y: 40))!
        topMenu.performActionForItem(at: topMenu.items.firstIndex { $0.title == "16 pt" }!)
        precondition(canvas.items[0].lineWidth == 2 && canvas.items[1].lineWidth == 16,
                     "Right-click must edit the topmost matching annotation only")
        precondition(canvas.widthMenu(at: CGPoint(x: 100, y: 100)) == nil)
        draw(.filledRect, 3.5, CGPoint(x: 70, y: 60), CGPoint(x: 150, y: 120))
        let fillMenu = canvas.widthMenu(at: CGPoint(x: 100, y: 80))!
        precondition(fillMenu.items.allSatisfy { $0.action == nil })
        canvas.setLineWidth(16, at: 2)
        precondition(canvas.items[2].lineWidth == 3.5)
        let fillPixel = NSBitmapImageRep(data: canvas.renderAnnotatedImage().tiffRepresentation!)!
            .colorAt(x: 100, y: 80)!.usingColorSpace(.deviceRGB)!
        precondition(fillPixel.redComponent > 0.8 && fillPixel.greenComponent < 0.6, "Solid fill must remain solid")
        print("PASS annotation context width, hit testing, overlap priority, fill and edit Undo/Redo")

        canvas.clear()
        draw(.highlighter, 8, CGPoint(x: 30, y: 80), CGPoint(x: 200, y: 80))
        let thin = NSBitmapImageRep(data: canvas.renderAnnotatedImage().tiffRepresentation!)!
        canvas.setLineWidth(40, at: 0)
        let thick = NSBitmapImageRep(data: canvas.renderAnnotatedImage().tiffRepresentation!)!
        let thinPixel = thin.colorAt(x: 100, y: 70)!.usingColorSpace(.deviceRGB)!
        let thickPixel = thick.colorAt(x: 100, y: 70)!.usingColorSpace(.deviceRGB)!
        precondition(thinPixel.greenComponent > 0.95 && thickPixel.greenComponent < 0.9,
                     "Marker width must affect exported pixels, including the smaller presets")
        try thick.representation(using: .png, properties: [:])!.write(to: directory.appendingPathComponent("annotation-marker-40.png"))
        print("PASS actual marker thickness in exported pixels")

        let controller = ScreenshotEditorWindowController(image: image)
        let editorWindow = controller.window!
        let content = editorWindow.contentView!
        let editorToolbar = PanelPreview.descendants(content).compactMap { $0 as? ScreenshotEditorToolbar }.first!
        let editorCanvas = PanelPreview.descendants(content).compactMap { $0 as? AnnotationCanvasView }.first!
        editorToolbar.selectLineWidth(6, for: .arrow)
        precondition(editorCanvas.activeTool == .arrow && editorCanvas.activeLineWidth == 6)
        editorToolbar.selectLineWidth(16, for: .pen)
        let arrowButton = PanelPreview.descendants(editorToolbar).compactMap { $0 as? AnnotationToolButton }
            .first { $0.tag == AnnotationTool.arrow.rawValue }!
        arrowButton.performClick(nil)
        precondition(editorCanvas.activeTool == .arrow && editorCanvas.activeLineWidth == 6,
                     "Changing tools must restore that tool's width on the actual canvas")
        for value: CGFloat in [620, 1000, 680, 719, 720, 620] {
            editorWindow.setContentSize(NSSize(width: value, height: 440))
            content.layoutSubtreeIfNeeded()
            content.layoutSubtreeIfNeeded()
            precondition(editorToolbar.frame.height == (value < 720 ? 80 : 44),
                         "Editor must reserve the adaptive toolbar height")
            verifyToolbar(editorToolbar)
        }
        print("PASS actual editor reflow at 620/680/719/720/1000 pt, with reserved canvas space")

        let secondEditor = ScreenshotEditorWindowController(image: image)
        var firstClosed = 0
        var secondClosed = 0
        controller.onCancel = { firstClosed += 1 }
        secondEditor.onCancel = { secondClosed += 1 }
        let closeKey = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command,
                                        timestamp: 0, windowNumber: secondEditor.window!.windowNumber,
                                        context: nil, characters: "w", charactersIgnoringModifiers: "w", isARepeat: false, keyCode: 13)!
        precondition(secondEditor.window!.performKeyEquivalent(with: closeKey))
        precondition(secondClosed == 1 && firstClosed == 0, "Command-W must close only its editor")
        editorToolbar.selectLineWidth(10, for: .line)
        precondition(editorCanvas.activeTool == .line && editorCanvas.activeLineWidth == 10,
                     "Closing another editor must preserve this editor's handlers")
        editorWindow.cancelOperation(nil)
        precondition(firstClosed == 1, "Escape/cancel must close its editor")
        print("PASS independent editor handlers and Command-W / Escape close callbacks")

        var count = 1
        for appearance: NSAppearance.Name in [.aqua, .darkAqua] {
            for size: CGFloat in [620, 680, 720, 1000] {
                let previewWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: size, height: 80),
                                             styleMask: [.borderless], backing: .buffered, defer: false)
                let preview = ScreenshotEditorToolbar()
                previewWindow.contentView = preview
                previewWindow.appearance = NSAppearance(named: appearance)
                preview.selectLineWidth(6, for: .arrow)
                preview.updateColorSelection(activeColor: NSColor(calibratedRed: 0.65, green: 0.3, blue: 0.8, alpha: 1))
                preview.layoutSubtreeIfNeeded()
                previewWindow.setContentSize(NSSize(width: size, height: preview.preferredHeight))
                preview.layoutSubtreeIfNeeded()
                verifyToolbar(preview)
                let rainbow = PanelPreview.descendants(preview).compactMap { $0 as? CustomColorButton }.first!
                precondition(rainbow.selectedColor != nil && rainbow.state == .on)
                precondition(!PanelPreview.descendants(preview).contains { $0 is NSColorWell }, "The solid color-well square must be removed")
                let bitmap = preview.bitmapImageRepForCachingDisplay(in: preview.bounds)!
                preview.cacheDisplay(in: preview.bounds, to: bitmap)
                let theme = appearance == .aqua ? "light" : "dark"
                let name = "editor-controls-\(theme)-\(Int(size))"
                try bitmap.representation(using: .png, properties: [:])!.write(to: directory.appendingPathComponent(name + ".png"))
                count += 1
                print("PASS \(name): adaptive grouping, no redundant width control, custom rainbow state")
            }
        }
        return count
    }

    private static func verifyToolbar(_ toolbar: ScreenshotEditorToolbar) {
        let controls = PanelPreview.descendants(toolbar).compactMap { $0 as? NSControl }.filter { !$0.isHiddenOrHasHiddenAncestor }
        for control in controls {
            let rect = toolbar.convert(control.bounds, from: control)
            precondition(rect.minX >= 0 && rect.maxX <= toolbar.bounds.width + 0.5
                         && rect.minY >= 0 && rect.maxY <= toolbar.bounds.height + 0.5,
                         "Toolbar control escapes its bounds: \(control) \(rect) in \(toolbar.bounds)")
        }
        precondition(controls.filter { $0 is AnnotationToolButton }.count == 6)
        precondition(controls.filter { $0 is CustomColorButton }.count == 1)
        precondition(!controls.contains { $0 is NSPopUpButton }, "Width belongs in context menus only")
    }
}
