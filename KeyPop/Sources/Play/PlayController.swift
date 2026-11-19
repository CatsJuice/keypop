import AppKit
import SpriteKit

private final class PlayWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// 管理“游戏模式”：全屏盖住所有显示器、进入 Kiosk、锁键盘、把按键分发给画面/声音/朗读。
final class PlayController {
    static let shared = PlayController()

    private let settings = Settings.shared
    private var windows: [NSWindow] = []
    private var scene: PlayScene?
    private let lock = KeyboardLock()
    private var localMonitor: Any?
    private var activity: NSObjectProtocol?
    private var lastFire: [Int: TimeInterval] = [:]
    private var savedOptions: NSApplication.PresentationOptions = []
    private var exitTimer: Timer?
    private var exitStart: TimeInterval = 0
    private(set) var isPlaying = false

    /// 退出组合键：按住 ⌃⌥⌘ 再按住 E 1.5 秒
    private let exitKey = 14
    private let exitHold: TimeInterval = 1.5
    var onExit: (() -> Void)?

    var lockedForReal: Bool { lock.isActive }

    func start() {
        guard !isPlaying else { return }
        isPlaying = true
        NSApp.activate(ignoringOtherApps: true)

        let level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
        let main = NSScreen.main ?? NSScreen.screens[0]
        for screen in NSScreen.screens {
            let w = PlayWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false, screen: screen)
            w.level = level
            w.backgroundColor = .black
            w.isOpaque = true
            w.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
            w.isReleasedWhenClosed = false
            w.acceptsMouseMovedEvents = true
            w.setFrame(screen.frame, display: true)
            if screen == main {
                let view = SKView(frame: CGRect(origin: .zero, size: screen.frame.size))
                view.ignoresSiblingOrder = false
                view.preferredFramesPerSecond = max(60, screen.maximumFramesPerSecond)
                view.allowsTransparency = false
                let scene = PlayScene(size: screen.frame.size)
                scene.scaleMode = .resizeFill
                scene.onClick = { [weak self] x in self?.playClick(x) }
                scene.onExitButton = { [weak self] down in
                    guard let self else { return }
                    if down { self.beginExit(byMouse: true) } else { self.cancelExit() }
                }
                view.presentScene(scene)
                w.contentView = view
                self.scene = scene
            }
            w.orderFrontRegardless()
            windows.append(w)
        }
        if let w = windows.first(where: { $0.screen == main }) {
            w.makeKeyAndOrderFront(nil)
            w.makeFirstResponder(w.contentView)
        }

        savedOptions = NSApp.presentationOptions
        NSApp.presentationOptions = [.hideDock, .hideMenuBar, .disableProcessSwitching, .disableForceQuit,
                                     .disableSessionTermination, .disableHideApplication, .disableAppleMenu]
        NSCursor.hide()
        activity = ProcessInfo.processInfo.beginActivity(options: [.idleDisplaySleepDisabled, .userInitiated], reason: "KeyPop 游戏中")

        SoundEngine.shared.setVolume(settings.volume)
        SoundEngine.shared.start()
        SoundEngine.shared.prewarm(pack: settings.soundPack)

        let handler: (KeyboardLock.Event) -> Void = { [weak self] e in self?.handle(e) }
        if !(settings.lockKeyboard && lock.start(handler)) {
            // 没开锁定（或没权限）时退回到 App 内拦截：挡住 ⌘Q、⌘, 等菜单快捷键，挡不住全局快捷键
            localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp, .flagsChanged]) { [weak self] ev in
                guard let self else { return ev }
                let isDown: Bool
                if ev.type == .flagsChanged {
                    isDown = !ev.modifierFlags.intersection([.shift, .control, .option, .command, .capsLock, .function]).isEmpty
                } else {
                    isDown = ev.type == .keyDown
                }
                self.handle(.init(code: Int(ev.keyCode), isDown: isDown, isRepeat: ev.type == .keyDown && ev.isARepeat,
                                  flags: ev.modifierFlags.intersection(.deviceIndependentFlagsMask)))
                return nil
            }
        }
    }

    func stop() {
        guard isPlaying else { return }
        isPlaying = false
        cancelExit()
        lock.stop()
        if let m = localMonitor { NSEvent.removeMonitor(m) }
        localMonitor = nil
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
        scene = nil
        NSApp.presentationOptions = savedOptions
        NSCursor.unhide()
        if let a = activity { ProcessInfo.processInfo.endActivity(a) }
        activity = nil
        onExit?()
    }

    // MARK: 按键

    private func handle(_ e: KeyboardLock.Event) {
        let exitMods: NSEvent.ModifierFlags = [.control, .option, .command]
        if e.code == exitKey && e.flags.isSuperset(of: exitMods) {
            if e.isDown { if exitTimer == nil { beginExit(byMouse: false) } } else if !exitByMouse { cancelExit() }
            return
        }
        if exitTimer != nil && !exitByMouse && !e.flags.isSuperset(of: exitMods) { cancelExit() }
        if exitTimer != nil { return }
        guard e.isDown else { return }

        let now = ProcessInfo.processInfo.systemUptime
        if e.isRepeat, now - (lastFire[e.code] ?? 0) < 0.12 { return }   // 长按时限速
        lastFire[e.code] = now

        let press = KeyMap.press(code: e.code)
        scene?.handle(press)
        SoundEngine.shared.play(press, pack: settings.soundPack)
        Speech.shared.speak(press, mode: settings.speech, volume: settings.volume)
    }

    private func playClick(_ x: CGFloat) {
        let idx = Int(x * 14)
        SoundEngine.shared.play(KeyPress(code: 2000 + 1, kind: .other(2001), pitchIndex: 4 + idx), pack: settings.soundPack == .chiptune ? .chiptune : .cartoon)
    }

    // MARK: 家长退出

    private var exitByMouse = false

    private func beginExit(byMouse: Bool) {
        guard exitTimer == nil else { return }
        exitByMouse = byMouse
        exitStart = ProcessInfo.processInfo.systemUptime
        scene?.setExitProgress(0)
        exitTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            guard let self else { return }
            let f = (ProcessInfo.processInfo.systemUptime - self.exitStart) / self.exitHold
            if f >= 1 { self.stop() } else { self.scene?.setExitProgress(CGFloat(f)) }
        }
    }

    private func cancelExit() {
        exitTimer?.invalidate()
        exitTimer = nil
        scene?.setExitProgress(nil)
    }
}
