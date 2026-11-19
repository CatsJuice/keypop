import SwiftUI
import AppKit

@main
struct KeyPopApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        Window("KeyPop", id: "launcher") {
            LauncherView()
                .frame(width: 720)
                .fixedSize(horizontal: false, vertical: true)
                .preferredColorScheme(.dark)
        }
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .appInfo) {
                Button("检查更新…") { Updater.shared.checkForUpdates() }
                Divider()
                Button("开始玩") { AppDelegate.startPlay() }
                    .keyboardShortcut("p", modifiers: [.command])
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        Textures.preloadEmoji()
        if DemoWindow.runIfRequested() {
            for w in NSApp.windows where w.title == "KeyPop" { w.orderOut(nil) }
            return
        }
        PlayController.shared.onExit = {
            NSApp.windows.first { $0.identifier?.rawValue.contains("launcher") == true || $0.title == "KeyPop" }?
                .makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
        _ = Updater.shared   // 启动 Sparkle，按计划在后台检查更新
        // 启动参数 --play：直接进入游戏（方便做成快捷方式）
        if CommandLine.arguments.contains("--play") {
            DispatchQueue.main.async { AppDelegate.startPlay() }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        PlayController.shared.isPlaying ? .terminateCancel : .terminateNow
    }

    static func startPlay() {
        for w in NSApp.windows where w.title == "KeyPop" { w.orderOut(nil) }
        PlayController.shared.start()
    }
}
