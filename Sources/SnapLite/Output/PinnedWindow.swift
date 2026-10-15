import AppKit

/// 钉在桌面上的截图：无边框浮动窗口，可拖动、滚轮缩放，右键菜单复制 / 保存 / 关闭，Esc 关闭。
@MainActor
final class PinnedWindow: NSPanel {
    private(set) static var all: [PinnedWindow] = []

    private let image: CGImage
    private let scale: CGFloat
    private let originalSize: NSSize
    private var zoom: CGFloat = 1

    static func pin(image: CGImage, scale: CGFloat, screenLocalRect: CGRect, snapshot: ScreenSnapshot) {
        let globalCG = screenLocalRect.offsetBy(dx: snapshot.cgFrame.minX, dy: snapshot.cgFrame.minY)
        let frame = CoordinateSpace.appKitRect(fromCG: globalCG)
        let w = PinnedWindow(image: image, scale: scale, frame: frame)
        all.append(w)
        w.orderFrontRegardless()
        w.makeKey()
    }

    static func closeAll() {
        for w in all { w.orderOut(nil) }
        all.removeAll()
    }

    private init(image: CGImage, scale: CGFloat, frame: CGRect) {
        self.image = image
        self.scale = scale
        self.originalSize = NSSize(width: CGFloat(image.width) / scale, height: CGFloat(image.height) / scale)
        super.init(contentRect: NSRect(origin: frame.origin, size: originalSize), styleMask: [.borderless],
                   backing: .buffered, defer: false)
        level = .floating
        isFloatingPanel = true
        isMovableByWindowBackground = true
        hasShadow = true
        isOpaque = false
        backgroundColor = .clear
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let view = PinnedImageView(frame: NSRect(origin: .zero, size: originalSize))
        view.image = NSImage(cgImage: image, size: originalSize)
        view.imageScaling = .scaleAxesIndependently
        view.autoresizingMask = [.width, .height]
        view.wantsLayer = true
        view.layer?.borderWidth = 1
        view.layer?.borderColor = NSColor.controlAccentColor.withAlphaComponent(0.8).cgColor
        contentView = view
    }

    override var canBecomeKey: Bool { true }

    override func mouseDown(with event: NSEvent) {
        // NSImageView 默认不允许点击拖动窗口，这里显式拖
        performDrag(with: event)
    }

    override func keyDown(with event: NSEvent) {
        let cmd = event.modifierFlags.contains(.command)
        switch (event.keyCode, cmd) {
        case (53, _), (13, true): dismiss()          // Esc / ⌘W
        case (8, true): copyImage()                  // ⌘C
        case (1, true): saveImage()                  // ⌘S
        case (29, true): resetSize()                 // ⌘0
        default: super.keyDown(with: event)
        }
    }

    override func scrollWheel(with event: NSEvent) {
        let delta = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY / 50 : event.scrollingDeltaY / 5
        guard delta != 0 else { return }
        setZoom(min(5, max(0.2, zoom * (1 + delta * 0.1))))
    }

    override func rightMouseDown(with event: NSEvent) {
        let menu = NSMenu()
        menu.addItem(withTitle: "复制图片  ⌘C", action: #selector(copyImage), keyEquivalent: "").target = self
        menu.addItem(withTitle: "保存到文件  ⌘S", action: #selector(saveImage), keyEquivalent: "").target = self
        menu.addItem(withTitle: "恢复原始大小  ⌘0", action: #selector(resetSize), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "关闭  Esc", action: #selector(dismiss), keyEquivalent: "").target = self
        menu.addItem(withTitle: "关闭所有钉图", action: #selector(dismissAll), keyEquivalent: "").target = self
        NSMenu.popUpContextMenu(menu, with: event, for: contentView!)
    }

    private func setZoom(_ z: CGFloat) {
        zoom = z
        let size = NSSize(width: originalSize.width * z, height: originalSize.height * z)
        let center = NSPoint(x: frame.midX, y: frame.midY)
        setFrame(NSRect(x: center.x - size.width / 2, y: center.y - size.height / 2, width: size.width, height: size.height),
                 display: true)
    }

    @objc private func copyImage() { Exporter.copyToClipboard(image, scale: scale) }

    @objc private func saveImage() {
        do {
            let url = try Exporter.save(image, scale: scale, suffix: " 钉图")
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch {
            Exporter.presentError("保存失败", error.localizedDescription)
        }
    }

    @objc private func resetSize() { setZoom(1) }

    @objc private func dismiss() {
        orderOut(nil)
        PinnedWindow.all.removeAll { $0 === self }
    }

    @objc private func dismissAll() { PinnedWindow.closeAll() }
}

private final class PinnedImageView: NSImageView {
    override var mouseDownCanMoveWindow: Bool { true }
    override func mouseDown(with event: NSEvent) { window?.performDrag(with: event) }
}
