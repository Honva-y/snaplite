import AppKit
import Combine

final class Preferences: ObservableObject {
    static let shared = Preferences()

    enum Format: String, CaseIterable, Identifiable {
        case png, jpg
        var id: String { rawValue }
        var title: String { rawValue.uppercased() }
    }

    enum SaveLocation: String, CaseIterable, Identifiable {
        case temporary, custom
        var id: String { rawValue }
        var title: String { self == .temporary ? "系统临时目录（自动清理）" : "自定义文件夹" }
    }

    private let d = UserDefaults.standard

    @Published var saveLocation: SaveLocation { didSet { d.set(saveLocation.rawValue, forKey: "saveLocation") } }
    /// 临时目录里的截图保留天数
    @Published var tempRetentionDays: Int { didSet { d.set(tempRetentionDays, forKey: "tempRetentionDays") } }
    @Published var annotationColor: NSColor { didSet { d.set(annotationColor.hexString, forKey: "annotationColor") } }
    @Published var annotationFontSize: Double { didSet { d.set(annotationFontSize, forKey: "annotationFontSize") } }

    @Published var saveDirectory: String { didSet { d.set(saveDirectory, forKey: "saveDirectory") } }
    @Published var format: Format { didSet { d.set(format.rawValue, forKey: "format") } }
    @Published var jpgQuality: Double { didSet { d.set(jpgQuality, forKey: "jpgQuality") } }
    @Published var saveToFile: Bool { didSet { d.set(saveToFile, forKey: "saveToFile") } }
    @Published var copyToClipboard: Bool { didSet { d.set(copyToClipboard, forKey: "copyToClipboard") } }
    @Published var playSound: Bool { didSet { d.set(playSound, forKey: "playSound") } }
    @Published var showPreview: Bool { didSet { d.set(showPreview, forKey: "showPreview") } }

    /// 长图最大高度（点）
    @Published var maxLongHeight: Int { didSet { d.set(maxLongHeight, forKey: "maxLongHeight") } }

    @Published var regionHotkey: Hotkey? { didSet { store(regionHotkey, "regionHotkey") } }
    @Published var windowHotkey: Hotkey? { didSet { store(windowHotkey, "windowHotkey") } }
    @Published var fullscreenHotkey: Hotkey? { didSet { store(fullscreenHotkey, "fullscreenHotkey") } }
    @Published var scrollHotkey: Hotkey? { didSet { store(scrollHotkey, "scrollHotkey") } }

    private init() {
        let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first?.path ?? NSHomeDirectory()
        saveDirectory = d.string(forKey: "saveDirectory") ?? desktop
        saveLocation = SaveLocation(rawValue: d.string(forKey: "saveLocation") ?? "") ?? .temporary
        tempRetentionDays = d.object(forKey: "tempRetentionDays") as? Int ?? 7
        annotationColor = d.string(forKey: "annotationColor").flatMap(NSColor.init(hexString:)) ?? AnnotationRenderer.palette[0]
        annotationFontSize = d.object(forKey: "annotationFontSize") as? Double ?? 18
        format = Format(rawValue: d.string(forKey: "format") ?? "") ?? .png
        jpgQuality = d.object(forKey: "jpgQuality") as? Double ?? 0.9
        saveToFile = d.object(forKey: "saveToFile") as? Bool ?? true
        copyToClipboard = d.object(forKey: "copyToClipboard") as? Bool ?? true
        playSound = d.object(forKey: "playSound") as? Bool ?? true
        showPreview = d.object(forKey: "showPreview") as? Bool ?? true
        maxLongHeight = d.object(forKey: "maxLongHeight") as? Int ?? 20000
        // 默认快捷键避开系统的 ⌘⇧3/4/5；区域截图用 F1（无修饰键）
        let ctrlShift = UInt32(Carbon.controlKey | Carbon.shiftKey)
        regionHotkey = Preferences.load(d, "regionHotkey", default: Hotkey(keyCode: 122, modifiers: 0))            // F1
        windowHotkey = Preferences.load(d, "windowHotkey", default: Hotkey(keyCode: 13, modifiers: ctrlShift))     // W
        fullscreenHotkey = Preferences.load(d, "fullscreenHotkey", default: Hotkey(keyCode: 3, modifiers: ctrlShift)) // F
        scrollHotkey = Preferences.load(d, "scrollHotkey", default: Hotkey(keyCode: 37, modifiers: ctrlShift))     // L
    }

    private func store(_ hk: Hotkey?, _ key: String) {
        if let hk, let data = try? JSONEncoder().encode(hk) {
            d.set(data, forKey: key)
        } else {
            d.set(Data(), forKey: key) // 空数据 = 用户显式清除
        }
    }

    private static func load(_ d: UserDefaults, _ key: String, default def: Hotkey) -> Hotkey? {
        guard let data = d.data(forKey: key) else { return def }
        if data.isEmpty { return nil }
        return try? JSONDecoder().decode(Hotkey.self, from: data)
    }

    /// 自定义目录
    var saveDirectoryURL: URL { URL(fileURLWithPath: (saveDirectory as NSString).expandingTildeInPath) }

    /// 系统临时目录下的 SnapLite 子目录
    static let temporaryDirectoryURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("SnapLite", isDirectory: true)

    /// 当前实际生效的保存目录
    var effectiveSaveDirectoryURL: URL {
        saveLocation == .temporary ? Preferences.temporaryDirectoryURL : saveDirectoryURL
    }
}

extension NSColor {
    var hexString: String {
        let c = usingColorSpace(.sRGB) ?? self
        return String(format: "#%02X%02X%02X", Int(c.redComponent * 255), Int(c.greenComponent * 255), Int(c.blueComponent * 255))
    }

    convenience init?(hexString: String) {
        var s = hexString.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        self.init(srgbRed: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255, blue: CGFloat(v & 0xFF) / 255, alpha: 1)
    }
}

import Carbon
