import Foundation
import Sparkle

/// 自动更新（Sparkle）。孩子在玩的时候不检查、不弹窗，回到设置页后再说。
final class Updater: NSObject, ObservableObject, SPUUpdaterDelegate {
    static let shared = Updater()

    private var controller: SPUStandardUpdaterController!
    @Published var canCheck = false

    var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    }

    private override init() {
        super.init()
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: self, userDriverDelegate: nil)
        controller.updater.publisher(for: \.canCheckForUpdates).assign(to: &$canCheck)
    }

    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }

    // 游戏中禁止任何更新检查（包括后台定时检查），避免弹窗打断孩子
    func updater(_ updater: SPUUpdater, mayPerform updateCheck: SPUUpdateCheck) throws {
        if PlayController.shared.isPlaying {
            throw NSError(domain: "KeyPop", code: 1, userInfo: [NSLocalizedDescriptionKey: "游戏中暂不检查更新"])
        }
    }
}
