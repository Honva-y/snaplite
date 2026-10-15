import CoreGraphics
import Foundation
import Stitching

// 拼接算法离线校验：合成一个带吸顶/吸底的"长页面"，切帧后拼回去，要求逐像素一致。
// 运行：swift run -c release stitch-check

var failures = 0
func check(_ cond: Bool, _ msg: String) {
    if cond { print("  ✓ \(msg)") } else { failures += 1; print("  ✗ \(msg)") }
}
func checkEqual<T: Equatable>(_ a: T, _ b: T, _ msg: String) {
    if a == b { print("  ✓ \(msg)") } else { failures += 1; print("  ✗ \(msg): \(a) != \(b)") }
}

struct LCG {
    var state: UInt64
    mutating func next() -> UInt8 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return UInt8(truncatingIfNeeded: state >> 33)
    }
}

/// 大面积空白 + 稀疏文字行的页面（模拟聊天 / 文档），每 70 行有 14 行内容
func makeSparsePage(width: Int, height: Int, seed: UInt64) -> [UInt8] {
    var rng = LCG(state: seed)
    var px = [UInt8](repeating: 250, count: width * height * 4)
    for y in 0..<height where y % 70 < 14 {
        let base = Int(rng.next())
        let period = 3 + base % 7
        let ink = UInt8(20 + base % 60)
        for x in 0..<width {
            let i = (y * width + x) * 4
            let on = ((x + base) / period) % 3 == 0
            px[i] = on ? ink : 250
            px[i + 1] = on ? ink : 250
            px[i + 2] = on ? ink &+ 30 : 250
            px[i + 3] = 255
        }
    }
    return px
}

func makePage(width: Int, height: Int, seed: UInt64) -> [UInt8] {
    var rng = LCG(state: seed)
    var px = [UInt8](repeating: 255, count: width * height * 4)
    for y in 0..<height {
        let base = rng.next()
        for x in 0..<width {
            let i = (y * width + x) * 4
            px[i] = base
            px[i + 1] = rng.next()
            px[i + 2] = UInt8(truncatingIfNeeded: x * 7 + y * 3)
            px[i + 3] = 255
        }
    }
    return px
}

func image(from rgba: [UInt8], width: Int, height: Int) -> CGImage {
    var copy = rgba
    return copy.withUnsafeMutableBytes { raw in
        CGContext(data: raw.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!.makeImage()!
    }
}

func rgba(of image: CGImage) -> [UInt8] {
    var out = [UInt8](repeating: 0, count: image.width * image.height * 4)
    out.withUnsafeMutableBytes { raw in
        let ctx = CGContext(data: raw.baseAddress, width: image.width, height: image.height, bitsPerComponent: 8,
                            bytesPerRow: image.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    }
    return out
}

func rows(_ px: [UInt8], width: Int, _ r: Range<Int>) -> [UInt8] {
    Array(px[(r.lowerBound * width * 4)..<(r.upperBound * width * 4)])
}

func frame(page: [UInt8], header: [UInt8], footer: [UInt8], width: Int, offset: Int, viewport: Int) -> CGImage {
    var px = header
    px += rows(page, width: width, offset..<(offset + viewport))
    px += footer
    return image(from: px, width: width, height: px.count / (width * 4))
}

func scenario(_ name: String, headerH: Int, footerH: Int, step: Int, expected: Int?, sparse: Bool = false) {
    print("▶ \(name)")
    let W = 320, pageH = 2600, viewport = 480
    let page = sparse ? makeSparsePage(width: W, height: pageH, seed: 42) : makePage(width: W, height: pageH, seed: 42)
    let header = makePage(width: W, height: headerH, seed: 7)
    let footer = makePage(width: W, height: footerH, seed: 9)

    var offsets: [Int] = [0]
    while offsets.last! + step < pageH - viewport { offsets.append(offsets.last! + step) }
    offsets.append(pageH - viewport)

    var opts = ScrollStitcher.Options()
    opts.minOverlap = 40
    let stitcher = ScrollStitcher(first: frame(page: page, header: header, footer: footer, width: W, offset: 0, viewport: viewport), options: opts)
    let start = Date()
    var allOK = true
    for (i, off) in offsets.dropFirst().enumerated() {
        let r = stitcher.append(frame(page: page, header: header, footer: footer, width: W, offset: off, viewport: viewport), expectedOffset: expected)
        if r != .appended(offset: off - offsets[i]) { allOK = false; print("    frame \(i + 1): got \(r), want offset \(off - offsets[i])") }
    }
    check(allOK, "所有帧偏移正确（\(offsets.count) 帧，\(Int(Date().timeIntervalSince(start) * 1000)) ms）")
    checkEqual(stitcher.append(frame(page: page, header: header, footer: footer, width: W, offset: offsets.last!, viewport: viewport)), .noChange, "重复末帧判定为无变化")
    checkEqual(stitcher.header, headerH, "吸顶高度")
    checkEqual(stitcher.footer, footerH, "吸底高度")
    let composed = stitcher.compose()!
    checkEqual(composed.height, headerH + pageH + footerH, "合成高度")
    check(rgba(of: composed) == header + page + footer, "逐像素一致")
}

scenario("普通滚动 + 已知步长", headerH: 0, footerH: 0, step: 300, expected: 300)
scenario("普通滚动 + 未知步长（手动模式）", headerH: 0, footerH: 0, step: 250, expected: nil)
scenario("吸顶 + 吸底", headerH: 56, footerH: 40, step: 260, expected: 260)
scenario("吸顶 + 手动模式", headerH: 64, footerH: 0, step: 200, expected: nil)
scenario("空白为主的页面 + 预期步长与实际不一致（平滑滚动）", headerH: 0, footerH: 0, step: 260, expected: 300, sparse: true)
scenario("空白为主的页面 + 吸顶 + 手动模式", headerH: 48, footerH: 0, step: 230, expected: nil, sparse: true)
scenario("聊天窗口：稀疏内容 + 顶栏 10% + 底部输入框 25% + 步长 30%", headerH: 48, footerH: 120, step: 144, expected: 144, sparse: true)
scenario("聊天窗口：同上，手动模式", headerH: 48, footerH: 120, step: 200, expected: nil, sparse: true)

print("▶ 滚反了（画面向上移动）")
do {
    let W = 300, viewport = 400
    let page = makeSparsePage(width: W, height: 2000, seed: 5)
    let s = ScrollStitcher(first: frame(page: page, header: [], footer: [], width: W, offset: 500, viewport: viewport))
    checkEqual(s.append(frame(page: page, header: [], footer: [], width: W, offset: 300, viewport: viewport), expectedOffset: 200), .movedUp(offset: 200), "判定为向上移动 200")
    checkEqual(s.frameCount, 1, "帧数不变")
    checkEqual(s.append(frame(page: page, header: [], footer: [], width: W, offset: 700, viewport: viewport), expectedOffset: 200), .appended(offset: 200), "随后正常向下追加")
}

print("▶ 滚动过多无重叠")
do {
    let W = 200, viewport = 300
    let page = makePage(width: W, height: 2000, seed: 3)
    let s = ScrollStitcher(first: frame(page: page, header: [], footer: [], width: W, offset: 0, viewport: viewport))
    checkEqual(s.append(frame(page: page, header: [], footer: [], width: W, offset: 800, viewport: viewport)), .noMatch, "判定为无法匹配")
    checkEqual(s.frameCount, 1, "帧数不变")
}

print("▶ copyRows")
do {
    let W = 10
    let page = makePage(width: W, height: 20, seed: 1)
    let part = ScrollStitcher.copyRows(image(from: page, width: W, height: 20), 5, 12)!
    checkEqual(part.height, 7, "高度")
    check(rgba(of: part) == rows(page, width: W, 5..<12), "内容")
}

print(failures == 0 ? "\n全部通过" : "\n失败 \(failures) 项")
exit(failures == 0 ? 0 : 1)
