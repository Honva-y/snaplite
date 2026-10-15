import AppKit

/// 选区确定后出现的小工具条：矩形 / 箭头 / 颜色 / 撤销 / 完成 / 取消。
final class AnnotationToolbar: NSView {
    var onTool: ((AnnotationTool) -> Void)?
    var onColor: ((NSColor) -> Void)?
    var onFontSize: ((CGFloat) -> Void)?
    var onUndo: (() -> Void)?
    var onPin: (() -> Void)?
    var onScroll: (() -> Void)?
    var onDone: (() -> Void)?
    var onCancel: (() -> Void)?

    private var toolButtons: [AnnotationTool: NSButton] = [:]
    private var swatches: [SwatchButton] = []
    private let undoButton: NSButton
    private let fontSizePopup = NSPopUpButton(frame: .zero, pullsDown: false)

    init(allowAnnotations: Bool, initialColor: NSColor, initialFontSize: CGFloat) {
        undoButton = NSButton()
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.78).cgColor
        layer?.cornerRadius = 8

        var views: [NSView] = []
        if allowAnnotations {
            let rect = makeButton("rectangle", tip: "矩形框 (R)", action: #selector(rectTapped))
            let arrow = makeButton("arrow.up.right", tip: "箭头 (A)", action: #selector(arrowTapped))
            let pen = makeButton("pencil.tip", tip: "画笔 (P)", action: #selector(penTapped))
            let mosaic = makeButton("checkerboard.rectangle", tip: "打码 (M)", action: #selector(mosaicTapped))
            let text = makeButton("t.square", tip: "文字 (T)", action: #selector(textTapped))
            toolButtons[.rect] = rect
            toolButtons[.arrow] = arrow
            toolButtons[.pen] = pen
            toolButtons[.mosaic] = mosaic
            toolButtons[.text] = text
            for size in AnnotationRenderer.fontSizes { fontSizePopup.addItem(withTitle: "\(Int(size))") }
            fontSizePopup.selectItem(withTitle: "\(Int(initialFontSize))")
            fontSizePopup.isBordered = false
            fontSizePopup.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
            fontSizePopup.contentTintColor = .white
            fontSizePopup.toolTip = "文字大小"
            fontSizePopup.target = self
            fontSizePopup.action = #selector(fontSizeChanged)
            fontSizePopup.translatesAutoresizingMaskIntoConstraints = false
            fontSizePopup.widthAnchor.constraint(equalToConstant: 52).isActive = true
            views += [rect, arrow, pen, mosaic, text, fontSizePopup, separator()]
            for c in AnnotationRenderer.palette {
                let s = SwatchButton(color: c)
                s.target = self
                s.action = #selector(swatchTapped(_:))
                s.isSelected = c == initialColor
                swatches.append(s)
                views.append(s)
            }
            configure(undoButton, "arrow.uturn.backward", tip: "撤销 (⌘Z)", action: #selector(undoTapped))
            let pin = makeButton("pin", tip: "钉在桌面 (⌘P)", action: #selector(pinTapped))
            let scroll = makeButton("rectangle.expand.vertical", tip: "从此选区开始滚动截图 (⌘L)", action: #selector(scrollTapped))
            views += [separator(), undoButton, separator(), pin, scroll, separator()]
        }
        let done = makeButton("checkmark", tip: "完成（双击选区 / 回车）", action: #selector(doneTapped))
        done.contentTintColor = NSColor(srgbRed: 0.3, green: 0.85, blue: 0.4, alpha: 1)
        let cancel = makeButton("xmark", tip: "取消 (Esc)", action: #selector(cancelTapped))
        cancel.contentTintColor = NSColor(srgbRed: 1, green: 0.4, blue: 0.4, alpha: 1)
        views += [done, cancel]

        let stack = NSStackView(views: views)
        stack.orientation = .horizontal
        stack.spacing = 4
        stack.edgeInsets = NSEdgeInsets(top: 5, left: 6, bottom: 5, right: 6)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        frame.size = stack.fittingSize
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    func setTool(_ tool: AnnotationTool) {
        for (t, b) in toolButtons {
            b.layer?.backgroundColor = t == tool ? NSColor.white.withAlphaComponent(0.25).cgColor : nil
        }
    }

    func setColor(_ color: NSColor) {
        for s in swatches { s.isSelected = s.color == color }
    }

    private func makeButton(_ symbol: String, tip: String, action: Selector) -> NSButton {
        let b = NSButton()
        configure(b, symbol, tip: tip, action: action)
        return b
    }

    private func configure(_ b: NSButton, _ symbol: String, tip: String, action: Selector) {
        b.image = NSImage(systemSymbolName: symbol, accessibilityDescription: tip)?
            .withSymbolConfiguration(.init(pointSize: 14, weight: .medium))
        b.isBordered = false
        b.imagePosition = .imageOnly
        b.contentTintColor = .white
        b.toolTip = tip
        b.target = self
        b.action = action
        b.wantsLayer = true
        b.layer?.cornerRadius = 5
        b.translatesAutoresizingMaskIntoConstraints = false
        b.widthAnchor.constraint(equalToConstant: 28).isActive = true
        b.heightAnchor.constraint(equalToConstant: 26).isActive = true
    }

    private func separator() -> NSView {
        let v = NSView()
        v.wantsLayer = true
        v.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.25).cgColor
        v.translatesAutoresizingMaskIntoConstraints = false
        v.widthAnchor.constraint(equalToConstant: 1).isActive = true
        v.heightAnchor.constraint(equalToConstant: 18).isActive = true
        return v
    }

    @objc private func rectTapped() { onTool?(.rect) }
    @objc private func arrowTapped() { onTool?(.arrow) }
    @objc private func penTapped() { onTool?(.pen) }
    @objc private func mosaicTapped() { onTool?(.mosaic) }
    @objc private func textTapped() { onTool?(.text) }
    @objc private func fontSizeChanged() {
        if let t = fontSizePopup.titleOfSelectedItem, let v = Double(t) { onFontSize?(CGFloat(v)) }
    }
    @objc private func undoTapped() { onUndo?() }
    @objc private func doneTapped() { onDone?() }
    @objc private func pinTapped() { onPin?() }
    @objc private func scrollTapped() { onScroll?() }
    @objc private func cancelTapped() { onCancel?() }
    @objc private func swatchTapped(_ sender: SwatchButton) { onColor?(sender.color) }
}

final class SwatchButton: NSButton {
    let color: NSColor
    var isSelected = false { didSet { needsDisplay = true } }

    init(color: NSColor) {
        self.color = color
        super.init(frame: .zero)
        isBordered = false
        title = ""
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: 22).isActive = true
        heightAnchor.constraint(equalToConstant: 26).isActive = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        let d: CGFloat = isSelected ? 16 : 13
        let circle = NSBezierPath(ovalIn: CGRect(x: bounds.midX - d / 2, y: bounds.midY - d / 2, width: d, height: d))
        color.setFill()
        circle.fill()
        NSColor.white.withAlphaComponent(isSelected ? 1 : 0.5).setStroke()
        circle.lineWidth = isSelected ? 2 : 1
        circle.stroke()
    }
}
