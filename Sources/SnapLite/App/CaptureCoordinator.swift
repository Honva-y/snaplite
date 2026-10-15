import AppKit

/// 串起一次完整的截图流程：权限 → 冻结屏幕 → 选区 → 截取 → 输出。
@MainActor
final class CaptureCoordinator {
    enum Mode {
        case region, window, fullscreen, scroll
    }

    var onCountdown: ((Int?) -> Void)?

    private var overlay: OverlaySession?
    private var scrollSession: ScrollCaptureSession?
    private var previousApp: NSRunningApplication?
    private var busy = false
    private var countdownTimer: Timer?

    func start(_ mode: Mode, delay: Int = 0) {
        guard !busy else { return }
        guard Permissions.screenRecordingGranted else {
            Permissions.requestScreenRecording()
            Exporter.presentError("需要屏幕录制权限", "请在「系统设置 → 隐私与安全性 → 屏幕录制」中允许 SnapLite，然后重新打开应用。")
            Permissions.openScreenRecordingSettings()
            return
        }
        busy = true
        previousApp = NSWorkspace.shared.frontmostApplication
        if delay > 0 {
            countdown(delay) { [weak self] in self?.begin(mode) }
        } else {
            begin(mode)
        }
    }

    private var countdownRemaining = 0

    private func countdown(_ seconds: Int, then: @escaping () -> Void) {
        countdownRemaining = seconds
        onCountdown?(seconds)
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] t in
            Task { @MainActor in
                guard let self else { t.invalidate(); return }
                self.countdownRemaining -= 1
                if self.countdownRemaining <= 0 {
                    t.invalidate()
                    self.countdownTimer = nil
                    self.onCountdown?(nil)
                    then()
                } else {
                    self.onCountdown?(self.countdownRemaining)
                }
            }
        }
    }

    private func begin(_ mode: Mode) {
        Task { @MainActor in
            do {
                let snapshots = try await ScreenCapturer.snapshotAllScreens()
                switch mode {
                case .fullscreen:
                    for (i, s) in snapshots.enumerated() {
                        Exporter.export(s.image, scale: s.scale, suffix: snapshots.count > 1 ? " 屏幕\(i + 1)" : "")
                    }
                    finish()
                case .window:
                    showOverlay(snapshots, overlayMode: .window, mode: mode)
                case .region:
                    showOverlay(snapshots, overlayMode: .region, mode: mode)
                case .scroll:
                    showOverlay(snapshots, overlayMode: .scrollRegion, mode: mode)
                }
            } catch {
                Exporter.presentError("截屏失败", error.localizedDescription)
                finish()
            }
        }
    }

    private func showOverlay(_ snapshots: [ScreenSnapshot], overlayMode: OverlaySession.Mode, mode: Mode) {
        let session = OverlaySession(snapshots: snapshots, mode: overlayMode)
        session.onComplete = { [weak self] result in self?.handle(result, mode: mode) }
        overlay = session
        session.show()
    }

    private func handle(_ result: OverlaySession.Result, mode: Mode) {
        overlay = nil
        switch result {
        case .cancelled:
            finish()
        case .region(let snap, let rect, let annotations, let action):
            if case .scroll = mode {
                startScroll(snap, rect)
                return
            }
            switch action {
            case .scroll:
                startScroll(snap, rect)
            case .capture, .pin:
                if let img = snap.crop(localRect: rect) {
                    let final = AnnotationRenderer.render(image: img, annotations: annotations, cropOrigin: rect.origin, scale: snap.scale)
                    if action == .pin {
                        PinnedWindow.pin(image: final, scale: snap.scale, screenLocalRect: rect, snapshot: snap)
                    } else {
                        Exporter.export(final, scale: snap.scale)
                    }
                }
                finish()
            }
        case .window(let snap, let info):
            let localRect = info.bounds.offsetBy(dx: -snap.cgFrame.minX, dy: -snap.cgFrame.minY)
                .intersection(CGRect(origin: .zero, size: snap.cgFrame.size)).integral
            if case .scroll = mode {
                startScroll(snap, localRect)
                return
            }
            Task { @MainActor in
                // 覆盖层刚关闭，给 WindowServer 一点时间
                try? await Task.sleep(nanoseconds: 60_000_000)
                if let img = try? await ScreenCapturer.captureWindow(info.id, scale: snap.scale) {
                    Exporter.export(img, scale: snap.scale)
                } else if let img = snap.crop(localRect: localRect) {
                    Exporter.export(img, scale: snap.scale)
                }
                finish()
            }
        }
    }

    private func startScroll(_ snap: ScreenSnapshot, _ rect: CGRect) {
        let session = ScrollCaptureSession(snapshot: snap, localRect: rect)
        session.onFinish = { [weak self] image in
            self?.scrollSession = nil
            if let image { Exporter.export(image, scale: snap.scale, suffix: " 长图") }
            self?.finish()
        }
        scrollSession = session
        session.start()
    }

    private func finish() {
        busy = false
        if let app = previousApp, app.processIdentifier != getpid() {
            app.activate()
        }
        previousApp = nil
    }
}
