import Foundation
import Combine

/// 特效主题：决定按键时的粒子风格
enum EffectTheme: String, CaseIterable, Identifiable {
    case fireworks, bubbles, confetti, starlight

    var id: String { rawValue }
    var title: String {
        switch self {
        case .fireworks: "烟花"
        case .bubbles: "泡泡"
        case .confetti: "彩纸"
        case .starlight: "星光"
        }
    }
    var subtitle: String {
        switch self {
        case .fireworks: "发光火花四散绽放"
        case .bubbles: "彩虹肥皂泡慢慢飘起"
        case .confetti: "彩色纸片翻转飘落"
        case .starlight: "闪烁星星和流星拖尾"
        }
    }
    var icon: String {
        switch self {
        case .fireworks: "party"
        case .bubbles: "bubbles"
        case .confetti: "balloon"
        case .starlight: "glowingstar"
        }
    }
}

/// 音效包：决定每个按键用什么音色
enum SoundPack: String, CaseIterable, Identifiable {
    case marimba, musicBox, harp, chiptune, cartoon

    var id: String { rawValue }
    var title: String {
        switch self {
        case .marimba: "木琴"
        case .musicBox: "八音盒"
        case .harp: "竖琴"
        case .chiptune: "游戏机"
        case .cartoon: "卡通"
        }
    }
    var subtitle: String {
        switch self {
        case .marimba: "温暖圆润的木头声"
        case .musicBox: "清脆叮咚，余音悠长"
        case .harp: "拨弦，像在弹琴"
        case .chiptune: "8-bit 复古电子音"
        case .cartoon: "弹簧、啵啵、滑哨"
        }
    }
}

/// 朗读语言
enum SpeechMode: String, CaseIterable, Identifiable {
    case off, chinese, english
    var id: String { rawValue }
    var title: String {
        switch self {
        case .off: "关闭"
        case .chinese: "中文"
        case .english: "English"
        }
    }
}

/// 所有设置，存在 UserDefaults 里
final class Settings: ObservableObject {
    static let shared = Settings()
    private let d = UserDefaults.standard

    @Published var theme: EffectTheme { didSet { d.set(theme.rawValue, forKey: "theme") } }
    @Published var soundPack: SoundPack { didSet { d.set(soundPack.rawValue, forKey: "soundPack") } }
    @Published var speech: SpeechMode { didSet { d.set(speech.rawValue, forKey: "speech") } }
    @Published var volume: Double { didSet { d.set(volume, forKey: "volume") } }
    @Published var showLetters: Bool { didSet { d.set(showLetters, forKey: "showLetters") } }
    @Published var ambientStars: Bool { didSet { d.set(ambientStars, forKey: "ambientStars") } }
    @Published var lockKeyboard: Bool { didSet { d.set(lockKeyboard, forKey: "lockKeyboard") } }
    @Published var mouseEffects: Bool { didSet { d.set(mouseEffects, forKey: "mouseEffects") } }

    private init() {
        theme = EffectTheme(rawValue: d.string(forKey: "theme") ?? "") ?? .fireworks
        soundPack = SoundPack(rawValue: d.string(forKey: "soundPack") ?? "") ?? .marimba
        speech = SpeechMode(rawValue: d.string(forKey: "speech") ?? "") ?? .off
        volume = d.object(forKey: "volume") as? Double ?? 0.8
        showLetters = d.object(forKey: "showLetters") as? Bool ?? true
        ambientStars = d.object(forKey: "ambientStars") as? Bool ?? true
        lockKeyboard = d.object(forKey: "lockKeyboard") as? Bool ?? true
        mouseEffects = d.object(forKey: "mouseEffects") as? Bool ?? true
    }
}
