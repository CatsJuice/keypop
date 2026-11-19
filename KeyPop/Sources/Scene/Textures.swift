import AppKit
import SpriteKit
import CoreText

/// 程序生成的纹理（全部用 CoreGraphics 高分辨率绘制，放大也细腻）
enum Palette {
    static let colors: [NSColor] = [
        NSColor(hex: 0xFF5E8A), NSColor(hex: 0xFF9F43), NSColor(hex: 0xFFD93D), NSColor(hex: 0x6BCB77),
        NSColor(hex: 0x4CC9F0), NSColor(hex: 0x4D96FF), NSColor(hex: 0x9B5DE5), NSColor(hex: 0xF15BB5),
    ]
    static func color(for code: Int) -> NSColor { colors[KeyMap.stableHash(code) % colors.count] }
    static var random: NSColor { colors.randomElement()! }
}

extension NSColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
    }
    func mixed(with other: NSColor, _ t: CGFloat) -> NSColor {
        let a = usingColorSpace(.sRGB)!, b = other.usingColorSpace(.sRGB)!
        return NSColor(srgbRed: a.redComponent + (b.redComponent - a.redComponent) * t,
                       green: a.greenComponent + (b.greenComponent - a.greenComponent) * t,
                       blue: a.blueComponent + (b.blueComponent - a.blueComponent) * t,
                       alpha: a.alphaComponent + (b.alphaComponent - a.alphaComponent) * t)
    }
    func lighter(_ t: CGFloat) -> NSColor { mixed(with: .white, t) }
    func darker(_ t: CGFloat) -> NSColor { mixed(with: .black, t) }
}

enum Textures {
    private static let space = CGColorSpace(name: CGColorSpace.sRGB)!

    static func draw(_ w: Int, _ h: Int, _ body: (CGContext) -> Void) -> CGImage {
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setAllowsAntialiasing(true)
        ctx.interpolationQuality = .high
        body(ctx)
        return ctx.makeImage()!
    }

    static func texture(_ img: CGImage) -> SKTexture {
        let t = SKTexture(cgImage: img)
        t.filteringMode = .linear
        t.usesMipmaps = true
        return t
    }

    /// 柔光圆
    static let glow: SKTexture = texture(draw(256, 256) { c in
        let g = CGGradient(colorsSpace: space, colors: [
            CGColor(gray: 1, alpha: 1), CGColor(gray: 1, alpha: 0.35), CGColor(gray: 1, alpha: 0.08), CGColor(gray: 1, alpha: 0),
        ] as CFArray, locations: [0, 0.18, 0.5, 1])!
        c.drawRadialGradient(g, startCenter: CGPoint(x: 128, y: 128), startRadius: 0,
                             endCenter: CGPoint(x: 128, y: 128), endRadius: 128, options: [])
    })

    /// 火花：亮核 + 柔光
    static let spark: SKTexture = texture(draw(64, 64) { c in
        let g = CGGradient(colorsSpace: space, colors: [
            CGColor(gray: 1, alpha: 1), CGColor(gray: 1, alpha: 0.9), CGColor(gray: 1, alpha: 0.25), CGColor(gray: 1, alpha: 0),
        ] as CFArray, locations: [0, 0.12, 0.35, 1])!
        c.drawRadialGradient(g, startCenter: CGPoint(x: 32, y: 32), startRadius: 0,
                             endCenter: CGPoint(x: 32, y: 32), endRadius: 32, options: [])
    })

    /// 四角闪光星 ✦
    static let sparkle: SKTexture = texture(draw(192, 192) { c in
        let m: CGFloat = 96
        let g = CGGradient(colorsSpace: space, colors: [CGColor(gray: 1, alpha: 0.6), CGColor(gray: 1, alpha: 0)] as CFArray,
                           locations: [0, 1])!
        c.drawRadialGradient(g, startCenter: CGPoint(x: m, y: m), startRadius: 0, endCenter: CGPoint(x: m, y: m),
                             endRadius: 40, options: [])
        c.setFillColor(CGColor(gray: 1, alpha: 1))
        let p = CGMutablePath()
        let long: CGFloat = 92, thin: CGFloat = 9
        p.move(to: CGPoint(x: m, y: m + long))
        p.addQuadCurve(to: CGPoint(x: m + long, y: m), control: CGPoint(x: m + thin, y: m + thin))
        p.addQuadCurve(to: CGPoint(x: m, y: m - long), control: CGPoint(x: m + thin, y: m - thin))
        p.addQuadCurve(to: CGPoint(x: m - long, y: m), control: CGPoint(x: m - thin, y: m - thin))
        p.addQuadCurve(to: CGPoint(x: m, y: m + long), control: CGPoint(x: m - thin, y: m + thin))
        c.addPath(p)
        c.fillPath()
    })

    /// 圆角五角星
    static let star: SKTexture = texture(draw(160, 160) { c in
        let p = CGMutablePath()
        for i in 0..<10 {
            let r: CGFloat = i % 2 == 0 ? 72 : 32
            let a = CGFloat(i) * .pi / 5 + .pi / 2
            let pt = CGPoint(x: 80 + cos(a) * r, y: 78 + sin(a) * r)
            i == 0 ? p.move(to: pt) : p.addLine(to: pt)
        }
        p.closeSubpath()
        c.addPath(p)
        c.setLineJoin(.round)
        c.setLineWidth(10)
        c.setStrokeColor(CGColor(gray: 1, alpha: 1))
        c.setFillColor(CGColor(gray: 1, alpha: 1))
        c.drawPath(using: .fillStroke)
    })

    /// 细圆环（冲击波）
    static let ring: SKTexture = texture(draw(512, 512) { c in
        for (w, a) in [(18.0, 0.12), (10.0, 0.3), (4.0, 1.0)] as [(CGFloat, CGFloat)] {
            c.setStrokeColor(CGColor(gray: 1, alpha: a))
            c.setLineWidth(w)
            c.strokeEllipse(in: CGRect(x: 20, y: 20, width: 472, height: 472))
        }
    })

    /// 彩纸片
    static let confetti: SKTexture = texture(draw(40, 64) { c in
        c.setFillColor(CGColor(gray: 1, alpha: 1))
        c.addPath(CGPath(roundedRect: CGRect(x: 2, y: 2, width: 36, height: 60), cornerWidth: 6, cornerHeight: 6, transform: nil))
        c.fillPath()
        c.setFillColor(CGColor(gray: 0, alpha: 0.12))   // 一侧暗面，翻转时更有立体感
        c.fill(CGRect(x: 2, y: 2, width: 12, height: 60))
    })

    /// 流星拖尾
    static let streak: SKTexture = texture(draw(512, 32) { c in
        c.addEllipse(in: CGRect(x: 0, y: 6, width: 512, height: 20))
        c.clip()
        let g = CGGradient(colorsSpace: space, colors: [CGColor(gray: 1, alpha: 0), CGColor(gray: 1, alpha: 0.5), CGColor(gray: 1, alpha: 1)] as CFArray,
                           locations: [0, 0.75, 1])!
        c.drawLinearGradient(g, start: .zero, end: CGPoint(x: 512, y: 0), options: [])
    })

    /// 火花光条（两端柔、中间亮）
    static let sparkLine: SKTexture = texture(draw(128, 32) { c in
        c.addEllipse(in: CGRect(x: 0, y: 0, width: 128, height: 32))
        c.clip()
        let g = CGGradient(colorsSpace: space, colors: [CGColor(gray: 1, alpha: 0), CGColor(gray: 1, alpha: 0.6), CGColor(gray: 1, alpha: 1)] as CFArray,
                           locations: [0, 0.6, 0.88])!
        c.drawLinearGradient(g, start: .zero, end: CGPoint(x: 128, y: 0), options: [.drawsAfterEndLocation])
        let core = CGGradient(colorsSpace: space, colors: [CGColor(gray: 1, alpha: 0.9), CGColor(gray: 1, alpha: 0)] as CFArray, locations: [0, 1])!
        c.drawRadialGradient(core, startCenter: CGPoint(x: 108, y: 16), startRadius: 0, endCenter: CGPoint(x: 108, y: 16), endRadius: 16, options: [])
    })

    /// 彩虹肥皂泡
    static let bubble: SKTexture = texture(draw(256, 256) { c in
        let ctr = CGPoint(x: 128, y: 128), r: CGFloat = 118
        let fill = CGGradient(colorsSpace: space, colors: [CGColor(gray: 1, alpha: 0.02), CGColor(gray: 1, alpha: 0.06), CGColor(gray: 1, alpha: 0.28)] as CFArray,
                              locations: [0, 0.75, 1])!
        c.drawRadialGradient(fill, startCenter: ctr, startRadius: 0, endCenter: ctr, endRadius: r, options: [])
        // 彩虹边：沿圆周按色相分段描边
        let steps = 120
        for i in 0..<steps {
            let a0 = CGFloat(i) / CGFloat(steps) * 2 * .pi, a1 = CGFloat(i + 1) / CGFloat(steps) * 2 * .pi + 0.02
            let hue = (CGFloat(i) / CGFloat(steps) + 0.55).truncatingRemainder(dividingBy: 1)
            c.setStrokeColor(NSColor(hue: hue, saturation: 0.55, brightness: 1, alpha: 0.55).cgColor)
            c.setLineWidth(7)
            c.addArc(center: ctr, radius: r - 5, startAngle: a0, endAngle: a1, clockwise: false)
            c.strokePath()
        }
        c.setStrokeColor(CGColor(gray: 1, alpha: 0.7))
        c.setLineWidth(2)
        c.strokeEllipse(in: CGRect(x: ctr.x - r, y: ctr.y - r, width: r * 2, height: r * 2))
        // 高光
        let hl = CGGradient(colorsSpace: space, colors: [CGColor(gray: 1, alpha: 0.95), CGColor(gray: 1, alpha: 0)] as CFArray, locations: [0, 1])!
        c.drawRadialGradient(hl, startCenter: CGPoint(x: 84, y: 176), startRadius: 0, endCenter: CGPoint(x: 84, y: 176), endRadius: 34, options: [])
        c.drawRadialGradient(hl, startCenter: CGPoint(x: 178, y: 74), startRadius: 0, endCenter: CGPoint(x: 178, y: 74), endRadius: 12, options: [])
    })

    // MARK: Emoji

    private static var emojiCache: [String: SKTexture] = [:]

    static func emoji(_ slug: String) -> SKTexture {
        if let t = emojiCache[slug] { return t }
        let t: SKTexture
        if let url = Bundle.main.url(forResource: slug, withExtension: "png", subdirectory: "Emoji"),
           let src = CGImageSourceCreateWithURL(url as CFURL, nil),
           let img = CGImageSourceCreateImageAtIndex(src, 0, nil) {
            t = texture(img)
        } else {
            t = glow
        }
        emojiCache[slug] = t
        return t
    }

    static func preloadEmoji() {
        let all = KeyMap.allEmoji.map { emoji($0) }
        SKTexture.preload(all) {}
    }

    // MARK: 立体大字

    private static var glyphCache: [String: SKTexture] = [:]

    /// 圆体粗字：白描边 + 渐变填充 + 顶部光泽
    static func glyph(_ text: String, color: NSColor) -> SKTexture {
        let key = "\(text)|\(color.description)"
        if let t = glyphCache[key] { return t }
        let size: CGFloat = 560
        let base = NSFont.systemFont(ofSize: size, weight: .black)
        let font = NSFont(descriptor: base.fontDescriptor.withDesign(.rounded) ?? base.fontDescriptor, size: size) ?? base
        let path = textPath(text, font: font as CTFont)
        let b = path.boundingBoxOfPath
        let pad = size * 0.12
        let w = Int(b.width + pad * 2), h = Int(b.height + pad * 2)
        let img = draw(w, h) { c in
            c.translateBy(x: pad - b.minX, y: pad - b.minY)
            // 外圈白边
            c.addPath(path)
            c.setLineJoin(.round)
            c.setLineWidth(size * 0.075)
            c.setStrokeColor(CGColor(gray: 1, alpha: 1))
            c.strokePath()
            // 渐变填充
            c.saveGState()
            c.addPath(path)
            c.clip()
            let fill = CGGradient(colorsSpace: space, colors: [color.lighter(0.35).cgColor, color.cgColor, color.darker(0.22).cgColor] as CFArray,
                                  locations: [0, 0.55, 1])!
            c.drawLinearGradient(fill, start: CGPoint(x: 0, y: b.maxY), end: CGPoint(x: 0, y: b.minY), options: [])
            // 顶部光泽
            let gloss = CGGradient(colorsSpace: space, colors: [CGColor(gray: 1, alpha: 0.55), CGColor(gray: 1, alpha: 0.0)] as CFArray, locations: [0, 1])!
            c.drawLinearGradient(gloss, start: CGPoint(x: 0, y: b.maxY), end: CGPoint(x: 0, y: b.midY + b.height * 0.05), options: [])
            // 内描边，让边缘更利落
            c.addPath(path)
            c.setLineWidth(size * 0.02)
            c.setStrokeColor(color.darker(0.35).withAlphaComponent(0.5).cgColor)
            c.strokePath()
            c.restoreGState()
        }
        let t = texture(img)
        glyphCache[key] = t
        return t
    }

    private static func textPath(_ s: String, font: CTFont) -> CGPath {
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: s, attributes: [.font: font]))
        let path = CGMutablePath()
        for run in CTLineGetGlyphRuns(line) as! [CTRun] {
            let attrs = CTRunGetAttributes(run) as NSDictionary
            let runFont = attrs[kCTFontAttributeName] as! CTFont
            let n = CTRunGetGlyphCount(run)
            var glyphs = [CGGlyph](repeating: 0, count: n)
            var pos = [CGPoint](repeating: .zero, count: n)
            CTRunGetGlyphs(run, CFRange(location: 0, length: n), &glyphs)
            CTRunGetPositions(run, CFRange(location: 0, length: n), &pos)
            for i in 0..<n {
                if let g = CTFontCreatePathForGlyph(runFont, glyphs[i], nil) {
                    path.addPath(g, transform: CGAffineTransform(translationX: pos[i].x, y: pos[i].y))
                }
            }
        }
        return path
    }
}
