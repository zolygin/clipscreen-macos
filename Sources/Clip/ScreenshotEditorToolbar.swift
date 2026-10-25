import AppKit

final class ScreenshotEditorToolbar: NSVisualEffectView {
    var onSelectTool: ((AnnotationTool) -> Void)?
    var onSelectColor: ((NSColor) -> Void)?
    var onOpenColorPicker: (() -> Void)?
    var onUndo: (() -> Void)?
    var onRedo: (() -> Void)?
    var onSave: (() -> Void)?
    var onCopy: (() -> Void)?

    private var toolButtons: [AnnotationTool: NSButton] = [:]
    private var colorButtons: [NSColor: NSButton] = [:]
    private var pickerButton: NSButton?
    private(set) var undoButton: NSButton!
    private(set) var redoButton: NSButton!

    private let colors: [NSColor] = [
        .systemRed,
        .systemYellow,
        .systemGreen,
        .systemBlue,
        .black,
        .white
    ]

    init() {
        super.init(frame: .zero)
        material = .headerView
        blendingMode = .withinWindow
        state = .active
        setupLayout()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func setupLayout() {
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 78),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            stack.heightAnchor.constraint(equalToConstant: 36)
        ])

        for tool in AnnotationTool.allCases {
            let btn = NSButton(image: NSImage(systemSymbolName: tool.symbolName, accessibilityDescription: tool.title)!,
                               target: self, action: #selector(toolClicked(_:)))
            btn.tag = tool.rawValue
            btn.isBordered = false
            btn.bezelStyle = .inline
            btn.toolTip = tool.title
            btn.widthAnchor.constraint(equalToConstant: 30).isActive = true
            btn.heightAnchor.constraint(equalToConstant: 30).isActive = true
            toolButtons[tool] = btn
            stack.addArrangedSubview(btn)
        }

        stack.addArrangedSubview(makeSeparator())

        for color in colors {
            let btn = ColorCircleButton(color: color, target: self, action: #selector(colorClicked(_:)))
            btn.widthAnchor.constraint(equalToConstant: 24).isActive = true
            btn.heightAnchor.constraint(equalToConstant: 24).isActive = true
            colorButtons[color] = btn
            stack.addArrangedSubview(btn)
        }

        let pickerBtn = NSButton(image: NSImage(systemSymbolName: "paintpalette.fill", accessibilityDescription: "Custom Color Picker")!,
                                 target: self, action: #selector(openColorPickerClicked))
        pickerBtn.isBordered = false
        pickerBtn.bezelStyle = .inline
        pickerBtn.toolTip = "Custom color picker…"
        pickerBtn.contentTintColor = .secondaryLabelColor
        pickerBtn.widthAnchor.constraint(equalToConstant: 26).isActive = true
        pickerBtn.heightAnchor.constraint(equalToConstant: 26).isActive = true
        self.pickerButton = pickerBtn
        stack.addArrangedSubview(pickerBtn)

        stack.addArrangedSubview(makeSeparator())

        undoButton = NSButton(image: NSImage(systemSymbolName: "arrow.uturn.backward", accessibilityDescription: "Undo")!,
                              target: self, action: #selector(undoClicked))
        undoButton.isBordered = false
        undoButton.bezelStyle = .inline
        undoButton.toolTip = "Undo (⌘Z)"
        undoButton.isEnabled = false
        undoButton.widthAnchor.constraint(equalToConstant: 28).isActive = true
        undoButton.heightAnchor.constraint(equalToConstant: 28).isActive = true
        stack.addArrangedSubview(undoButton)

        redoButton = NSButton(image: NSImage(systemSymbolName: "arrow.uturn.forward", accessibilityDescription: "Redo")!,
                              target: self, action: #selector(redoClicked))
        redoButton.isBordered = false
        redoButton.bezelStyle = .inline
        redoButton.toolTip = "Redo (⇧⌘Z)"
        redoButton.isEnabled = false
        redoButton.widthAnchor.constraint(equalToConstant: 28).isActive = true
        redoButton.heightAnchor.constraint(equalToConstant: 28).isActive = true
        stack.addArrangedSubview(redoButton)

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        stack.addArrangedSubview(spacer)

        let saveBtn = NSButton(title: "Save…", target: self, action: #selector(saveClicked))
        saveBtn.bezelStyle = .rounded
        saveBtn.controlSize = .regular
        saveBtn.toolTip = "Save to disk (⌘S)"
        stack.addArrangedSubview(saveBtn)

        let copyBtn = NSButton(title: "Copy", target: self, action: #selector(copyClicked))
        copyBtn.bezelStyle = .rounded
        copyBtn.controlSize = .regular
        copyBtn.keyEquivalent = "\r"
        copyBtn.toolTip = "Copy to clipboard and close (Enter / ⌘C)"
        stack.addArrangedSubview(copyBtn)
    }

    private func makeSeparator() -> NSView {
        let v = NSBox()
        v.boxType = .separator
        v.widthAnchor.constraint(equalToConstant: 1).isActive = true
        v.heightAnchor.constraint(equalToConstant: 18).isActive = true
        return v
    }

    func updateToolSelection(activeTool: AnnotationTool) {
        for (tool, btn) in toolButtons {
            let isSelected = tool == activeTool
            btn.contentTintColor = isSelected ? .controlAccentColor : .secondaryLabelColor
            btn.wantsLayer = true
            btn.layer?.cornerRadius = 6
            btn.layer?.backgroundColor = isSelected ? NSColor.controlAccentColor.withAlphaComponent(0.15).cgColor : nil
        }
    }

    func updateColorSelection(activeColor: NSColor) {
        var matchedPreset = false
        for (color, btn) in colorButtons {
            if let circle = btn as? ColorCircleButton {
                let match = (color == activeColor)
                circle.isSelected = match
                if match { matchedPreset = true }
            }
        }
        if let pickerBtn = pickerButton {
            pickerBtn.wantsLayer = true
            pickerBtn.layer?.cornerRadius = 6
            if !matchedPreset {
                pickerBtn.contentTintColor = activeColor
                pickerBtn.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.15).cgColor
            } else {
                pickerBtn.contentTintColor = .secondaryLabelColor
                pickerBtn.layer?.backgroundColor = nil
            }
        }
    }

    @objc private func toolClicked(_ sender: NSButton) {
        guard let tool = AnnotationTool(rawValue: sender.tag) else { return }
        onSelectTool?(tool)
    }

    @objc private func colorClicked(_ sender: ColorCircleButton) {
        onSelectColor?(sender.color)
    }

    @objc private func openColorPickerClicked() {
        onOpenColorPicker?()
    }

    @objc private func undoClicked() { onUndo?() }
    @objc private func redoClicked() { onRedo?() }
    @objc private func saveClicked() { onSave?() }
    @objc private func copyClicked() { onCopy?() }
}
