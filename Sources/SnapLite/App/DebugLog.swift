import Foundation
import ImageIO

/// 简单的文件日志：~/Library/Logs/SnapLite.log
enum DebugLog {
    private static let url: URL = {
        let dir = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Logs", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("SnapLite.log")
    }()
    private static let queue = DispatchQueue(label: "SnapLite.log")
    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return f
    }()

    /// 每次长截图会话的帧转储目录（每次会话清空）：~/Library/Logs/SnapLite-frames/
    static let framesDir: URL = url.deletingLastPathComponent().appendingPathComponent("SnapLite-frames", isDirectory: true)

    static func resetFrames() {
        try? FileManager.default.removeItem(at: framesDir)
        try? FileManager.default.createDirectory(at: framesDir, withIntermediateDirectories: true)
    }

    static func dumpFrame(_ image: CGImage, name: String) {
        let target = framesDir.appendingPathComponent(name + ".png")
        queue.async {
            guard let dest = CGImageDestinationCreateWithURL(target as CFURL, "public.png" as CFString, 1, nil) else { return }
            CGImageDestinationAddImage(dest, image, nil)
            CGImageDestinationFinalize(dest)
        }
    }

    static func write(_ message: String) {
        let line = "\(formatter.string(from: Date())) \(message)\n"
        queue.async {
            guard let data = line.data(using: .utf8) else { return }
            if let h = try? FileHandle(forWritingTo: url) {
                h.seekToEndOfFile()
                h.write(data)
                try? h.close()
            } else {
                try? data.write(to: url)
            }
        }
    }
}
