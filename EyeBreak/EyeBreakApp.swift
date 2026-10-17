import Combine
import SwiftUI
import os

@main
struct EyeBreakApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuContentView(
                model: appDelegate.model, launchAtLogin: appDelegate.launchAtLogin,
                stats: appDelegate.stats, sounds: appDelegate.sounds,
                updates: appDelegate.updates, schedule: appDelegate.schedule,
                openSettings: { appDelegate.openSettings(achievements: $0) },
                menuWindowChanged: { appDelegate.menuWindow = $0 }
            )
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
    let launchAtLogin: LaunchAtLogin
    let stats: TomatoStats
    let updates: AppUpdater
    weak var menuWindow: NSWindow?
    private let shouldShowOnboarding: Bool
    private var settingsWindow: SettingsWindowController?
    private var onboardingWindow: OnboardingWindowController?
    private var shortcutMonitor: Any?
    private var breakPanel: BreakPanelController?
    private var cancellables: Set<AnyCancellable> = []

    override init() {
        // 必须先读持久域：后续状态对象与 Sparkle 的初始化可能写入偏好。
        let defaults = UserDefaults.standard
        let domain = Bundle.main.bundleIdentifier.flatMap { defaults.persistentDomain(forName: $0) } ?? [:]
        shouldShowOnboarding = OnboardingPolicy.shouldPresent(persistentDomain: domain)
        if !shouldShowOnboarding, !EyeBreakConfig.isRunningTests {
            defaults.set(true, forKey: OnboardingPolicy.seenKey)
        }
        launchAtLogin = LaunchAtLogin()
        stats = TomatoStats()
        updates = AppUpdater()
        let schedule = WorkScheduleSettings()
        let sounds = ReminderSounds(choice: EyeBreakConfig.reminderSound)
        sounds.onChoiceChanged = { EyeBreakConfig.reminderSound = $0 }
        let model = EyeBreakModel(
            workInterval: EyeBreakConfig.workInterval,
            restDuration: EyeBreakConfig.restDuration,
            reminder: sounds,
            isWorkTime: { [weak schedule] in schedule?.schedule.contains(Date()) ?? true },
            exerciseIndex: EyeBreakConfig.exerciseIndex,
            enabledExercises: EyeBreakConfig.enabledExercises
        )
        model.onPreferencesChanged = { work, rest in
            EyeBreakConfig.save(workInterval: work, restDuration: rest)
        }
        model.onEnabledExercisesChanged = { EyeBreakConfig.enabledExercises = $0 }
        schedule.onScheduleChanged = { [weak model] in model?.workScheduleDidChange() }
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
            model.startAutomatically()
        } else if let snapshot = EyeBreakConfig.loadSnapshot() {
            model.restore(snapshot)
        }
        // 先恢复再开始保存，避免启动时的初始状态覆盖掉上次的快照
        model.onSnapshot = { EyeBreakConfig.saveSnapshot($0) }
        updates.start()
        installShortcuts()
        if shouldShowOnboarding { showOnboarding() }
        // 专注模式在启动前就已开启时，系统不会再调用过滤条件，这里主动读一次当前状态
        Task { [model] in
            if let filter = try? await EyeBreakFocusFilter.current {
                model.setFocusHold(filter.pauseReminders)
            }
        }
        // 跨过零点时刷新今日番茄和本周统计
        NotificationCenter.default.publisher(for: .NSCalendarDayChanged)
            .receive(on: RunLoop.main)
            .sink { [stats] _ in MainActor.assumeIsolated { stats.refresh() } }
            .store(in: &cancellables)
        #if DEBUG
        Logger(subsystem: "EyeBreak", category: "debug")
            .notice("Idle seconds at launch: \(SystemIdle.seconds(), format: .fixed(precision: 1)), away threshold: \(EyeBreakConfig.awayThreshold), login item enabled: \(self.launchAtLogin.isEnabled), audio devices: \(MeetingDetector.audioDevices().count), running audio devices: \(MeetingDetector.audioDevices().filter(MeetingDetector.isAudioDeviceRunning).count), mic in use: \(MeetingDetector.isMicrophoneInUse()), visible windows: \((CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]])?.count ?? -1), frontmost fullscreen: \(FullscreenDetector.isFrontmostAppFullscreen())")
        #endif
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let shortcutMonitor { NSEvent.removeMonitor(shortcutMonitor) }
        model.shutdown()
    }

    func openSettings(achievements: Bool = false) {
        menuWindow?.close()
        if settingsWindow == nil {
            settingsWindow = SettingsWindowController(
                model: model, launchAtLogin: launchAtLogin, stats: stats,
                sounds: sounds, updates: updates, schedule: schedule,
                onReplayOnboarding: { [weak self] in self?.showOnboarding() }
            )
        }
        settingsWindow?.show(section: achievements ? .about : nil, focusAchievements: achievements)
    }

    private func showOnboarding() {
        menuWindow?.close()
        if onboardingWindow == nil {
            onboardingWindow = OnboardingWindowController(model: model)
        }
        onboardingWindow?.present()
    }

    /// LSUIElement 没有可见主菜单，用应用内事件监听保证快捷键有效；不监听其他应用。
    private func installShortcuts() {
        shortcutMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let handled = MainActor.assumeIsolated {
                guard let self,
                      event.modifierFlags.intersection([.command, .control, .option, .shift]) == .command,
                      event.charactersIgnoringModifiers == ",",
                      self.menuWindow?.isVisible == true || NSApp.keyWindow != nil else { return false }
                self.openSettings()
                return true
            }
            return handled ? nil : event
        }
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
        case .working: state = String(localized: "专注中")
        case .awaitingBreak: state = String(localized: "等待休息")
        case .resting: state = String(localized: "休息中")
        case .away: state = String(localized: "离开中")
        case .offHours: state = String(localized: "工作时段外")
        case .idle, .paused: state = String(localized: "未在计时")
        }
        if let text = model.menuBarText, model.phase != .awaitingBreak {
            return String(localized: "EyeBreak \(state)，剩余 \(text)")
        }
        return "EyeBreak " + state
    }
}
