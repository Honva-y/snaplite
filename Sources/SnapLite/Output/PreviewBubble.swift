import AppKit

/// 截图完成后右下角的小预览，点击可在 Finder 中显示，几秒后自动消失。
@MainActor
final class PreviewBubble {
    private static var current: PreviewBubble?

    private let panel: NSPanel
    private let fileURL: URL?
    private var timer: Timer?

    static func show(image: CGImage, fileURL: URL?, copied: Bool) {
        current?.close()
        let bubble = PreviewBubble(image: image, fileURL: fileURL, copied: copied)
        current = bubble
        bubble.present()
    }

    private init(image: CGImage, fileURL: URL?, copied: Bool) {
        self.fileURL = fileURL
        let width: CGFloat = 240
        let maxThumbHeight: CGFloat = 180
        let aspect = CGFloat(image.height) / CGFloat(max(1, image.width))
        let thumbWidth = width - 24
        let thumbHeight = min(maxThumbHeight, thumbWidth * aspect)
        let height = thumbHeight + 52

        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: width, height: height),
                        styleMask: [.nonactivatingPanel, .borderless], backing: .buffered, defer: false)
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.hidesOnDeactivate = false

        let container = NSVisualEffectView(frame: panel.contentView!.bounds)
        container.material = .hudWindow
        container.state = .active
        container.wantsLayer = true
        container.layer?.cornerRadius = 12
        container.layer?.masksToBounds = true
        panel.contentView = container

        let imageView = NSImageView(frame: NSRect(x: 12, y: 40, width: thumbWidth, height: thumbHeight))
        imageView.image = NSImage(cgImage: image, size: NSSize(width: thumbWidth, height: thumbHeight))
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.wantsLayer = true
        imageView.layer?.cornerRadius = 6
        imageView.layer?.masksToBounds = true
        container.addSubview(imageView)

        let text: String
        if let url = fileURL {
            let place = Preferences.shared.saveLocation == .temporary ? "临时目录" : url.deletingLastPathComponent().lastPathComponent
            text = "已保存到 \(place)\(copied ? "，并已复制" : "") · 点击查看"
        } else {
            text = copied ? "已复制到剪贴板" : "完成"
        }
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 11)
        label.textColor = .secondaryLabelColor
        label.lineBreakMode = .byTruncatingMiddle
        label.frame = NSRect(x: 12, y: 12, width: thumbWidth, height: 18)
        container.addSubview(label)

        let click = NSClickGestureRecognizer(target: self, action: #selector(clicked))
        container.addGestureRecognizer(click)
    }

    private func present() {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let vf = screen.visibleFrame
        let size = panel.frame.size
        panel.setFrameOrigin(NSPoint(x: vf.maxX - size.width - 16, y: vf.minY + 16))
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            panel.animator().alphaValue = 1
        }
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.close() }
        }
    }

    @objc private func clicked() {
        if let url = fileURL {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
        close()
    }

    private func close() {
        timer?.invalidate()
        timer = nil
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.15
            panel.animator().alphaValue = 0
        }, completionHandler: { [panel] in
            panel.orderOut(nil)
        })
        if PreviewBubble.current === self { PreviewBubble.current = nil }
    }
}
