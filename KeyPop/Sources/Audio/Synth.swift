import Foundation

/// 离线合成：每种声音渲染成一段 Float 采样，由 SoundEngine 缓存后播放。
enum Synth {
    static let sr: Double = 44_100
    private static let twoPi = 2 * Double.pi

    // MARK: 音阶

    private static let penta = [0, 2, 4, 7, 9]

    static func freq(base: Double, index: Int) -> Double {
        let i = max(0, index)
        let semis = (i / 5) * 12 + penta[i % 5]
        return base * pow(2, Double(semis) / 12)
    }

    static func baseFreq(_ pack: SoundPack) -> Double {
        switch pack {
        case .marimba: 196.0     // G3
        case .musicBox: 523.25   // C5
        case .harp: 220.0        // A3
        case .chiptune: 261.63   // C4
        case .cartoon: 293.66    // D4
        }
    }

    // MARK: 单个音

    static func note(_ pack: SoundPack, _ f: Double, variant: Int = 0) -> [Float] {
        switch pack {
        case .marimba: return marimba(f)
        case .musicBox: return musicBox(f)
        case .harp: return harp(f)
        case .chiptune: return chip(f)
        case .cartoon: return cartoon(f, variant: variant)
        }
    }

    static func marimba(_ f: Double) -> [Float] {
        render(1.3) { t in
            let a = min(1, t / 0.002)
            let body = sin(twoPi * f * t) * exp(-t * 5.5)
            let wood = 0.32 * sin(twoPi * f * 3.93 * t) * exp(-t * 26)
            let click = 0.12 * sin(twoPi * f * 9.2 * t) * exp(-t * 70)
            return a * (body + wood + click)
        }
    }

    static func musicBox(_ f: Double) -> [Float] {
        render(2.4) { t in
            let a = min(1, t / 0.003)
            let idx = 1.8 * exp(-t * 7)
            let fm = sin(twoPi * f * t + idx * sin(twoPi * f * 3.5 * t))
            let shimmer = 0.35 * sin(twoPi * f * 1.004 * t) * exp(-t * 2.5)
            let octave = 0.18 * sin(twoPi * f * 2 * t) * exp(-t * 5)
            return a * (fm * exp(-t * 2.4) + shimmer + octave)
        }
    }

    /// Karplus-Strong 拨弦
    static func harp(_ f: Double) -> [Float] {
        let n = Int(sr * 2.2)
        let period = max(2, Int((sr / f).rounded()))
        var buf = [Float](repeating: 0, count: n)
        var rng = SplitMix(seed: UInt64(f * 1000))
        var prev: Float = 0
        for i in 0..<min(period, n) {          // 预先低通的噪声激励 → 更柔和
            let r = Float(rng.nextDouble() * 2 - 1)
            prev = prev * 0.55 + r * 0.45
            buf[i] = prev
        }
        let decay: Float = f > 700 ? 0.9985 : 0.9965
        for i in period..<n {
            let a = buf[i - period]
            let b = i - period - 1 >= 0 ? buf[i - period - 1] : 0
            buf[i] = (a + b) * 0.5 * decay
        }
        // 叠一点正弦让音头更饱满
        for i in 0..<n {
            let t = Double(i) / sr
            buf[i] += Float(0.25 * sin(twoPi * f * t) * exp(-t * 3))
        }
        return buf
    }

    /// 8-bit：带限方波 + 开头快速琶音
    static func chip(_ f: Double) -> [Float] {
        var phase = 0.0
        let arp = [1.0, 1.26, 1.5, 2.0]
        return render(0.42) { t in
            let step = Int(t / 0.04)
            let mult = t < 0.16 ? arp[step % arp.count] : 1.0
            let vib = t > 0.16 ? 1 + 0.012 * sin(twoPi * 7 * t) : 1
            let ff = f * mult * vib
            phase += ff / sr
            phase -= floor(phase)
            let env = t < 0.3 ? 0.9 : 0.9 * max(0, 1 - (t - 0.3) / 0.12)
            return env * pulse(phase, duty: 0.25, dt: ff / sr) * 0.6
        }
    }

    static func cartoon(_ f: Double, variant: Int) -> [Float] {
        switch variant % 5 {
        case 0: // 弹簧 boing
            var ph = 0.0
            return render(0.55) { t in
                let ff = f * (1 + 0.45 * sin(twoPi * 11 * t) * exp(-t * 5)) * (1 - 0.25 * t)
                ph += ff / sr
                return sin(twoPi * ph) * exp(-t * 5) * min(1, t / 0.004)
            }
        case 1: // 啵
            var ph = 0.0
            return render(0.16) { t in
                let ff = f * (1 + 2.5 * min(1, t / 0.05))
                ph += ff / sr
                return sin(twoPi * ph) * exp(-t * 28) * min(1, t / 0.002)
            }
        case 2: // 滑哨上行
            var ph = 0.0
            return render(0.45) { t in
                let ff = f * (1 + 1.4 * t / 0.45) * (1 + 0.02 * sin(twoPi * 9 * t))
                ph += ff / sr
                let env = min(1, t / 0.03) * min(1, (0.45 - t) / 0.08)
                return (sin(twoPi * ph) + 0.15 * sin(2 * twoPi * ph)) * env * 0.8
            }
        case 3: // 吱吱
            var ph = 0.0
            return render(0.3) { t in
                let blip = t < 0.12 ? t : t - 0.15
                guard blip >= 0 else { return 0 }
                let ff = f * 2.2 * (1 + 0.6 * blip / 0.12)
                ph += ff / sr
                return sin(twoPi * ph) * exp(-blip * 22) * min(1, blip / 0.004)
            }
        default: // 水滴 bloop
            var ph = 0.0
            return render(0.25) { t in
                let ff = f * 2 * exp(-t * 9) + f * 0.5
                ph += ff / sr
                return sin(twoPi * ph) * exp(-t * 14) * min(1, t / 0.003)
            }
        }
    }

    // MARK: 特殊按键

    /// 空格：扫弦和弦 + 低音“咚”
    static func space(_ pack: SoundPack, base: Double) -> [Float] {
        var out = [Float](repeating: 0, count: Int(sr * 2.4))
        if pack == .chiptune {
            mix(&out, noiseBurst(0.6, cutoffStart: 6000, cutoffEnd: 200), at: 0, gain: 0.9)
            var ph = 0.0
            mix(&out, render(0.5) { t in
                ph += (600 * exp(-t * 6) + 60) / sr
                return pulse(ph - floor(ph), duty: 0.5, dt: 0.01) * exp(-t * 4) * 0.5
            }, at: 0, gain: 0.7)
            return out
        }
        if pack == .cartoon {
            mix(&out, noiseBurst(0.35, cutoffStart: 800, cutoffEnd: 5000), at: 0, gain: 0.35)
            mix(&out, cartoon(base * 1.5, variant: 1), at: 0.3, gain: 1)
            mix(&out, cartoon(base * 2, variant: 1), at: 0.38, gain: 0.8)
            return out
        }
        for (i, m) in [1.0, 1.25, 1.5, 2.0, 2.5].enumerated() {
            mix(&out, note(pack, base * m), at: Double(i) * 0.028, gain: 0.55)
        }
        mix(&out, render(0.6) { t in sin(twoPi * (55 + 70 * exp(-t * 18)) * t) * exp(-t * 6) }, at: 0, gain: 0.7)
        return out
    }

    /// 一串音（回车/方向键/退格/数字）
    static func run(_ pack: SoundPack, base: Double, start: Int, steps: [Int], gap: Double, variant: Int = 1) -> [Float] {
        var out = [Float](repeating: 0, count: Int(sr * (gap * Double(steps.count) + 2.4)))
        for (i, s) in steps.enumerated() {
            mix(&out, note(pack, freq(base: base, index: start + s), variant: variant), at: Double(i) * gap, gain: 0.7)
        }
        return out
    }

    // MARK: 基础工具

    static func render(_ dur: Double, _ fn: (Double) -> Double) -> [Float] {
        let n = Int(sr * dur)
        var out = [Float](repeating: 0, count: n)
        for i in 0..<n { out[i] = Float(fn(Double(i) / sr)) }
        // 结尾 10ms 淡出，避免爆音
        let fade = min(n, Int(sr * 0.01))
        for i in 0..<fade { out[n - 1 - i] *= Float(i) / Float(fade) }
        return out
    }

    static func noiseBurst(_ dur: Double, cutoffStart: Double, cutoffEnd: Double) -> [Float] {
        var rng = SplitMix(seed: 42)
        var lp = 0.0
        return render(dur) { t in
            let p = t / dur
            let fc = cutoffStart * pow(cutoffEnd / cutoffStart, p)
            let k = 1 - exp(-twoPi * fc / sr)
            lp += (rng.nextDouble() * 2 - 1 - lp) * k
            return lp * exp(-t * 5) * min(1, t / 0.003)
        }
    }

    /// polyBLEP 带限脉冲波，减少刺耳的混叠
    static func pulse(_ phase: Double, duty: Double, dt: Double) -> Double {
        func blep(_ t: Double) -> Double {
            if t < dt { let x = t / dt; return x + x - x * x - 1 }
            if t > 1 - dt { let x = (t - 1) / dt; return x * x + x + x + 1 }
            return 0
        }
        var v = phase < duty ? 1.0 : -1.0
        v += blep(phase)
        var p2 = phase - duty
        if p2 < 0 { p2 += 1 }
        v -= blep(p2)
        return v
    }

    static func mix(_ dst: inout [Float], _ src: [Float], at seconds: Double, gain: Float) {
        let off = Int(seconds * sr)
        let n = min(src.count, dst.count - off)
        guard n > 0 else { return }
        for i in 0..<n { dst[off + i] += src[i] * gain }
    }

    static func normalized(_ s: [Float], peak: Float = 0.7) -> [Float] {
        let m = s.reduce(0) { max($0, abs($1)) }
        guard m > 0 else { return s }
        // 去掉结尾的静音
        var end = s.count
        while end > 1, abs(s[end - 1]) < m * 0.0005 { end -= 1 }
        let g = peak / m
        return s[0..<end].map { $0 * g }
    }
}

struct SplitMix {
    var state: UInt64
    init(seed: UInt64) { state = seed &+ 0x9E37_79B9_7F4A_7C15 }
    mutating func next() -> UInt64 {
        state = state &+ 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
    mutating func nextDouble() -> Double { Double(next() >> 11) / Double(1 << 53) }
}
