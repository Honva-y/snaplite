import AppKit

enum AnnotationTool: Equatable {
    case none, rect, arrow, pen, mosaic, text
}

/// 一条标注，坐标为覆盖层视图坐标（左上原点，点）。
struct Annotation {
    var kind: AnnotationTool
    var start: CGPoint
    var end: CGPoint
    var color: NSColor
    var lineWidth: CGFloat = 3
    /// 画笔轨迹
    var points: [CGPoint] = []
    /// 文字内容
    var text: String = ""
    var fontSize: CGFloat = 18

    var length: CGFloat { hypot(end.x - start.x, end.y - start.y) }

    var rect: CGRect {
        CGRect(x: min(start.x, end.x), y: min(start.y, end.y), width: abs(end.x - start.x), height: abs(end.y - start.y))
    }
}

enum AnnotationRenderer {
    static let palette: [NSColor] = [
        NSColor(srgbRed: 0.96, green: 0.26, blue: 0.21, alpha: 1), // 红
        NSColor(srgbRed: 1.00, green: 0.62, blue: 0.04, alpha: 1), // 橙
        NSColor(srgbRed: 1.00, green: 0.86, blue: 0.10, alpha: 1), // 黄
        NSColor(srgbRed: 0.20, green: 0.78, blue: 0.35, alpha: 1), // 绿
        NSColor(srgbRed: 0.04, green: 0.52, blue: 1.00, alpha: 1), // 蓝
        NSColor(srgbRed: 0.69, green: 0.32, blue: 0.87, alpha: 1), // 紫
        .white,
        .black,
    ]

    /// 马赛克块大小（点）
    static let mosaicBlockPoints: CGFloat = 10

    static let fontSizes: [CGFloat] = [12, 14, 16, 18, 20, 24, 28, 32, 40, 48]

    static func font(size: CGFloat) -> NSFont {
        .systemFont(ofSize: size, weight: .regular)
    }

    static func textAttributes(color: NSColor, size: CGFloat) -> [NSAttributedString.Key: Any] {
        [.font: font(size: size), .foregroundColor: color]
    }

    /// 在当前（翻转坐标的）绘图上下文里画一条标注。
    /// 目标坐标 = (视图坐标 - offset) × scale。
    /// 打码需要底图：`source` 为像素图，`sourceScale` 为视图坐标到底图像素的比例，`sourceOffset` 为底图左上角对应的视图坐标。
    static func draw(_ a: Annotation, offset: CGPoint = .zero, scale: CGFloat = 1,
                     source: CGImage? = nil, sourceScale: CGFloat = 1, sourceOffset: CGPoint = .zero) {
        func map(_ p: CGPoint) -> CGPoint { CGPoint(x: (p.x - offset.x) * scale, y: (p.y - offset.y) * scale) }
        let s = map(a.start), e = map(a.end)
        let width = a.lineWidth * scale
        a.color.setStroke()
        a.color.setFill()
        switch a.kind {
        case .rect:
            let r = CGRect(x: min(s.x, e.x), y: min(s.y, e.y), width: abs(e.x - s.x), height: abs(e.y - s.y))
            let path = NSBezierPath(roundedRect: r, xRadius: width, yRadius: width)
            path.lineWidth = width
            path.lineJoinStyle = .round
            path.stroke()
        case .arrow:
            let angle = atan2(e.y - s.y, e.x - s.x)
            let headLength = max(12 * scale, width * 4)
            let headHalfWidth = headLength * 0.45
            let lineEnd = CGPoint(x: e.x - cos(angle) * headLength * 0.8, y: e.y - sin(angle) * headLength * 0.8)
            let line = NSBezierPath()
            line.move(to: s)
            line.line(to: lineEnd)
            line.lineWidth = width
            line.lineCapStyle = .round
            line.stroke()
            let base = CGPoint(x: e.x - cos(angle) * headLength, y: e.y - sin(angle) * headLength)
            let perp = CGPoint(x: -sin(angle), y: cos(angle))
            let head = NSBezierPath()
            head.move(to: e)
            head.line(to: CGPoint(x: base.x + perp.x * headHalfWidth, y: base.y + perp.y * headHalfWidth))
            head.line(to: CGPoint(x: base.x - perp.x * headHalfWidth, y: base.y - perp.y * headHalfWidth))
            head.close()
            head.fill()
        case .pen:
            let pts = a.points.map(map)
            guard let first = pts.first else { return }
            let path = NSBezierPath()
            path.lineWidth = width
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            path.move(to: first)
            if pts.count == 1 {
                path.line(to: first)
            } else if pts.count == 2 {
                path.line(to: pts[1])
            } else {
                // 用相邻点中点做二次曲线，让线条顺滑
                for i in 1..<(pts.count - 1) {
                    let mid = CGPoint(x: (pts[i].x + pts[i + 1].x) / 2, y: (pts[i].y + pts[i + 1].y) / 2)
                    path.curve(to: mid, controlPoint1: pts[i], controlPoint2: pts[i])
                }
                path.line(to: pts[pts.count - 1])
            }
            path.stroke()
        case .mosaic:
            guard let source else { return }
            let viewRect = a.rect
            guard viewRect.width >= 1, viewRect.height >= 1 else { return }
            let px = CGRect(x: (viewRect.minX - sourceOffset.x) * sourceScale, y: (viewRect.minY - sourceOffset.y) * sourceScale,
                            width: viewRect.width * sourceScale, height: viewRect.height * sourceScale).integral
            guard let crop = source.cropping(to: px) else { return }
            let block = max(2, Int(mosaicBlockPoints * sourceScale))
            let smallW = max(1, crop.width / block), smallH = max(1, crop.height / block)
            guard let ctx = CGContext(data: nil, width: smallW, height: smallH, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
            ctx.interpolationQuality = .medium
            ctx.draw(crop, in: CGRect(x: 0, y: 0, width: smallW, height: smallH))
            guard let small = ctx.makeImage() else { return }
            let dest = CGRect(x: min(s.x, e.x), y: min(s.y, e.y), width: abs(e.x - s.x), height: abs(e.y - s.y))
            let ns = NSImage(cgImage: small, size: dest.size)
            ns.draw(in: dest, from: .zero, operation: .copy, fraction: 1, respectFlipped: true,
                    hints: [.interpolation: NSImageInterpolation.none])
        case .text:
            guard !a.text.isEmpty else { return }
            let attr = NSAttributedString(string: a.text, attributes: textAttributes(color: a.color, size: a.fontSize * scale))
            attr.draw(at: s)
        case .none:
            break
        }
    }

    /// 把标注烙到已裁好的像素图上。`cropOrigin` 为选区在视图中的左上角（点）。
    static func render(image: CGImage, annotations: [Annotation], cropOrigin: CGPoint, scale: CGFloat) -> CGImage {
        guard !annotations.isEmpty else { return image }
        let w = image.width, h = image.height
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return image }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        ctx.translateBy(x: 0, y: CGFloat(h))
        ctx.scaleBy(x: 1, y: -1)
        let ns = NSGraphicsContext(cgContext: ctx, flipped: true)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ns
        for a in annotations {
            draw(a, offset: cropOrigin, scale: scale, source: image, sourceScale: scale, sourceOffset: cropOrigin)
        }
        NSGraphicsContext.restoreGraphicsState()
        return ctx.makeImage() ?? image
    }
}
