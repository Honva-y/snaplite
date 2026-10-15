import AppKit

/// 一块显示器在某一时刻的冻结画面。所有矩形统一使用 CoreGraphics 全局坐标（原点在主屏左上角，单位为点）。
struct ScreenSnapshot {
    let screen: NSScreen
    let displayID: CGDirectDisplayID
    /// 该屏幕在 CG 全局坐标中的位置
    let cgFrame: CGRect
    let scale: CGFloat
    let image: CGImage

    /// 把屏幕内的局部点坐标矩形裁成像素图。
    func crop(localRect: CGRect) -> CGImage? {
        let px = CGRect(x: localRect.minX * scale, y: localRect.minY * scale,
                        width: localRect.width * scale, height: localRect.height * scale).integral
        return image.cropping(to: px)
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        return (deviceDescription[key] as? NSNumber).map { CGDirectDisplayID($0.uint32Value) } ?? 0
    }
}

enum CoordinateSpace {
    /// CG 全局坐标（左上原点）→ AppKit 屏幕坐标（左下原点）
    static func appKitRect(fromCG r: CGRect) -> CGRect {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        return CGRect(x: r.minX, y: primaryHeight - r.maxY, width: r.width, height: r.height)
    }

    static func cgPoint(fromAppKit p: CGPoint) -> CGPoint {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        return CGPoint(x: p.x, y: primaryHeight - p.y)
    }
}

struct WindowInfo {
    let id: CGWindowID
    let pid: pid_t
    /// CG 全局坐标
    let bounds: CGRect
    let title: String?
    let ownerName: String?

    var displayName: String {
        if let t = title, !t.isEmpty { return t }
        return ownerName ?? "窗口"
    }
}

enum WindowLister {
    /// 屏幕上可见的普通窗口，按从前到后排序，排除本进程。
    static func onScreenWindows() -> [WindowInfo] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return [] }
        let me = getpid()
        return list.compactMap { d in
            guard let layer = (d[kCGWindowLayer as String] as? NSNumber)?.intValue, layer == 0,
                  let pid = (d[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value, pid != me,
                  let num = (d[kCGWindowNumber as String] as? NSNumber)?.uint32Value,
                  let bd = d[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: bd),
                  bounds.width >= 20, bounds.height >= 20 else { return nil }
            let alpha = (d[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1
            guard alpha > 0.01 else { return nil }
            return WindowInfo(id: num, pid: pid, bounds: bounds,
                              title: d[kCGWindowName as String] as? String,
                              ownerName: d[kCGWindowOwnerName as String] as? String)
        }
    }
}
