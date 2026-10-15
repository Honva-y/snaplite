import AppKit

/// 长截图进行中的悬浮控制面板：实时缩略图、状态、完成/取消。
final class ScrollPanel: NSPanel {
    var onFinish: (() -> Void)?
    var onCancel: (() -> Void)?

    private let statusLabel = NSTextField(labelWithString: "")
    private let hintLabel = NSTextField(wrappingLabelWithString: "")
    private let imageView = NSImageView()
    private let finishButton = NSButton(title: "完成", target: nil, action: nil)
    private let cancelButton = NSButton(title: "取消", target: nil, action: nil)
    private let thumbWidth: CGFloat = 160
    private let maxThumbHeight: CGFloat = 320

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 200, height: 200),
                   styleMask: [.titled, .nonactivatingPanel, .utilityWindow, .closable],
                   backing: .buffered, defer: false)
        title = "长截图"
        isFloatingPanel = true
        level = .floating
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = false
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        statusLabel.font = .systemFont(ofSize: 12, weight: .medium)
        hintLabel.font = .systemFont(ofSize: 11)
        hintLabel.textColor = .secondaryLabelColor
        hintLabel.preferredMaxLayoutWidth = thumbWidth
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.imageAlignment = .alignTop
        imageView.wantsLayer = true
        imageView.layer?.borderColor = NSColor.separatorColor.cgColor
        imageView.layer?.borderWidth = 1
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.widthAnchor.constraint(equalToConstant: thumbWidth).isActive = true
        thumbHeightConstraint = imageView.heightAnchor.constraint(equalToConstant: 60)
        thumbHeightConstraint.isActive = true

        finishButton.target = self
        finishButton.action = #selector(finishTapped)
        finishButton.keyEquivalent = "\r"
        cancelButton.target = self
        cancelButton.action = #selector(cancelTapped)
        cancelButton.keyEquivalent = "\u{1b}"
        let buttons = NSStackView(views: [cancelButton, finishButton])
        buttons.orientation = .horizontal
        buttons.spacing = 8

        let stack = NSStackView(views: [statusLabel, imageView, hintLabel, buttons])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView = stack
        setContentSize(stack.fittingSize)
    }

    private var thumbHeightConstraint: NSLayoutConstraint!

    override var canBecomeKey: Bool { true }

    func update(status: String, hint: String, thumbnail: CGImage?) {
        statusLabel.stringValue = status
        hintLabel.stringValue = hint
        if let t = thumbnail {
            let h = min(maxThumbHeight, thumbWidth * CGFloat(t.height) / CGFloat(max(1, t.width)))
            thumbHeightConstraint.constant = max(24, h)
            imageView.image = NSImage(cgImage: t, size: NSSize(width: thumbWidth, height: h))
        }
        if let stack = contentView as? NSStackView {
            let size = stack.fittingSize
            let origin = frame.origin
            let topLeft = NSPoint(x: origin.x, y: frame.maxY)
            setContentSize(size)
            setFrameTopLeftPoint(topLeft)
        }
    }

    func setBusy(_ busy: Bool) {
        finishButton.isEnabled = !busy
        cancelButton.isEnabled = !busy
    }

    override func close() {
        onCancel?()
        super.close()
    }

    @objc private func finishTapped() { onFinish?() }
    @objc private func cancelTapped() { onCancel?() }

    /// 把面板放到选区旁边（不遮挡选区）。`region` 为 CG 全局坐标。
    func place(besideRegion region: CGRect, on screen: NSScreen) {
        let screenCG = CGDisplayBounds(screen.displayID)
        let size = frame.size
        let gap: CGFloat = 16
        var originCG: CGPoint
        if region.maxX + gap + size.width <= screenCG.maxX {
            originCG = CGPoint(x: region.maxX + gap, y: region.minY)
        } else if region.minX - gap - size.width >= screenCG.minX {
            originCG = CGPoint(x: region.minX - gap - size.width, y: region.minY)
        } else {
            originCG = CGPoint(x: screenCG.maxX - size.width - gap, y: screenCG.minY + 40)
        }
        originCG.y = min(max(originCG.y, screenCG.minY + 30), screenCG.maxY - size.height - gap)
        let appKit = CoordinateSpace.appKitRect(fromCG: CGRect(origin: originCG, size: size))
        setFrameOrigin(appKit.origin)
    }
}
