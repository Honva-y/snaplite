import AppKit
import SwiftUI

enum SettingsTab: String, CaseIterable {
    case general, hotkeys, scrolling, permissions
}

final class SettingsWindowController: NSWindowController {
    private let model = SettingsModel()

    init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 380),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "SnapLite 设置"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.contentViewController = NSHostingController(rootView: SettingsView(model: model))
        window.center()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func show(tab: SettingsTab?) {
        if let tab { model.tab = tab }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

final class SettingsModel: ObservableObject {
    @Published var tab: SettingsTab = .general
}
