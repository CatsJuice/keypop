import Foundation

/// 一次按键归类后的结果
enum KeyKind: Equatable {
    case letter(Character)
    case digit(Int)
    case space
    case enter
    case backspace
    case arrow(ArrowDirection)
    case other(Int)
}

enum ArrowDirection { case up, down, left, right }

struct KeyPress {
    let code: Int          // macOS 虚拟键码；系统媒体键为 1000 + NX 键码
    let kind: KeyKind
    /// 按键在键盘上的“音高位置”，左→右、下→上逐渐升高
    let pitchIndex: Int
}

enum KeyMap {
    /// 字母 → (emoji, 英文单词, 中文)
    static let letters: [Character: (emoji: String, en: String, zh: String)] = [
        "A": ("apple", "Apple", "苹果"),
        "B": ("bear", "Bear", "小熊"),
        "C": ("cat", "Cat", "小猫"),
        "D": ("dog", "Dog", "小狗"),
        "E": ("elephant", "Elephant", "大象"),
        "F": ("frog", "Frog", "青蛙"),
        "G": ("giraffe", "Giraffe", "长颈鹿"),
        "H": ("horse", "Horse", "小马"),
        "I": ("icecream", "Ice cream", "冰淇淋"),
        "J": ("juice", "Juice", "果汁"),
        "K": ("koala", "Koala", "考拉"),
        "L": ("lion", "Lion", "狮子"),
        "M": ("monkey", "Monkey", "猴子"),
        "N": ("peanuts", "Nuts", "花生"),
        "O": ("octopus", "Octopus", "章鱼"),
        "P": ("panda", "Panda", "熊猫"),
        "Q": ("crown", "Queen", "皇冠"),
        "R": ("rabbit", "Rabbit", "小兔子"),
        "S": ("star", "Star", "星星"),
        "T": ("tiger", "Tiger", "老虎"),
        "U": ("unicorn", "Unicorn", "独角兽"),
        "V": ("violin", "Violin", "小提琴"),
        "W": ("whale", "Whale", "鲸鱼"),
        "X": ("fox", "Fox", "狐狸"),
        "Y": ("yoyo", "Yo-yo", "悠悠球"),
        "Z": ("zebra", "Zebra", "斑马"),
    ]

    /// 数字键会弹出 N 个同样的小东西，方便数数
    static let digitEmoji = ["doughnut", "duck", "fish", "strawberry", "babychick", "cherries", "bee", "ladybug", "butterfly", "turtle"]
    static let digitWordsEN = ["Zero", "One", "Two", "Three", "Four", "Five", "Six", "Seven", "Eight", "Nine"]
    static let digitWordsZH = ["零", "一", "二", "三", "四", "五", "六", "七", "八", "九"]

    /// 其他键随机（但固定）对应的 emoji
    static let funEmoji = ["balloon", "bubbles", "rainbow", "lollipop", "butterfly", "chick", "blossom", "strawberry",
                           "rocket", "fish", "ribbon", "doughnut", "sun", "ladybug", "teddy", "kite", "bee", "crab",
                           "turtle", "sunflower", "watermelon", "cupcake", "party", "snowman", "penguin", "owl",
                           "dolphin", "cherries", "pig", "cow", "hamster", "heart"]

    static var allEmoji: [String] {
        Array(Set(letters.values.map(\.emoji) + digitEmoji + funEmoji + ["cyclone", "comet", "parachute", "bird", "glowingstar"]))
    }

    private static let letterCodes: [Int: Character] = [
        0: "A", 11: "B", 8: "C", 2: "D", 14: "E", 3: "F", 5: "G", 4: "H", 34: "I", 38: "J", 40: "K", 37: "L", 46: "M",
        45: "N", 31: "O", 35: "P", 12: "Q", 15: "R", 1: "S", 17: "T", 32: "U", 9: "V", 13: "W", 7: "X", 16: "Y", 6: "Z",
    ]
    private static let digitCodes: [Int: Int] = [
        29: 0, 18: 1, 19: 2, 20: 3, 21: 4, 23: 5, 22: 6, 26: 7, 28: 8, 25: 9,
        82: 0, 83: 1, 84: 2, 85: 3, 86: 4, 87: 5, 88: 6, 89: 7, 91: 8, 92: 9,
    ]
    /// 主键区四排，从下往上
    private static let rows: [[Int]] = [
        [6, 7, 8, 9, 11, 45, 46, 43, 47, 44],
        [0, 1, 2, 3, 5, 4, 38, 40, 37, 41, 39],
        [12, 13, 14, 15, 17, 16, 32, 34, 31, 35, 33, 30, 42],
        [50, 18, 19, 20, 21, 23, 22, 26, 28, 25, 29, 27, 24],
    ]
    private static let positions: [Int: Int] = {
        var m: [Int: Int] = [:]
        for (r, row) in rows.enumerated() {
            for (c, code) in row.enumerated() { m[code] = r * 2 + c }
        }
        return m
    }()

    static func press(code: Int) -> KeyPress {
        let kind: KeyKind
        if let ch = letterCodes[code] { kind = .letter(ch) }
        else if let d = digitCodes[code] { kind = .digit(d) }
        else {
            switch code {
            case 49: kind = .space
            case 36, 76: kind = .enter
            case 51, 117: kind = .backspace
            case 126: kind = .arrow(.up)
            case 125: kind = .arrow(.down)
            case 123: kind = .arrow(.left)
            case 124: kind = .arrow(.right)
            default: kind = .other(code)
            }
        }
        let pitch: Int
        if let p = positions[code] {
            pitch = p
        } else if case .digit(let d) = kind {
            pitch = 8 + d          // 小键盘数字
        } else {
            pitch = stableHash(code) % 18
        }
        return KeyPress(code: code, kind: kind, pitchIndex: pitch)
    }

    static func stableHash(_ n: Int) -> Int {
        var x = UInt64(truncatingIfNeeded: n &+ 0x9E37_79B9)
        x = (x ^ (x >> 16)) &* 0x85EB_CA6B
        x = (x ^ (x >> 13)) &* 0xC2B2_AE35
        return Int(truncatingIfNeeded: x ^ (x >> 16)) & 0x7FFF_FFFF
    }
}
