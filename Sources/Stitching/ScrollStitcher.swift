import CoreGraphics
import Foundation

/// 长截图拼接器：逐帧追加同尺寸的截图，自动找出滚动偏移、剔除吸顶/吸底固定元素，
/// 最后合成一张长图。全部在像素坐标下工作。
public final class ScrollStitcher {
    public struct Options {
        /// 相邻两帧至少要有多少行重叠，太小容易误匹配。
        public var minOverlap: Int = 40
        /// 合成结果最大高度（像素），防止内存失控。
        public var maxTotalHeight: Int = 40_000
        /// 平均灰度差低于此值视为"同一行"。
        public var equalThreshold: Int = 3
        /// 匹配得分（加权平均灰度差）低于此值才接受。真实匹配通常接近 0；
        /// 日志、表格这类行行相似的内容在错误偏移上也能得 5～8 分，所以阈值要严。
        public var acceptThreshold: Double = 3
        /// 固定头/尾最多占帧高的比例。
        public var maxStickyRatio: Double = 0.4
        /// 判定为"有内容"的行所需的明暗跨度。
        public var contentSpread: Int = 20
        public init() {}
    }

    public enum AppendResult: Equatable {
        case appended(offset: Int)
        case noChange
        case noMatch
        /// 画面反而向上移动了（滚动方向反了），未追加
        case movedUp(offset: Int)
        case limitReached
    }

    public let width: Int
    public let frameHeight: Int
    public let options: Options
    public private(set) var header: Int = 0
    public private(set) var footer: Int = 0
    public private(set) var frameCount: Int = 1
    public private(set) var lastOffset: Int = 0
    /// 最近一次 append 的诊断信息（供日志）
    public private(set) var lastDebug: String = ""

    private var lastImage: CGImage
    private var lastSignature: RowSignature
    /// 已定型的内容条带（自上而下）。为空表示只有第一帧。
    private var strips: [CGImage] = []

    public init(first: CGImage, options: Options = Options()) {
        self.width = first.width
        self.frameHeight = first.height
        self.options = options
        self.lastImage = first
        self.lastSignature = RowSignature(image: first)
    }

    /// 当前已拼接的总高度（像素，含头尾）。
    public var totalHeight: Int {
        if strips.isEmpty { return frameHeight }
        return strips.reduce(0) { $0 + $1.height } + footer
    }

    public func append(_ image: CGImage, expectedOffset: Int? = nil) -> AppendResult {
        guard image.width == width, image.height == frameHeight else { return .noMatch }
        let sig = RowSignature(image: image)
        if ScrollStitcher.isIdentical(lastSignature, sig, options: options) {
            lastDebug = "identical to previous frame"
            return .noChange
        }

        // 第一次匹配：先用全帧粗找偏移，再检测固定元素，然后在内容区精找。
        guard var match = ScrollStitcher.findOffset(prev: lastSignature, next: sig, header: header, footer: footer,
                                                    expected: expectedOffset, options: options) else {
            // 正向找不到：反过来搜一下，判断是不是滚反了
            if let up = ScrollStitcher.findOffset(prev: sig, next: lastSignature, header: header, footer: footer,
                                                  expected: nil, options: options) {
                lastDebug = "moved UP by \(up.offset) score \(String(format: "%.2f", up.score))"
                return .movedUp(offset: up.offset)
            }
            lastDebug = "no offset accepted (expected \(expectedOffset.map(String.init) ?? "nil"), header \(header), footer \(footer))"
            return .noMatch
        }
        let sticky = ScrollStitcher.detectSticky(prev: lastSignature, next: sig, offset: match.offset, options: options)
        let newHeader = max(header, sticky.header)
        let newFooter = max(footer, sticky.footer)
        if newHeader != header || newFooter != footer {
            if let refined = ScrollStitcher.findOffset(prev: lastSignature, next: sig, header: newHeader, footer: newFooter,
                                                       expected: expectedOffset, options: options) {
                match = refined
            }
        }
        let d = match.offset
        lastDebug = "offset \(d) score \(String(format: "%.2f", match.score)) sticky \(sticky.header)/\(sticky.footer) expected \(expectedOffset.map(String.init) ?? "nil")"
        guard d > 0 else { return .noChange }
        if totalHeight + d > options.maxTotalHeight { return .limitReached }

        // 尾部固定区变大时，之前定型的条带底部混入了固定元素，裁掉。
        if newFooter > footer, let last = strips.last {
            let trim = newFooter - footer
            if last.height > trim, let trimmed = ScrollStitcher.copyRows(last, 0, last.height - trim) {
                strips[strips.count - 1] = trimmed
            }
        }
        header = newHeader
        footer = newFooter

        if strips.isEmpty {
            if let first = ScrollStitcher.copyRows(lastImage, 0, frameHeight - footer) { strips.append(first) }
        }
        let bottom = frameHeight - footer
        if let strip = ScrollStitcher.copyRows(image, bottom - d, bottom) { strips.append(strip) }

        lastImage = image
        lastSignature = sig
        lastOffset = d
        frameCount += 1
        return .appended(offset: d)
    }

    /// 合成最终长图。
    public func compose() -> CGImage? {
        if strips.isEmpty { return lastImage }
        let total = totalHeight
        guard let ctx = ScrollStitcher.makeContext(width: width, height: total) else { return nil }
        var y = 0
        for s in strips {
            ctx.draw(s, in: CGRect(x: 0, y: total - y - s.height, width: width, height: s.height))
            y += s.height
        }
        if footer > 0, let f = ScrollStitcher.copyRows(lastImage, frameHeight - footer, frameHeight) {
            ctx.draw(f, in: CGRect(x: 0, y: 0, width: width, height: footer))
        }
        return ctx.makeImage()
    }

    /// 缩略图，用于实时预览。
    public func thumbnail(width tw: Int) -> CGImage? {
        let total = totalHeight
        guard total > 0, tw > 0 else { return nil }
        let scale = CGFloat(tw) / CGFloat(width)
        let th = max(1, Int(CGFloat(total) * scale))
        guard let ctx = ScrollStitcher.makeContext(width: tw, height: th) else { return nil }
        ctx.interpolationQuality = .medium
        if strips.isEmpty {
            ctx.draw(lastImage, in: CGRect(x: 0, y: 0, width: tw, height: th))
            return ctx.makeImage()
        }
        var y: CGFloat = 0
        for s in strips {
            let h = CGFloat(s.height) * scale
            ctx.draw(s, in: CGRect(x: 0, y: CGFloat(th) - y - h, width: CGFloat(tw), height: h))
            y += h
        }
        if footer > 0, let f = ScrollStitcher.copyRows(lastImage, frameHeight - footer, frameHeight) {
            ctx.draw(f, in: CGRect(x: 0, y: 0, width: CGFloat(tw), height: CGFloat(footer) * scale))
        }
        return ctx.makeImage()
    }

    // MARK: - 纯算法（公开以便测试）

    /// 两帧画面是否一致（用于判断滚动动画是否已停稳）。
    public static func framesIdentical(_ a: CGImage, _ b: CGImage, options: Options = Options()) -> Bool {
        guard a.width == b.width, a.height == b.height else { return false }
        return isIdentical(RowSignature(image: a), RowSignature(image: b), options: options)
    }

    public static func isIdentical(_ a: RowSignature, _ b: RowSignature, options: Options) -> Bool {
        guard a.rows == b.rows else { return false }
        let eq = options.equalThreshold * RowSignature.buckets
        for y in 0..<a.rows where a.diff(y, b, y) >= eq { return false }
        return true
    }

    /// 找出 next 相对 prev 向下滚动的像素数 d，使得 next[y] ≈ prev[y + d]。
    ///
    /// 打分要点：
    /// 1. 按行加权：权重 = 行的明暗跨度，空白行几乎不计分，避免大面积空白页面上错误偏移侥幸得低分。
    /// 2. 双通道：整个内容区的加权均值，以及去掉上下边缘各 15% 后的中间带均值，取较小者。
    ///    吸顶 / 吸底还没被识别时，中间带能绕开它们。
    /// 3. 近似同分的候选里，优先选重叠区内容行更多（证据更充分）的，再选离预期更近的。
    public static func findOffset(prev: RowSignature, next: RowSignature, header: Int, footer: Int,
                                  expected: Int?, options: Options) -> (offset: Int, score: Double)? {
        let H = prev.rows
        guard next.rows == H, H > 0 else { return nil }
        let B = RowSignature.buckets
        let top = header, bottom = H - footer
        let contentH = bottom - top
        let maxD = contentH - options.minOverlap
        guard maxD >= 1 else { return nil }

        var weights = [Int](repeating: 1, count: H)
        var informativePrefix = [Int](repeating: 0, count: H + 1)
        for y in 0..<H {
            let sp = next.spread(y)
            weights[y] = max(1, sp)
            informativePrefix[y + 1] = informativePrefix[y] + (sp >= options.contentSpread ? 1 : 0)
        }
        func informativeRows(_ lo: Int, _ hi: Int) -> Int {
            hi > lo ? informativePrefix[hi] - informativePrefix[lo] : 0
        }
        // 多组上下裁边通道：吸顶 / 吸底还没被识别时，总有一组能绕开它们。
        // 已知 header/footer 后（top/bottom 已收窄）只用整个内容区。
        var trims: [(Double, Double)] = [(0, 0)]
        if header == 0 && footer == 0 {
            for x in [0.0, 0.15, 0.3] { for y in [0.0, 0.15, 0.3] where x + y > 0 { trims.append((x, y)) } }
        }
        // 通道 = 当前帧去掉顶部 X、上一帧去掉底部 Y 后仍能对应上的行：y ∈ [top + X, bottom - Y - d)
        let channels: [(lo: Int, hi: Int)] = trims.map { t in
            (lo: top + Int(Double(H) * t.0), hi: bottom - Int(Double(H) * t.1))
        }
        let minChannelRows = max(20, options.minOverlap / 2)

        var result: (offset: Int, score: Double)?
        prev.data.withUnsafeBufferPointer { a in
            next.data.withUnsafeBufferPointer { b in
                weights.withUnsafeBufferPointer { w in
                    // 对一个 d：先算每行加权差的前缀和，再由各通道 O(1) 取区间均值，取最小的有效通道
                    var diffPrefix = [Int](repeating: 0, count: H + 1)
                    var weightPrefix = [Int](repeating: 0, count: H + 1)
                    func raw(_ d: Int, stride: Int) -> Double {
                        let hi = bottom - d
                        var y = top
                        var acc = 0, wacc = 0
                        // 前缀数组只在采样行上累加，非采样行沿用上一值
                        var last = top
                        while y < hi {
                            let i = (y + d) * B, j = y * B
                            var s = 0
                            for k in 0..<B { s += abs(Int(a[i + k]) - Int(b[j + k])) }
                            acc += s * w[y]
                            wacc += w[y]
                            for f in (last + 1)...(y + 1) { diffPrefix[f] = acc; weightPrefix[f] = wacc }
                            last = y + 1
                            y += stride
                        }
                        if last < hi + 1 { for f in (last + 1)...(hi + 1) { diffPrefix[f] = acc; weightPrefix[f] = wacc } }
                        var best = Double.infinity
                        for c in channels {
                            let clo = c.lo, chi = min(c.hi - d, hi)
                            guard chi - clo >= minChannelRows, informativeRows(clo, chi) >= 2 else { continue }
                            let ws = weightPrefix[chi] - weightPrefix[clo]
                            guard ws > 0 else { continue }
                            let v = Double(diffPrefix[chi] - diffPrefix[clo]) / Double(ws * B)
                            if v < best { best = v }
                        }
                        return best
                    }
                    func penalty(_ d: Int) -> Double {
                        guard let e = expected else { return 0 }
                        return 3.0 * Double(abs(d - e)) / Double(H)
                    }

                    // 粗扫：每 3 行采样一次
                    var coarse = [Double](repeating: .infinity, count: maxD + 1)
                    var bestAdj = Double.infinity
                    for d in 1...maxD {
                        coarse[d] = raw(d, stride: 3) + penalty(d)
                        if coarse[d] < bestAdj { bestAdj = coarse[d] }
                    }
                    // 近似同分的候选：证据多者优先，再看离预期距离，最后偏向更大的 d
                    var bestD = 0
                    var bestKey = (-1, -Int.max, 0)
                    if bestAdj.isFinite {
                        for d in 1...maxD where coarse[d] <= bestAdj + 0.5 {
                            let evidence = informativeRows(top, bottom - d)
                            let closeness = expected.map { -abs(d - $0) } ?? 0
                            let key = (evidence, closeness, d)
                            if key > bestKey { bestKey = key; bestD = d }
                        }
                    }
                    // 所有候选都没有证据（重叠区整片空白）：有预期步长就按预期，否则放弃
                    guard bestD > 0 else {
                        if let e = expected, e >= 1, e <= maxD { result = (e, 0) }
                        return
                    }

                    // 精修：在最佳值附近逐行比较
                    var fineD = bestD
                    var fineRaw = Double.infinity
                    var fineAdj = Double.infinity
                    for d in max(1, bestD - 3)...min(maxD, bestD + 3) {
                        let r = raw(d, stride: 1)
                        let adj = r + penalty(d)
                        if adj < fineAdj { fineAdj = adj; fineRaw = r; fineD = d }
                    }
                    if fineRaw < options.acceptThreshold {
                        result = (fineD, fineRaw)
                    }
                }
            }
        }
        return result
    }

    /// 检测吸顶 / 吸底固定元素高度。
    /// 判定为固定的行：在两帧同一位置相同，且与按偏移平移后的内容不同，且本身有内容（非纯色）。
    public static func detectSticky(prev: RowSignature, next: RowSignature, offset d: Int,
                                    options: Options) -> (header: Int, footer: Int) {
        let H = prev.rows
        guard next.rows == H, d > 0, d < H else { return (0, 0) }
        let eq = options.equalThreshold * RowSignature.buckets
        let limit = Int(Double(H) * options.maxStickyRatio)

        var header = 0
        var y = 0
        while y < H - d && y < limit {
            guard prev.diff(y, next, y) < eq else { break }
            if prev.diff(y + d, next, y) >= eq && next.spread(y) >= options.contentSpread {
                header = y + 1
            }
            y += 1
        }

        var footer = 0
        y = H - 1
        while y >= d && (H - 1 - y) < limit {
            guard prev.diff(y, next, y) < eq else { break }
            if prev.diff(y, next, y - d) >= eq && next.spread(y) >= options.contentSpread {
                footer = H - y
            }
            y -= 1
        }
        return (header, footer)
    }

    // MARK: - 位图工具

    static func makeContext(width: Int, height: Int) -> CGContext? {
        guard width > 0, height > 0 else { return nil }
        return CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                         space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                         bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    }

    /// 复制图像的 [y0, y1) 行（自上而下计数）为独立的新图，释放对原图的引用。
    public static func copyRows(_ image: CGImage, _ y0: Int, _ y1: Int) -> CGImage? {
        let w = image.width, h = y1 - y0
        guard h > 0, y0 >= 0, y1 <= image.height, let ctx = makeContext(width: w, height: h) else { return nil }
        ctx.interpolationQuality = .none
        ctx.draw(image, in: CGRect(x: 0, y: -CGFloat(image.height - y1), width: CGFloat(w), height: CGFloat(image.height)))
        return ctx.makeImage()
    }
}
