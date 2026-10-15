import AppKit
import ImageIO
import UniformTypeIdentifiers

@MainActor
enum Exporter {
    /// 按偏好设置输出：存文件 / 复制剪贴板 / 提示音 / 预览气泡。
    static func export(_ image: CGImage, scale: CGFloat, suffix: String = "") {
        let p = Preferences.shared
        var savedURL: URL?
        if p.saveToFile {
            do {
                savedURL = try save(image, scale: scale, suffix: suffix)
            } catch {
                presentError("保存失败", error.localizedDescription)
            }
        }
        if p.copyToClipboard { copyToClipboard(image, scale: scale) }
        if p.playSound { SoundPlayer.playShutter() }
        if p.showPreview { PreviewBubble.show(image: image, fileURL: savedURL, copied: p.copyToClipboard) }
    }

    static func save(_ image: CGImage, scale: CGFloat, suffix: String) throws -> URL {
        let p = Preferences.shared
        let dir = p.effectiveSaveDirectoryURL
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = uniqueURL(in: dir, ext: p.format.rawValue, suffix: suffix)
        let data = try encode(image, format: p.format, quality: p.jpgQuality, scale: scale)
        try data.write(to: url)
        return url
    }

    static func encode(_ image: CGImage, format: Preferences.Format, quality: Double, scale: CGFloat) throws -> Data {
        let type: UTType = format == .png ? .png : .jpeg
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil) else {
            throw NSError(domain: "SnapLite", code: 1, userInfo: [NSLocalizedDescriptionKey: "无法创建图片编码器"])
        }
        let dpi = 72 * scale
        var props: [CFString: Any] = [kCGImagePropertyDPIWidth: dpi, kCGImagePropertyDPIHeight: dpi]
        if format == .jpg { props[kCGImageDestinationLossyCompressionQuality] = quality }
        CGImageDestinationAddImage(dest, image, props as CFDictionary)
        guard CGImageDestinationFinalize(dest) else {
            throw NSError(domain: "SnapLite", code: 2, userInfo: [NSLocalizedDescriptionKey: "图片编码失败"])
        }
        return data as Data
    }

    static func copyToClipboard(_ image: CGImage, scale: CGFloat) {
        let size = NSSize(width: CGFloat(image.width) / scale, height: CGFloat(image.height) / scale)
        let ns = NSImage(cgImage: image, size: size)
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects([ns])
    }

    private static func uniqueURL(in dir: URL, ext: String, suffix: String) -> URL {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH.mm.ss"
        let base = "SnapLite \(f.string(from: Date()))\(suffix)"
        var url = dir.appendingPathComponent("\(base).\(ext)")
        var n = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = dir.appendingPathComponent("\(base) (\(n)).\(ext)")
            n += 1
        }
        return url
    }

    static func presentError(_ title: String, _ message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}

enum SoundPlayer {
    private static let candidates = [
        "/System/Library/Components/CoreAudio.component/Contents/SharedSupport/SystemSounds/system/Grab.aif",
        "/System/Library/Sounds/Pop.aiff",
    ]
    private static var sound: NSSound? = {
        for path in candidates where FileManager.default.fileExists(atPath: path) {
            if let s = NSSound(contentsOfFile: path, byReference: true) { return s }
        }
        return nil
    }()

    static func playShutter() {
        sound?.stop()
        sound?.play()
    }
}
