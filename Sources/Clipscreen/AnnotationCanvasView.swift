import AppKit

/// Keeps text editing shortcuts local instead of triggering screenshot Copy/Undo.
final class AnnotationTextView: NSTextView {
    var onFinish: ((Bool) -> Void)?
    private let editingUndoManager = UndoManager()
    override var undoManager: UndoManager? { editingUndoManager }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onFinish?(false); return }
        if event.keyCode == 36 && event.modifierFlags.contains(.command) { onFinish?(true); return }
        super.keyDown(with: event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags.contains(.command) else { return false }
        if event.keyCode == 36 { onFinish?(true); return true }
        switch event.charactersIgnoringModifiers?.lowercased() {
        case "a": selectAll(nil)
        case "c": copy(nil)
        case "x": cut(nil)
        case "v": pasteAsPlainText(nil)
        case "z":
            if flags.contains(.shift) { undoManager?.redo() } else { undoManager?.undo() }
        default: return false
        }
        return true
    }
}

final class AnnotationCanvasView: NSView, NSTextViewDelegate {
    let baseImage: NSImage
    private(set) var items: [AnnotationItem] = []
    private var undoSnapshots: [[AnnotationItem]] = []
    private var redoSnapshots: [[AnnotationItem]] = []
    private var currentItem: AnnotationItem?
    private(set) var textEditor: AnnotationTextView?
    private var textScroll: NSScrollView?
    private var textDraft: AnnotationItem?
    private var editingTextIndex: Int?
    private(set) var selectedTextIndex: Int?
    private var textDragOrigin: CGPoint?
    private var textDragStart: CGPoint?
    private var recordedTextMove = false
    var activeTextStyle = AnnotationTextStyle()
    var onSelectText: ((AnnotationTextStyle, NSColor) -> Void)?

    var activeTool: AnnotationTool = .pen {
        didSet {
            if activeTool != oldValue {
                finishTextEditing()
                selectedTextIndex = nil
                activeLineWidth = activeTool.defaultLineWidth
                needsDisplay = true
            }
        }
    }
    var activeColor: NSColor = .systemRed
    var activeLineWidth: CGFloat = 3.5

    var onHistoryChange: ((_ canUndo: Bool, _ canRedo: Bool) -> Void)?

    init(image: NSImage) {
        self.baseImage = image
        super.init(frame: .zero)
        wantsLayer = true
        setAccessibilityLabel("Screenshot annotation canvas")
        setAccessibilityHelp("Select Text, then click the image to type. Double-click text to edit, drag to move. Command-Return applies; Escape cancels editing.")
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var acceptsFirstResponder: Bool { true }

    var canUndo: Bool { !undoSnapshots.isEmpty }
    var canRedo: Bool { !redoSnapshots.isEmpty }

    func undo() {
        finishTextEditing()
        selectedTextIndex = nil
        guard let snapshot = undoSnapshots.popLast() else { return }
        redoSnapshots.append(items)
        items = snapshot
        needsDisplay = true
        onHistoryChange?(canUndo, canRedo)
    }

    func redo() {
        finishTextEditing()
        selectedTextIndex = nil
        guard let snapshot = redoSnapshots.popLast() else { return }
        undoSnapshots.append(items)
        items = snapshot
        needsDisplay = true
        onHistoryChange?(canUndo, canRedo)
    }

    func clear() {
        finishTextEditing()
        selectedTextIndex = nil
        guard !items.isEmpty else { return }
        recordUndo()
        items.removeAll()
        needsDisplay = true
        onHistoryChange?(canUndo, canRedo)
    }

    private func recordUndo() {
        undoSnapshots.append(items)
        redoSnapshots.removeAll()
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        finishTextEditing()
        guard imageRect.contains(convert(event.locationInWindow, from: nil)),
              let point = toImagePoint(event.locationInWindow) else { return nil }
        let tolerance = 6 * baseImage.size.width / max(1, imageRect.width)
        return widthMenu(at: point, tolerance: tolerance)
    }

    func widthMenu(at point: CGPoint, tolerance: CGFloat = 6) -> NSMenu? {
        guard let index = items.indices.reversed().first(where: {
            AnnotationRenderer.contains(point, in: items[$0], tolerance: tolerance)
        }) else { return nil }
        let item = items[index]
        if item.tool == .text {
            let menu = NSMenu(title: "Text")
            let edit = NSMenuItem(title: "Edit Text…", action: #selector(editSelectedText), keyEquivalent: "")
            edit.target = self
            edit.tag = index
            menu.addItem(edit)
            return menu
        }
        return StrokeWidthMenu(tool: item.tool, width: item.lineWidth) { [weak self] in
            self?.setLineWidth($0, at: index)
        }
    }

    func setLineWidth(_ width: CGFloat, at index: Int) {
        guard items.indices.contains(index), items[index].tool.usesLineWidth,
              items[index].tool.lineWidths.contains(width), items[index].lineWidth != width else { return }
        recordUndo()
        items[index].lineWidth = width
        needsDisplay = true
        onHistoryChange?(canUndo, canRedo)
    }

    @objc private func editSelectedText(_ sender: NSMenuItem) {
        activeTool = .text
        beginText(at: items[sender.tag].startPoint, editing: sender.tag)
    }

    func setTextStyle(_ style: AnnotationTextStyle) {
        guard AnnotationTextStyle.sizes.contains(style.size) else { return }
        activeTextStyle = style
        if textDraft != nil {
            textDraft?.textStyle = style
            updateTextEditorLayout()
        } else if let index = selectedTextIndex, items[index].textStyle != style {
            recordUndo()
            items[index].textStyle = style
            onHistoryChange?(canUndo, canRedo)
        }
        needsDisplay = true
    }

    func setColor(_ color: NSColor) {
        activeColor = color
        if textDraft != nil {
            textDraft?.color = color
            updateTextEditorLayout()
        } else if let index = selectedTextIndex, items[index].color != color {
            recordUndo()
            items[index].color = color
            onHistoryChange?(canUndo, canRedo)
        }
        needsDisplay = true
    }

    func beginText(at point: CGPoint, editing index: Int? = nil) {
        finishTextEditing()
        textDragOrigin = nil
        textDragStart = nil
        selectedTextIndex = index
        editingTextIndex = index
        let anchor = CGPoint(x: min(max(0, point.x), max(0, baseImage.size.width - 24)),
                             y: min(max(activeTextStyle.size * 1.25, point.y), baseImage.size.height))
        textDraft = index.map { items[$0] } ?? AnnotationItem(
            tool: .text, startPoint: anchor, endPoint: anchor, points: [], color: activeColor,
            lineWidth: 0, textStyle: activeTextStyle, textMaxWidth: max(24, baseImage.size.width - anchor.x))
        let draft = textDraft!
        activeTextStyle = draft.textStyle
        activeColor = draft.color
        onSelectText?(draft.textStyle, draft.color)

        let editor = AnnotationTextView(frame: .zero)
        editor.isRichText = false
        editor.isAutomaticQuoteSubstitutionEnabled = false
        editor.isAutomaticDashSubstitutionEnabled = false
        editor.allowsUndo = true
        editor.isVerticallyResizable = true
        editor.isHorizontallyResizable = false
        editor.textContainerInset = .zero
        editor.textContainer?.lineFragmentPadding = 0
        editor.textContainer?.widthTracksTextView = true
        editor.drawsBackground = false
        editor.insertionPointColor = .controlAccentColor
        editor.string = draft.text
        editor.delegate = self
        editor.setAccessibilityLabel("Annotation text")
        editor.setAccessibilityHelp("Return inserts a new line. Command-Return applies text. Escape cancels this edit.")
        editor.onFinish = { [weak self] apply in self?.finishTextEditing(commit: apply) }
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.contentView.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.wantsLayer = true
        scroll.layer?.borderWidth = 1
        scroll.layer?.borderColor = NSColor.controlAccentColor.cgColor
        scroll.documentView = editor
        addSubview(scroll)
        textEditor = editor
        textScroll = scroll
        updateTextEditorLayout()
        window?.makeFirstResponder(editor)
        editor.setSelectedRange(NSRange(location: 0, length: (draft.text as NSString).length))
        needsDisplay = true
    }

    func textDidChange(_ notification: Notification) {
        textDraft?.text = textEditor?.string ?? ""
        updateTextEditorLayout()
    }

    override func layout() {
        super.layout()
        updateTextEditorLayout()
    }

    private func updateTextEditorLayout() {
        guard var draft = textDraft, let editor = textEditor, let scroll = textScroll else { return }
        draft.text = editor.string
        let scale = imageRect.width / max(1, baseImage.size.width)
        let width = max(1, draft.textMaxWidth * scale)
        editor.font = draft.textStyle.font.font(size: draft.textStyle.size * scale)
        editor.textColor = draft.color
        editor.typingAttributes = [.font: editor.font!, .foregroundColor: draft.color]
        editor.setFrameSize(NSSize(width: width, height: max(1, AnnotationRenderer.textRect(for: draft).height * scale)))
        editor.textContainer?.containerSize = NSSize(width: width, height: .greatestFiniteMagnitude)
        let top = imageRect.minY + draft.startPoint.y * scale
        let height = min(max(28, editor.frame.height + 4), max(1, top - imageRect.minY))
        scroll.frame = NSRect(x: imageRect.minX + draft.startPoint.x * scale, y: top - height, width: width, height: height)
    }

    func finishTextEditing(commit: Bool = true) {
        guard var draft = textDraft else { return }
        draft.text = textEditor?.string ?? draft.text
        let index = editingTextIndex
        textDraft = nil
        editingTextIndex = nil
        textEditor?.delegate = nil
        if window?.firstResponder === textEditor { window?.makeFirstResponder(self) }
        textScroll?.removeFromSuperview()
        textScroll = nil
        textEditor = nil
        if commit {
            let empty = draft.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            if let index {
                let old = items[index]
                if empty || old.text != draft.text || old.textStyle != draft.textStyle || old.color != draft.color {
                    recordUndo()
                    if empty { items.remove(at: index); selectedTextIndex = nil }
                    else { items[index] = draft; selectedTextIndex = index }
                }
            } else if !empty {
                recordUndo()
                items.append(draft)
                selectedTextIndex = items.count - 1
            }
            onHistoryChange?(canUndo, canRedo)
        } else if let index {
            activeTextStyle = items[index].textStyle
            activeColor = items[index].color
            onSelectText?(activeTextStyle, activeColor)
        }
        needsDisplay = true
    }

    override func keyDown(with event: NSEvent) {
        if activeTool == .text {
            if event.keyCode == 36 {
                let point = selectedTextIndex.map { items[$0].startPoint }
                    ?? CGPoint(x: baseImage.size.width * 0.2, y: baseImage.size.height * 0.7)
                beginText(at: point, editing: selectedTextIndex)
                return
            }
            if [51, 117].contains(event.keyCode), let index = selectedTextIndex {
                recordUndo()
                items.remove(at: index)
                selectedTextIndex = nil
                needsDisplay = true
                onHistoryChange?(canUndo, canRedo)
                return
            }
        }
        super.keyDown(with: event)
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
        finishTextEditing()
        window?.makeFirstResponder(self)
        guard imageRect.contains(convert(event.locationInWindow, from: nil)),
              let pt = toImagePoint(event.locationInWindow) else { selectedTextIndex = nil; needsDisplay = true; return }
        if activeTool == .text {
            let hit = items.indices.reversed().first {
                items[$0].tool == .text && AnnotationRenderer.contains(pt, in: items[$0], tolerance: 3)
            }
            selectedTextIndex = hit
            if let hit {
                activeTextStyle = items[hit].textStyle
                activeColor = items[hit].color
                onSelectText?(activeTextStyle, activeColor)
                if event.clickCount > 1 { beginText(at: pt, editing: hit) }
                else {
                    textDragOrigin = items[hit].startPoint
                    textDragStart = pt
                    recordedTextMove = false
                }
            } else { beginText(at: pt) }
            needsDisplay = true
            return
        }
        selectedTextIndex = nil
        currentItem = AnnotationItem(tool: activeTool, startPoint: pt, endPoint: pt,
                                     points: [pt], color: activeColor, lineWidth: activeLineWidth)
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        if let index = selectedTextIndex, let origin = textDragOrigin, let start = textDragStart,
           let point = toImagePoint(event.locationInWindow) {
            if !recordedTextMove { recordUndo(); recordedTextMove = true }
            let rect = AnnotationRenderer.textRect(for: items[index])
            items[index].startPoint = CGPoint(
                x: min(max(0, origin.x + point.x - start.x), max(0, baseImage.size.width - rect.width)),
                y: min(max(rect.height, origin.y + point.y - start.y), baseImage.size.height))
            needsDisplay = true
            onHistoryChange?(canUndo, canRedo)
            return
        }
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
        textDragOrigin = nil
        textDragStart = nil
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
        recordUndo()
        items.append(item)
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
        context.clip(to: CGRect(origin: .zero, size: baseImage.size))
        for (index, item) in all.enumerated() where index != editingTextIndex {
            AnnotationRenderer.render(item: item, in: context)
        }
        if let index = selectedTextIndex, textDraft == nil {
            context.setStrokeColor(NSColor.controlAccentColor.cgColor)
            context.setLineWidth(1 / scaleX)
            context.setLineDash(phase: 0, lengths: [4 / scaleX, 3 / scaleX])
            context.stroke(AnnotationRenderer.textRect(for: items[index]).insetBy(dx: -3 / scaleX, dy: -3 / scaleX))
        }
        context.restoreGState()
    }

    func renderAnnotatedImage() -> NSImage {
        finishTextEditing()
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
