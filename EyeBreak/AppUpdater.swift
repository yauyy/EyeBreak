import AppKit
import Combine
import Sparkle
import os

/// 基于 Sparkle 的自动更新：后台每天检查一次，发现新版本时在菜单里温和提示；
/// 用户点「更新」后由 Sparkle 下载、校验签名、安装并重启。
/// 唯一的联网行为就是读取更新源和下载安装包，不上传任何数据。
@MainActor
final class AppUpdater: NSObject, ObservableObject {
    /// 后台检查发现、但还没展示给用户的新版本号
    @Published private(set) var availableVersion: String?
    @Published private(set) var canCheckForUpdates = false
    @Published var automaticChecks = true {
        didSet {
            if let updater, updater.automaticallyChecksForUpdates != automaticChecks {
                updater.automaticallyChecksForUpdates = automaticChecks
            }
        }
    }

    let currentVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"

    /// 是否配置了更新公钥；本地开发构建没有公钥时不启用更新
    let isConfigured: Bool = {
        let key = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String ?? ""
        return !key.isEmpty && !key.hasPrefix("$(")
    }()

    private var controller: SPUStandardUpdaterController?
    private var updater: SPUUpdater? { controller?.updater }
    private var cancellables: Set<AnyCancellable> = []
    private let logger = Logger(subsystem: "EyeBreak", category: "update")

    func start() {
        guard isConfigured, controller == nil else {
            if !isConfigured { logger.notice("Updater disabled: no public key configured") }
            return
        }
        let controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: self, userDriverDelegate: self)
        self.controller = controller
        automaticChecks = controller.updater.automaticallyChecksForUpdates
        controller.updater.publisher(for: \.canCheckForUpdates)
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.canCheckForUpdates = $0 }
            .store(in: &cancellables)
    }

    /// 用户主动检查更新，或点击菜单里的「更新」查看已发现的新版本
    func checkForUpdates() {
        // 菜单栏应用默认不在前台，先激活，确保更新窗口出现在最上层
        NSApp.activate(ignoringOtherApps: true)
        controller?.checkForUpdates(nil)
    }
}

extension AppUpdater: SPUUpdaterDelegate {
    #if DEBUG
    /// 仅 Debug：-EyeBreakTestFeedURL 指向本地更新源，用于在本机测试自动更新
    func feedURLString(for updater: SPUUpdater) -> String? {
        UserDefaults.standard.string(forKey: "EyeBreakTestFeedURL")
    }
    #endif
}

extension AppUpdater: @preconcurrency SPUStandardUserDriverDelegate {
    /// 菜单栏应用在后台发现更新时，不直接弹窗打断用户，改为在菜单里提示
    var supportsGentleScheduledUpdateReminders: Bool { true }

    func standardUserDriverShouldHandleShowingScheduledUpdate(_ update: SUAppcastItem, andInImmediateFocus immediateFocus: Bool) -> Bool {
        // 刚启动时（immediateFocus）由 Sparkle 直接展示，其余时候交给菜单提示
        immediateFocus
    }

    func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
        if !handleShowingUpdate {
            logger.notice("Update available: \(update.displayVersionString, privacy: .public)")
            availableVersion = update.displayVersionString
        }
    }

    func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        availableVersion = nil
    }

    func standardUserDriverWillFinishUpdateSession() {
        availableVersion = nil
    }
}
