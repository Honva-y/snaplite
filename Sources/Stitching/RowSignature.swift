import CoreGraphics
import Foundation

/// 每一行图像压缩成 64 个灰度桶，用于快速逐行比较。
/// 忽略右侧 `rightMargin` 像素，避免 macOS 悬浮滚动条闪现干扰匹配。
public struct RowSignature {
    public static let buckets = 64
    public let rows: Int
    public let data: [UInt8]

    public init(rows: Int, data: [UInt8]) {
        precondition(data.count == rows * RowSignature.buckets)
        self.rows = rows
        self.data = data
    }

    public init(image: CGImage, rightMargin: Int = 24) {
        let w = image.width, h = image.height
        guard w > 0, h > 0 else {
            self.rows = 0
            self.data = []
            return
        }
        var gray = [UInt8](repeating: 0, count: w * h)
        gray.withUnsafeMutableBytes { raw in
            if let ctx = CGContext(data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8,
                                   bytesPerRow: w, space: CGColorSpaceCreateDeviceGray(),
                                   bitmapInfo: CGImageAlphaInfo.none.rawValue) {
                ctx.interpolationQuality = .none
                ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            }
        }
        let B = RowSignature.buckets
        let usable = w > rightMargin + B ? w - rightMargin : w
        var bounds = [(Int, Int)]()
        bounds.reserveCapacity(B)
        for b in 0..<B {
            var x0 = b * usable / B
            var x1 = (b + 1) * usable / B
            x0 = min(x0, usable - 1)
            if x1 <= x0 { x1 = x0 + 1 }
            x1 = min(x1, usable)
            if x1 <= x0 { x0 = x1 - 1 }
            bounds.append((x0, x1))
        }
        var out = [UInt8](repeating: 0, count: h * B)
        gray.withUnsafeBufferPointer { g in
            out.withUnsafeMutableBufferPointer { o in
                for y in 0..<h {
                    let rowBase = y * w
                    for b in 0..<B {
                        let (x0, x1) = bounds[b]
                        var sum = 0
                        for x in x0..<x1 { sum += Int(g[rowBase + x]) }
                        o[y * B + b] = UInt8(sum / (x1 - x0))
                    }
                }
            }
        }
        self.rows = h
        self.data = out
    }

    /// 两行之间的绝对差之和（0 ... 64*255）。
    @inline(__always)
    public func diff(_ r1: Int, _ other: RowSignature, _ r2: Int) -> Int {
        let B = RowSignature.buckets
        var s = 0
        data.withUnsafeBufferPointer { a in
            other.data.withUnsafeBufferPointer { b in
                let i = r1 * B, j = r2 * B
                for k in 0..<B { s += abs(Int(a[i + k]) - Int(b[j + k])) }
            }
        }
        return s
    }

    /// 一行内的明暗跨度（max - min），接近 0 表示纯色行。
    public func spread(_ r: Int) -> Int {
        let B = RowSignature.buckets
        var lo = 255, hi = 0
        let base = r * B
        for k in 0..<B {
            let v = Int(data[base + k])
            if v < lo { lo = v }
            if v > hi { hi = v }
        }
        return hi - lo
    }
}
