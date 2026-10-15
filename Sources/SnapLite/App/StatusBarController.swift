import AppKit
import ServiceManagement

@MainActor
final class StatusBarController: NSObject, NSMenuDelegate {
    private let item: NSStatusItem
    private let coordinator: CaptureCoordinator
    private let openSettings: () -> Void
    private let menu = NSMenu()

    init(coordinator: CaptureCoordinator, openSettings: @escaping () -> Void) {
        self.coordinator = coordinator
        self.openSettings = openSettings
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: "SnapLite")
            button.image?.isTemplate = true
        }
        menu.delegate = self
        item.menu = menu
        rebuildMenu()
    }

    func showCountdown(_ remaining: Int?) {
        item.button?.title = remaining.map { " \($0)" } ?? ""
    }

    func menuNeedsUpdate(_ menu: NSMenu) { rebuildMenu() }

    private func rebuildMenu() {
        let p = Preferences.shared
        menu.removeAllItems()
        add("区域截图", #selector(captureRegion), hotkey: p.regionHotkey)
        add("窗口截图", #selector(captureWindow), hotkey: p.windowHotkey)
        add("全屏截图", #selector(captureFullscreen), hotkey: p.fullscreenHotkey)
        menu.addItem(.separator())
        add("长截图", #selector(captureScroll), hotkey: p.scrollHotkey)
        menu.addItem(.separator())
        let delay = NSMenuItem(title: "延时区域截图", action: nil, keyEquivalent: "")
        let sub = NSMenu()
        for secs in [3, 5, 10] {
            let mi = NSMenuItem(title: "\(secs) 秒后", action: #selector(captureDelayed(_:)), keyEquivalent: "")
            mi.target = self
            mi.tag = secs
            sub.addItem(mi)
        }
        delay.submenu = sub
        menu.addItem(delay)
        menu.addItem(.separator())
        if !PinnedWindow.all.isEmpty {
            add("关闭所有钉图（\(PinnedWindow.all.count)）", #selector(closePins))
        }
        add("打开保存目录", #selector(openSaveDirectory))
        let login = add("登录时启动", #selector(toggleLaunchAtLogin))
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        let settings = add("设置…", #selector(showSettings))
        settings.keyEquivalent = ","
        settings.keyEquivalentModifierMask = .command
        menu.addItem(.separator())
        let quit = add("退出 SnapLite", #selector(quit))
        quit.keyEquivalent = "q"
        quit.keyEquivalentModifierMask = .command
    }

    @discardableResult
    private func add(_ title: String, _ action: Selector, hotkey: Hotkey? = nil) -> NSMenuItem {
        let mi = NSMenuItem(title: title, action: action, keyEquivalent: "")
        mi.target = self
        if let hk = hotkey, let key = hk.menuKeyEquivalent {
            mi.keyEquivalent = key
            mi.keyEquivalentModifierMask = hk.flags
        } else if let hk = hotkey {
            mi.title = "\(title)    \(hk.displayString)"
        }
        menu.addItem(mi)
        return mi
    }

    @objc private func captureRegion() { coordinator.start(.region) }
    @objc private func captureWindow() { coordinator.start(.window) }
    @objc private func captureFullscreen() { coordinator.start(.fullscreen) }
    @objc private func captureScroll() { coordinator.start(.scroll) }
    @objc private func captureDelayed(_ sender: NSMenuItem) { coordinator.start(.region, delay: sender.tag) }
    @objc private func openSaveDirectory() { let url = Preferences.shared.effectiveSaveDirectoryURL
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        NSWorkspace.shared.open(url) }
    @objc private func showSettings() { openSettings() }
    @objc private func closePins() { PinnedWindow.closeAll() }
    @objc private func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
            UserDefaults.standard.set(true, forKey: "launchAtLoginConfigured")
        } catch {
            Exporter.presentError("设置登录项失败", error.localizedDescription)
        }
    }
    @objc private func quit() { NSApp.terminate(nil) }
}
