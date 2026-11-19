import SwiftUI
import AppKit
import SpriteKit

struct LauncherView: View {
    @ObservedObject private var s = Settings.shared
    @State private var trusted = KeyboardLock.isTrusted
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    /// 叠在整个设置页上的透明特效层，点特效卡片时在卡片上原地放一次
    @State private var fxScene: PlayScene = {
        let scene = PlayScene(size: CGSize(width: 720, height: 1000))
        scene.isPreview = true
        scene.scaleMode = .resizeFill
        scene.backgroundColor = .clear
        return scene
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 26) {
            header
            section("特效") {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4), spacing: 12) {
                    ForEach(EffectTheme.allCases) { t in
                        OptionCard(emoji: t.icon, title: t.title, subtitle: t.subtitle, selected: s.theme == t, action: { s.theme = t }) { rect in
                            // 卡片中 emoji 的位置（SpriteKit 坐标 y 轴向上）
                            let p = CGPoint(x: rect.midX, y: fxScene.size.height - (rect.minY + 40))
                            fxScene.previewBurst(at: p, theme: t)
                        }
                    }
                }
            }
            section("音效") {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 5), spacing: 12) {
                    ForEach(SoundPack.allCases) { p in
                        OptionCard(emoji: icon(p), title: p.title, subtitle: p.subtitle, selected: s.soundPack == p) {
                            s.soundPack = p
                            preview(p)
                        }
                    }
                }
                HStack(spacing: 14) {
                    Image(systemName: "speaker.fill").foregroundStyle(.secondary)
                    Slider(value: $s.volume, in: 0...1) { _ in SoundEngine.shared.setVolume(s.volume); preview(s.soundPack) }
                    Image(systemName: "speaker.wave.3.fill").foregroundStyle(.secondary)
                }
                .padding(.top, 4)
            }
            section("更多") {
                VStack(spacing: 0) {
                    row("朗读字母和数字", detail: "按 A 会说“A，苹果”") {
                        Picker("", selection: $s.speech) {
                            ForEach(SpeechMode.allCases) { Text($0.title).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 210)
                        .onChange(of: s.speech) { _, m in
                            Speech.shared.speak(KeyMap.press(code: 0), mode: m, volume: s.volume)
                        }
                    }
                    Divider().opacity(0.4)
                    row("显示大字母", detail: "关掉后字母键只出小动物") { Toggle("", isOn: $s.showLetters).toggleStyle(.switch) }
                    Divider().opacity(0.4)
                    row("背景星光", detail: "纯黑背景上点缀若隐若现的小星星") { Toggle("", isOn: $s.ambientStars).toggleStyle(.switch) }
                    Divider().opacity(0.4)
                    row("鼠标特效", detail: "光标拖尾、点击爆炸") { Toggle("", isOn: $s.mouseEffects).toggleStyle(.switch) }
                    Divider().opacity(0.4)
                    lockRow
                }
                .padding(.horizontal, 16)
                .background(RoundedRectangle(cornerRadius: 14).fill(.white.opacity(0.05)))
            }
            footer
        }
        .padding(32)
        .coordinateSpace(name: "launcher")
        .overlay(SpriteView(scene: fxScene, options: [.allowsTransparency]).allowsHitTesting(false))
        .background(Color(white: 0.06))
        .onReceive(timer) { _ in trusted = KeyboardLock.isTrusted }
    }

    private var header: some View {
        HStack(spacing: 16) {
            EmojiImage(slug: "piano").frame(width: 64, height: 64)
            VStack(alignment: .leading, spacing: 4) {
                Text("KeyPop").font(.system(size: 34, weight: .black, design: .rounded))
                Text("给小朋友拍键盘玩的特效乐园").font(.system(size: 15, design: .rounded)).foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private var lockRow: some View {
        row("锁定键盘", detail: lockDetail) {
            HStack(spacing: 10) {
                if s.lockKeyboard && !trusted {
                    Button("去授权") {
                        KeyboardLock.requestPermission()
                        KeyboardLock.openSettings()
                    }
                }
                Toggle("", isOn: $s.lockKeyboard).toggleStyle(.switch)
            }
        }
    }

    private var lockDetail: String {
        if !s.lockKeyboard { return "关闭时 Raycast、Spotlight 等全局快捷键仍可能把孩子带出去" }
        return trusted ? "已授权：拦截所有快捷键（Raycast、⌘Tab、⌘, 等）" : "需要在“辅助功能”里允许 KeyPop，否则只能拦住部分快捷键"
    }

    private var footer: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text("家长退出：按住左上角「退出」按钮，或按住 ⌃⌥⌘ 再按住 E，约 1.5 秒")
                Text("Emoji 来自 Microsoft Fluent Emoji（MIT）").foregroundStyle(.tertiary)
            }
            .font(.system(size: 12, design: .rounded))
            .foregroundStyle(.secondary)
            Spacer()
            Button(action: AppDelegate.startPlay) {
                Text("开始玩")
                    .font(.system(size: 20, weight: .heavy, design: .rounded))
                    .padding(.horizontal, 34)
                    .padding(.vertical, 12)
                    .background(Capsule().fill(LinearGradient(colors: [Color(hex: 0xFF9F43), Color(hex: 0xFF5E8A)], startPoint: .topLeading, endPoint: .bottomTrailing)))
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.defaultAction)
        }
    }

    private func section<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.system(size: 13, weight: .bold, design: .rounded)).foregroundStyle(.secondary)
            content()
        }
    }

    private func row<C: View>(_ title: String, detail: String, @ViewBuilder _ control: () -> C) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 14, weight: .semibold, design: .rounded))
                Text(detail).font(.system(size: 12, design: .rounded)).foregroundStyle(.secondary)
            }
            Spacer()
            control()
        }
        .padding(.vertical, 12)
    }

    private func icon(_ p: SoundPack) -> String {
        switch p {
        case .marimba: "violin"
        case .musicBox: "ribbon"
        case .harp: "blossom"
        case .chiptune: "rocket"
        case .cartoon: "frog"
        }
    }

    private func preview(_ p: SoundPack) {
        SoundEngine.shared.setVolume(s.volume)
        SoundEngine.shared.play(KeyMap.press(code: 36), pack: p)
    }
}

private struct OptionCard: View {
    let emoji: String
    let title: String
    let subtitle: String
    let selected: Bool
    let action: () -> Void
    var onTapFrame: ((CGRect) -> Void)? = nil
    @State private var hover = false
    @State private var frame = CGRect.zero

    var body: some View {
        Button {
            action()
            onTapFrame?(frame)
        } label: {
            VStack(spacing: 8) {
                EmojiImage(slug: emoji)
                    .frame(width: 52, height: 52)
                    .scaleEffect(selected ? 1.1 : (hover ? 1.05 : 1))
                Text(title).font(.system(size: 15, weight: .bold, design: .rounded))
                Text(subtitle).font(.system(size: 11, design: .rounded)).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center).lineLimit(2, reservesSpace: true)
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 14).fill(.white.opacity(selected ? 0.12 : (hover ? 0.07 : 0.04))))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(selected ? Color(hex: 0xFFD93D) : .clear, lineWidth: 2))
            .contentShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("launcher")) } action: { frame = $0 }
        .onHover { hover = $0 }
        .animation(.spring(duration: 0.3, bounce: 0.5), value: selected)
        .animation(.easeOut(duration: 0.15), value: hover)
    }
}

struct EmojiImage: View {
    let slug: String
    var body: some View {
        if let url = Bundle.main.url(forResource: slug, withExtension: "png", subdirectory: "Emoji"), let img = NSImage(contentsOf: url) {
            Image(nsImage: img).resizable().interpolation(.high).aspectRatio(contentMode: .fit)
        } else {
            Color.clear
        }
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}
