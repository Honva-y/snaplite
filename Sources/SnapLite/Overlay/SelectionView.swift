import AppKit

/// 覆盖在冻结画面上的选区视图。坐标系为翻转（左上原点），单位与屏幕点一致。
/// 流程：拖拽 / 点窗口确定选区 → 出现工具条，可画矩形和箭头 → 双击选区、回车或点 ✓ 完成。
final class SelectionView: NSView, NSTextFieldDelegate {
    private enum Phase { case selecting, selected }

    private let snapshot: ScreenSnapshot
    private let windows: [WindowInfo]
    private let mode: OverlaySession.Mode
    private unowned let session: OverlaySession
    private let image: NSImage

    private var phase: Phase = .selecting
    private var mouse: CGPoint?
    private var dragStart: CGPoint?
    private var selection: CGRect?
    private var hoverWindow: WindowInfo?

    /// 选区确定后的拖拽种类
    private enum DragKind { case move, resize(Edges) }
    private struct Edges: OptionSet {
        let rawValue: Int
        static let top = Edges(rawValue: 1), bottom = Edges(rawValue: 2), left = Edges(rawValue: 4), right = Edges(rawValue: 8)
    }
    private var dragKind: DragKind?
    private var dragOrigin: CGPoint = .zero
    private var dragStartRect: CGRect = .zero
    private let handleTolerance: CGFloat = 6

    private var tool: AnnotationTool = .none
    private var color: NSColor
    private var fontSize: CGFloat
    private var annotations: [Annotation] = []
    private var currentAnnotation: Annotation?
    private var toolbar: AnnotationToolbar?
    private var textEditor: NSTextField?
    private var textEditorOrigin: CGPoint = .zero

    private var allowAnnotations: Bool { mode == .region }

    init(snapshot: ScreenSnapshot, windows: [WindowInfo], mode: OverlaySession.Mode, session: OverlaySession) {
        self.snapshot = snapshot
        self.windows = windows
        self.mode = mode
        self.session = session
        self.image = NSImage(cgImage: snapshot.image, size: snapshot.cgFrame.size)
        self.color = Preferences.shared.annotationColor
        self.fontSize = CGFloat(Preferences.shared.annotationFontSize)
        super.init(frame: CGRect(origin: .zero, size: snapshot.cgFrame.size))
        wantsLayer = true
        let area = NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    // MARK: - 命中测试与光标

    private enum Hit { case outside, inside, edge(Edges) }

    private func hit(_ p: CGPoint, in sel: CGRect) -> Hit {
        let tol = handleTolerance
        guard sel.insetBy(dx: -tol, dy: -tol).contains(p) else { return .outside }
        var e: Edges = []
        if abs(p.x - sel.minX) <= tol { e.insert(.left) }
        if abs(p.x - sel.maxX) <= tol { e.insert(.right) }
        if abs(p.y - sel.minY) <= tol { e.insert(.top) }
        if abs(p.y - sel.maxY) <= tol { e.insert(.bottom) }
        if !e.isEmpty { return .edge(e) }
        return sel.contains(p) ? .inside : .outside
    }

    private func updateCursor(at p: CGPoint) {
        guard phase == .selected, let sel = selection else { NSCursor.crosshair.set(); return }
        if let kind = dragKind {
            if case .move = kind { NSCursor.closedHand.set() }
            return
        }
        switch hit(p, in: sel) {
        case .edge(let e): resizeCursor(for: e).set()
        case .inside:
            switch tool {
            case .none: NSCursor.openHand.set()
            case .text: NSCursor.iBeam.set()
            default: NSCursor.crosshair.set()
            }
        case .outside: NSCursor.crosshair.set()
        }
    }

    private func resizeCursor(for e: Edges) -> NSCursor {
        if #available(macOS 15, *) {
            let position: NSCursor.FrameResizePosition
            switch (e.contains(.top), e.contains(.bottom), e.contains(.left), e.contains(.right)) {
            case (true, _, true, _): position = .topLeft
            case (true, _, _, true): position = .topRight
            case (_, true, true, _): position = .bottomLeft
            case (_, true, _, true): position = .bottomRight
            case (true, _, _, _): position = .top
            case (_, true, _, _): position = .bottom
            case (_, _, true, _): position = .left
            default: position = .right
            }
            return NSCursor.frameResize(position: position, directions: .all)
        }
        let horizontal = e.contains(.left) || e.contains(.right)
        let vertical = e.contains(.top) || e.contains(.bottom)
        if horizontal && vertical { return .crosshair }
        return horizontal ? .resizeLeftRight : .resizeUpDown
    }

    // MARK: - 窗口查找

    private func localRect(of w: WindowInfo) -> CGRect {
        w.bounds.offsetBy(dx: -snapshot.cgFrame.minX, dy: -snapshot.cgFrame.minY).intersection(bounds)
    }

    private func windowUnder(_ p: CGPoint) -> WindowInfo? {
        windows.first { localRect(of: $0).contains(p) }
    }

    func refreshHover() {
        guard phase == .selecting else { return }
        let p = convert(window?.mouseLocationOutsideOfEventStream ?? .zero, from: nil)
        guard bounds.contains(p) else { return }
        mouse = p
        hoverWindow = windowUnder(p)
        needsDisplay = true
    }

    func clearHover() {
        mouse = nil
        hoverWindow = nil
        needsDisplay = true
    }

    // MARK: - 阶段切换

    private func enterSelected() {
        phase = .selected
        hoverWindow = nil
        showToolbar()
        if let m = mouse { updateCursor(at: m) }
        needsDisplay = true
    }

    private func resetToSelecting() {
        phase = .selecting
        selection = nil
        finishTextEditing(save: false)
        annotations.removeAll()
        currentAnnotation = nil
        toolbar?.removeFromSuperview()
        toolbar = nil
        dragKind = nil
        NSCursor.crosshair.set()
        needsDisplay = true
    }

    private func commit(_ action: OverlaySession.RegionAction = .capture) {
        finishTextEditing(save: true)
        guard let sel = selection?.integral, sel.width >= 2, sel.height >= 2 else { return }
        Preferences.shared.annotationColor = color
        Preferences.shared.annotationFontSize = Double(fontSize)
        session.didSelectRegion(sel, annotations: annotations, action: action, in: snapshot)
    }

    private func showToolbar() {
        toolbar?.removeFromSuperview()
        let tb = AnnotationToolbar(allowAnnotations: allowAnnotations, initialColor: color, initialFontSize: fontSize)
        tb.onTool = { [weak self] t in self?.setTool(t) }
        tb.onColor = { [weak self] c in
            self?.color = c
            self?.toolbar?.setColor(c)
        }
        tb.onFontSize = { [weak self] size in
            guard let self else { return }
            self.fontSize = size
            self.textEditor?.font = AnnotationRenderer.font(size: size)
            self.textEditor?.frame.size.height = size + 10
        }
        tb.onUndo = { [weak self] in self?.undo() }
        tb.onDone = { [weak self] in self?.commit() }
        tb.onPin = { [weak self] in self?.commit(.pin) }
        tb.onScroll = { [weak self] in self?.commit(.scroll) }
        tb.onCancel = { [weak self] in self?.session.cancel() }
        tb.setTool(tool)
        addSubview(tb)
        toolbar = tb
        positionToolbar()
    }

    private func positionToolbar() {
        guard let tb = toolbar, let sel = selection else { return }
        let size = tb.frame.size
        let gap: CGFloat = 8
        var y = sel.maxY + gap
        if y + size.height > bounds.maxY { y = sel.minY - gap - size.height }
        if y < 0 { y = sel.maxY - gap - size.height }
        var x = sel.maxX - size.width
        x = min(max(0, x), bounds.maxX - size.width)
        tb.frame = CGRect(origin: CGPoint(x: x, y: y), size: size)
    }

    private func setTool(_ t: AnnotationTool) {
        guard allowAnnotations else { return }
        finishTextEditing(save: true)
        tool = (tool == t) ? .none : t
        toolbar?.setTool(tool)
        if let m = mouse { updateCursor(at: m) }
    }

    // MARK: - 文字输入

    private func beginTextEditing(at p: CGPoint, in sel: CGRect) {
        finishTextEditing(save: true)
        let field = NSTextField(frame: .zero)
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = AnnotationRenderer.font(size: fontSize)
        field.textColor = color
        field.placeholderString = "输入文字，回车确定"
        field.delegate = self
        field.lineBreakMode = .byClipping
        field.cell?.isScrollable = true
        field.cell?.wraps = false
        let width = max(80, sel.maxX - p.x)
        field.frame = CGRect(x: p.x - 2, y: p.y - 2, width: width, height: fontSize + 10)
        addSubview(field)
        textEditor = field
        textEditorOrigin = p
        window?.makeFirstResponder(field)
    }

    private func finishTextEditing(save: Bool) {
        guard let field = textEditor else { return }
        textEditor = nil
        let text = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        field.delegate = nil
        field.removeFromSuperview()
        if save, !text.isEmpty {
            var a = Annotation(kind: .text, start: textEditorOrigin, end: textEditorOrigin, color: color)
            a.text = text
            a.fontSize = fontSize
            annotations.append(a)
        }
        window?.makeFirstResponder(self)
        needsDisplay = true
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        // 回车或失焦：保存
        finishTextEditing(save: true)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            finishTextEditing(save: false)
            return true
        }
        return false
    }

    private func undo() {
        guard !annotations.isEmpty else { return }
        annotations.removeLast()
        needsDisplay = true
    }

    // MARK: - 鼠标

    override func mouseMoved(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        mouse = p
        if phase == .selecting, dragStart == nil { hoverWindow = windowUnder(p) }
        session.requestKey(window as! OverlayWindow)
        updateCursor(at: p)
        needsDisplay = true
    }

    override func mouseEntered(with event: NSEvent) { mouseMoved(with: event) }

    override func mouseExited(with event: NSEvent) {
        if dragStart == nil { clearHover() }
    }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        mouse = p
        if phase == .selected, let sel = selection {
            switch hit(p, in: sel) {
            case .edge(let e):
                dragKind = .resize(e)
                dragOrigin = p
                dragStartRect = sel
                return
            case .inside:
                if event.clickCount == 2 {
                    commit()
                    return
                }
                if textEditor != nil { finishTextEditing(save: true) }
                if tool == .text {
                    beginTextEditing(at: p, in: sel)
                    return
                }
                if tool != .none {
                    var a = Annotation(kind: tool, start: p, end: p, color: color)
                    if tool == .pen { a.points = [p] }
                    currentAnnotation = a
                    dragStart = p
                } else {
                    dragKind = .move
                    dragOrigin = p
                    dragStartRect = sel
                    updateCursor(at: p)
                }
                needsDisplay = true
                return
            case .outside:
                // 点在选区外：重新选择
                resetToSelecting()
            }
        }
        dragStart = p
        selection = nil
        hoverWindow = nil
        session.interactionBegan(in: self)
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        mouse = p
        if let kind = dragKind {
            let dx = p.x - dragOrigin.x, dy = p.y - dragOrigin.y
            var r = dragStartRect
            switch kind {
            case .move:
                r.origin.x = min(max(0, r.minX + dx), bounds.maxX - r.width)
                r.origin.y = min(max(0, r.minY + dy), bounds.maxY - r.height)
            case .resize(let e):
                let minSize: CGFloat = 4
                if e.contains(.left) { let nx = min(max(0, r.minX + dx), r.maxX - minSize); r.size.width = r.maxX - nx; r.origin.x = nx }
                if e.contains(.right) { r.size.width = min(max(minSize, r.width + dx), bounds.maxX - r.minX) }
                if e.contains(.top) { let ny = min(max(0, r.minY + dy), r.maxY - minSize); r.size.height = r.maxY - ny; r.origin.y = ny }
                if e.contains(.bottom) { r.size.height = min(max(minSize, r.height + dy), bounds.maxY - r.minY) }
            }
            selection = r
            positionToolbar()
            needsDisplay = true
            return
        }
        if var a = currentAnnotation, let sel = selection {
            let clamped = CGPoint(x: min(max(p.x, sel.minX), sel.maxX), y: min(max(p.y, sel.minY), sel.maxY))
            a.end = clamped
            if a.kind == .pen { a.points.append(clamped) }
            currentAnnotation = a
        } else if mode != .window, let s = dragStart {
            selection = CGRect(x: min(s.x, p.x), y: min(s.y, p.y), width: abs(p.x - s.x), height: abs(p.y - s.y))
                .intersection(bounds)
        }
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        defer { dragStart = nil }
        if dragKind != nil {
            dragKind = nil
            if let sel = selection { selection = sel.integral }
            positionToolbar()
            updateCursor(at: p)
            needsDisplay = true
            return
        }
        if let a = currentAnnotation {
            currentAnnotation = nil
            let keep = a.kind == .pen ? a.points.count >= 2 : a.length >= 4
            if keep { annotations.append(a) }
            needsDisplay = true
            return
        }
        guard let start = dragStart, phase == .selecting else { return }
        let isClick = hypot(p.x - start.x, p.y - start.y) < 4
        if isClick || mode == .window {
            guard let w = windowUnder(p) else {
                selection = nil
                needsDisplay = true
                return
            }
            if mode == .window {
                session.didSelectWindow(w, in: snapshot)
            } else {
                selection = localRect(of: w).integral
                enterSelected()
            }
            return
        }
        if let sel = selection?.integral, sel.width >= 2, sel.height >= 2 {
            selection = sel
            enterSelected()
        } else {
            selection = nil
            needsDisplay = true
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        if phase == .selected { resetToSelecting() } else { session.cancel() }
    }

    override func keyDown(with event: NSEvent) {
        let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
        switch (event.keyCode, flags) {
        case (53, _): // Esc
            session.cancel()
        case (36, _), (76, _): // Enter
            if phase == .selected {
                commit()
            } else if let w = hoverWindow {
                if mode == .window { session.didSelectWindow(w, in: snapshot) } else { selection = localRect(of: w).integral; enterSelected() }
            }
        case (6, .command): // ⌘Z
            undo()
        case (35, .command): // ⌘P 钉在桌面
            if phase == .selected, allowAnnotations { commit(.pin) }
        case (37, .command): // ⌘L 滚动截图
            if phase == .selected, allowAnnotations { commit(.scroll) }
        case (15, []): // R
            setTool(.rect)
        case (0, []): // A
            setTool(.arrow)
        case (35, []): // P
            setTool(.pen)
        case (46, []): // M
            setTool(.mosaic)
        case (17, []): // T
            setTool(.text)
        default:
            super.keyDown(with: event)
        }
    }

    // MARK: - 绘制

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current else { return }
        image.draw(in: bounds, from: .zero, operation: .copy, fraction: 1, respectFlipped: true, hints: nil)

        let hole: CGRect? = selection ?? (dragStart == nil ? hoverWindow.map(localRect(of:)) : nil)
        let dim = NSBezierPath(rect: bounds)
        if let hole, !hole.isEmpty {
            dim.appendRect(hole)
            dim.windingRule = .evenOdd
        }
        NSColor.black.withAlphaComponent(0.42).setFill()
        dim.fill()

        if let sel = selection, !sel.isEmpty {
            ctx.saveGraphicsState()
            NSBezierPath(rect: sel).addClip()
            for a in annotations { AnnotationRenderer.draw(a, source: snapshot.image, sourceScale: snapshot.scale) }
            if let a = currentAnnotation { AnnotationRenderer.draw(a, source: snapshot.image, sourceScale: snapshot.scale) }
            ctx.restoreGraphicsState()

            NSColor.white.setStroke()
            let border = NSBezierPath(rect: sel.insetBy(dx: -0.5, dy: -0.5))
            border.lineWidth = 1
            border.stroke()
            if phase == .selected { drawHandles(sel) }
            drawLabel(sizeText(sel), anchoredTo: sel)
        } else if let hw = hoverWindow, dragStart == nil {
            let r = localRect(of: hw)
            NSColor.controlAccentColor.setStroke()
            let border = NSBezierPath(rect: r.insetBy(dx: -1, dy: -1))
            border.lineWidth = 2
            border.stroke()
            drawLabel("\(hw.displayName)  \(sizeText(r))", anchoredTo: r)
        }

        if phase == .selecting, let m = mouse, dragStart != nil || mode != .window {
            drawMagnifier(at: m, context: ctx)
        }
        if phase == .selecting && dragStart == nil {
            drawHint(selectingHint)
        } else if phase == .selected && annotations.isEmpty && currentAnnotation == nil {
            drawHint(allowAnnotations ? "双击或回车完成 · ⌘P 钉在桌面 · ⌘L 滚动截图 · R 矩形 A 箭头 P 画笔 M 打码 T 文字" : "双击或回车开始 · 拖动选区移动，拖边缘调整")
        }
    }

    private var selectingHint: String {
        switch mode {
        case .window: return "点击选择窗口 · Esc 取消"
        case .region: return "拖拽选择区域 · 点击选择窗口 · Esc 取消"
        case .scrollRegion: return "框选要滚动截取的区域 · 点击选择窗口 · Esc 取消"
        }
    }

    private func drawHandles(_ sel: CGRect) {
        let d: CGFloat = 7
        let points = [
            CGPoint(x: sel.minX, y: sel.minY), CGPoint(x: sel.midX, y: sel.minY), CGPoint(x: sel.maxX, y: sel.minY),
            CGPoint(x: sel.minX, y: sel.midY), CGPoint(x: sel.maxX, y: sel.midY),
            CGPoint(x: sel.minX, y: sel.maxY), CGPoint(x: sel.midX, y: sel.maxY), CGPoint(x: sel.maxX, y: sel.maxY),
        ]
        for p in points {
            let r = CGRect(x: p.x - d / 2, y: p.y - d / 2, width: d, height: d)
            let path = NSBezierPath(ovalIn: r)
            NSColor.white.setFill()
            path.fill()
            NSColor.controlAccentColor.setStroke()
            path.lineWidth = 1.5
            path.stroke()
        }
    }

    private func sizeText(_ r: CGRect) -> String {
        "\(Int(r.width * snapshot.scale)) × \(Int(r.height * snapshot.scale))"
    }

    private func labelAttributes(size: CGFloat = 12) -> [NSAttributedString.Key: Any] {
        [.font: NSFont.monospacedDigitSystemFont(ofSize: size, weight: .medium), .foregroundColor: NSColor.white]
    }

    private func drawLabel(_ text: String, anchoredTo r: CGRect) {
        let attr = NSAttributedString(string: text, attributes: labelAttributes())
        let size = attr.size()
        let pad: CGFloat = 6
        var origin = CGPoint(x: r.minX, y: r.minY - size.height - pad * 2 - 4)
        if origin.y < 0 { origin.y = r.minY + 4 }
        if origin.x + size.width + pad * 2 > bounds.maxX { origin.x = bounds.maxX - size.width - pad * 2 }
        let bg = CGRect(x: origin.x, y: origin.y, width: size.width + pad * 2, height: size.height + pad)
        NSColor.black.withAlphaComponent(0.7).setFill()
        NSBezierPath(roundedRect: bg, xRadius: 4, yRadius: 4).fill()
        attr.draw(at: CGPoint(x: bg.minX + pad, y: bg.minY + pad / 2))
    }

    private func drawHint(_ text: String) {
        let attr = NSAttributedString(string: text, attributes: labelAttributes(size: 13))
        let size = attr.size()
        let bg = CGRect(x: bounds.midX - size.width / 2 - 12, y: 60, width: size.width + 24, height: size.height + 12)
        NSColor.black.withAlphaComponent(0.6).setFill()
        NSBezierPath(roundedRect: bg, xRadius: 8, yRadius: 8).fill()
        attr.draw(at: CGPoint(x: bg.minX + 12, y: bg.minY + 6))
    }

    private func drawMagnifier(at p: CGPoint, context: NSGraphicsContext) {
        let size: CGFloat = 120
        let zoom: CGFloat = 8
        let srcSize = size / zoom
        let src = CGRect(x: p.x - srcSize / 2, y: p.y - srcSize / 2, width: srcSize, height: srcSize)
        let srcFlipped = CGRect(x: src.minX, y: image.size.height - src.maxY, width: src.width, height: src.height)

        let infoHeight: CGFloat = 22
        var origin = CGPoint(x: p.x + 24, y: p.y + 24)
        if origin.x + size > bounds.maxX { origin.x = p.x - 24 - size }
        if origin.y + size + infoHeight > bounds.maxY { origin.y = p.y - 24 - size - infoHeight }
        let frame = CGRect(x: origin.x, y: origin.y, width: size, height: size)

        context.saveGraphicsState()
        context.imageInterpolation = .none
        NSColor.black.setFill()
        frame.fill()
        image.draw(in: frame, from: srcFlipped, operation: .copy, fraction: 1, respectFlipped: true, hints: nil)
        context.restoreGraphicsState()

        NSColor.controlAccentColor.withAlphaComponent(0.8).setStroke()
        let cross = NSBezierPath()
        cross.move(to: CGPoint(x: frame.midX, y: frame.minY)); cross.line(to: CGPoint(x: frame.midX, y: frame.maxY))
        cross.move(to: CGPoint(x: frame.minX, y: frame.midY)); cross.line(to: CGPoint(x: frame.maxX, y: frame.midY))
        cross.lineWidth = 1
        cross.stroke()
        NSColor.white.setStroke()
        let border = NSBezierPath(rect: frame.insetBy(dx: -0.5, dy: -0.5))
        border.lineWidth = 1
        border.stroke()

        var info = "(\(Int(p.x)), \(Int(p.y)))"
        if let sel = selection, !sel.isEmpty { info += "  \(sizeText(sel))" }
        let attr = NSAttributedString(string: info, attributes: labelAttributes(size: 11))
        let bg = CGRect(x: frame.minX, y: frame.maxY, width: size, height: infoHeight)
        NSColor.black.withAlphaComponent(0.75).setFill()
        bg.fill()
        attr.draw(at: CGPoint(x: bg.minX + 6, y: bg.minY + 4))
    }
}
