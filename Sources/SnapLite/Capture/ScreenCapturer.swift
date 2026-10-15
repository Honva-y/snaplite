import AppKit
import ScreenCaptureKit

enum CaptureError: LocalizedError {
    case displayNotFound
    case windowNotFound
    case permissionDenied

    var errorDescription: String? {
        switch self {
        case .displayNotFound: return "找不到对应的显示器"
        case .windowNotFound: return "窗口已不在屏幕上"
        case .permissionDenied: return "没有屏幕录制权限"
        }
    }
}

/// ScreenCaptureKit 封装。所有矩形单位为点，输出为像素级 CGImage。
enum ScreenCapturer {
    static func shareableContent() async throws -> SCShareableContent {
        try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
    }

    /// 冻结所有屏幕。
    static func snapshotAllScreens() async throws -> [ScreenSnapshot] {
        let content = try await shareableContent()
        var result: [ScreenSnapshot] = []
        for screen in NSScreen.screens {
            let id = screen.displayID
            let image = try await captureDisplay(id, rect: nil, excludingWindowIDs: [], content: content)
            result.append(ScreenSnapshot(screen: screen, displayID: id, cgFrame: CGDisplayBounds(id),
                                         scale: screen.backingScaleFactor, image: image))
        }
        return result
    }

    /// 截取某块显示器的一部分。`rect` 为该显示器的局部坐标（左上原点，点）。
    static func captureDisplay(_ displayID: CGDirectDisplayID, rect: CGRect?, excludingWindowIDs: Set<CGWindowID>,
                               content existing: SCShareableContent?) async throws -> CGImage {
        let content: SCShareableContent
        if let given = existing { content = given } else { content = try await shareableContent() }
        guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
            throw CaptureError.displayNotFound
        }
        let excluded = content.windows.filter { excludingWindowIDs.contains($0.windowID) }
        let filter = SCContentFilter(display: display, excludingWindows: excluded)
        let scale = NSScreen.screens.first { $0.displayID == displayID }?.backingScaleFactor ?? 2
        let r = rect ?? CGRect(origin: .zero, size: CGSize(width: display.width, height: display.height))
        let config = baseConfig()
        config.sourceRect = r
        config.width = Int((r.width * scale).rounded())
        config.height = Int((r.height * scale).rounded())
        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
    }

    /// 单独截取一个窗口（透明背景、保留圆角、不带阴影）。
    static func captureWindow(_ windowID: CGWindowID, scale: CGFloat) async throws -> CGImage {
        let content = try await shareableContent()
        guard let window = content.windows.first(where: { $0.windowID == windowID }) else {
            throw CaptureError.windowNotFound
        }
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let config = baseConfig()
        config.width = Int((window.frame.width * scale).rounded())
        config.height = Int((window.frame.height * scale).rounded())
        config.ignoreShadowsSingleWindow = true
        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
    }

    private static func baseConfig() -> SCStreamConfiguration {
        let config = SCStreamConfiguration()
        config.showsCursor = false
        config.captureResolution = .best
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.colorSpaceName = CGColorSpace.sRGB
        return config
    }
}
