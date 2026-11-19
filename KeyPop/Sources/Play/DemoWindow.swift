import AppKit
import SpriteKit

/// 开发用：`KeyPop --demo [主题] [键码...]` 在普通窗口里自动“按键”，方便截图检查画面，不进 Kiosk、不锁键盘。
enum DemoWindow {
    private static var window: NSWindow?

    static func runIfRequested() -> Bool {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--demo") else { return false }
        let rest = Array(args[(i + 1)...])
        if let t = rest.first.flatMap(EffectTheme.init(rawValue:)) { Settings.shared.theme = t }
        let codes = rest.compactMap(Int.init)
        let seq = codes.isEmpty ? [0, 49, 20, 11, 126, 50, 36, 6] : codes

        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1280, height: 800), styleMask: [.titled, .closable],
                         backing: .buffered, defer: false)
        w.title = "KeyPop Demo"
        let view = SKView(frame: w.contentLayoutRect)
        let scene = PlayScene(size: view.bounds.size)
        scene.scaleMode = .resizeFill
        view.presentScene(scene)
        w.contentView = view
        w.center()
        w.makeKeyAndOrderFront(nil)
        window = w
        NSApp.activate(ignoringOtherApps: true)
        if args.contains("--show-exit") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { scene.showExitButton() }
        }
        let gap = args.contains("--fast") ? 0.03 : 0.18
        for (n, code) in seq.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8 + Double(n) * gap) {
                let p = KeyMap.press(code: code)
                scene.handle(p)
                SoundEngine.shared.play(p, pack: Settings.shared.soundPack)
            }
        }
        return true
    }
}
