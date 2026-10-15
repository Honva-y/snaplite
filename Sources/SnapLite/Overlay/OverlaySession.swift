import AppKit

/// 一次选区交互：每块屏幕一个全屏覆盖窗口，任意一个窗口完成选择后整体关闭。
@MainActor
final class OverlaySession {
    enum Mode { case region, scrollRegion, window }

    /// 选区确定后用户选择的动作
    enum RegionAction: Equatable { case capture, pin, scroll }

    enum Result {
        case cancelled
        /// 屏幕局部坐标（左上原点，点）的矩形、用户画的标注、以及选择的动作
        case region(ScreenSnapshot, CGRect, [Annotation], RegionAction)
        case window(ScreenSnapshot, WindowInfo)
    }

    var onComplete: ((Result) -> Void)?

    private let snapshots: [ScreenSnapshot]
    private let mode: Mode
    private var windows: [OverlayWindow] = []
    private var finished = false

    init(snapshots: [ScreenSnapshot], mode: Mode) {
        self.snapshots = snapshots
        self.mode = mode
    }

    func show() {
        let visible = WindowLister.onScreenWindows()
        for snap in snapshots {
            let local = visible.filter { $0.bounds.intersects(snap.cgFrame) }
            let w = OverlayWindow(snapshot: snap, windows: local, mode: mode, session: self)
            windows.append(w)
            w.orderFrontRegardless()
        }
        NSApp.activate(ignoringOtherApps: true)
        let mouse = CoordinateSpace.cgPoint(fromAppKit: NSEvent.mouseLocation)
        let target = windows.first { $0.snapshot.cgFrame.contains(mouse) } ?? windows.first
        target?.makeKeyAndOrderFront(nil)
        target?.selectionView.refreshHover()
    }

    // MARK: - 来自 SelectionView 的回调

    func requestKey(_ window: OverlayWindow) {
        guard !finished, !window.isKeyWindow else { return }
        window.makeKey()
    }

    func interactionBegan(in view: SelectionView) {
        for w in windows where w.selectionView !== view { w.selectionView.clearHover() }
    }

    func didSelectRegion(_ rect: CGRect, annotations: [Annotation], action: RegionAction, in snapshot: ScreenSnapshot) {
        complete(.region(snapshot, rect, annotations, action))
    }

    func didSelectWindow(_ info: WindowInfo, in snapshot: ScreenSnapshot) {
        complete(.window(snapshot, info))
    }

    func cancel() {
        complete(.cancelled)
    }

    private func complete(_ result: Result) {
        guard !finished else { return }
        finished = true
        for w in windows { w.orderOut(nil) }
        windows.removeAll()
        onComplete?(result)
    }
}

final class OverlayWindow: NSWindow {
    let snapshot: ScreenSnapshot
    let selectionView: SelectionView

    init(snapshot: ScreenSnapshot, windows: [WindowInfo], mode: OverlaySession.Mode, session: OverlaySession) {
        self.snapshot = snapshot
        selectionView = SelectionView(snapshot: snapshot, windows: windows, mode: mode, session: session)
        super.init(contentRect: snapshot.screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        level = .screenSaver
        isOpaque = true
        backgroundColor = .black
        hasShadow = false
        ignoresMouseEvents = false
        acceptsMouseMovedEvents = true
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        contentView = selectionView
        initialFirstResponder = selectionView
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
