// 生成 AppIcon.icns。
//   swift Scripts/make-icon.swift Resources/AppIcon.icns                       → 默认渐变底 + 取景框符号
//   swift Scripts/make-icon.swift Resources/AppIcon.icns Resources/source.png  → 用指定图片，按 macOS 图标规范裁成圆角方块
import AppKit

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.icns"
let sourcePath = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : nil
let source = sourcePath.flatMap { NSImage(contentsOfFile: $0) }
if sourcePath != nil && source == nil { print("读不到图片 \(sourcePath!)"); exit(1) }

let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("SnapLite.iconset")
try? FileManager.default.removeItem(at: tmp)
try! FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)

func render(_ px: Int) -> Data {
    let img = NSImage(size: NSSize(width: px, height: px))
    img.lockFocus()
    NSGraphicsContext.current?.imageInterpolation = .high
    let s = CGFloat(px)
    // macOS 图标：内容占画布 824/1024，圆角约为边长的 22.5%
    let inset = s * (1 - 824.0 / 1024.0) / 2
    let r = NSRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let path = NSBezierPath(roundedRect: r, xRadius: r.width * 0.225, yRadius: r.width * 0.225)
    if let source {
        // 柔和投影
        let shadow = NSShadow()
        shadow.shadowBlurRadius = s * 0.02
        shadow.shadowOffset = NSSize(width: 0, height: -s * 0.01)
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
        NSGraphicsContext.saveGraphicsState()
        shadow.set()
        NSColor.white.setFill()
        path.fill()
        NSGraphicsContext.restoreGraphicsState()

        NSGraphicsContext.saveGraphicsState()
        path.addClip()
        // 等比铺满圆角方块（aspect fill）
        let src = source.size
        let scale = max(r.width / src.width, r.height / src.height)
        let drawSize = NSSize(width: src.width * scale, height: src.height * scale)
        let drawRect = NSRect(x: r.midX - drawSize.width / 2, y: r.midY - drawSize.height / 2,
                              width: drawSize.width, height: drawSize.height)
        source.draw(in: drawRect, from: .zero, operation: .sourceOver, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
    } else {
        NSGradient(starting: NSColor(calibratedRed: 0.16, green: 0.55, blue: 0.98, alpha: 1),
                   ending: NSColor(calibratedRed: 0.05, green: 0.25, blue: 0.65, alpha: 1))!.draw(in: path, angle: -60)
        let cfg = NSImage.SymbolConfiguration(pointSize: s * 0.5, weight: .medium)
        if let sym = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: nil)?.withSymbolConfiguration(cfg) {
            let tinted = NSImage(size: sym.size, flipped: false) { rect in
                sym.draw(in: rect)
                NSColor.white.set()
                rect.fill(using: .sourceAtop)
                return true
            }
            let size = tinted.size
            tinted.draw(in: NSRect(x: (s - size.width) / 2, y: (s - size.height) / 2, width: size.width, height: size.height))
        }
    }
    img.unlockFocus()
    let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!
    return rep.representation(using: .png, properties: [:])!
}

for base in [16, 32, 128, 256, 512] {
    try! render(base).write(to: tmp.appendingPathComponent("icon_\(base)x\(base).png"))
    try! render(base * 2).write(to: tmp.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", tmp.path, "-o", out]
try! p.run()
p.waitUntilExit()
print(p.terminationStatus == 0 ? "生成 \(out)" : "iconutil 失败")
