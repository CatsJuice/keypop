import AVFoundation

/// 朗读字母和数字：“A，苹果” / “A. Apple”
final class Speech {
    static let shared = Speech()
    private let synth = AVSpeechSynthesizer()
    private var voices: [String: AVSpeechSynthesisVoice] = [:]

    func speak(_ press: KeyPress, mode: SpeechMode, volume: Double) {
        guard mode != .off else { return }
        let text: String
        switch press.kind {
        case .letter(let ch):
            guard let w = KeyMap.letters[ch] else { return }
            text = mode == .chinese ? "\(ch)，\(w.zh)" : "\(ch). \(w.en)!"
        case .digit(let d):
            text = mode == .chinese ? KeyMap.digitWordsZH[d] : KeyMap.digitWordsEN[d]
        default:
            return
        }
        let lang = mode == .chinese ? "zh-CN" : "en-US"
        let u = AVSpeechUtterance(string: text)
        u.voice = voice(for: lang)
        u.rate = 0.44
        u.pitchMultiplier = 1.15
        u.volume = Float(min(1, volume * 1.1))
        // 孩子乱按时只读最新的，不排队
        if synth.isSpeaking { synth.stopSpeaking(at: .immediate) }
        synth.speak(u)
    }

    /// 优先选质量最好的（高级 > 增强 > 默认）声音
    private func voice(for lang: String) -> AVSpeechSynthesisVoice? {
        if let v = voices[lang] { return v }
        let best = AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language == lang && !$0.voiceTraits.contains(.isNoveltyVoice) }
            .max { $0.quality.rawValue < $1.quality.rawValue }
            ?? AVSpeechSynthesisVoice(language: lang)
        voices[lang] = best
        return best
    }
}
