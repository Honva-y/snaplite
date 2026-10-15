import AppKit
import ScreenCaptureKit
import Stitching

/// 长截图会话（手动滚动）：监听用户在选区内的滚动，停下后截帧并拼接。
@MainActor
final class ScrollCaptureSession {
    var onFinish: ((CGImage?) -> Void)?

    private let snapshot: ScreenSnapshot
    /// 屏幕局部坐标（点）
    private let localRect: CGRect
    private let panel = ScrollPanel()
    private var content: SCShareableContent?
    private var stitcher: ScrollStitcher?
    private var scrollMonitor: Any?
    private var localScrollMonitor: Any?
    private var manualWork: DispatchWorkItem?
    private var capturing = false
    private var pendingCapture = false
    private var finished = false

    private var globalRect: CGRect {
        localRect.offsetBy(dx: snapshot.cgFrame.minX, dy: snapshot.cgFrame.minY)
    }

    init(snapshot: ScreenSnapshot, localRect: CGRect) {
        self.snapshot = snapshot
        self.localRect = localRect
    }

    func start() {
        panel.onFinish = { [weak self] in self?.finish() }
        panel.onCancel = { [weak self] in self?.cancel() }
        panel.update(status: "准备中…", hint: "", thumbnail: nil)
        panel.place(besideRegion: globalRect, on: snapshot.screen)
        panel.orderFrontRegardless()
        panel.makeKey()

        Task { @MainActor in
            do {
                content = try await ScreenCapturer.shareableContent()
                let first = try await captureRegion()
                DebugLog.resetFrames()
                DebugLog.write("session start: region=\(Int(localRect.minX)),\(Int(localRect.minY)) \(Int(localRect.width))x\(Int(localRect.height))pt scale=\(snapshot.scale)")
                DebugLog.dumpFrame(first, name: "frame-000")
                var opts = ScrollStitcher.Options()
                opts.minOverlap = max(40, first.height / 8)
                opts.maxTotalHeight = Int(CGFloat(Preferences.shared.maxLongHeight) * snapshot.scale)
                stitcher = ScrollStitcher(first: first, options: opts)
                refreshPanel(hint: "请在选区内向下滚动，停下后会自动拼接。")
                startMonitoring()
            } catch {
                Exporter.presentError("长截图失败", error.localizedDescription)
                cancel()
            }
        }
    }

    private func captureRegion() async throws -> CGImage {
        try await ScreenCapturer.captureDisplay(snapshot.displayID, rect: localRect,
                                                excludingWindowIDs: [CGWindowID(panel.windowNumber)], content: content)
    }

    /// 截一帧，并等到画面不再变化（滚动动画、懒加载渲染完成）再返回。
    private func captureSettled() async throws -> CGImage {
        var frame = try await captureRegion()
        for _ in 0..<5 {
            try? await Task.sleep(nanoseconds: 70_000_000)
            let again = try await captureRegion()
            let same = await Task.detached(priority: .userInitiated) { ScrollStitcher.framesIdentical(frame, again) }.value
            frame = again
            if same { break }
        }
        return frame
    }

    private func append(_ image: CGImage) async -> ScrollStitcher.AppendResult {
        guard let st = stitcher else { return .noMatch }
        return await Task.detached(priority: .userInitiated) { st.append(image, expectedOffset: nil) }.value
    }

    // MARK: - 监听滚动

    private func startMonitoring() {
        let handler: (NSEvent) -> Void = { [weak self] _ in
            Task { @MainActor in self?.scheduleCapture() }
        }
        scrollMonitor = NSEvent.addGlobalMonitorForEvents(matching: .scrollWheel, handler: handler)
        localScrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
            handler(event)
            return event
        }
    }

    private func scheduleCapture() {
        manualWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor in await self?.captureAndAppend() }
        }
        manualWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
    }

    private func captureAndAppend() async {
        guard !finished else { return }
        if capturing { pendingCapture = true; return }
        capturing = true
        defer {
            capturing = false
            if pendingCapture { pendingCapture = false; scheduleCapture() }
        }
        guard let image = try? await captureSettled() else { return }
        let index = stitcher?.frameCount ?? 0
        DebugLog.dumpFrame(image, name: String(format: "frame-%03d", index))
        let result = await append(image)
        DebugLog.write("manual: result=\(result) [\(stitcher?.lastDebug ?? "")]")
        switch result {
        case .appended:
            refreshPanel(hint: "继续滚动，或点“完成”。")
        case .noChange:
            break
        case .noMatch:
            refreshPanel(hint: "滚得太多，没有重叠部分。请往回滚一点再继续。")
        case .movedUp:
            refreshPanel(hint: "检测到向上滚动，已忽略；请向下滚动。")
        case .limitReached:
            refreshPanel(hint: "已达到最大高度。")
        }
    }

    // MARK: - 面板 / 收尾

    private func refreshPanel(hint: String? = nil) {
        guard let st = stitcher else { return }
        let heightPts = Int(CGFloat(st.totalHeight) / snapshot.scale)
        let status = "已拼接 \(st.frameCount) 帧 · \(heightPts) pt"
        panel.update(status: status, hint: hint ?? "请在选区内向下滚动。", thumbnail: st.thumbnail(width: 320))
    }

    private func stopSources() {
        manualWork?.cancel()
        if let m = scrollMonitor { NSEvent.removeMonitor(m) }
        if let m = localScrollMonitor { NSEvent.removeMonitor(m) }
        scrollMonitor = nil
        localScrollMonitor = nil
    }

    private func finish() {
        guard !finished else { return }
        finished = true
        stopSources()
        panel.setBusy(true)
        panel.update(status: "正在合成…", hint: "", thumbnail: nil)
        let st = stitcher
        Task { @MainActor in
            let image = await Task.detached(priority: .userInitiated) { st?.compose() }.value
            closePanel()
            onFinish?(image)
        }
    }

    private func cancel() {
        guard !finished else { return }
        finished = true
        stopSources()
        closePanel()
        onFinish?(nil)
    }

    private func closePanel() {
        panel.onCancel = nil
        panel.onFinish = nil
        panel.orderOut(nil)
    }
}
