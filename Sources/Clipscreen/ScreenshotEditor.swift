import AppKit

final class ScreenshotEditorWindowController: NSWindowController, NSWindowDelegate {
    private let canvas: AnnotationCanvasView
    private let toolbar = ScreenshotEditorToolbar()
    private let image: NSImage
    private var toolbarHeight: NSLayoutConstraint!
    var onComplete: ((NSImage) -> Void)?
    var onCancel: (() -> Void)?

    init(image: NSImage) {
        self.image = image
        self.canvas = AnnotationCanvasView(image: image)

        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let maxW = screen.width * 0.85
        let maxH = screen.height * 0.85

        let toolbarMinWidth: CGFloat = 680
        let naturalW = max(toolbarMinWidth, min(image.size.width + 64, maxW))
        let naturalH = max(440, min(image.size.height + 140, maxH))

        let initialSize = NSSize(width: naturalW, height: naturalH)

        let editorWindow = ScreenshotEditorWindow(
            contentRect: NSRect(origin: .zero, size: initialSize),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered, defer: false
        )
        editorWindow.minSize = NSSize(width: 620, height: 400)
        editorWindow.title = "Clipscreen — Screenshot Editor"
        editorWindow.isReleasedWhenClosed = false
        editorWindow.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        editorWindow.center()
        super.init(window: editorWindow)
        editorWindow.delegate = self
        editorWindow.onUndo = { [weak self] in self?.undoAction() }
        editorWindow.onRedo = { [weak self] in self?.redoAction() }
        editorWindow.onCopy = { [weak self] in self?.copyAction() }
        editorWindow.onSave = { [weak self] in self?.saveAction() }

        buildUI(editorWindow)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func buildUI(_ window: NSWindow) {
        let contentSize = window.contentRect(forFrameRect: window.frame).size
        let content = NSView(frame: NSRect(origin: .zero, size: contentSize))
        content.autoresizingMask = [.width, .height]
        window.contentView = content

        let separator = NSBox()
        separator.boxType = .separator
        toolbar.translatesAutoresizingMaskIntoConstraints = false
        separator.translatesAutoresizingMaskIntoConstraints = false
        canvas.translatesAutoresizingMaskIntoConstraints = false

        content.addSubview(toolbar)
        content.addSubview(separator)
        content.addSubview(canvas)

        NSLayoutConstraint.activate([
            toolbar.topAnchor.constraint(equalTo: content.topAnchor),
            toolbar.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            toolbar.trailingAnchor.constraint(equalTo: content.trailingAnchor),

            separator.topAnchor.constraint(equalTo: toolbar.bottomAnchor),
            separator.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            separator.heightAnchor.constraint(equalToConstant: 1),

            canvas.topAnchor.constraint(equalTo: separator.bottomAnchor),
            canvas.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            canvas.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            canvas.bottomAnchor.constraint(equalTo: content.bottomAnchor)
        ])
        toolbarHeight = toolbar.heightAnchor.constraint(equalToConstant: toolbar.preferredHeight)
        toolbarHeight.isActive = true
        toolbar.onPreferredHeightChange = { [weak self] height in self?.toolbarHeight.constant = height }

        toolbar.onSelectTool = { [weak self] tool in
            guard let self else { return }
            self.canvas.activeTool = tool
            self.canvas.activeLineWidth = self.toolbar.lineWidth(for: tool)
            self.toolbar.updateToolSelection(activeTool: tool)
            if tool == .text { self.window?.makeFirstResponder(self.canvas.textEditor ?? self.canvas as NSResponder) }
        }
        toolbar.onSelectLineWidth = { [weak self] width in self?.canvas.activeLineWidth = width }
        toolbar.onSelectColor = { [weak self] color in
            guard let self else { return }
            self.canvas.setColor(color)
            self.toolbar.updateColorSelection(activeColor: color)
        }
        toolbar.onSelectTextStyle = { [weak self] style in
            guard let self else { return }
            self.canvas.setTextStyle(style)
            self.window?.makeFirstResponder(self.canvas.textEditor ?? self.canvas as NSResponder)
        }
        canvas.onSelectText = { [weak self] style, color in
            self?.toolbar.updateToolSelection(activeTool: .text)
            self?.toolbar.updateTextStyle(style)
            self?.toolbar.updateColorSelection(activeColor: color)
        }
        toolbar.onUndo = { [weak self] in self?.undoAction() }
        toolbar.onRedo = { [weak self] in self?.redoAction() }
        toolbar.onSave = { [weak self] in self?.saveAction() }
        toolbar.onCopy = { [weak self] in self?.copyAction() }

        canvas.onHistoryChange = { [weak self] canUndo, canRedo in
            self?.toolbar.undoButton.isEnabled = canUndo
            self?.toolbar.redoButton.isEnabled = canRedo
        }

        toolbar.updateToolSelection(activeTool: canvas.activeTool)
        toolbar.updateColorSelection(activeColor: canvas.activeColor)
    }

    @objc private func undoAction() { canvas.undo() }
    @objc private func redoAction() { canvas.redo() }
    @objc func undo(_ sender: Any?) { undoAction() }
    @objc func redo(_ sender: Any?) { redoAction() }

    @objc private func copyAction() {
        let annotated = canvas.renderAnnotatedImage()
        onComplete?(annotated)
        closeEditor()
    }

    @objc private func saveAction() {
        canvas.finishTextEditing()
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.png]
        savePanel.nameFieldStringValue = "Screenshot \(DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .medium)).png"
        savePanel.beginSheetModal(for: window!) { [weak self] response in
            guard response == .OK, let url = savePanel.url, let self else { return }
            let annotated = self.canvas.renderAnnotatedImage()
            if let tiff = annotated.tiffRepresentation,
               let rep = NSBitmapImageRep(data: tiff),
               let png = rep.representation(using: .png, properties: [:]) {
                try? png.write(to: url)
            }
        }
    }

    private func closeEditor() {
        toolbar.deactivateColorPicker()
        window?.close()
    }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
        closeEditor()
    }

    func windowWillClose(_ notification: Notification) {
        toolbar.deactivateColorPicker()
        onCancel?()
    }
}
