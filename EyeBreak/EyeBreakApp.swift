import Combine
import SwiftUI
import os

@main
struct EyeBreakApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuContentView(model: appDelegate.model, launchAtLogin: appDelegate.launchAtLogin, stats: appDelegate.stats, sounds: appDelegate.sounds, updates: appDelegate.updates, schedule: appDelegate.schedule)
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
    let sounds: ReminderSounds
    let schedule: WorkScheduleSettings
    let launchAtLogin = LaunchAtLogin()
    let stats = TomatoStats()
    let updates = AppUpdater()
    private var breakPanel: BreakPanelController?
    private var cancellables: Set<AnyCancellable> = []

    override init() {
        let schedule = WorkScheduleSettings()
        let sounds = ReminderSounds(choice: EyeBreakConfig.reminderSound)
        sounds.onChoiceChanged = { EyeBreakConfig.reminderSound = $0 }
        let model = EyeBreakModel(
            workInterval: EyeBreakConfig.workInterval,
            restDuration: EyeBreakConfig.restDuration,
            reminder: sounds,
            isWorkTime: { [weak schedule] in schedule?.schedule.contains(Date()) ?? true },
            exerciseIndex: EyeBreakConfig.exerciseIndex
        )
        model.onPreferencesChanged = { work, rest in
            EyeBreakConfig.save(workInterval: work, restDuration: rest)
        }
        self.model = model
        IntentHub.shared.model = model
        self.sounds = sounds
        self.schedule = schedule
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
        updates.start()
        #if DEBUG
        Logger(subsystem: "EyeBreak", category: "debug")
            .notice("Idle seconds at launch: \(SystemIdle.seconds(), format: .fixed(precision: 1)), away threshold: \(EyeBreakConfig.awayThreshold), login item enabled: \(self.launchAtLogin.isEnabled), audio devices: \(MeetingDetector.audioDevices().count), running audio devices: \(MeetingDetector.audioDevices().filter(MeetingDetector.isAudioDeviceRunning).count), mic in use: \(MeetingDetector.isMicrophoneInUse()), visible windows: \((CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]])?.count ?? -1), frontmost fullscreen: \(FullscreenDetector.isFrontmostAppFullscreen())")
        #endif
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.shutdown()
    }
}

private struct MenuBarLabel: View {
    @ObservedObject var model: EyeBreakModel
    @AppStorage(EyeBreakConfig.showMenuBarTimeKey) private var showTime = false

    var body: some View {
        Image(nsImage: MenuBarIcon.compose(icon: NSImage(named: assetName) ?? NSImage(), text: showTime ? model.menuBarText : nil))
            .accessibilityLabel(accessibility)
    }

    /// 单色番茄仔剪影，表情随状态变化（Assets 中的 MenuBar*，由 Design/style 导出）
    private var assetName: String {
        switch model.phase {
        case .working: return "MenuBarWorking"
        case .awaitingBreak: return "MenuBarAwaiting"
        case .resting: return "MenuBarResting"
        case .idle, .paused, .away, .offHours: return "MenuBarIdle"
        }
    }

    private var accessibility: String {
        let state: String
        switch model.phase {
        case .working: state = "专注中"
        case .awaitingBreak: state = "等待休息"
        case .resting: state = "休息中"
        case .away: state = "离开中"
        case .offHours: state = "工作时段外"
        case .idle, .paused: state = "未在计时"
        }
        if let text = model.menuBarText, model.phase != .awaitingBreak {
            return "EyeBreak \(state)，剩余 \(text)"
        }
        return "EyeBreak \(state)"
    }
}
