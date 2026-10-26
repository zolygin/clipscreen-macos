import AppKit

final class AnnotationToolButton: ClipIconButton {
    var widthMenu: (() -> NSMenu)?
    override func menu(for event: NSEvent) -> NSMenu? { widthMenu?() }

    override func accessibilityPerformShowMenu() -> Bool {
        guard let menu = widthMenu?() else { return false }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: bounds.maxY + 4), in: self)
        return true
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 109, event.modifierFlags.contains(.shift), accessibilityPerformShowMenu() { return }
        super.keyDown(with: event)
    }
}

final class ScreenshotEditorToolbar: NSVisualEffectView {
    var onSelectTool: ((AnnotationTool) -> Void)?
    var onSelectColor: ((NSColor) -> Void)?
    var onSelectLineWidth: ((CGFloat) -> Void)?
    var onPreferredHeightChange: ((CGFloat) -> Void)?
    var onUndo: (() -> Void)?
    var onRedo: (() -> Void)?
    var onSave: (() -> Void)?
    var onCopy: (() -> Void)?

    private var toolButtons: [AnnotationTool: AnnotationToolButton] = [:]
    private var colorButtons: [NSColor: ColorCircleButton] = [:]
    private var widths: [AnnotationTool: CGFloat] = [:]
    private var activeColor: NSColor = .systemRed
    private var ownsColorPanel = false
    private lazy var customColor = CustomColorButton(target: self, action: #selector(openColorPicker))
    private let topRow = NSStackView()
    private let bottomRow = NSStackView()
    private let colorGroup = NSStackView()
    private let colorDivider = NSBox()
    private var isCompact = true
    private(set) var preferredHeight: CGFloat = 80
    private(set) var undoButton: NSButton!
    private(set) var redoButton: NSButton!

    init() {
        super.init(frame: .zero)
        material = .headerView
        blendingMode = .withinWindow
        state = .active
        setupLayout()
        updateToolSelection(activeTool: .pen)
        updateColorSelection(activeColor: .systemRed)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func setupLayout() {
        let tools = group()
        for tool in AnnotationTool.allCases {
            let button = AnnotationToolButton(tool.icon, label: tool.title, target: self, action: #selector(toolClicked(_:)))
            button.tag = tool.rawValue
            button.toolTip = tool == .filledRect ? "Filled Rectangle — drag to cover an area" : "\(tool.title) · Right-click for line width"
            button.widthMenu = { [weak self] in self?.makeWidthMenu(for: tool) ?? NSMenu() }
            size(button, width: 30, height: 30)
            toolButtons[tool] = button
            tools.addArrangedSubview(button)
        }

        configure(colorGroup)
        colorGroup.setHuggingPriority(.required, for: .horizontal)
        let label = NSTextField(labelWithString: "Color")
        label.font = .systemFont(ofSize: 11)
        label.textColor = .secondaryLabelColor
        colorGroup.addArrangedSubview(label)
        let colors: [(NSColor, String)] = [(.systemRed, "Red"), (.systemYellow, "Yellow"), (.systemGreen, "Green"),
                                          (.systemBlue, "Blue"), (.black, "Black"), (.white, "White")]
        for (color, name) in colors {
            let button = ColorCircleButton(color: color, label: name, target: self, action: #selector(colorClicked(_:)))
            size(button, width: 24, height: 24)
            colorButtons[color] = button
            colorGroup.addArrangedSubview(button)
        }
        size(customColor, width: 30, height: 30)
        colorGroup.addArrangedSubview(customColor)

        let actions = group()
        undoButton = ClipIconButton(.undo, label: "Undo (⌘Z)", target: self, action: #selector(undoClicked))
        redoButton = ClipIconButton(.redo, label: "Redo (⇧⌘Z)", target: self, action: #selector(redoClicked))
        for button in [undoButton!, redoButton!] {
            button.isEnabled = false
            size(button, width: 28, height: 28)
            actions.addArrangedSubview(button)
        }
        actions.addArrangedSubview(makeSeparator())
        let save = NSButton(title: "Save…", target: self, action: #selector(saveClicked))
        let copy = NSButton(title: "Copy", target: self, action: #selector(copyClicked))
        save.toolTip = "Save to disk (⌘S)"
        copy.toolTip = "Copy to clipboard and close (Enter / ⌘C)"
        copy.keyEquivalent = "\r"
        for button in [save, copy] {
            button.bezelStyle = .rounded
            button.controlSize = .regular
            actions.addArrangedSubview(button)
        }

        configure(topRow, spacing: 8)
        configure(bottomRow, spacing: 8)
        topRow.addArrangedSubview(tools)
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        topRow.addArrangedSubview(spacer)
        topRow.addArrangedSubview(actions)
        bottomRow.addArrangedSubview(colorGroup)
        for row in [topRow, bottomRow] {
            row.translatesAutoresizingMaskIntoConstraints = false
            addSubview(row)
        }
        colorDivider.boxType = .separator
        size(colorDivider, width: 1, height: 18)
        NSLayoutConstraint.activate([
            topRow.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            topRow.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            topRow.topAnchor.constraint(equalTo: topAnchor, constant: 7),
            topRow.heightAnchor.constraint(equalToConstant: 30),
            bottomRow.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            bottomRow.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -14),
            bottomRow.topAnchor.constraint(equalTo: topRow.bottomAnchor, constant: 6),
            bottomRow.heightAnchor.constraint(equalToConstant: 30)
        ])
    }

    override func layout() {
        let compact = bounds.width < 720
        if compact != isCompact {
            isCompact = compact
            colorGroup.removeFromSuperview()
            colorDivider.removeFromSuperview()
            if compact {
                bottomRow.addArrangedSubview(colorGroup)
            } else {
                topRow.insertArrangedSubview(colorDivider, at: 1)
                topRow.insertArrangedSubview(colorGroup, at: 2)
            }
            bottomRow.isHidden = !compact
            preferredHeight = compact ? 80 : 44
            onPreferredHeightChange?(preferredHeight)
        }
        super.layout()
    }

    func lineWidth(for tool: AnnotationTool) -> CGFloat { widths[tool] ?? tool.defaultLineWidth }

    func selectLineWidth(_ width: CGFloat, for tool: AnnotationTool) {
        guard tool.usesLineWidth, tool.lineWidths.contains(width) else { return }
        widths[tool] = width
        updateToolSelection(activeTool: tool)
        onSelectTool?(tool)
        onSelectLineWidth?(width)
    }

    func makeWidthMenu(for tool: AnnotationTool) -> NSMenu {
        StrokeWidthMenu(tool: tool, width: lineWidth(for: tool)) { [weak self] in self?.selectLineWidth($0, for: tool) }
    }

    func updateToolSelection(activeTool: AnnotationTool) {
        for (tool, button) in toolButtons {
            button.setActive(tool == activeTool)
            let selected = tool == activeTool ? "Selected" : "Not selected"
            let width = tool.usesLineWidth ? StrokeWidthMenu.label(lineWidth(for: tool)) : "Solid fill"
            button.setAccessibilityValue("\(selected), \(width)")
            button.toolTip = tool.usesLineWidth ? "\(tool.title) · \(width) · Right-click for line width"
                : "Filled Rectangle — drag to cover an area"
            button.setAccessibilityHelp(tool.usesLineWidth ? "Right-click or press Shift-F10 for line width" : "Solid fill has no outline width")
        }
    }

    func updateColorSelection(activeColor: NSColor) {
        self.activeColor = activeColor
        for (color, button) in colorButtons { button.isSelected = color == activeColor }
        customColor.selectedColor = colorButtons.keys.contains(activeColor) ? nil : activeColor
        if ownsColorPanel && NSColorPanel.shared.color != activeColor { NSColorPanel.shared.color = activeColor }
    }

    @objc private func openColorPicker() {
        let panel = NSColorPanel.shared
        panel.title = "Clipscreen — Colors"
        ownsColorPanel = true
        panel.showsAlpha = false
        panel.isContinuous = true
        panel.color = activeColor
        panel.setTarget(self)
        panel.setAction(#selector(customColorChanged(_:)))
        panel.makeKeyAndOrderFront(nil)
    }

    func deactivateColorPicker() {
        guard ownsColorPanel else { return }
        NSColorPanel.shared.setTarget(nil)
        NSColorPanel.shared.setAction(nil)
        NSColorPanel.shared.orderOut(nil)
        ownsColorPanel = false
    }

    @objc private func customColorChanged(_ sender: NSColorPanel) {
        onSelectColor?(sender.color)
        updateColorSelection(activeColor: sender.color)
    }

    private func group() -> NSStackView {
        let stack = NSStackView()
        configure(stack)
        stack.setHuggingPriority(.required, for: .horizontal)
        return stack
    }

    private func configure(_ stack: NSStackView, spacing: CGFloat = 4) {
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = spacing
    }

    private func size(_ view: NSView, width: CGFloat, height: CGFloat) {
        view.widthAnchor.constraint(equalToConstant: width).isActive = true
        view.heightAnchor.constraint(equalToConstant: height).isActive = true
    }

    private func makeSeparator() -> NSView {
        let separator = NSBox()
        separator.boxType = .separator
        size(separator, width: 1, height: 18)
        return separator
    }

    @objc private func toolClicked(_ sender: NSButton) {
        guard let tool = AnnotationTool(rawValue: sender.tag) else { return }
        onSelectTool?(tool)
    }
    @objc private func colorClicked(_ sender: ColorCircleButton) {
        onSelectColor?(sender.color)
        updateColorSelection(activeColor: sender.color)
    }
    @objc private func undoClicked() { onUndo?() }
    @objc private func redoClicked() { onRedo?() }
    @objc private func saveClicked() { onSave?() }
    @objc private func copyClicked() { onCopy?() }
}
