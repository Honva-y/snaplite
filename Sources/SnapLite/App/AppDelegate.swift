import AppKit
import ServiceManagement

extension Notification.Name {
    static let hotkeysChanged = Notification.Name("SnapLite.hotkeysChanged")
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let coordinator = CaptureCoordinator()
    let hotkeys = HotkeyManager()
    private var statusBar: StatusBarController!
    private var settings: SettingsWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusBar = StatusBarController(coordinator: coordinator, openSettings: { [weak self] in self?.showSettings() })
        coordinator.onCountdown = { [weak self] remaining in self?.statusBar.showCountdown(remaining) }
        registerHotkeys()
        TempCleaner.start()
        enableLaunchAtLoginOnce()
        NotificationCenter.default.addObserver(forName: .hotkeysChanged, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.registerHotkeys() }
        }
        if !Permissions.screenRecordingGranted {
            Permissions.requestScreenRecording()
            showSettings(tab: .permissions)
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return false
    }

    /// 首次运行自动登记为登录项；之后由用户在菜单或设置里控制。
    private func enableLaunchAtLoginOnce() {
        let key = "launchAtLoginConfigured"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        guard Bundle.main.bundlePath.hasSuffix(".app") else { return } // 直接跑二进制时跳过
        do {
            try SMAppService.mainApp.register()
            UserDefaults.standard.set(true, forKey: key)
        } catch {
            NSLog("SnapLite: 登记登录项失败 %@", error.localizedDescription)
        }
    }

    private func registerHotkeys() {
        hotkeys.unregisterAll()
        let p = Preferences.shared
        let pairs: [(Hotkey?, CaptureCoordinator.Mode)] = [
            (p.regionHotkey, .region),
            (p.windowHotkey, .window),
            (p.fullscreenHotkey, .fullscreen),
            (p.scrollHotkey, .scroll),
        ]
        for (hk, mode) in pairs {
            guard let hk else { continue }
            hotkeys.register(hk) { [weak self] in self?.coordinator.start(mode) }
        }
    }

    func showSettings(tab: SettingsTab? = nil) {
        if settings == nil { settings = SettingsWindowController() }
        settings?.show(tab: tab)
    }
}
