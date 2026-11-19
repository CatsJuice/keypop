import AVFoundation

/// 播放引擎：合成好的声音缓存成 PCM，用一组播放节点轮流播放，统一过混响。
final class SoundEngine {
    static let shared = SoundEngine()

    private let engine = AVAudioEngine()
    private let submix = AVAudioMixerNode()
    private let reverb = AVAudioUnitReverb()
    private var players: [AVAudioPlayerNode] = []
    private var nextPlayer = 0
    private var cache: [String: AVAudioPCMBuffer] = [:]
    private let format = AVAudioFormat(standardFormatWithSampleRate: Synth.sr, channels: 1)!
    private var started = false

    private init() {
        engine.attach(submix)
        engine.attach(reverb)
        reverb.loadFactoryPreset(.largeRoom)
        for _ in 0..<24 {
            let p = AVAudioPlayerNode()
            engine.attach(p)
            engine.connect(p, to: submix, format: format)
            players.append(p)
        }
        engine.connect(submix, to: reverb, format: nil)
        engine.connect(reverb, to: engine.mainMixerNode, format: nil)
    }

    func start() {
        guard !started else { return }
        do {
            try engine.start()
            players.forEach { $0.play() }
            started = true
        } catch {
            NSLog("KeyPop audio start failed: \(error)")
        }
    }

    func setVolume(_ v: Double) { engine.mainMixerNode.outputVolume = Float(v) }

    func play(_ press: KeyPress, pack: SoundPack) {
        start()
        reverb.wetDryMix = pack == .musicBox || pack == .harp ? 22 : (pack == .chiptune ? 6 : 14)
        let key = "\(pack.rawValue)|\(cacheKey(press))"
        let buf: AVAudioPCMBuffer
        if let b = cache[key] {
            buf = b
        } else {
            buf = makeBuffer(Synth.normalized(samples(press, pack: pack)))
            cache[key] = buf
        }
        let p = players[nextPlayer]
        nextPlayer = (nextPlayer + 1) % players.count
        p.scheduleBuffer(buf, at: nil, options: .interrupts)
        if !p.isPlaying { p.play() }
    }

    /// 预先合成常用声音，避免第一次按下时卡顿
    func prewarm(pack: SoundPack) {
        let codes = Array(0...50) + [123, 124, 125, 126]
        DispatchQueue.global(qos: .utility).async {
            let rendered = codes.map { code -> (String, [Float]) in
                let p = KeyMap.press(code: code)
                return ("\(pack.rawValue)|\(self.cacheKey(p))", Synth.normalized(self.samples(p, pack: pack)))
            }
            DispatchQueue.main.async {
                for (k, s) in rendered where self.cache[k] == nil { self.cache[k] = self.makeBuffer(s) }
            }
        }
    }

    private func cacheKey(_ p: KeyPress) -> String {
        switch p.kind {
        case .letter, .other: "n\(p.pitchIndex)|\(p.code % 5)"
        case .digit(let d): "d\(d)"
        case .space: "space"
        case .enter: "enter"
        case .backspace: "back"
        case .arrow(let a): "arrow\(a)"
        }
    }

    private func samples(_ p: KeyPress, pack: SoundPack) -> [Float] {
        let base = Synth.baseFreq(pack)
        switch p.kind {
        case .letter, .other:
            return Synth.note(pack, Synth.freq(base: base, index: p.pitchIndex), variant: p.code)
        case .digit(let d):
            // 数字 N：弹出 N 个小东西，每个配一个上行的音
            let n = max(1, d)
            return Synth.run(pack, base: base, start: 5, steps: Array(0..<n), gap: 0.12, variant: 1)
        case .space:
            return Synth.space(pack, base: base)
        case .enter:
            return Synth.run(pack, base: base, start: 5, steps: [0, 1, 2, 3, 4, 5, 7], gap: 0.075, variant: 4)
        case .backspace:
            return Synth.run(pack, base: base, start: 10, steps: [4, 2, 0], gap: 0.08, variant: 4)
        case .arrow(let a):
            if pack == .cartoon {
                return Synth.cartoon(base * (a == .down ? 2.5 : 1), variant: a == .down ? 4 : 2)
            }
            switch a {
            case .up: return Synth.run(pack, base: base, start: 5, steps: [0, 1, 2, 3, 4], gap: 0.045)
            case .down: return Synth.run(pack, base: base, start: 5, steps: [4, 3, 2, 1, 0], gap: 0.045)
            case .left: return Synth.run(pack, base: base, start: 7, steps: [2, 0], gap: 0.07)
            case .right: return Synth.run(pack, base: base, start: 7, steps: [0, 2], gap: 0.07)
            }
        }
    }

    private func makeBuffer(_ s: [Float]) -> AVAudioPCMBuffer {
        let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(max(1, s.count)))!
        buf.frameLength = AVAudioFrameCount(s.count)
        s.withUnsafeBufferPointer { src in
            buf.floatChannelData![0].update(from: src.baseAddress!, count: s.count)
        }
        return buf
    }
}
