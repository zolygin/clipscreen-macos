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
            } else if tool == .filledRect {
                precondition(menu.items.map { $0.title } == ["Solid Fill", "Blur Area"])
                precondition(menu.items.first?.state == .on, "Solid Fill must remain the default")
            } else {
                precondition(menu.items.allSatisfy { $0.action == nil }, "Text must not advertise a no-op width")
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
        precondition(fillMenu.items.map { $0.title } == ["Solid Fill", "Blur Area"])
        precondition(fillMenu.items.first?.state == .on)
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

        PresentationChecks.run()
        let controller = ScreenshotEditorWindowController(image: image)
        let editorWindow = controller.window!
        precondition(editorWindow.collectionBehavior.contains(.moveToActiveSpace)
                     && editorWindow.collectionBehavior.contains(.fullScreenAuxiliary))
        precondition(editorWindow.level == .normal, "Presenting an editor must not permanently pin it above other apps")
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
        for value: CGFloat in [620, 1000, 680, 779, 780, 620] {
            editorWindow.setContentSize(NSSize(width: value, height: 440))
            content.layoutSubtreeIfNeeded()
            content.layoutSubtreeIfNeeded()
            precondition(editorToolbar.frame.height == (value < 780 ? 80 : 44),
                         "Editor must reserve the adaptive toolbar height")
            verifyToolbar(editorToolbar)
        }
        print("PASS actual editor reflow at 620/680/779/780/1000 pt, with reserved canvas space")

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
            for size: CGFloat in [620, 680, 780, 1000] {
                let previewWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: size, height: 80),
                                             styleMask: [.borderless], backing: .buffered, defer: false)
                let preview = ScreenshotEditorToolbar()
                preview.frame = NSRect(origin: .zero, size: previewWindow.contentRect(forFrameRect: previewWindow.frame).size)
                preview.autoresizingMask = [.width, .height]
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
        count += try checkText(directory: directory)
        count += try BlurChecks.run(directory: directory)
        return count
    }

    private static func checkText(directory: URL) throws -> Int {
        let image = NSImage(size: NSSize(width: 640, height: 360), flipped: false) { rect in
            NSColor.white.setFill(); rect.fill(); return true
        }
        let controller = ScreenshotEditorWindowController(image: image)
        let window = controller.window!
        let content = window.contentView!
        let canvas = PanelPreview.descendants(content).compactMap { $0 as? AnnotationCanvasView }.first!
        let toolbar = PanelPreview.descendants(content).compactMap { $0 as? ScreenshotEditorToolbar }.first!
        let textButton = PanelPreview.descendants(toolbar).compactMap { $0 as? ClipIconButton }
            .first { $0.accessibilityLabel() == "Text — click the image to type" }!
        textButton.performClick(nil)
        content.layoutSubtreeIfNeeded()
        precondition(canvas.activeTool == .text && toolbar.preferredHeight == 80)
        toolbar.selectTextStyle(AnnotationTextStyle(font: .serif, size: 32))
        precondition(canvas.activeTextStyle == toolbar.textStyle)
        func key(_ code: UInt16, _ chars: String, _ flags: NSEvent.ModifierFlags = []) -> NSEvent {
            NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0,
                            windowNumber: window.windowNumber, context: nil, characters: chars,
                            charactersIgnoringModifiers: chars, isARepeat: false, keyCode: code)!
        }
        func mouse(_ type: NSEvent.EventType, _ point: CGPoint, count: Int = 1) -> NSEvent {
            let rect = canvas.imageRect
            let scale = rect.width / image.size.width
            let location = canvas.convert(NSPoint(x: rect.minX + point.x * scale, y: rect.minY + point.y * scale), to: nil)
            return NSEvent.mouseEvent(with: type, location: location, modifierFlags: [], timestamp: 0,
                                     windowNumber: window.windowNumber, context: nil, eventNumber: 0,
                                     clickCount: count, pressure: 1)!
        }
        // A native text view, not a modal prompt: text remains editable on the canvas.
        canvas.mouseDown(with: mouse(.leftMouseDown, CGPoint(x: 40, y: 300)))
        let editor = canvas.textEditor!
        editor.insertText("Hello, Clipscreen!", replacementRange: NSRange(location: NSNotFound, length: 0))
        editor.keyDown(with: key(36, "\r"))
        editor.insertText("Привет, Mac 👋", replacementRange: NSRange(location: NSNotFound, length: 0))
        precondition(editor.string.contains("\n") && canvas.items.isEmpty)
        precondition(!window.performKeyEquivalent(with: key(36, "\r")), "Return must not copy/close the screenshot during text input")
        precondition(window.performKeyEquivalent(with: key(0, "a", .command)))
        precondition(editor.selectedRange().length == (editor.string as NSString).length)
        precondition(window.performKeyEquivalent(with: key(36, "\r", .command)))
        precondition(canvas.items.count == 1 && canvas.items[0].text.contains("Привет"))
        precondition(canvas.items[0].textStyle == AnnotationTextStyle(font: .serif, size: 32))
        canvas.undo(); precondition(canvas.items.isEmpty)
        canvas.redo(); precondition(canvas.items.count == 1)

        let first = canvas.items[0]
        let rect = AnnotationRenderer.textRect(for: first)
        precondition(AnnotationRenderer.contains(CGPoint(x: rect.midX, y: rect.midY), in: first, tolerance: 0))
        canvas.mouseDown(with: mouse(.leftMouseDown, CGPoint(x: rect.minX + 10, y: rect.maxY - 10), count: 2))
        precondition(canvas.textEditor != nil)
        canvas.textEditor!.string = "Cancelled edit"
        toolbar.selectTextStyle(AnnotationTextStyle(font: .monospaced, size: 48))
        canvas.textEditor!.keyDown(with: key(53, "\u{1b}"))
        precondition(canvas.items[0].text == first.text && canvas.items[0].textStyle == first.textStyle,
                     "Escape must restore the original text and style without closing the editor")
        // Selected-object style changes and movement are reversible too.
        toolbar.selectTextStyle(AnnotationTextStyle(font: .monospaced, size: 24))
        precondition(canvas.items[0].textStyle.font == .monospaced)
        canvas.undo(); precondition(canvas.items[0].textStyle == first.textStyle)
        canvas.redo()
        let beforeMove = canvas.items[0].startPoint
        let hit = CGPoint(x: beforeMove.x + 8, y: beforeMove.y - 8)
        canvas.mouseDown(with: mouse(.leftMouseDown, hit))
        canvas.mouseDragged(with: mouse(.leftMouseDragged, CGPoint(x: hit.x + 20, y: hit.y - 30)))
        canvas.mouseUp(with: mouse(.leftMouseUp, CGPoint(x: hit.x + 20, y: hit.y - 30)))
        precondition(canvas.items[0].startPoint != beforeMove)
        canvas.undo(); precondition(canvas.items[0].startPoint == beforeMove)
        canvas.redo()
        canvas.mouseDown(with: mouse(.leftMouseDown, CGPoint(x: canvas.items[0].startPoint.x + 8, y: canvas.items[0].startPoint.y - 8)))
        canvas.mouseUp(with: mouse(.leftMouseUp, CGPoint(x: canvas.items[0].startPoint.x + 8, y: canvas.items[0].startPoint.y - 8)))
        canvas.setColor(.systemBlue)
        precondition(canvas.items[0].color == .systemBlue)
        canvas.undo(); precondition(canvas.items[0].color == first.color)
        canvas.redo()
        precondition(canvas.widthMenu(at: CGPoint(x: canvas.items[0].startPoint.x + 5, y: canvas.items[0].startPoint.y - 5))?.items.first?.title == "Edit Text…")
        // Export must include the latest uncommitted text without editor chrome.
        canvas.beginText(at: CGPoint(x: 40, y: 140))
        canvas.textEditor!.insertText("Saved draft", replacementRange: NSRange(location: NSNotFound, length: 0))
        let exported = NSBitmapImageRep(data: canvas.renderAnnotatedImage().tiffRepresentation!)!
        precondition(canvas.items.count == 2 && canvas.textEditor == nil)
        var colored = 0
        for x in 30..<500 {
            for y in 30..<300 {
                let color = exported.colorAt(x: x, y: y)!.usingColorSpace(.deviceRGB)!
                if color.blueComponent > 0.5 && color.redComponent < 0.7 { colored += 1 }
            }
        }
        precondition(colored > 100, "Text must be present in exported pixels")
        try exported.representation(using: .png, properties: [:])!.write(to: directory.appendingPathComponent("editor-text-export.png"))
        canvas.beginText(at: .zero)
        canvas.textEditor!.string = "   \n"
        canvas.finishTextEditing()
        precondition(canvas.items.count == 2, "Whitespace-only text must not create an invisible annotation")
        canvas.beginText(at: canvas.items[1].startPoint, editing: 1)
        canvas.textEditor!.string = ""
        canvas.finishTextEditing()
        precondition(canvas.items.count == 1)
        canvas.undo(); precondition(canvas.items.count == 2)
        canvas.redo(); precondition(canvas.items.count == 1)
        precondition(window.performKeyEquivalent(with: key(36, "\r")))
        precondition(canvas.textEditor != nil, "Keyboard-only Return on the canvas must open text input")
        canvas.finishTextEditing(commit: false)
        toolbar.selectTextStyle(AnnotationTextStyle(font: .serif, size: .nan))
        precondition(toolbar.textStyle.size.isFinite)
        print("PASS text: actual typing, newlines, Unicode, cancel, style/color, drag, deletion, Undo/Redo, keyboard routing and PNG export")

        let fontNames = Set(AnnotationFont.available.map { $0.font(size: 24).fontName })
        precondition(fontNames.count == AnnotationFont.available.count && fontNames.count == 8, "Installed font choices must resolve distinctly")
        print("PASS eight distinct installed macOS font choices")
        var count = 1
        for theme: NSAppearance.Name in [.aqua, .darkAqua] {
            for width: CGFloat in [620, 780, 900, 960, 1000, 1440] {
                window.appearance = NSAppearance(named: theme)
                window.setContentSize(NSSize(width: width, height: 520))
                toolbar.updateToolSelection(activeTool: .text)
                for font in AnnotationFont.available {
                    toolbar.selectTextStyle(AnnotationTextStyle(font: font, size: 96))
                    content.layoutSubtreeIfNeeded(); content.layoutSubtreeIfNeeded()
                    verifyToolbar(toolbar)
                    precondition(abs(toolbar.bounds.width - width) < 0.5,
                                 "The toolbar must not impose its old single-row width: requested \(width), actual \(toolbar.bounds.width)")
                    precondition(PanelPreview.descendants(toolbar).compactMap { $0 as? NSPopUpButton }
                        .filter { !$0.isHiddenOrHasHiddenAncestor }.count == 2,
                        "Both text controls must remain attached and visible")
                    precondition(width < 960 || toolbar.preferredHeight == 44,
                                 "Wide text toolbars must stay on one row: width \(width), height \(toolbar.preferredHeight)")
                    precondition(width > 780 || toolbar.preferredHeight == 80,
                                 "Narrow text toolbars must reserve room for all controls: width \(width), height \(toolbar.preferredHeight)")
                    precondition(toolbar.frame.height == toolbar.preferredHeight,
                                 "The actual editor must reserve the measured toolbar height")
                }
                toolbar.selectTextStyle(AnnotationTextStyle(font: .monospaced, size: 24))
                content.layoutSubtreeIfNeeded()
                let bitmap = content.bitmapImageRepForCachingDisplay(in: content.bounds)!
                content.cacheDisplay(in: content.bounds, to: bitmap)
                let name = "editor-text-\(theme == .aqua ? "light" : "dark")-\(Int(width))"
                try bitmap.representation(using: .png, properties: [:])!.write(to: directory.appendingPathComponent(name + ".png"))
                count += 1
                print("PASS \(name): text controls, all font choices and 96 pt selection remain inside toolbar")
            }
        }
        window.setContentSize(NSSize(width: 960, height: 520))
        toolbar.updateToolSelection(activeTool: .pen)
        content.layoutSubtreeIfNeeded(); content.layoutSubtreeIfNeeded()
        let wideCanvas = canvas.frame
        let wideToolbar = toolbar.frame
        var heightChanges = 0
        let reserveHeight = toolbar.onPreferredHeightChange
        toolbar.onPreferredHeightChange = { value in heightChanges += 1; reserveHeight?(value) }
        for _ in 0..<10 {
            textButton.performClick(nil)
            for font in AnnotationFont.available {
                toolbar.selectTextStyle(AnnotationTextStyle(font: font, size: 96))
                content.layoutSubtreeIfNeeded(); content.layoutSubtreeIfNeeded()
                precondition(toolbar.frame == wideToolbar && canvas.frame == wideCanvas,
                             "Text/font changes must not double a wide header or move the screenshot")
            }
            toolbar.onSelectTool?(.pen)
        }
        precondition(heightChanges == 0, "Wide tool changes must not trigger toolbar height callbacks")
        toolbar.onPreferredHeightChange = reserveHeight
        // Resizing while Text is active must return to one row as soon as it fits.
        toolbar.onSelectTool?(.text)
        for width: CGFloat in [620, 960, 900, 1000, 780, 1440, 960] {
            window.setContentSize(NSSize(width: width, height: 520))
            content.layoutSubtreeIfNeeded(); content.layoutSubtreeIfNeeded()
            verifyToolbar(toolbar)
            precondition(width < 960 || toolbar.frame.height == 44)
            precondition(width > 780 || toolbar.frame.height == 80)
        }
        print("PASS wide Text/font changes preserve header/canvas geometry; narrow/wide resize wraps only when needed")
        // Verify full-resolution export and the three font designs on a 2x screenshot.
        let retinaRep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1280, pixelsHigh: 720,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        retinaRep.size = image.size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: retinaRep)
        NSColor.white.setFill(); NSRect(origin: .zero, size: image.size).fill()
        NSGraphicsContext.restoreGraphicsState()
        let retinaImage = NSImage(size: image.size)
        retinaImage.addRepresentation(retinaRep)
        let retina = AnnotationCanvasView(image: retinaImage)
        retina.frame = NSRect(x: 0, y: 0, width: 680, height: 400)
        retina.activeTool = .text
        retina.activeColor = .black
        for (index, font) in AnnotationFont.available.prefix(3).enumerated() {
            retina.activeTextStyle = AnnotationTextStyle(font: font, size: 28)
            retina.beginText(at: CGPoint(x: 30, y: 310 - CGFloat(index) * 90))
            retina.textEditor!.insertText("\(font.title) · Привет, Mac 👋", replacementRange: NSRange(location: NSNotFound, length: 0))
            retina.finishTextEditing()
        }
        let result = retina.renderAnnotatedImage()
        let output = result.representations.first as! NSBitmapImageRep
        precondition(output.pixelsWide == 1280 && output.pixelsHigh == 720 && result.size == image.size)
        try output.representation(using: .png, properties: [:])!.write(to: directory.appendingPathComponent("editor-text-fonts-retina.png"))
        print("PASS 2x export preserves 1280×720 pixels and all three system font designs")
        count += 1
        // Very long input must wrap/scroll during editing and survive resizing without losing characters.
        canvas.beginText(at: CGPoint(x: 40, y: 300))
        canvas.textEditor!.insertText("Local undo", replacementRange: NSRange(location: NSNotFound, length: 0))
        let typed = canvas.textEditor!.string
        precondition(window.performKeyEquivalent(with: key(6, "z", .command)))
        precondition(canvas.textEditor!.string != typed && canvas.items.count == 1)
        precondition(window.performKeyEquivalent(with: key(6, "z", [.command, .shift])))
        precondition(canvas.textEditor!.string == typed)
        canvas.textEditor!.selectAll(nil)
        let longText = String(repeating: "Длинная подпись / Long annotation 👋 ", count: 30)
        canvas.textEditor!.insertText(longText, replacementRange: NSRange(location: NSNotFound, length: 0))
        window.setContentSize(NSSize(width: 620, height: 400))
        content.layoutSubtreeIfNeeded(); content.layoutSubtreeIfNeeded()
        precondition(canvas.textEditor!.string == longText)
        let scroll = PanelPreview.descendants(canvas).compactMap { $0 as? NSScrollView }.first!
        precondition(!canvas.textEditor!.drawsBackground && !scroll.drawsBackground,
                     "Text entry must not obscure the screenshot or hide black text in dark mode")
        precondition(canvas.bounds.contains(scroll.frame))
        let bitmap = content.bitmapImageRepForCachingDisplay(in: content.bounds)!
        content.cacheDisplay(in: content.bounds, to: bitmap)
        try bitmap.representation(using: .png, properties: [:])!.write(to: directory.appendingPathComponent("editor-text-editing-narrow.png"))
        canvas.finishTextEditing(commit: false)
        print("PASS long multilingual text and editing viewport survive narrow-window resize")
        return count + 1
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
        let pickers = controls.compactMap { $0 as? NSPopUpButton }
        precondition(pickers.count == 0 || pickers.count == 2,
                     "Only the two contextual text controls belong in the toolbar")
        for (index, first) in controls.enumerated() {
            for second in controls.dropFirst(index + 1) {
                let a = toolbar.convert(first.bounds, from: first)
                let b = toolbar.convert(second.bounds, from: second)
                precondition(!a.intersects(b), "Toolbar controls overlap: \(first) and \(second)")
            }
        }
    }
}

/// All ordering and activation calls are intercepted; these tests never show a
/// window, activate the test executable, or launch the system capture tool.
private final class PresentationWindow: NSWindow {
    var visibleForTest = false
    var keyForTest = false
    var miniaturizedForTest = false
    var canReceiveKeyForTest = false
    var frontCalls = 0
    var keyCalls = 0
    override var isVisible: Bool { visibleForTest }
    override var isKeyWindow: Bool { keyForTest }
    override var isMiniaturized: Bool { miniaturizedForTest }
    override func orderFrontRegardless() { frontCalls += 1; visibleForTest = true }
    override func makeKeyAndOrderFront(_ sender: Any?) {
        keyCalls += 1
        visibleForTest = true
        if canReceiveKeyForTest { keyForTest = true }
    }
    override func deminiaturize(_ sender: Any?) { miniaturizedForTest = false }
}

private enum PresentationChecks {
    static func run() {
        func window() -> PresentationWindow {
            PresentationWindow(contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
                               styleMask: [.titled], backing: .buffered, defer: false)
        }
        let notifications = NotificationCenter()
        var active = false
        var activations = 0
        var scheduled: [(TimeInterval, DispatchWorkItem)] = []
        let first = window()
        let presenter = ScreenshotEditorPresenter(notifications: notifications, activate: {
            precondition(first.visibleForTest, "An editor must exist and be visible before activation is requested")
            activations += 1
        }, isApplicationActive: { active }, schedule: { scheduled.append(($0, $1)) })
        presenter.present(first)
        precondition(activations == 1 && first.frontCalls == 1 && first.keyCalls == 1)
        precondition(scheduled.map { $0.0 } == [0.15, 0.4, 0.8])
        // The activation notification, not synchronous return, completes keyboard focus.
        active = true
        first.canReceiveKeyForTest = true
        notifications.post(name: NSApplication.didBecomeActiveNotification, object: nil)
        precondition(first.keyForTest && first.frontCalls == 2 && first.keyCalls == 2)
        scheduled[0].1.perform()
        let finishedFront = first.frontCalls
        let finishedActivation = activations
        scheduled.forEach { $0.1.perform() }
        notifications.post(name: NSApplication.didBecomeActiveNotification, object: nil)
        precondition(first.frontCalls == finishedFront && activations == finishedActivation,
                     "A settled editor must stop retrying and observing future activations")
        print("PASS editor presentation: visible before activation, asynchronous focus, stop after success")

        scheduled.removeAll()
        active = false
        first.keyForTest = false
        first.canReceiveKeyForTest = false
        presenter.present(first)
        let beforeRestore = first.frontCalls
        scheduled[0].1.perform() // screencapture has restored the source app instead.
        precondition(first.frontCalls > beforeRestore)
        first.canReceiveKeyForTest = true
        active = true
        notifications.post(name: NSApplication.didBecomeActiveNotification, object: nil)
        scheduled[1].1.perform()
        let requestsAfterRestore = activations
        scheduled[2].1.perform()
        precondition(activations == requestsAfterRestore && first.keyForTest)
        print("PASS editor presentation: capture/source-app focus race recovers and stops")

        scheduled.removeAll()
        active = false
        first.keyForTest = false
        first.canReceiveKeyForTest = false
        let beforeDenied = activations
        presenter.present(first)
        scheduled.forEach { $0.1.perform() }
        precondition(activations - beforeDenied == 4, "Denied activation must have a bounded retry budget")
        let afterDenied = first.frontCalls
        notifications.post(name: NSApplication.didBecomeActiveNotification, object: nil)
        precondition(first.frontCalls == afterDenied)
        print("PASS editor presentation: denied activation cannot create an endless focus loop")

        scheduled.removeAll()
        presenter.present(first)
        notifications.post(name: NSWindow.willCloseNotification, object: first)
        first.visibleForTest = false
        let afterClose = activations
        scheduled.forEach { $0.1.perform() }
        notifications.post(name: NSApplication.didBecomeActiveNotification, object: nil)
        precondition(!first.visibleForTest && activations == afterClose, "Closing an editor must cancel stale presentation work")
        print("PASS editor presentation: close cancels queued focus requests without reopening")

        // Hidden/minimized windows reflect a later user decision and must stay that way.
        for minimize in [false, true] {
            scheduled.removeAll()
            presenter.present(first)
            if minimize { first.miniaturizedForTest = true }
            else { first.visibleForTest = false }
            let count = activations
            scheduled.forEach { $0.1.perform() }
            precondition(activations == count)
            if minimize { precondition(first.miniaturizedForTest); first.miniaturizedForTest = false }
            else { precondition(!first.visibleForTest) }
        }
        print("PASS editor presentation: hide/minimize cancels retry without reversing the user's action")

        scheduled.removeAll()
        presenter.present(first)
        let oldWork = scheduled
        let second = window()
        second.canReceiveKeyForTest = true
        presenter.present(second)
        let firstCount = first.frontCalls
        oldWork.forEach { $0.1.perform() }
        notifications.post(name: NSWindow.willCloseNotification, object: first)
        active = true
        notifications.post(name: NSApplication.didBecomeActiveNotification, object: nil)
        precondition(first.frontCalls == firstCount && second.keyForTest,
                     "A newer editor must supersede old focus work; closing the old one must not cancel the new one")
        presenter.cancel()
        let secondCount = second.frontCalls
        scheduled.forEach { $0.1.perform() }
        precondition(second.frontCalls == secondCount, "Starting another capture must cancel pending editor activation")
        print("PASS editor presentation: newest editor wins; explicit capture cancellation invalidates old retries")
    }
}
