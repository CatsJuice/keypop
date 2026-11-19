import SpriteKit

/// 由 update() 手动驱动的粒子（彩纸翻转、泡泡漂浮、旋涡），比 SKAction 更省、更可控
private final class Piece {
    enum Kind { case confetti, bubble, spiral, spark }
    let node: SKSpriteNode
    let kind: Kind
    var vel: CGVector
    var life: CGFloat = 0
    let maxLife: CGFloat
    var phase = CGFloat.random(in: 0...(2 * .pi))
    var flipSpeed = CGFloat.random(in: 5...11)
    var spin = CGFloat.random(in: -5...5)
    var baseScale: CGFloat = 1
    var thickness: CGFloat = 4
    var tint: NSColor = .white
    // 旋涡
    var center = CGPoint.zero
    var angle: CGFloat = 0
    var radius0: CGFloat = 0

    init(_ node: SKSpriteNode, _ kind: Kind, vel: CGVector, life: CGFloat) {
        self.node = node; self.kind = kind; self.vel = vel; maxLife = life
    }
}

final class PlayScene: SKScene {
    private let settings = Settings.shared
    private let ambient = SKNode(), pools = SKNode(), fx = SKNode(), items = SKNode(), overlay = SKNode()
    private var pieces: [Piece] = []
    private var recentSpots: [CGPoint] = []
    private var lastUpdate: TimeInterval = 0
    private var hint: SKNode?
    private let cursor = SKNode()
    private var cursorTrail: SKEmitterNode?
    private var lastMouse = CGPoint.zero
    private var exitNode: SKNode?

    /// 鼠标点击时播放声音（x 方向 0…1）
    var onClick: ((CGFloat) -> Void)?
    /// 按下 / 松开左上角退出按钮
    var onExitButton: ((Bool) -> Void)?
    private let exitButton = SKNode()
    private var exitButtonHeld = false

    private var unit: CGFloat { min(size.width, size.height) }

    /// 预览模式：透明背景，只用来在设置页里放一下特效
    var isPreview = false
    private var themeOverride: EffectTheme?
    private var theme: EffectTheme { themeOverride ?? settings.theme }

    /// 在设置页卡片上原地放一次该主题的特效
    func previewBurst(at p: CGPoint, theme t: EffectTheme) {
        themeOverride = t
        burst(at: p, color: Palette.random, power: 0.85)
        trim()
    }
    private var k: CGFloat { unit / 1000 }   // 速度/尺寸随屏幕缩放

    // MARK: 生命周期

    override func didMove(to view: SKView) {
        backgroundColor = isPreview ? .clear : .black
        anchorPoint = .zero
        for (i, n) in [ambient, pools, fx, items, overlay].enumerated() {
            n.zPosition = CGFloat(i * 10)
            addChild(n)
        }
        if isPreview { return }
        buildAmbient()
        buildCursor()
        buildExitButton()
        showHint()
    }

    override func didChangeSize(_ oldSize: CGSize) {
        guard oldSize != size, ambient.parent != nil, !isPreview else { return }
        buildAmbient()
        layoutExitButton()
    }

    // MARK: 背景 & 提示

    private func buildAmbient() {
        ambient.removeAllChildren()
        guard settings.ambientStars, size.width > 0 else { return }
        for _ in 0..<170 {
            let s = SKSpriteNode(texture: Textures.spark)
            let d = CGFloat.random(in: 2...6) * max(1, k)
            s.size = CGSize(width: d, height: d)
            s.position = CGPoint(x: .random(in: 0...size.width), y: .random(in: 0...size.height))
            s.color = Bool.random() ? .white : Palette.random.lighter(0.5)
            s.colorBlendFactor = 1
            s.alpha = .random(in: 0.04...0.25)
            s.blendMode = .add
            let lo = CGFloat.random(in: 0.02...0.1), hi = CGFloat.random(in: 0.15...0.4)
            let t1 = Double.random(in: 1.5...4), t2 = Double.random(in: 1.5...4)
            s.run(.sequence([.wait(forDuration: .random(in: 0...3)),
                             .repeatForever(.sequence([.fadeAlpha(to: hi, duration: t1), .fadeAlpha(to: lo, duration: t2)]))]))
            s.run(.repeatForever(.moveBy(x: .random(in: -4...4), y: .random(in: 2...7), duration: 10)))
            ambient.addChild(s)
        }
    }

    private func showHint() {
        let node = SKNode()
        node.position = CGPoint(x: size.width / 2, y: size.height / 2)
        let piano = emojiSprite("piano", size: unit * 0.22)
        piano.position = CGPoint(x: 0, y: unit * 0.12)
        piano.run(.repeatForever(.sequence([.rotate(toAngle: 0.12, duration: 0.8), .rotate(toAngle: -0.12, duration: 0.8)])))
        node.addChild(piano)
        node.addChild(label("随便按键盘吧！", size: unit * 0.075, weight: .heavy, y: -unit * 0.06))
        node.addChild(label("每个按键都有不同的特效和声音", size: unit * 0.03, weight: .medium, y: -unit * 0.13, alpha: 0.6))
        node.addChild(label("家长退出：按住 ⌃ ⌥ ⌘ 再按住 E", size: unit * 0.022, weight: .medium, y: -size.height / 2 + unit * 0.05, alpha: 0.35))
        overlay.addChild(node)
        hint = node
    }

    private func dismissHint() {
        guard let h = hint else { return }
        hint = nil
        h.run(.sequence([.group([.fadeOut(withDuration: 0.4), .scale(to: 0.9, duration: 0.4)]), .removeFromParent()]))
    }

    private func label(_ text: String, size: CGFloat, weight: NSFont.Weight, y: CGFloat, alpha: CGFloat = 1) -> SKLabelNode {
        let base = NSFont.systemFont(ofSize: size, weight: weight)
        let font = NSFont(descriptor: base.fontDescriptor.withDesign(.rounded) ?? base.fontDescriptor, size: size) ?? base
        let l = SKLabelNode()
        l.attributedText = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: NSColor.white])
        l.verticalAlignmentMode = .center
        l.position = CGPoint(x: 0, y: y)
        l.alpha = alpha
        return l
    }

    // MARK: 按键入口

    func handle(_ press: KeyPress) {
        dismissHint()
        switch press.kind {
        case .letter(let ch):
            letter(ch, color: Palette.colors[Int(ch.asciiValue ?? 65) % Palette.colors.count])
        case .digit(let d):
            digit(d, color: Palette.colors[(d + 3) % Palette.colors.count])
        case .space:
            bigShow()
        case .enter:
            emojiRain()
        case .backspace:
            vortex(color: Palette.color(for: press.code))
        case .arrow(let dir):
            comet(dir, color: Palette.color(for: press.code))
        case .other(let code):
            funPop(code, color: Palette.color(for: code))
        }
        trim()
    }

    // MARK: 各类按键

    private func letter(_ ch: Character, color: NSColor) {
        guard let info = KeyMap.letters[ch] else { return }
        let p = pickSpot()
        let s = unit * 0.24
        let group = SKNode()
        group.position = p
        var emojiX: CGFloat = 0
        if settings.showLetters {
            let g = glyphSprite(String(ch), color: color, height: s * 1.25)
            g.position = CGPoint(x: -s * 0.6, y: 0)
            group.addChild(g)
            emojiX = s * 0.64
        }
        group.addChild(halo(color, size: s * 3.2, at: .zero))
        let e = emojiSprite(info.emoji, size: s * 1.05)
        e.position = CGPoint(x: emojiX, y: 0)
        group.addChild(e)
        wiggle(e, delay: 0.12)
        addSparkleAura(to: group, width: s * 2.2, height: s * 1.2, color: color)
        present(group)
        lightPool(at: p, color: color)
        burst(at: p, color: color, power: 1)
    }

    private func digit(_ d: Int, color: NSColor) {
        let s = unit * 0.2
        let n = max(1, d)
        let perRow = min(n, 5)
        let rows = (n + perRow - 1) / perRow
        let gap = s * 0.62
        var p = pickSpot(margin: 0.3)
        p.y = min(max(p.y, size.height * 0.2 + CGFloat(rows) * gap), size.height * 0.68)
        let group = SKNode()
        group.position = p
        group.addChild(halo(color, size: s * 3, at: CGPoint(x: 0, y: s * 0.4)))
        let g = glyphSprite("\(d)", color: color, height: s * 1.35)
        g.position = CGPoint(x: 0, y: s * 0.45)
        group.addChild(g)
        present(group, hold: 1.4 + 0.12 * Double(n))
        burst(at: CGPoint(x: p.x, y: p.y + s * 0.45), color: color, power: 0.8)
        lightPool(at: p, color: color)

        let slug = KeyMap.digitEmoji[d]
        for i in 0..<n {
            let r = i / perRow, c = i % perRow
            let inRow = min(perRow, n - r * perRow)
            let x = (CGFloat(c) - CGFloat(inRow - 1) / 2) * gap
            let y = -s * 0.35 - CGFloat(r) * gap
            let e = emojiSprite(slug, size: s * 0.55)
            e.position = CGPoint(x: x, y: y)
            e.setScale(0)
            group.addChild(e)
            let delay = 0.12 * Double(i)
            e.run(.sequence([.wait(forDuration: delay), springScale(to: 1, duration: 0.45)]))
            run(.sequence([.wait(forDuration: delay), .run { [weak self] in
                guard let self else { return }
                self.sparkBurst(at: CGPoint(x: p.x + x, y: p.y + y), color: color, count: 26, speed: 260, life: 0.6)
            }]))
        }
    }

    private func funPop(_ code: Int, color: NSColor) {
        let p = pickSpot()
        let s = unit * 0.22
        let slug = KeyMap.funEmoji[KeyMap.stableHash(code) % KeyMap.funEmoji.count]
        let group = SKNode()
        group.position = p
        group.addChild(halo(color, size: s * 2.6, at: .zero))
        let e = emojiSprite(slug, size: s)
        group.addChild(e)
        wiggle(e, delay: 0.1)
        present(group, hold: 0.8)
        lightPool(at: p, color: color)
        burst(at: p, color: color, power: 0.75)
    }

    /// 空格：全屏大秀
    private func bigShow() {
        switch theme {
        case .fireworks:
            for i in 0..<5 {
                let x = size.width * (0.14 + 0.18 * CGFloat(i)) + .random(in: -40...40) * k
                let top = CGPoint(x: x + .random(in: -60...60) * k, y: size.height * .random(in: 0.55...0.85))
                launchShell(from: CGPoint(x: x, y: -20), to: top, delay: Double(i) * 0.13, color: Palette.random)
            }
        case .bubbles:
            for _ in 0..<34 {
                let x = CGFloat.random(in: 0...size.width)
                spawnBubble(at: CGPoint(x: x, y: -60 * k), vel: CGVector(dx: .random(in: -30...30) * k, dy: .random(in: 120...320) * k),
                            size: .random(in: 50...170) * k, life: .random(in: 3...5.5))
            }
        case .confetti:
            confettiCannon(from: CGPoint(x: 0, y: 0), angle: .pi * 0.3, count: 140)
            confettiCannon(from: CGPoint(x: size.width, y: 0), angle: .pi * 0.7, count: 140)
        case .starlight:
            for i in 0..<7 {
                run(.sequence([.wait(forDuration: Double(i) * 0.12), .run { [weak self] in self?.shootingStar(big: true) }]))
            }
        }
        lightPool(at: CGPoint(x: size.width / 2, y: size.height * 0.4), color: Palette.random, scale: 2.4)
    }

    /// 回车：emoji 雨
    private func emojiRain() {
        let s = unit * 0.13
        for i in 0..<16 {
            let slug = KeyMap.funEmoji.randomElement()!
            let e = emojiSprite(slug, size: s * .random(in: 0.7...1.3))
            e.position = CGPoint(x: .random(in: s...(size.width - s)), y: size.height + s)
            e.zRotation = .random(in: -0.5...0.5)
            items.addChild(e)
            let dur = Double.random(in: 1.6...2.8)
            let fall = SKAction.moveTo(y: -s * 1.5, duration: dur)
            fall.timingMode = .easeIn
            e.run(.sequence([.wait(forDuration: Double(i) * 0.05 + .random(in: 0...0.3)),
                             .group([fall, .rotate(byAngle: .random(in: -3...3), duration: dur)]), .removeFromParent()]))
        }
        burst(at: CGPoint(x: size.width / 2, y: size.height * 0.85), color: Palette.random, power: 0.7)
    }

    /// 退格：旋涡把东西吸走
    private func vortex(color: NSColor) {
        let p = pickSpot()
        let s = unit * 0.22
        let e = emojiSprite("cyclone", size: s)
        e.position = p
        e.setScale(0)
        items.addChild(e)
        e.run(.group([.rotate(byAngle: -.pi * 6, duration: 1.6),
                      .sequence([springScale(to: 1, duration: 0.4), .wait(forDuration: 0.8),
                                 .group([.scale(to: 0, duration: 0.4), .fadeOut(withDuration: 0.4)]), .removeFromParent()])]))
        for i in 0..<90 {
            let n = SKSpriteNode(texture: i % 4 == 0 ? Textures.sparkle : Textures.spark)
            let d = CGFloat.random(in: 10...24) * k
            n.size = CGSize(width: d, height: d)
            n.color = i % 3 == 0 ? .white : Palette.colors[i % Palette.colors.count]
            n.colorBlendFactor = 1
            n.blendMode = .add
            fx.addChild(n)
            let piece = Piece(n, .spiral, vel: .zero, life: .random(in: 0.9...1.4))
            piece.center = p
            piece.angle = .random(in: 0...(2 * .pi))
            piece.radius0 = .random(in: 140...360) * k
            piece.spin = .random(in: 4...7)
            pieces.append(piece)
        }
        lightPool(at: p, color: color)
    }

    /// 方向键：小东西带着拖尾飞过屏幕
    private func comet(_ dir: ArrowDirection, color: NSColor) {
        let s = unit * 0.16
        let W = size.width, H = size.height
        let start: CGPoint, end: CGPoint, slug: String, dur: Double
        switch dir {
        case .up:
            let x = W * .random(in: 0.2...0.8)
            start = CGPoint(x: x, y: -s); end = CGPoint(x: x + .random(in: -0.15...0.15) * W, y: H + s)
            slug = "rocket"; dur = 1.3
        case .down:
            let x = W * .random(in: 0.2...0.8)
            start = CGPoint(x: x, y: H + s); end = CGPoint(x: x + .random(in: -0.1...0.1) * W, y: -s)
            slug = "parachute"; dur = 2.6
        case .left:
            let y = H * .random(in: 0.2...0.8)
            start = CGPoint(x: W + s, y: y); end = CGPoint(x: -s, y: y + .random(in: -0.1...0.1) * H)
            slug = "fish"; dur = 1.6
        case .right:
            let y = H * .random(in: 0.2...0.8)
            start = CGPoint(x: -s, y: y); end = CGPoint(x: W + s, y: y + .random(in: -0.1...0.1) * H)
            slug = "bird"; dur = 1.6
        }
        let node = SKNode()
        node.position = start
        let e = emojiSprite(slug, size: s)
        let heading = atan2(end.y - start.y, end.x - start.x)
        switch dir {
        case .up: e.zRotation = heading - .pi / 4    // 火箭图本身朝右上
        case .right: e.xScale = -1                    // 小鸟图本身朝左
        default: break
        }
        node.addChild(e)
        items.addChild(node)

        let trail = makeEmitter(texture: Textures.spark, count: 0, life: 0.9, lifeRange: 0.3, speed: 50 * k, speedRange: 40 * k,
                                scale: 0.45 * max(1, k), scaleRange: 0.2, scaleSpeed: -0.4, alphaSpeed: -1.1, gravity: 0,
                                colors: [.white, color, color.darker(0.3)])
        trail.particleBirthRate = 140
        trail.particlePositionRange = CGVector(dx: s * 0.3, dy: s * 0.3)
        trail.targetNode = fx
        node.addChild(trail)
        let glitter = makeEmitter(texture: Textures.sparkle, count: 0, life: 1.1, lifeRange: 0.3, speed: 30 * k, speedRange: 30 * k,
                                  scale: 0.18 * max(1, k), scaleRange: 0.08, scaleSpeed: -0.1, alphaSpeed: 0, gravity: -20 * k,
                                  colors: [.white, color.lighter(0.4)])
        glitter.particleBirthRate = 22
        glitter.particleAlphaSequence = twinkle
        glitter.targetNode = fx
        node.addChild(glitter)

        let wobble = dir == .down ? 0.06 * unit : 0.035 * unit
        let perp = CGVector(dx: -sin(heading), dy: cos(heading))
        let move = SKAction.customAction(withDuration: dur) { n, t in
            let f = t / CGFloat(dur)
            let w = sin(f * .pi * (dir == .down ? 4 : 3)) * wobble
            n.position = CGPoint(x: start.x + (end.x - start.x) * f + perp.dx * w,
                                 y: start.y + (end.y - start.y) * f + perp.dy * w)
            if dir == .down { e.zRotation = sin(f * .pi * 4) * 0.15 }
        }
        node.run(.sequence([move, .run { trail.particleBirthRate = 0; glitter.particleBirthRate = 0; e.isHidden = true },
                            .run { [weak self] in self?.retire(node) }]))
    }

    // MARK: 主题爆炸

    private func burst(at p: CGPoint, color: NSColor, power: CGFloat) {
        switch theme {
        case .fireworks:
            flash(at: p, color: color, size: 420 * k * power)
            shockwave(at: p, color: color, size: 620 * k * power)
            sparkBurst(at: p, color: color, count: Int(110 * power), speed: 620 * power, life: 1.3)
            glitter(at: p, color: color, count: Int(22 * power), speed: 200 * power)
            if power >= 0.8 {
                for i in 0..<4 {
                    let a = CGFloat.random(in: 0...(2 * .pi)), r = CGFloat.random(in: 120...240) * k * power
                    let q = CGPoint(x: p.x + cos(a) * r, y: p.y + sin(a) * r - 40 * k)
                    run(.sequence([.wait(forDuration: 0.45 + Double(i) * 0.08), .run { [weak self] in
                        self?.sparkBurst(at: q, color: .white, count: 18, speed: 160, life: 0.4)
                    }]))
                }
            }
        case .bubbles:
            shockwave(at: p, color: color.lighter(0.5), size: 500 * k * power)
            for _ in 0..<Int(12 * power) {
                let a = CGFloat.random(in: 0...(2 * .pi)), v = CGFloat.random(in: 60...260) * k
                spawnBubble(at: p, vel: CGVector(dx: cos(a) * v, dy: sin(a) * v + 60 * k),
                            size: .random(in: 36...120) * k, life: .random(in: 2...3.6))
            }
        case .confetti:
            flash(at: p, color: color, size: 300 * k * power)
            spawnConfetti(at: p, count: Int(70 * power), angle: .pi / 2, spread: .pi * 1.6, speed: 750 * power)
        case .starlight:
            flash(at: p, color: color, size: 380 * k * power)
            starBurst(at: p, color: color, count: Int(26 * power))
            glitter(at: p, color: .white, count: Int(40 * power), speed: 140 * power)
            if power >= 0.8 { shootingStar(big: false) }
        }
    }

    private func flash(at p: CGPoint, color: NSColor, size d: CGFloat) {
        let f = SKSpriteNode(texture: Textures.glow)
        f.position = p
        f.size = CGSize(width: d, height: d)
        f.color = color.lighter(0.15)
        f.colorBlendFactor = 1
        f.blendMode = .add
        f.alpha = 0.75
        f.setScale(0.3)
        fx.addChild(f)
        f.run(.sequence([.scale(to: 1, duration: 0.12),
                         .group([.scale(to: 1.4, duration: 0.5), .fadeOut(withDuration: 0.5)]), .removeFromParent()]))
    }

    private func shockwave(at p: CGPoint, color: NSColor, size d: CGFloat) {
        let r = SKSpriteNode(texture: Textures.ring)
        r.position = p
        r.size = CGSize(width: d, height: d)
        r.color = color.lighter(0.4)
        r.colorBlendFactor = 1
        r.blendMode = .add
        r.setScale(0.1)
        fx.addChild(r)
        let grow = SKAction.scale(to: 1, duration: 0.55)
        grow.timingMode = .easeOut
        r.run(.sequence([.group([grow, .fadeOut(withDuration: 0.55)]), .removeFromParent()]))
    }

    private func lightPool(at p: CGPoint, color: NSColor, scale: CGFloat = 1) {
        let g = SKSpriteNode(texture: Textures.glow)
        g.position = p
        g.size = CGSize(width: unit * 1.3 * scale, height: unit * 1.3 * scale)
        g.color = color
        g.colorBlendFactor = 1
        g.blendMode = .add
        g.alpha = 0
        pools.addChild(g)
        g.run(.sequence([.fadeAlpha(to: 0.16, duration: 0.15), .fadeOut(withDuration: 1.8), .removeFromParent()]))
    }

    private func halo(_ color: NSColor, size d: CGFloat, at p: CGPoint) -> SKSpriteNode {
        let g = SKSpriteNode(texture: Textures.glow)
        g.size = CGSize(width: d, height: d)
        g.position = p
        g.color = color
        g.colorBlendFactor = 1
        g.blendMode = .add
        g.alpha = 0.32
        g.zPosition = -1
        g.run(.repeatForever(.sequence([.fadeAlpha(to: 0.4, duration: 0.6), .fadeAlpha(to: 0.25, duration: 0.6)])))
        return g
    }

    private let twinkle = SKKeyframeSequence(keyframeValues: [0, 1, 0.25, 1, 0.3, 0.9, 0] as [NSNumber],
                                             times: [0, 0.08, 0.25, 0.42, 0.6, 0.8, 1])

    private func makeEmitter(texture: SKTexture, count: Int, life: CGFloat, lifeRange: CGFloat, speed: CGFloat, speedRange: CGFloat,
                             scale: CGFloat, scaleRange: CGFloat, scaleSpeed: CGFloat, alphaSpeed: CGFloat, gravity: CGFloat,
                             colors: [NSColor]) -> SKEmitterNode {
        let e = SKEmitterNode()
        e.particleTexture = texture
        e.particleBirthRate = count > 0 ? 100_000 : 0
        e.numParticlesToEmit = count
        e.particleLifetime = life
        e.particleLifetimeRange = lifeRange
        e.particleSpeed = speed
        e.particleSpeedRange = speedRange
        e.emissionAngleRange = 2 * .pi
        e.particleScale = scale
        e.particleScaleRange = scaleRange
        e.particleScaleSpeed = scaleSpeed
        e.particleAlphaSpeed = alphaSpeed
        e.yAcceleration = gravity
        e.particleBlendMode = .add
        e.particleColorBlendFactor = 1
        e.particleRotationRange = 2 * .pi
        if colors.count > 1 {
            let times = colors.indices.map { NSNumber(value: Double($0) / Double(colors.count - 1) * (colors.count == 2 ? 1 : 0.6)) }
            e.particleColorSequence = SKKeyframeSequence(keyframeValues: colors, times: times)
        } else {
            e.particleColor = colors.first ?? .white
        }
        return e
    }

    private func fire(_ e: SKEmitterNode, at p: CGPoint, maxLife: CGFloat) {
        e.position = p
        e.targetNode = fx
        fx.addChild(e)
        e.run(.sequence([.wait(forDuration: Double(maxLife) + 0.3), .removeFromParent()]))
    }

    /// 火花：拉长成流线的小光条，随速度伸缩、受重力和空气阻力，最后闪烁熄灭
    private func sparkBurst(at p: CGPoint, color: NSColor, count: Int, speed: CGFloat, life: CGFloat) {
        let tints = [color.lighter(0.15), color, color.lighter(0.45), color, NSColor(hex: 0xFFF6D8)]
        for i in 0..<count {
            let n = SKSpriteNode(texture: Textures.sparkLine)
            n.anchorPoint = CGPoint(x: 0.85, y: 0.5)
            n.position = p
            n.blendMode = .add
            n.colorBlendFactor = 1
            n.color = .white
            fx.addChild(n)
            let a = CGFloat.random(in: 0...(2 * .pi))
            // 大部分火花速度接近，形成清晰的球形外壳；少数慢一些填充内部
            let v = speed * k * (i % 4 == 0 ? .random(in: 0.25...0.7) : .random(in: 0.85...1.05))
            let piece = Piece(n, .spark, vel: CGVector(dx: cos(a) * v, dy: sin(a) * v), life: life * .random(in: 0.75...1.25))
            piece.thickness = .random(in: 3.5...6.5) * max(1, k)
            piece.tint = tints[i % tints.count]
            pieces.append(piece)
        }
    }

    private func glitter(at p: CGPoint, color: NSColor, count: Int, speed: CGFloat) {
        let e = makeEmitter(texture: Textures.sparkle, count: count, life: 1.6, lifeRange: 0.5, speed: speed * k, speedRange: speed * 0.5 * k,
                            scale: 0.22 * max(1, k), scaleRange: 0.1, scaleSpeed: -0.05, alphaSpeed: 0, gravity: -60 * k,
                            colors: [.white, color.lighter(0.5)])
        e.particleAlphaSequence = twinkle
        e.particleRotationSpeed = 1.5
        fire(e, at: p, maxLife: 2.1)
    }

    private func starBurst(at p: CGPoint, color: NSColor, count: Int) {
        let e = makeEmitter(texture: Textures.star, count: count, life: 1.8, lifeRange: 0.4, speed: 240 * k, speedRange: 120 * k,
                            scale: 0.28 * max(1, k), scaleRange: 0.15, scaleSpeed: -0.1, alphaSpeed: 0, gravity: -80 * k,
                            colors: [NSColor(hex: 0xFFF6CC), NSColor(hex: 0xFFD93D), color.lighter(0.2)])
        e.particleBlendMode = .alpha
        e.particleAlphaSequence = SKKeyframeSequence(keyframeValues: [0, 1, 0.75, 1, 0.8, 1, 0] as [NSNumber],
                                                     times: [0, 0.06, 0.3, 0.5, 0.7, 0.85, 1])
        e.particleRotationSpeed = 2.5
        fire(e, at: p, maxLife: 2.2)
    }

    private func addSparkleAura(to node: SKNode, width: CGFloat, height: CGFloat, color: NSColor) {
        let e = makeEmitter(texture: Textures.sparkle, count: 0, life: 0.9, lifeRange: 0.3, speed: 12 * k, speedRange: 10 * k,
                            scale: 0.16 * max(1, k), scaleRange: 0.08, scaleSpeed: 0, alphaSpeed: 0, gravity: 30 * k,
                            colors: [.white, color.lighter(0.5)])
        e.particleBirthRate = 9
        e.particlePositionRange = CGVector(dx: width, dy: height)
        e.particleAlphaSequence = twinkle
        e.targetNode = fx
        e.zPosition = 2
        node.addChild(e)
        e.run(.sequence([.wait(forDuration: 1.2), .run { e.particleBirthRate = 0 }]))
    }

    private func launchShell(from: CGPoint, to: CGPoint, delay: Double, color: NSColor) {
        let shell = SKNode()
        shell.position = from
        let trail = makeEmitter(texture: Textures.spark, count: 0, life: 0.6, lifeRange: 0.2, speed: 30 * k, speedRange: 20 * k,
                                scale: 0.3 * max(1, k), scaleRange: 0.1, scaleSpeed: -0.4, alphaSpeed: -1.5, gravity: -150 * k,
                                colors: [.white, NSColor(hex: 0xFFC46B)])
        trail.particleBirthRate = 220
        trail.targetNode = fx
        shell.addChild(trail)
        let rise = SKAction.move(to: to, duration: 0.65)
        rise.timingMode = .easeOut
        fx.addChild(shell)
        shell.isHidden = true
        trail.particleBirthRate = 0
        shell.run(.sequence([
            .wait(forDuration: delay),
            .run { shell.isHidden = false; trail.particleBirthRate = 220 },
            rise,
            .run { [weak self] in
                trail.particleBirthRate = 0
                guard let self else { return }
                self.flash(at: to, color: color, size: 520 * self.k)
                self.sparkBurst(at: to, color: color, count: 150, speed: 680, life: 1.6)
                self.glitter(at: to, color: color, count: 30, speed: 260)
                self.lightPool(at: to, color: color)
            },
            .wait(forDuration: 1), .removeFromParent(),
        ]))
    }

    private func shootingStar(big: Bool) {
        let fromLeft = Bool.random()
        let start = CGPoint(x: fromLeft ? .random(in: -0.1...0.4) * size.width : .random(in: 0.6...1.1) * size.width,
                            y: size.height * .random(in: 0.75...1.05))
        let angle: CGFloat = fromLeft ? -.random(in: 0.35...0.7) : .pi + .random(in: 0.35...0.7)
        let dist = unit * (big ? 0.9 : 0.55)
        let end = CGPoint(x: start.x + cos(angle) * dist, y: start.y + sin(angle) * dist)
        let head = SKSpriteNode(texture: Textures.streak)
        head.size = CGSize(width: unit * (big ? 0.32 : 0.2), height: 14 * max(1, k))
        head.anchorPoint = CGPoint(x: 1, y: 0.5)
        head.zRotation = angle
        head.position = start
        head.color = NSColor(hex: 0xFFF3B0)
        head.colorBlendFactor = 1
        head.blendMode = .add
        let core = SKSpriteNode(texture: Textures.sparkle)
        core.size = CGSize(width: 46 * max(1, k), height: 46 * max(1, k))
        core.color = .white
        head.addChild(core)
        fx.addChild(head)
        let dur = big ? 0.9 : 0.6
        let move = SKAction.move(to: end, duration: dur)
        move.timingMode = .easeIn
        head.run(.sequence([.group([move, .sequence([.wait(forDuration: dur * 0.6), .fadeOut(withDuration: dur * 0.4)])]),
                            .run { [weak self] in self?.retire(head) }]))
        let dust = makeEmitter(texture: Textures.spark, count: 0, life: 1.0, lifeRange: 0.4, speed: 20 * k, speedRange: 20 * k,
                               scale: 0.2 * max(1, k), scaleRange: 0.1, scaleSpeed: -0.15, alphaSpeed: -0.9, gravity: -40 * k,
                               colors: [.white, Palette.random.lighter(0.4)])
        dust.particleBirthRate = 160
        dust.targetNode = fx
        head.addChild(dust)
    }

    private func spawnBubble(at p: CGPoint, vel: CGVector, size d: CGFloat, life: CGFloat) {
        let b = SKSpriteNode(texture: Textures.bubble)
        b.size = CGSize(width: d, height: d)
        b.position = p
        b.alpha = 0
        b.run(.fadeAlpha(to: 0.95, duration: 0.2))
        fx.addChild(b)
        let piece = Piece(b, .bubble, vel: vel, life: life)
        pieces.append(piece)
    }

    private func spawnConfetti(at p: CGPoint, count: Int, angle: CGFloat, spread: CGFloat, speed: CGFloat) {
        for _ in 0..<count {
            let n = SKSpriteNode(texture: Textures.confetti)
            let w = CGFloat.random(in: 10...18) * max(1, k)
            n.size = CGSize(width: w, height: w * 1.6)
            n.color = Palette.random
            n.colorBlendFactor = 1
            n.position = p
            n.zRotation = .random(in: 0...(2 * .pi))
            fx.addChild(n)
            let a = angle + .random(in: -spread / 2...spread / 2)
            let v = CGFloat.random(in: 0.35...1) * speed * k
            pieces.append(Piece(n, .confetti, vel: CGVector(dx: cos(a) * v, dy: sin(a) * v), life: .random(in: 2.4...4)))
        }
    }

    private func confettiCannon(from p: CGPoint, angle: CGFloat, count: Int) {
        spawnConfetti(at: p, count: count, angle: angle, spread: 0.6, speed: 1900)
    }

    // MARK: 精灵 & 动画

    private func emojiSprite(_ slug: String, size d: CGFloat) -> SKSpriteNode {
        let s = SKSpriteNode(texture: Textures.emoji(slug))
        s.size = CGSize(width: d, height: d)
        return s
    }

    private func glyphSprite(_ text: String, color: NSColor, height: CGFloat) -> SKSpriteNode {
        let t = Textures.glyph(text, color: color)
        let ts = t.size()
        let s = SKSpriteNode(texture: t)
        s.size = CGSize(width: ts.width * height / ts.height, height: height)
        return s
    }

    /// 带回弹的缩放
    private func springScale(to target: CGFloat, duration: Double) -> SKAction {
        let a = SKAction.scale(to: target, duration: duration)
        a.timingFunction = { t in t >= 1 ? 1 : Float(1 - exp(-6 * Double(t)) * cos(12 * Double(t))) }
        return a
    }

    private func present(_ group: SKNode, hold: Double = 1.1) {
        group.setScale(0.01)
        group.zRotation = .random(in: -0.25...0.25)
        items.addChild(group)
        let rot = SKAction.rotate(toAngle: 0, duration: 0.6)
        rot.timingFunction = { t in t >= 1 ? 1 : Float(1 - exp(-5 * Double(t)) * cos(10 * Double(t))) }
        let leave = SKAction.group([.moveBy(x: 0, y: unit * 0.07, duration: 0.7), .fadeOut(withDuration: 0.7), .scale(to: 0.85, duration: 0.7)])
        leave.timingMode = .easeIn
        group.run(.sequence([.group([springScale(to: 1, duration: 0.6), rot]), .wait(forDuration: hold), leave,
                             .run { [weak self] in self?.retire(group) }]))
    }

    private func wiggle(_ node: SKNode, delay: Double) {
        node.run(.sequence([
            .wait(forDuration: delay),
            .rotate(toAngle: 0.18, duration: 0.09), .rotate(toAngle: -0.15, duration: 0.12),
            .rotate(toAngle: 0.08, duration: 0.12), .rotate(toAngle: 0, duration: 0.12),
            .repeatForever(.sequence([.moveBy(x: 0, y: 6 * k, duration: 0.45), .moveBy(x: 0, y: -6 * k, duration: 0.45)])),
        ]))
    }

    // MARK: 安全移除
    //
    // SpriteKit 的坑：带 targetNode 的发射器如果在还有粒子存活时被移除，那些粒子会冻结在画面上永远不消失。
    // 所以移除任何节点前，先让它里面的发射器停止发射，等最后一颗粒子熄灭后再真正移除。

    /// 停止节点内所有发射器，等粒子自然熄灭后移除
    private func retire(_ node: SKNode) {
        guard node.parent != nil, node.action(forKey: "retire") == nil else { return }
        var wait: CGFloat = 0
        var emitters: [SKEmitterNode] = []
        if let e = node as? SKEmitterNode { emitters.append(e) }
        node.enumerateChildNodes(withName: ".//*") { n, _ in
            if let e = n as? SKEmitterNode { emitters.append(e) }
        }
        for e in emitters {
            e.particleBirthRate = 0
            e.removeAllActions()   // 防止之前排好的动作再把发射率改回去
            wait = max(wait, e.particleLifetime + e.particleLifetimeRange / 2)
        }
        node.alpha = 0
        node.run(.sequence([.wait(forDuration: Double(wait) + 0.1), .removeFromParent()]), withKey: "retire")
    }

    /// 立刻清掉一个发射器和它已经发出的粒子
    private func kill(_ e: SKEmitterNode) {
        e.particleBirthRate = 0
        e.resetSimulation()
        e.removeFromParent()
    }

    // MARK: 选位置 & 清理

    private func pickSpot(margin: CGFloat = 0.2) -> CGPoint {
        var best = CGPoint(x: size.width / 2, y: size.height / 2), bestD: CGFloat = -1
        for _ in 0..<12 {
            let p = CGPoint(x: .random(in: size.width * margin...size.width * (1 - margin)),
                            y: .random(in: size.height * 0.24...size.height * 0.76))
            let d = recentSpots.map { hypot($0.x - p.x, $0.y - p.y) }.min() ?? .greatestFiniteMagnitude
            if d > bestD { bestD = d; best = p }
        }
        recentSpots.append(best)
        if recentSpots.count > 4 { recentSpots.removeFirst() }
        return best
    }

    private func trim() {
        // 孩子狂按时，最早的内容提前退场，避免画面糊成一片
        let groups = items.children.filter { $0.action(forKey: "retire") == nil }
        if groups.count > 14 {
            for n in groups.prefix(groups.count - 14) where n.action(forKey: "out") == nil {
                n.run(.sequence([.fadeOut(withDuration: 0.2), .run { [weak self] in self?.retire(n) }]), withKey: "out")
            }
        }
        let emitters = fx.children.compactMap { $0 as? SKEmitterNode }
        if emitters.count > 70 { emitters.prefix(emitters.count - 70).forEach { kill($0) } }
        if pieces.count > 1600 {
            for p in pieces.prefix(pieces.count - 1600) { p.node.removeFromParent() }
            pieces.removeFirst(pieces.count - 1600)
        }
    }

    // MARK: 每帧更新

    override func update(_ currentTime: TimeInterval) {
        let dt = CGFloat(lastUpdate == 0 ? 1.0 / 60 : min(1.0 / 20, currentTime - lastUpdate))
        lastUpdate = currentTime
        var i = 0
        while i < pieces.count {
            let p = pieces[i]
            p.life += dt
            if p.life >= p.maxLife {
                finish(p)
                pieces.swapAt(i, pieces.count - 1)
                pieces.removeLast()
                continue
            }
            step(p, dt)
            i += 1
        }
    }

    private func step(_ p: Piece, _ dt: CGFloat) {
        let f = p.life / p.maxLife
        let n = p.node
        switch p.kind {
        case .confetti:
            p.vel.dy -= 1100 * k * dt
            let drag = 1 - min(1, 3.2 * dt)
            p.vel.dx *= drag
            p.vel.dy *= drag
            n.position.x += (p.vel.dx + sin(p.life * 3 + p.phase) * 60 * k) * dt
            n.position.y += p.vel.dy * dt
            n.xScale = cos(p.phase + p.life * p.flipSpeed)
            n.zRotation += p.spin * dt
            n.alpha = f > 0.8 ? (1 - f) / 0.2 : 1
        case .bubble:
            p.vel.dx *= 1 - min(1, 1.5 * dt)
            p.vel.dy += (90 * k - p.vel.dy) * min(1, 1.2 * dt)   // 慢慢趋向上浮速度
            n.position.x += (p.vel.dx + sin(p.life * 2 + p.phase) * 25 * k) * dt
            n.position.y += p.vel.dy * dt
            let w = 1 + 0.05 * sin(p.life * 7 + p.phase)
            n.xScale = w
            n.yScale = 2 - w
        case .spark:
            p.vel.dy -= 260 * k * dt
            let drag = 1 - min(1, 2.4 * dt)
            p.vel.dx *= drag
            p.vel.dy *= drag
            n.position.x += p.vel.dx * dt
            n.position.y += p.vel.dy * dt
            let speed = hypot(p.vel.dx, p.vel.dy)
            n.zRotation = atan2(p.vel.dy, p.vel.dx)
            n.size = CGSize(width: max(p.thickness * 1.6, speed * 0.13), height: p.thickness * (1 - f * 0.5))
            if p.life > 0.08, n.color == .white { n.color = p.tint }   // 先白后彩
            let fade = 1 - pow(f, 2.2)
            n.alpha = f > 0.6 ? fade * CGFloat.random(in: 0.35...1) : fade   // 末段闪烁
        case .spiral:
            p.angle += p.spin * dt * (1 + 2.5 * f)
            let r = p.radius0 * (1 - pow(f, 1.4))
            n.position = CGPoint(x: p.center.x + cos(p.angle) * r, y: p.center.y + sin(p.angle) * r)
            n.alpha = f < 0.15 ? f / 0.15 : 1 - pow(f, 3)
            n.setScale(1 - f * 0.6)
        }
    }

    private func finish(_ p: Piece) {
        if p.kind == .bubble {
            let pos = p.node.position
            let d = p.node.size.width
            p.node.run(.sequence([.group([.scale(to: 1.35, duration: 0.1), .fadeOut(withDuration: 0.1)]), .removeFromParent()]))
            let e = makeEmitter(texture: Textures.spark, count: 14, life: 0.4, lifeRange: 0.15, speed: d * 1.6, speedRange: d * 0.5,
                                scale: 0.18 * max(1, k), scaleRange: 0.05, scaleSpeed: -0.3, alphaSpeed: -2, gravity: -200 * k,
                                colors: [.white, NSColor(hex: 0xBDEBFF)])
            fire(e, at: pos, maxLife: 0.6)
        } else {
            p.node.removeFromParent()
        }
    }

    // MARK: 鼠标

    private func buildCursor() {
        let dot = SKSpriteNode(texture: Textures.sparkle)
        dot.size = CGSize(width: 44, height: 44)
        dot.run(.repeatForever(.rotate(byAngle: .pi, duration: 3)))
        let glow = SKSpriteNode(texture: Textures.glow)
        glow.size = CGSize(width: 70, height: 70)
        glow.color = NSColor(hex: 0xFFD93D)
        glow.colorBlendFactor = 1
        glow.blendMode = .add
        glow.alpha = 0.5
        cursor.addChild(glow)
        cursor.addChild(dot)
        cursor.zPosition = 100
        cursor.position = CGPoint(x: size.width / 2, y: size.height / 2)
        cursor.isHidden = true
        overlay.addChild(cursor)
        let trail = makeEmitter(texture: Textures.sparkle, count: 0, life: 0.7, lifeRange: 0.3, speed: 30, speedRange: 30,
                                scale: 0.14, scaleRange: 0.06, scaleSpeed: -0.1, alphaSpeed: 0, gravity: -60,
                                colors: [.white, NSColor(hex: 0xFFD93D), NSColor(hex: 0xFF5E8A)])
        trail.particleAlphaSequence = twinkle
        trail.targetNode = fx
        cursor.addChild(trail)
        cursorTrail = trail
    }

    private func moveCursor(_ p: CGPoint) {
        let dist = hypot(p.x - lastMouse.x, p.y - lastMouse.y)
        lastMouse = p
        cursor.position = p
        cursor.isHidden = false
        showExitButton()
        guard settings.mouseEffects else { return }
        cursorTrail?.particleBirthRate = min(120, dist * 3)
        cursorTrail?.removeAction(forKey: "stop")
        cursorTrail?.run(.sequence([.wait(forDuration: 0.06), .run { [weak self] in self?.cursorTrail?.particleBirthRate = 0 }]), withKey: "stop")
    }

    override func mouseMoved(with event: NSEvent) { moveCursor(event.location(in: self)) }
    override func mouseDragged(with event: NSEvent) { moveCursor(event.location(in: self)) }

    override func mouseDown(with event: NSEvent) {
        let p = event.location(in: self)
        moveCursor(p)
        if exitButton.alpha > 0.3, exitButton.calculateAccumulatedFrame().insetBy(dx: -12, dy: -12).contains(p) {
            exitButtonHeld = true
            exitButton.run(.scale(to: 0.94, duration: 0.08))
            onExitButton?(true)
            return
        }
        guard settings.mouseEffects else { return }
        dismissHint()
        burst(at: p, color: Palette.random, power: 0.5)
        onClick?(p.x / max(1, size.width))
    }

    override func mouseUp(with event: NSEvent) {
        guard exitButtonHeld else { return }
        exitButtonHeld = false
        exitButton.run(.scale(to: 1, duration: 0.08))
        onExitButton?(false)
    }

    // MARK: 左上角退出按钮（鼠标动了才出现，静止 2 秒后隐藏；要按住才退出，防止孩子误点）

    private func buildExitButton() {
        let w: CGFloat = 132, h: CGFloat = 48
        let bg = SKShapeNode(rectOf: CGSize(width: w, height: h), cornerRadius: h / 2)
        bg.fillColor = NSColor(white: 1, alpha: 0.12)
        bg.strokeColor = NSColor(white: 1, alpha: 0.18)
        bg.lineWidth = 1
        exitButton.addChild(bg)
        let l = label("✕  按住退出", size: 18, weight: .semibold, y: 0)
        exitButton.addChild(l)
        exitButton.zPosition = 150
        exitButton.alpha = 0
        overlay.addChild(exitButton)
        layoutExitButton()
    }

    private func layoutExitButton() {
        exitButton.position = CGPoint(x: 32 + 66, y: size.height - 32 - 24)
    }

    func showExitButton() {
        exitButton.removeAction(forKey: "hide")
        if exitButton.alpha < 1, exitButton.action(forKey: "show") == nil {
            exitButton.run(.fadeIn(withDuration: 0.2), withKey: "show")
        }
        exitButton.run(.sequence([.wait(forDuration: 2), .run { [weak self] in
            guard let self, !self.exitButtonHeld else { return }
            self.exitButton.run(.fadeOut(withDuration: 0.4))
        }]), withKey: "hide")
    }

    // MARK: 退出进度

    func setExitProgress(_ f: CGFloat?) {
        guard let f else {
            exitNode?.removeFromParent()
            exitNode = nil
            return
        }
        if exitNode == nil {
            let n = SKNode()
            n.position = CGPoint(x: size.width / 2, y: size.height / 2)
            n.zPosition = 200
            let bg = SKShapeNode(rectOf: CGSize(width: 420, height: 220), cornerRadius: 36)
            bg.fillColor = NSColor(white: 0.12, alpha: 0.92)
            bg.strokeColor = NSColor(white: 1, alpha: 0.1)
            n.addChild(bg)
            n.addChild(label("继续按住，马上退出", size: 30, weight: .bold, y: -62))
            let ring = SKShapeNode()
            ring.name = "ring"
            ring.lineWidth = 10
            ring.lineCap = .round
            ring.strokeColor = NSColor(hex: 0xFFD93D)
            ring.position = CGPoint(x: 0, y: 26)
            n.addChild(ring)
            overlay.addChild(n)
            exitNode = n
        }
        if let ring = exitNode?.childNode(withName: "ring") as? SKShapeNode {
            let path = CGMutablePath()
            path.addArc(center: .zero, radius: 46, startAngle: .pi / 2, endAngle: .pi / 2 - 2 * .pi * max(0.001, f), clockwise: true)
            ring.path = path
        }
    }
}
