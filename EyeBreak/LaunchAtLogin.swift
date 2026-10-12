import Combine
import ServiceManagement
import os

/// 开机自启：把 App 本身注册为登录项（macOS 13 起的 SMAppService，无需辅助程序）
@MainActor
final class LaunchAtLogin: ObservableObject {
    @Published private(set) var isEnabled = false
    /// 已注册，但用户需要在「系统设置 → 通用 → 登录项」里批准
    @Published private(set) var needsApproval = false
    @Published private(set) var failed = false

    private let logger = Logger(subsystem: "EyeBreak", category: "login-item")

    init() {
        refresh()
    }

    func refresh() {
        let status = SMAppService.mainApp.status
        isEnabled = status == .enabled || status == .requiresApproval
        needsApproval = status == .requiresApproval
    }

    func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            failed = false
        } catch {
            logger.error("Login item update failed: \(error.localizedDescription)")
            failed = true
        }
        refresh()
    }

    func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
