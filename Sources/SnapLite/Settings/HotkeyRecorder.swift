import AppKit
import SwiftUI

struct HotkeyRecorder: NSViewRepresentable {
    @Binding var hotkey: Hotkey?

    func makeNSView(context: Context) -> HotkeyRecorderView {
        let v = HotkeyRecorderView()
        v.onChange = { hotkey = $0 }
        return v
    }

    func updateNSView(_ view: HotkeyRecorderView, context: Context) {
        view.hotkey = hotkey
    }
}

final class HotkeyRecorderView: NSView {
    var hotkey: Hotkey? { didSet { needsDisplay = true } }
    var onChange: ((Hotkey?) -> Void)?
    private var recording = false { didSet { needsDisplay = true } }

    override var intrinsicContentSize: NSSize { NSSize(width: 150, height: 24) }
    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        recording.toggle()
    }

    override func resignFirstResponder() -> Bool {
        recording = false
        return true
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard recording else { return false }
        handle(event)
        return true
    }

    override func keyDown(with event: NSEvent) {
        guard recording else { super.keyDown(with: event); return }
        handle(event)
    }

    private func handle(_ event: NSEvent) {
        let code = UInt32(event.keyCode)
        if code == 53 { recording = false; return }                       // Esc：取消录制
        if code == 51 || code == 117 { set(nil); return }                // 退格 / Delete：清除
        let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
        guard !flags.isEmpty || Hotkey.isFunctionKey(code) else { NSSound.beep(); return }
        set(Hotkey(keyCode: event.keyCode, flags: flags))
    }

    private func set(_ hk: Hotkey?) {
        hotkey = hk
        recording = false
        onChange?(hk)
    }

    override func draw(_ dirtyRect: NSRect) {
        let r = bounds.insetBy(dx: 0.5, dy: 0.5)
        let path = NSBezierPath(roundedRect: r, xRadius: 6, yRadius: 6)
        (recording ? NSColor.controlAccentColor.withAlphaComponent(0.15) : NSColor.controlBackgroundColor).setFill()
        path.fill()
        (recording ? NSColor.controlAccentColor : NSColor.separatorColor).setStroke()
        path.stroke()
        let text = recording ? "按下快捷键…（退格清除）" : (hotkey?.displayString ?? "未设置，点击录制")
        let attr = NSAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: 12),
            .foregroundColor: hotkey == nil && !recording ? NSColor.secondaryLabelColor : NSColor.labelColor,
        ])
        let size = attr.size()
        attr.draw(at: NSPoint(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2))
    }
}
