import Combine
import SwiftUI
import os

@main
struct EyeBreakApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuContentView(model: appDelegate.model, launchAtLogin: appDelegate.launchAtLogin, stats: appDelegate.stats)
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
    let launchAtLogin = LaunchAtLogin()
    let stats = TomatoStats()
    private var breakPanel: BreakPanelController?
    private var cancellables: Set<AnyCancellable> = []

    override init() {
        let model = EyeBreakModel(
            workInterval: EyeBreakConfig.workInterval,
            restDuration: EyeBreakConfig.restDuration,
            reminder: ReminderSounds(),
            exerciseIndex: EyeBreakConfig.exerciseIndex
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
        // 先记账再创建面板：两者都订阅 breakCompleted，按订阅顺序收到，庆祝画面才能显示最新数量
        model.breakCompleted
            .sink { [stats] in MainActor.assumeIsolated { stats.recordBreak() } }
            .store(in: &cancellables)
        model.$exerciseIndex
            .dropFirst()
            .sink { EyeBreakConfig.exerciseIndex = $0 }
            .store(in: &cancellables)
        breakPanel = BreakPanelController(model: model, stats: stats)
        if EyeBreakConfig.autoStart {
            model.start()
        } else if let snapshot = EyeBreakConfig.loadSnapshot() {
            model.restore(snapshot)
        }
        // 先恢复再开始保存，避免启动时的初始状态覆盖掉上次的快照
        model.onSnapshot = { EyeBreakConfig.saveSnapshot($0) }
        #if DEBUG
        Logger(subsystem: "EyeBreak", category: "debug")
            .notice("Idle seconds at launch: \(SystemIdle.seconds(), format: .fixed(precision: 1)), away threshold: \(EyeBreakConfig.awayThreshold), login item enabled: \(self.launchAtLogin.isEnabled), audio devices: \(MeetingDetector.audioDevices().count), running audio devices: \(MeetingDetector.audioDevices().filter(MeetingDetector.isAudioDeviceRunning).count), mic in use: \(MeetingDetector.isMicrophoneInUse())")
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
