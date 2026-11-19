// 用 CoreGraphics 绘制 App 图标：一颗立体键帽“砰”地弹出彩色星星和彩纸。
// 用法：swift scripts/IconRenderer.swift <warm|sky|night> <输出.png> [porcelain|midnight|candy]
import AppKit
import CoreGraphics
import CoreText

let args = CommandLine.arguments
let variant = args.count > 1 ? args[1] : "warm"
let outPath = args.count > 2 ? args[2] : "icon.png"
let capStyle = args.count > 3 ? args[3] : "porcelain"
let S = 1024
let cs = CGColorSpace(name: CGColorSpace.sRGB)!

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}
func gradient(_ colors: [CGColor], _ locs: [CGFloat]? = nil) -> CGGradient {
    CGGradient(colorsSpace: cs, colors: colors as CFArray, locations: locs)!
}

/// macOS 风格的超椭圆圆角方块
func squircle(_ r: CGRect) -> CGPath {
    let p = CGMutablePath()
    let n: CGFloat = 5
    let a = r.width / 2, b = r.height / 2, cx = r.midX, cy = r.midY
    for i in 0...360 {
        let t = CGFloat(i) * .pi / 180
        let c = cos(t), s = sin(t)
        let x = cx + a * (c < 0 ? -1 : 1) * pow(abs(c), 2 / n)
        let y = cy + b * (s < 0 ? -1 : 1) * pow(abs(s), 2 / n)
        i == 0 ? p.move(to: CGPoint(x: x, y: y)) : p.addLine(to: CGPoint(x: x, y: y))
    }
    p.closeSubpath()
    return p
}

func sparkle(_ c: CGContext, at p: CGPoint, r: CGFloat, color: CGColor, rot: CGFloat = 0) {
    c.saveGState()
    c.translateBy(x: p.x, y: p.y)
    c.rotate(by: rot)
    let path = CGMutablePath()
    let t = r * 0.16
    path.move(to: CGPoint(x: 0, y: r))
    path.addQuadCurve(to: CGPoint(x: r, y: 0), control: CGPoint(x: t, y: t))
    path.addQuadCurve(to: CGPoint(x: 0, y: -r), control: CGPoint(x: t, y: -t))
    path.addQuadCurve(to: CGPoint(x: -r, y: 0), control: CGPoint(x: -t, y: -t))
    path.addQuadCurve(to: CGPoint(x: 0, y: r), control: CGPoint(x: -t, y: t))
    c.setShadow(offset: .zero, blur: r * 0.5, color: CGColor(gray: 1, alpha: 0.6))
    c.addPath(path)
    c.setFillColor(color)
    c.fillPath()
    c.restoreGState()
}

func star(_ c: CGContext, at p: CGPoint, r: CGFloat, rot: CGFloat) {
    c.saveGState()
    c.translateBy(x: p.x, y: p.y)
    c.rotate(by: rot)
    let path = CGMutablePath()
    for i in 0..<10 {
        let rr = i % 2 == 0 ? r : r * 0.48
        let a = CGFloat(i) * .pi / 5 + .pi / 2
        let pt = CGPoint(x: cos(a) * rr, y: sin(a) * rr)
        i == 0 ? path.move(to: pt) : path.addLine(to: pt)
    }
    path.closeSubpath()
    c.setShadow(offset: CGSize(width: 0, height: -r * 0.12), blur: r * 0.25, color: CGColor(gray: 0, alpha: 0.25))
    c.addPath(path)
    c.setLineJoin(.round)
    c.setLineWidth(r * 0.22)
    c.setStrokeColor(rgb(0xFFC21A))
    c.setFillColor(rgb(0xFFC21A))
    c.drawPath(using: .fillStroke)
    c.setShadow(offset: .zero, blur: 0, color: nil)
    c.addPath(path)
    c.clip()
    c.drawLinearGradient(gradient([rgb(0xFFF3A0), rgb(0xFFD93D), rgb(0xFFA91F)], [0, 0.45, 1]),
                         start: CGPoint(x: 0, y: r), end: CGPoint(x: 0, y: -r), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    c.restoreGState()
}

func confetti(_ c: CGContext, at p: CGPoint, w: CGFloat, h: CGFloat, color: UInt32, rot: CGFloat) {
    c.saveGState()
    c.translateBy(x: p.x, y: p.y)
    c.rotate(by: rot)
    c.setShadow(offset: CGSize(width: 0, height: -4), blur: 6, color: CGColor(gray: 0, alpha: 0.18))
    c.addPath(CGPath(roundedRect: CGRect(x: -w / 2, y: -h / 2, width: w, height: h), cornerWidth: min(w, h) / 2, cornerHeight: min(w, h) / 2, transform: nil))
    c.setFillColor(rgb(color))
    c.fillPath()
    c.restoreGState()
}

func textPath(_ s: String, size: CGFloat) -> CGPath {
    let base = NSFont.systemFont(ofSize: size, weight: .black)
    let font = NSFont(descriptor: base.fontDescriptor.withDesign(.rounded)!, size: size)! as CTFont
    let line = CTLineCreateWithAttributedString(NSAttributedString(string: s, attributes: [.font: font]))
    let path = CGMutablePath()
    for run in CTLineGetGlyphRuns(line) as! [CTRun] {
        let n = CTRunGetGlyphCount(run)
        var g = [CGGlyph](repeating: 0, count: n), pos = [CGPoint](repeating: .zero, count: n)
        CTRunGetGlyphs(run, CFRange(location: 0, length: n), &g)
        CTRunGetPositions(run, CFRange(location: 0, length: n), &pos)
        for i in 0..<n {
            if let gp = CTFontCreatePathForGlyph(font, g[i], nil) {
                path.addPath(gp, transform: CGAffineTransform(translationX: pos[i].x, y: pos[i].y))
            }
        }
    }
    return path
}

let ctx = CGContext(data: nil, width: S, height: S, bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
let c = ctx
let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
let shape = squircle(tile)

// 图标底板 + 外阴影
c.saveGState()
c.setShadow(offset: CGSize(width: 0, height: -12), blur: 30, color: CGColor(gray: 0, alpha: 0.35))
c.addPath(shape)
c.setFillColor(rgb(0x000000))
c.fillPath()
c.restoreGState()

c.saveGState()
c.addPath(shape)
c.clip()
// 键帽中心放在略高于几何中心的位置，让整体视觉重心居中（缩小后也不会显得往下坠）
let center = CGPoint(x: 512, y: 505)
switch variant {
case "sky":
    c.drawLinearGradient(gradient([rgb(0x7BD8FF), rgb(0x4D96FF), rgb(0x3A6CF0)], [0, 0.55, 1]),
                         start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    c.drawRadialGradient(gradient([rgb(0xFFFFFF, 0.45), rgb(0xFFFFFF, 0)]), startCenter: CGPoint(x: 512, y: 560), startRadius: 0,
                         endCenter: CGPoint(x: 512, y: 560), endRadius: 420, options: [])
case "night":
    c.setFillColor(rgb(0x0A0A10))
    c.fill(tile)
    c.drawRadialGradient(gradient([rgb(0xFF5E8A, 0.55), rgb(0xFF5E8A, 0)]), startCenter: CGPoint(x: 380, y: 690), startRadius: 0,
                         endCenter: CGPoint(x: 380, y: 690), endRadius: 420, options: [])
    c.drawRadialGradient(gradient([rgb(0x4CC9F0, 0.45), rgb(0x4CC9F0, 0)]), startCenter: CGPoint(x: 660, y: 350), startRadius: 0,
                         endCenter: CGPoint(x: 660, y: 350), endRadius: 400, options: [])
default: // warm
    c.drawLinearGradient(gradient([rgb(0xFFE15A), rgb(0xFFA43A), rgb(0xFF6A88)], [0, 0.5, 1]),
                         start: CGPoint(x: 260, y: 924), end: CGPoint(x: 760, y: 100), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    c.drawRadialGradient(gradient([rgb(0xFFFFFF, 0.5), rgb(0xFFFFFF, 0)]), startCenter: CGPoint(x: 512, y: 600), startRadius: 0,
                         endCenter: CGPoint(x: 512, y: 600), endRadius: 400, options: [])
}
// 顶部柔光
c.drawLinearGradient(gradient([rgb(0xFFFFFF, 0.18), rgb(0xFFFFFF, 0)]), start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 640), options: [])

// 放射光芒
c.saveGState()
c.translateBy(x: center.x, y: center.y + 50)
for i in 0..<14 {
    let a = CGFloat(i) / 14 * 2 * .pi
    let p = CGMutablePath()
    p.move(to: .zero)
    p.addLine(to: CGPoint(x: cos(a - 0.09) * 620, y: sin(a - 0.09) * 620))
    p.addLine(to: CGPoint(x: cos(a + 0.09) * 620, y: sin(a + 0.09) * 620))
    p.closeSubpath()
    c.addPath(p)
}
c.setFillColor(CGColor(gray: 1, alpha: variant == "night" ? 0.05 : 0.12))
c.fillPath()
c.restoreGState()

// 键帽
/// 内阴影：在 path 内侧沿某个方向投下阴影，用来做顶面的“碟形”凹陷
func innerShadow(_ path: CGPath, offset: CGSize, blur: CGFloat, color: CGColor) {
    c.saveGState()
    c.addPath(path)
    c.clip()
    let ring = CGMutablePath()
    ring.addRect(path.boundingBoxOfPath.insetBy(dx: -200, dy: -200))
    ring.addPath(path)
    c.setShadow(offset: offset, blur: blur, color: color)
    c.addPath(ring)
    c.setFillColor(CGColor(gray: 0, alpha: 1))
    c.fillPath(using: .evenOdd)
    c.restoreGState()
}

struct CapColors {
    let sideTop: UInt32, sideBottom: UInt32, faceTop: UInt32, faceBottom: UInt32
    let rimPink: CGFloat, rimCyan: CGFloat, gloss: CGFloat, dish: CGFloat
}
let cc: CapColors
switch capStyle {
case "midnight":
    cc = CapColors(sideTop: 0x3A4068, sideBottom: 0x151830, faceTop: 0x4A5285, faceBottom: 0x2B3058, rimPink: 0.75, rimCyan: 0.7, gloss: 0.22, dish: 0.45)
case "candy":
    cc = CapColors(sideTop: 0xFF7EA3, sideBottom: 0xB81E5A, faceTop: 0xFFB3C8, faceBottom: 0xFF6E98, rimPink: 0.3, rimCyan: 0.35, gloss: 0.5, dish: 0.3)
default: // porcelain 白瓷
    cc = CapColors(sideTop: 0xF2F0F7, sideBottom: 0x9EA3BD, faceTop: 0xFFFFFF, faceBottom: 0xECEAF3, rimPink: 0.45, rimCyan: 0.4, gloss: 0.7, dish: 0.16)
}

let capW: CGFloat = 470, capH: CGFloat = 436
let capBase = CGRect(x: center.x - capW / 2, y: center.y - capH / 2, width: capW, height: capH)
/// 连续曲率圆角矩形（和 macOS/iOS 图标一样的“平滑圆角”）：
/// 每个角用超椭圆曲线，和直边相接处曲率为 0，不会出现普通圆角那种生硬的转折。
/// extent 是圆角占用的边长，视觉上约等于普通圆角半径的 1.5 倍。
func smoothRect(_ r: CGRect, extent e0: CGFloat, n: CGFloat = 3.2) -> CGPath {
    let e = min(e0, r.width / 2, r.height / 2)
    let p = CGMutablePath()
    // 四个角：圆心、x 方向、y 方向
    let corners: [(CGPoint, CGFloat, CGFloat)] = [
        (CGPoint(x: r.maxX - e, y: r.maxY - e), 1, 1),
        (CGPoint(x: r.minX + e, y: r.maxY - e), -1, 1),
        (CGPoint(x: r.minX + e, y: r.minY + e), -1, -1),
        (CGPoint(x: r.maxX - e, y: r.minY + e), 1, -1),
    ]
    let steps = 48
    for (k, (ctr, sx, sy)) in corners.enumerated() {
        for i in 0...steps {
            // 每个角从水平方向扫到竖直方向（逆时针顺序）
            var t = CGFloat(i) / CGFloat(steps) * .pi / 2
            if k % 2 == 1 { t = .pi / 2 - t }
            let x = ctr.x + sx * e * pow(cos(t), 2 / n)
            let y = ctr.y + sy * e * pow(sin(t), 2 / n)
            let pt = CGPoint(x: x, y: y)
            (k == 0 && i == 0) ? p.move(to: pt) : p.addLine(to: pt)
        }
    }
    p.closeSubpath()
    return p
}
let side = smoothRect(capBase, extent: 165)
// 顶面四周只留一圈细边，底部稍厚一点保留立体感（像从略微斜上方看）
let top = CGRect(x: capBase.minX + 24, y: capBase.minY + 58, width: capW - 48, height: capH - 80)
let topPath = smoothRect(top, extent: 145)

// 1. 接触阴影
c.saveGState()
c.translateBy(x: center.x, y: capBase.minY + 8)
c.scaleBy(x: 1, y: 0.18)
c.drawRadialGradient(gradient([CGColor(gray: 0, alpha: 0.85), CGColor(gray: 0, alpha: 0)]), startCenter: .zero, startRadius: 0,
                     endCenter: .zero, endRadius: capW * 0.66, options: [])
c.restoreGState()

// 2. 底座（侧面）
c.saveGState()
c.setShadow(offset: CGSize(width: 0, height: -16), blur: 36, color: CGColor(gray: 0, alpha: 0.6))
c.addPath(side)
c.setFillColor(rgb(cc.sideBottom))
c.fillPath()
c.restoreGState()
c.saveGState()
c.addPath(side)
c.clip()
c.drawLinearGradient(gradient([rgb(cc.sideTop), rgb(cc.sideBottom)]), start: CGPoint(x: 0, y: capBase.maxY), end: CGPoint(x: 0, y: capBase.minY),
                     options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
// 左右两侧的弧面暗部
c.drawLinearGradient(gradient([CGColor(gray: 0, alpha: 0.22), CGColor(gray: 0, alpha: 0), CGColor(gray: 0, alpha: 0), CGColor(gray: 0, alpha: 0.22)], [0, 0.16, 0.84, 1]),
                     start: CGPoint(x: capBase.minX, y: 0), end: CGPoint(x: capBase.maxX, y: 0), options: [])
// 环境反光：左上映粉、右下映青，和背景光晕呼应
c.setBlendMode(.plusLighter)
c.drawRadialGradient(gradient([rgb(0xFF5E8A, cc.rimPink), rgb(0xFF5E8A, 0)]), startCenter: CGPoint(x: capBase.minX, y: capBase.midY + 60), startRadius: 0,
                     endCenter: CGPoint(x: capBase.minX, y: capBase.midY + 60), endRadius: 230, options: [])
c.drawRadialGradient(gradient([rgb(0x4CC9F0, cc.rimCyan), rgb(0x4CC9F0, 0)]), startCenter: CGPoint(x: capBase.maxX, y: capBase.minY + 70), startRadius: 0,
                     endCenter: CGPoint(x: capBase.maxX, y: capBase.minY + 70), endRadius: 230, options: [])
c.setBlendMode(.normal)
c.restoreGState()
// 底座上沿的倒角高光
c.saveGState()
c.addPath(side)
c.clip()
c.translateBy(x: 0, y: -3)
c.addPath(side)
c.setLineWidth(5)
c.setStrokeColor(CGColor(gray: 1, alpha: capStyle == "midnight" ? 0.25 : 0.6))
c.strokePath()
c.restoreGState()

// 3. 顶面
c.saveGState()
c.setShadow(offset: CGSize(width: 0, height: -10), blur: 18, color: CGColor(gray: 0, alpha: capStyle == "midnight" ? 0.5 : 0.22))
c.addPath(topPath)
c.setFillColor(rgb(cc.faceBottom))
c.fillPath()
c.restoreGState()
c.saveGState()
c.addPath(topPath)
c.clip()
c.drawLinearGradient(gradient([rgb(cc.faceTop), rgb(cc.faceBottom)]), start: CGPoint(x: 0, y: top.maxY), end: CGPoint(x: 0, y: top.minY),
                     options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
// 左上的柔和高光
c.drawRadialGradient(gradient([CGColor(gray: 1, alpha: cc.gloss), CGColor(gray: 1, alpha: 0)]),
                     startCenter: CGPoint(x: top.minX + top.width * 0.28, y: top.maxY - 50), startRadius: 0,
                     endCenter: CGPoint(x: top.minX + top.width * 0.28, y: top.maxY - 50), endRadius: top.width * 0.5, options: [])
c.restoreGState()
// 碟形凹陷：上沿内阴影 + 下沿亮边
innerShadow(topPath, offset: CGSize(width: 0, height: -10), blur: 22, color: CGColor(gray: 0, alpha: cc.dish))
innerShadow(topPath, offset: CGSize(width: 0, height: 4), blur: 6, color: CGColor(gray: 1, alpha: capStyle == "midnight" ? 0.18 : 0.8))

// 4. 字母
let letter = textPath("A", size: 300)
let lb = letter.boundingBoxOfPath
c.saveGState()
c.translateBy(x: top.midX - lb.midX, y: top.midY - lb.midY + 4)
switch capStyle {
case "candy":
    c.saveGState()
    c.setShadow(offset: CGSize(width: 0, height: -7), blur: 10, color: rgb(0x9E1448, 0.55))
    c.addPath(letter)
    c.setFillColor(rgb(0xFFFFFF))
    c.fillPath()
    c.restoreGState()
    c.saveGState()
    c.addPath(letter)
    c.clip()
    c.drawLinearGradient(gradient([rgb(0xFFFFFF), rgb(0xFFE4EE)]), start: CGPoint(x: 0, y: lb.maxY), end: CGPoint(x: 0, y: lb.minY), options: [])
    c.restoreGState()
case "midnight":
    // 霓虹发光字
    c.saveGState()
    c.setShadow(offset: .zero, blur: 40, color: rgb(0xFF4F8B, 0.9))
    c.addPath(letter)
    c.setFillColor(rgb(0xFF5E8A))
    c.fillPath()
    c.restoreGState()
    c.saveGState()
    c.addPath(letter)
    c.clip()
    c.drawLinearGradient(gradient([rgb(0xFFE07A), rgb(0xFF7A59), rgb(0xFF3D8B)], [0, 0.45, 1]),
                         start: CGPoint(x: 0, y: lb.maxY), end: CGPoint(x: 0, y: lb.minY), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    c.restoreGState()
    innerShadow(letter, offset: CGSize(width: 0, height: -4), blur: 4, color: CGColor(gray: 1, alpha: 0.6))
default:
    // 凸起的糖果字：深色投影 + 饱和渐变 + 上半部光泽 + 底部暗边
    c.saveGState()
    c.setShadow(offset: CGSize(width: 0, height: -8), blur: 12, color: rgb(0x8A1450, 0.35))
    c.addPath(letter)
    c.setFillColor(rgb(0xE8336F))
    c.fillPath()
    c.restoreGState()
    c.saveGState()
    c.addPath(letter)
    c.clip()
    c.drawLinearGradient(gradient([rgb(0xFF9A4D), rgb(0xFF4F7B), rgb(0xD92A7A)], [0, 0.5, 1]),
                         start: CGPoint(x: 0, y: lb.maxY), end: CGPoint(x: 0, y: lb.minY), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    c.drawLinearGradient(gradient([CGColor(gray: 1, alpha: 0.42), CGColor(gray: 1, alpha: 0)]),
                         start: CGPoint(x: 0, y: lb.maxY), end: CGPoint(x: 0, y: lb.midY + 20), options: [])
    c.restoreGState()
    innerShadow(letter, offset: CGSize(width: 0, height: 5), blur: 6, color: rgb(0x7A0E45, 0.45))
    innerShadow(letter, offset: CGSize(width: 0, height: -3), blur: 3, color: CGColor(gray: 1, alpha: 0.55))
}
c.restoreGState()

// 从键帽里“砰”出来的星星和彩纸
// 星星压住键帽两个上角，像是刚从键里“砰”出来；四周留出均衡的点缀
star(c, at: CGPoint(x: 742, y: 758), r: 98, rot: 0.25)
star(c, at: CGPoint(x: 288, y: 742), r: 62, rot: -0.3)
sparkle(c, at: CGPoint(x: 512, y: 850), r: 48, color: CGColor(gray: 1, alpha: 1))
sparkle(c, at: CGPoint(x: 182, y: 486), r: 34, color: CGColor(gray: 1, alpha: 1), rot: 0.2)
sparkle(c, at: CGPoint(x: 846, y: 470), r: 40, color: CGColor(gray: 1, alpha: 1), rot: -0.15)
confetti(c, at: CGPoint(x: 405, y: 832), w: 24, h: 52, color: 0x4CC9F0, rot: 0.5)
confetti(c, at: CGPoint(x: 624, y: 852), w: 24, h: 50, color: 0x6BCB77, rot: -0.7)
confetti(c, at: CGPoint(x: 196, y: 640), w: 24, h: 48, color: 0x9B5DE5, rot: 1.1)
confetti(c, at: CGPoint(x: 838, y: 628), w: 24, h: 50, color: 0xFF5E8A, rot: -0.3)
confetti(c, at: CGPoint(x: 200, y: 330), w: 24, h: 24, color: 0xFFD93D, rot: 0)
confetti(c, at: CGPoint(x: 826, y: 318), w: 22, h: 44, color: 0x4D96FF, rot: 0.8)
c.restoreGState()

let img = ctx.makeImage()!
let rep = NSBitmapImageRep(cgImage: img)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: outPath))
print("✓ \(outPath)")
