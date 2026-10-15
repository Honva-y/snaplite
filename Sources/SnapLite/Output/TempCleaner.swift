import AppKit

/// 定期清理临时目录里过期的截图（系统自己也会在重启等时机清理该目录）。
@MainActor
enum TempCleaner {
    private static var timer: Timer?

    static func start() {
        run()
        timer = Timer.scheduledTimer(withTimeInterval: 6 * 3600, repeats: true) { _ in
            Task { @MainActor in run() }
        }
    }

    static func run() {
        let dir = Preferences.temporaryDirectoryURL
        let days = max(1, Preferences.shared.tempRetentionDays)
        let cutoff = Date().addingTimeInterval(-Double(days) * 86400)
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles]) else { return }
        for url in items {
            let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date()
            if date < cutoff { try? fm.removeItem(at: url) }
        }
    }
}
