import SwiftUI
import os

@main
struct EyeBreakApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuContentView(model: appDelegate.model)
        } label: {
            MenuBarLabel(model: appDelegate.model)
        }
        .menuBarExtraStyle(.window)
    }
}

/// 计时模型、提示音和休息面板由 AppDelegate 持有，生命周期等同于进程，
/// 与菜单面板是否打开无关——关闭面板不会停止计时。
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model: EyeBreakModel
    private var breakPanel: BreakPanelController?

    override init() {
        let model = EyeBreakModel(
            workInterval: EyeBreakConfig.workInterval,
            restDuration: EyeBreakConfig.restDuration,
            reminder: ReminderSounds()
        )
        model.onPreferencesChanged = { work, rest in
            EyeBreakConfig.save(workInterval: work, restDuration: rest)
        }
        self.model = model
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 单元测试以本 App 为宿主运行，不要在测试中弹出面板
        guard !EyeBreakConfig.isRunningTests else { return }
        breakPanel = BreakPanelController(model: model)
        if EyeBreakConfig.autoStart { model.start() }
        #if DEBUG
        Logger(subsystem: "EyeBreak", category: "debug")
            .notice("Idle seconds at launch: \(SystemIdle.seconds(), format: .fixed(precision: 1)), away threshold: \(EyeBreakConfig.awayThreshold)")
        #endif
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.shutdown()
    }
}

private struct MenuBarLabel: View {
    @ObservedObject var model: EyeBreakModel

    var body: some View {
        Image(nsImage: Self.icon(named: assetName))
            .accessibilityLabel(accessibility)
    }

    /// 彩色番茄仔，表情随状态变化（Assets 中的 MenuBar*，由 Design/style 导出）
    private var assetName: String {
        switch model.phase {
        case .working: return "MenuBarWorking"
        case .awaitingBreak: return "MenuBarAwaiting"
        case .resting: return "MenuBarResting"
        case .idle, .paused, .away: return "MenuBarIdle"
        }
    }

    /// 菜单栏默认把图片当模板渲染成单色，这里显式关闭模板模式以保留颜色
    private static func icon(named name: String) -> NSImage {
        let image = NSImage(named: name) ?? NSImage()
        image.isTemplate = false
        image.size = NSSize(width: 18, height: 18)
        return image
    }

    private var accessibility: String {
        switch model.phase {
        case .working: return "EyeBreak 专注中"
        case .awaitingBreak: return "EyeBreak 等待休息"
        case .resting: return "EyeBreak 休息中"
        case .away: return "EyeBreak 离开中"
        case .idle, .paused: return "EyeBreak 未在计时"
        }
    }
}
