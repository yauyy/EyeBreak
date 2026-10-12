import SwiftUI

@main
struct EyeBreakApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuContentView(model: appDelegate.model, notifications: appDelegate.notifications)
        } label: {
            MenuBarLabel(model: appDelegate.model)
        }
        .menuBarExtraStyle(.window)
    }
}

/// 计时模型、通知服务和休息面板由 AppDelegate 持有，生命周期等同于进程，
/// 与菜单面板是否打开无关——关闭面板不会停止计时。
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let notifications: NotificationService
    let model: EyeBreakModel
    private var breakPanel: BreakPanelController?

    override init() {
        let service = NotificationService()
        let model = EyeBreakModel(
            workInterval: EyeBreakConfig.workInterval,
            restDuration: EyeBreakConfig.restDuration,
            reminder: service
        )
        model.onPreferencesChanged = { work, rest in
            EyeBreakConfig.save(workInterval: work, restDuration: rest)
        }
        service.onStartBreak = { [weak model] in model?.startBreak() }
        notifications = service
        self.model = model
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 单元测试以本 App 为宿主运行，不要在测试中弹出授权对话框和面板
        guard !EyeBreakConfig.isRunningTests else { return }
        breakPanel = BreakPanelController(model: model)
        Task { await notifications.prepare() }
        if EyeBreakConfig.autoStart { model.start() }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        // 用户可能刚从系统设置改完通知权限
        Task { await notifications.refreshStatus() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.shutdown()
    }
}

private struct MenuBarLabel: View {
    @ObservedObject var model: EyeBreakModel

    var body: some View {
        Image(systemName: symbol)
            .accessibilityLabel(accessibility)
    }

    private var symbol: String {
        switch model.phase {
        case .working: return "eye"
        case .awaitingBreak: return "bell.badge"
        case .resting: return "cup.and.saucer"
        case .idle, .paused: return "eye.slash"
        }
    }

    private var accessibility: String {
        switch model.phase {
        case .working: return "EyeBreak 专注中"
        case .awaitingBreak: return "EyeBreak 等待休息"
        case .resting: return "EyeBreak 休息中"
        case .idle, .paused: return "EyeBreak 未在计时"
        }
    }
}
