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
    var onSelectTextStyle: ((AnnotationTextStyle) -> Void)?
    var onSelectFillMode: ((RectangleFillMode) -> Void)?
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
    private static weak var colorPanelOwner: ScreenshotEditorToolbar?
    private var ownsColorPanel: Bool { Self.colorPanelOwner === self }
    private lazy var customColor = CustomColorButton(target: self, action: #selector(openColorPicker))
    private let topRow = NSStackView()
    private let bottomRow = NSStackView()
    private let toolsGroup = NSStackView()
    private let actionsGroup = NSStackView()
    private let styleGroup = NSStackView()
    private let colorGroup = NSStackView()
    private let textOptions = NSStackView()
    private lazy var textButton = ClipIconButton(.type, label: "Text — click the image to type", target: self, action: #selector(textClicked))
    private let fontPicker = NSPopUpButton()
    private let fontSizePicker = NSPopUpButton()
    private(set) var textStyle = AnnotationTextStyle()
    private(set) var fillMode: RectangleFillMode = .solid
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
        widthAnchor.constraint(greaterThanOrEqualToConstant: 620).isActive = true
        updateToolSelection(activeTool: .pen)
        updateColorSelection(activeColor: .systemRed)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func setupLayout() {
        configure(toolsGroup, spacing: 2)
        toolsGroup.setHuggingPriority(.required, for: .horizontal)
        for tool in AnnotationTool.allCases where tool != .text {
            let button = AnnotationToolButton(tool.icon, label: tool.title, target: self, action: #selector(toolClicked(_:)))
            button.tag = tool.rawValue
            button.toolTip = tool == .filledRect ? "Filled Rectangle — drag to cover an area" : "\(tool.title) · Right-click for line width"
            if tool != .eraser {
                button.widthMenu = { [weak self] in self?.makeWidthMenu(for: tool) ?? NSMenu() }
            }
            size(button, width: 28, height: 28)
            toolButtons[tool] = button
            toolsGroup.addArrangedSubview(button)
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

        configure(styleGroup, spacing: 6)
        styleGroup.setHuggingPriority(.required, for: .horizontal)
        styleGroup.addArrangedSubview(colorGroup)
        styleGroup.addArrangedSubview(makeSeparator())
        size(textButton, width: 30, height: 30)
        textButton.setAccessibilityHelp("Select Text, then click the image to type. Press Return on the canvas to add text from the keyboard.")
        styleGroup.addArrangedSubview(textButton)
        configure(textOptions, spacing: 6)
        for font in AnnotationFont.available {
            fontPicker.addItem(withTitle: font.title)
            fontPicker.lastItem?.tag = font.rawValue
        }
        fontPicker.target = self
        fontPicker.action = #selector(textStyleChanged)
        fontPicker.toolTip = "Text font — installed macOS typefaces"
        fontPicker.setAccessibilityLabel("Text font")
        size(fontPicker, width: 124, height: 26)
        for value in AnnotationTextStyle.sizes {
            fontSizePicker.addItem(withTitle: StrokeWidthMenu.label(value))
            fontSizePicker.lastItem?.representedObject = NSNumber(value: Double(value))
        }
        fontSizePicker.target = self
        fontSizePicker.action = #selector(textStyleChanged)
        fontSizePicker.toolTip = "Text size in image points"
        fontSizePicker.setAccessibilityLabel("Text size")
        size(fontSizePicker, width: 76, height: 26)
        textOptions.addArrangedSubview(fontPicker)
        textOptions.addArrangedSubview(fontSizePicker)
        textOptions.isHidden = true
        styleGroup.addArrangedSubview(textOptions)
        updateTextStyle(textStyle)

        configure(actionsGroup)
        actionsGroup.setHuggingPriority(.required, for: .horizontal)
        undoButton = ClipIconButton(.undo, label: "Undo (⌘Z)", target: self, action: #selector(undoClicked))
        redoButton = ClipIconButton(.redo, label: "Redo (⇧⌘Z)", target: self, action: #selector(redoClicked))
        for button in [undoButton!, redoButton!] {
            button.isEnabled = false
            size(button, width: 28, height: 28)
            actionsGroup.addArrangedSubview(button)
        }
        actionsGroup.addArrangedSubview(makeSeparator())
        let save = NSButton(title: "Save…", target: self, action: #selector(saveClicked))
        let copy = NSButton(title: "Copy", target: self, action: #selector(copyClicked))
        save.toolTip = "Save to disk (⌘S)"
        copy.toolTip = "Copy to clipboard and close (Enter / ⌘C)"
        copy.keyEquivalent = "\r"
        for button in [save, copy] {
            button.bezelStyle = .rounded
            button.controlSize = .regular
            actionsGroup.addArrangedSubview(button)
        }

        configure(topRow, spacing: 8)
        configure(bottomRow, spacing: 8)
        topRow.addArrangedSubview(toolsGroup)
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        spacer.widthAnchor.constraint(greaterThanOrEqualToConstant: 8).isActive = true
        topRow.addArrangedSubview(spacer)
        topRow.addArrangedSubview(actionsGroup)
        bottomRow.addArrangedSubview(styleGroup)
        for row in [topRow, bottomRow] {
            // Row widths are assigned during reflow, so their current contents
            // cannot impose a stale minimum width on the resizable editor window.
            row.translatesAutoresizingMaskIntoConstraints = true
            addSubview(row)
        }
        colorDivider.boxType = .separator
        size(colorDivider, width: 1, height: 18)
    }

    override func layout() {
        updateRowLayout()
        let width = max(0, bounds.width - 2 * 14)
        topRow.frame = NSRect(x: 14, y: bounds.height - 7 - 30, width: width, height: 30)
        bottomRow.frame = NSRect(x: 14, y: bounds.height - 7 - 30 - 6 - 30, width: width, height: 30)
        super.layout()
    }

    private func updateRowLayout() {
        // Measure the visible controls, including contextual font settings. Selecting
        // Text must not add a row when the current window already has enough room.
        let requiredWidth = contentWidth(toolsGroup) + contentWidth(styleGroup)
            + contentWidth(actionsGroup) + 1 + 4 * 8 + 2 * 14 + 8
        let compact = bounds.width < max(780, ceil(requiredWidth))
        guard compact != isCompact else { return }
        isCompact = compact
        styleGroup.removeFromSuperview()
        colorDivider.removeFromSuperview()
        if compact {
            bottomRow.addArrangedSubview(styleGroup)
        } else {
            topRow.insertArrangedSubview(colorDivider, at: 1)
            topRow.insertArrangedSubview(styleGroup, at: 2)
        }
        bottomRow.isHidden = !compact
        preferredHeight = compact ? 80 : 44
        onPreferredHeightChange?(preferredHeight)
    }

    /// Measure the controls' natural widths independently of their current row.
    /// A constrained stack's fitting size can reflect the current row allocation.
    private func contentWidth(_ view: NSView) -> CGFloat {
        if let stack = view as? NSStackView {
            let visible = stack.arrangedSubviews.filter { !$0.isHidden }
            return visible.reduce(CGFloat.zero) { $0 + contentWidth($1) }
                + CGFloat(max(0, visible.count - 1)) * stack.spacing
        }
        if let width = view.constraints.first(where: {
            $0.isActive && $0.firstAttribute == .width && $0.relation == .equal
                && $0.secondItem == nil && $0.firstItem as? NSView === view
        }) { return width.constant }
        return max(0, view.intrinsicContentSize.width)
    }

    func updateTextStyle(_ style: AnnotationTextStyle) {
        textStyle = style
        fontPicker.selectItem(withTag: style.font.rawValue)
        fontSizePicker.selectItem(at: AnnotationTextStyle.sizes.firstIndex(of: style.size) ?? 3)
    }

    func selectTextStyle(_ style: AnnotationTextStyle) {
        guard AnnotationTextStyle.sizes.contains(style.size), style.font.isAvailable else { return }
        updateTextStyle(style)
        onSelectTextStyle?(style)
    }

    @objc private func textStyleChanged() {
        guard let font = AnnotationFont(rawValue: fontPicker.selectedTag()),
              let size = fontSizePicker.selectedItem?.representedObject as? NSNumber else { return }
        selectTextStyle(AnnotationTextStyle(font: font, size: CGFloat(size.doubleValue)))
    }

    @objc private func textClicked() { onSelectTool?(.text) }

    func lineWidth(for tool: AnnotationTool) -> CGFloat { widths[tool] ?? tool.defaultLineWidth }

    func selectLineWidth(_ width: CGFloat, for tool: AnnotationTool) {
        guard tool.usesLineWidth, tool.lineWidths.contains(width) else { return }
        widths[tool] = width
        updateToolSelection(activeTool: tool)
        onSelectTool?(tool)
        onSelectLineWidth?(width)
    }

    func selectFillMode(_ mode: RectangleFillMode) {
        fillMode = mode
        onSelectTool?(.filledRect)
        onSelectFillMode?(mode)
        updateToolSelection(activeTool: .filledRect)
    }

    func makeWidthMenu(for tool: AnnotationTool) -> NSMenu {
        if tool == .eraser { return NSMenu(title: "Eraser") }
        if tool == .filledRect {
            return RectangleFillMenu(mode: fillMode) { [weak self] in self?.selectFillMode($0) }
        }
        return StrokeWidthMenu(tool: tool, width: lineWidth(for: tool)) { [weak self] in self?.selectLineWidth($0, for: tool) }
    }

    func updateToolSelection(activeTool: AnnotationTool) {
        textButton.setActive(activeTool == .text)
        textButton.setAccessibilityValue(activeTool == .text ? "Selected" : "Not selected")
        textOptions.isHidden = activeTool != .text
        updateRowLayout()
        needsLayout = true
        for (tool, button) in toolButtons {
            button.setActive(tool == activeTool)
            if tool == .eraser {
                button.setAccessibilityValue(tool == activeTool ? "Selected" : "Not selected")
                button.toolTip = "Eraser — click an annotation to remove it"
                button.setAccessibilityHelp("Click one annotation to delete it. Command-Z restores it. The screenshot itself is preserved.")
                continue
            }
            if tool == .filledRect {
                button.image = fillMode.icon.image()
                button.setAccessibilityLabel(fillMode.title)
                button.setAccessibilityValue("\(tool == activeTool ? "Selected" : "Not selected"), \(fillMode.title)")
                button.toolTip = "\(fillMode.title) · Right-click for Fill or Blur"
                button.setAccessibilityHelp("Right-click or press Shift-F10 to choose Solid Fill or Blur Area")
                continue
            }
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
        Self.colorPanelOwner = self
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
        Self.colorPanelOwner = nil
    }

    @objc private func customColorChanged(_ sender: NSColorPanel) {
        onSelectColor?(sender.color)
        updateColorSelection(activeColor: sender.color)
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
