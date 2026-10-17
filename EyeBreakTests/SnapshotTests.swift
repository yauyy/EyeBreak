import AppKit
import SwiftUI
import Testing
@testable import EyeBreak

private enum SnapshotEnvironment {
    /// TEST_RUNNER_ 前缀便于 xcodebuild 将变量转交给独立测试宿主。
    static let directory = ProcessInfo.processInfo.environment["EYEBREAK_SNAPSHOT_DIR"]
        ?? ProcessInfo.processInfo.environment["TEST_RUNNER_EYEBREAK_SNAPSHOT_DIR"]

    /// String(localized:) 读取宿主语言，因此每种语言必须分别启动测试进程。
    static let language = Bundle.main.preferredLocalizations.first?.hasPrefix("en") == true ? "en" : "zh-Hans"
}

private enum SnapshotScene: String, CaseIterable, Sendable {
    case menuCollapsed = "menu-collapsed"
    case menuWeek = "menu-week"
    case menuDeferred = "menu-deferred-rest-now"
    case menuSnooze = "menu-snooze-pending-hints"
    case menuWorst = "menu-worst-update"
    case settingsGeneral = "settings-general"
    case settingsRest = "settings-rest"
    case settingsSchedule = "settings-schedule"
    case settingsAbout = "settings-about"
    case settingsScheduleEnabled = "settings-schedule-enabled"
    case panelAwaiting = "panel-awaiting"
    case panelAwaitingDrinkWater = "panel-awaiting-drink-water"
    case panelResting = "panel-resting"
    case panelCelebrating = "panel-celebrating"
    case onboarding

    var width: CGFloat {
        switch self {
        case .menuCollapsed, .menuWeek, .menuDeferred, .menuSnooze, .menuWorst: 280
        case .settingsGeneral, .settingsRest, .settingsSchedule, .settingsAbout, .settingsScheduleEnabled: 520
        case .panelAwaiting, .panelAwaitingDrinkWater, .panelResting, .panelCelebrating: 300
        case .onboarding: 460
        }
    }

    var fixedHeight: CGFloat? {
        switch self {
        case .settingsGeneral, .settingsRest, .settingsSchedule, .settingsAbout, .settingsScheduleEnabled: 480
        case .panelAwaiting, .panelAwaitingDrinkWater, .panelResting, .panelCelebrating: 264
        default: nil
        }
    }
}

private enum SnapshotAppearance: String, CaseIterable, Sendable {
    case light
    case dark

    var name: NSAppearance.Name { self == .light ? .aqua : .darkAqua }
    var colorScheme: ColorScheme { self == .light ? .light : .dark }
}

@MainActor
private final class SnapshotReminder: ReminderDelivering {
    func deliverReminder(restDuration: TimeInterval) {}
    func cancelPendingReminders() {}
    func playBreakComplete() {}
}

/// 每张截图重新建立独立数据，既不读取用户偏好，也不会启动计时器或访问更新网络。
@MainActor
private final class SnapshotFixture {
    let suiteName: String
    let defaults: UserDefaults
    let model: EyeBreakModel
    let stats: TomatoStats
    let updates = AppUpdater()
    let schedule: WorkScheduleSettings
    let launchAtLogin = LaunchAtLogin(refreshesSystemStatus: false)
    let sounds = ReminderSounds(choice: .glass)
    let panelState = BreakPanelController.State()
    let presentation = SettingsPresentation()

    init(scene: SnapshotScene) throws {
        let suite = "EyeBreak.SnapshotTests.\(UUID().uuidString)"
        suiteName = suite
        defaults = try #require(UserDefaults(suiteName: suite))
        let initialDate = Date(timeIntervalSince1970: 1_791_799_200) // 2026-10-12 10:00 UTC
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        // 本周柱状图、连续天数、累计和成就均为固定值。
        defaults.set([
            "2026-10-06": 2, "2026-10-07": 4, "2026-10-08": 1,
            "2026-10-09": 5, "2026-10-10": 3, "2026-10-11": 2, "2026-10-12": 8
        ], forKey: "tomatoCounts")
        defaults.set(72, forKey: "tomatoTotal")
        defaults.set([Achievement.firstTomato, .dailyFive, .streakThree, .totalFifty].map(\.rawValue), forKey: "achievements")
        defaults.set(false, forKey: EyeBreakConfig.showMenuBarTimeKey)
        stats = TomatoStats(defaults: defaults, now: { initialDate }, calendar: calendar)
        schedule = WorkScheduleSettings(defaults: defaults)
        schedule.schedule = WorkSchedule(isEnabled: scene == .settingsScheduleEnabled, startHour: 9, endHour: 19, weekdaysOnly: true)
        // 提醒前固定轮换位置；喝水场景选中第 4 个，其余场景仍从第 0 个开始。
        let clock = SnapshotClock(now: initialDate)
        model = EyeBreakModel(
            workInterval: 1200, restDuration: 20, reminder: SnapshotReminder(),
            now: { clock.now }, idleTime: { 0 },
            isInMeeting: { scene == .menuDeferred }, isFullscreen: { false },
            isWorkTime: { true },
            exerciseIndex: scene == .panelAwaitingDrinkWater ? RestExercise.drinkWater.rawValue - 1 : -1,
            usesSystemTimer: false
        )
        updates.setSnapshotState(availableVersion: scene == .menuWorst ? "1.4.0" : nil)
        panelState.isPresented = true

        switch scene {
        case .menuCollapsed, .menuWeek:
            model.start()
            clock.now += 90
            model.tick()
        case .menuDeferred:
            model.start()
            clock.now += 1200
            model.tick()
            #expect(model.deferReason == .meeting)
        case .menuSnooze, .menuWorst:
            model.start()
            clock.now += 1200
            model.tick()
            model.snooze()
            model.setWorkInterval(1500)
            #expect(model.isSnoozing)
        case .panelAwaiting, .panelAwaitingDrinkWater, .panelResting, .panelCelebrating:
            model.start()
            clock.now += 1200
            model.tick()
            #expect(model.exercise == (scene == .panelAwaitingDrinkWater ? .drinkWater : .lookFar))
            if scene == .panelResting {
                model.startBreak()
                clock.now += 7
                model.tick()
                #expect(model.remainingSeconds == 13)
            }
            if scene == .panelCelebrating {
                stats.recordBreak()
                panelState.celebrating = true
            }
        default: break
        }
    }

    func cleanUp() {
        model.shutdown()
        defaults.removePersistentDomain(forName: suiteName)
    }

    func content(for scene: SnapshotScene) -> AnyView {
        switch scene {
        case .menuCollapsed, .menuWeek, .menuDeferred, .menuSnooze, .menuWorst:
            return AnyView(MenuBody(
                model: model, stats: stats, updates: updates, schedule: schedule,
                showWeekStats: .constant(scene == .menuWeek || scene == .menuWorst),
                openSettings: { _ in },
                showsAllPendingHintsForTesting: scene == .menuSnooze || scene == .menuWorst
            ))
        case .settingsGeneral, .settingsRest, .settingsSchedule, .settingsAbout, .settingsScheduleEnabled:
            switch scene {
            case .settingsRest: presentation.section = .rest
            case .settingsSchedule, .settingsScheduleEnabled: presentation.section = .schedule
            case .settingsAbout: presentation.section = .about
            default: presentation.section = .general
            }
            return AnyView(SettingsContentView(
                model: model, launchAtLogin: launchAtLogin, stats: stats, sounds: sounds,
                updates: updates, schedule: schedule, presentation: presentation, onReplayOnboarding: {}
            ))
        case .panelAwaiting, .panelAwaitingDrinkWater, .panelResting, .panelCelebrating:
            return AnyView(BreakPanelView(
                model: model, state: panelState, stats: stats,
                animationTime: scene == .panelAwaitingDrinkWater ? 1.4 : 1.8
            ))
        case .onboarding:
            return AnyView(OnboardingView(model: model, begin: {}, dismiss: {}))
        }
    }
}

@MainActor
private final class SnapshotClock {
    var now: Date
    init(now: Date) { self.now = now }
}

@MainActor
struct SnapshotTests {
    @Test("520 × 480 休息页的五个开关及单动作提示完整显示，无需滚动", arguments: [false, true], SnapshotAppearance.allCases)
    private func restSettingsFitWindow(onlyDrinkWater: Bool, appearance: SnapshotAppearance) async throws {
        let fixture = try SnapshotFixture(scene: .settingsRest)
        defer { fixture.cleanUp() }
        if onlyDrinkWater {
            for exercise in RestExercise.allCases where exercise != .drinkWater {
                fixture.model.setExercise(exercise, enabled: false)
            }
            #expect(fixture.model.enabledExercises == [.drinkWater])
        }
        let content = fixture.content(for: .settingsRest)
            .defaultAppStorage(fixture.defaults)
            .environment(\.locale, Locale(identifier: SnapshotEnvironment.language))
            .environment(\.colorScheme, appearance.colorScheme)
            .transaction { $0.disablesAnimations = true }
        let host = NSHostingView(rootView: content)
        host.appearance = NSAppearance(named: appearance.name)
        host.frame = NSRect(x: 0, y: 0, width: 520, height: 480)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = host.appearance
        window.contentView = host
        defer { window.close() }
        host.layoutSubtreeIfNeeded()
        await Task.yield()
        host.layoutSubtreeIfNeeded()

        // 检查实际滚动内容和可见区域，避免固定窗口高度掩盖第五个开关被截断。
        let scrollView = try #require(firstScrollView(in: host))
        let document = try #require(scrollView.documentView)
        let visibleSize = scrollView.contentView.bounds.size
        #expect(document.bounds.height > 200)
        #expect(document.bounds.height <= visibleSize.height + 1)
        #expect(document.bounds.width <= visibleSize.width + 1)
        #expect(host.bounds.size == NSSize(width: 520, height: 480))
        print("Settings 休息页 \(SnapshotEnvironment.language) \(appearance.rawValue)，仅喝水=\(onlyDrinkWater)：内容 \(document.bounds.size)，可见 \(visibleSize)")
    }

    @Test(
        "按宿主语言生成菜单、设置、提醒和引导的深浅色 PNG",
        .enabled(if: SnapshotEnvironment.directory?.isEmpty == false, "设置 EYEBREAK_SNAPSHOT_DIR 后才生成截图"),
        arguments: SnapshotScene.allCases, SnapshotAppearance.allCases
    )
    private func matrix(scene: SnapshotScene, appearance: SnapshotAppearance) async throws {
        let directory = try outputDirectory()
        let fixture = try SnapshotFixture(scene: scene)
        defer { fixture.cleanUp() }
        let content = fixture.content(for: scene)
            .defaultAppStorage(fixture.defaults)
            .environment(\.locale, Locale(identifier: SnapshotEnvironment.language))
            .environment(\.colorScheme, appearance.colorScheme)
            .transaction { $0.disablesAnimations = true }
        let host = NSHostingView(rootView: content)
        host.appearance = NSAppearance(named: appearance.name)
        host.frame = NSRect(x: 0, y: 0, width: scene.width, height: scene.fixedHeight ?? 1)
        // 挂载到不显示的窗口，使 SwiftUI 获得真实 AppKit 外观及完整布局生命周期。
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = host.appearance
        window.contentView = host
        defer { window.close() }
        host.layoutSubtreeIfNeeded()
        if scene.fixedHeight == nil {
            window.setContentSize(NSSize(width: scene.width, height: ceil(host.fittingSize.height)))
        }
        // Canvas 与 SwiftUI 的布局提交跨越主队列，等待提交后再缓存显示内容。
        await Task.yield()
        host.layoutSubtreeIfNeeded()
        host.displayIfNeeded()
        #expect(host.bounds.width == scene.width)
        #expect(host.bounds.height > 0)

        let bitmap = try #require(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(host.bounds.width * 2), pixelsHigh: Int(host.bounds.height * 2),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ))
        bitmap.size = host.bounds.size
        host.effectiveAppearance.performAsCurrentDrawingAppearance {
            host.cacheDisplay(in: host.bounds, to: bitmap)
        }
        let data = try #require(bitmap.representation(using: .png, properties: [:]))
        let filename = "\(scene.rawValue)-\(SnapshotEnvironment.language)-\(appearance.rawValue).png"
        let file = directory.appendingPathComponent(filename)
        try data.write(to: file, options: .atomic)
        #expect(FileManager.default.fileExists(atPath: file.path))
        print("EyeBreak 截图：\(file.path)")
    }

    private func outputDirectory() throws -> URL {
        let path = try #require(SnapshotEnvironment.directory)
        let temporary = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().standardizedFileURL
        let directory = (path.hasPrefix("/") ? URL(fileURLWithPath: path, isDirectory: true)
                         : temporary.appendingPathComponent(path, isDirectory: true))
            .resolvingSymlinksInPath().standardizedFileURL
        // 测试宿主启用 App Sandbox，只允许写进它自己的 tmp。
        let prefix = temporary.path.hasSuffix("/") ? temporary.path : temporary.path + "/"
        #expect(directory.path == temporary.path || directory.path.hasPrefix(prefix))
        guard directory.path == temporary.path || directory.path.hasPrefix(prefix) else {
            throw CocoaError(.fileWriteNoPermission)
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func firstScrollView(in view: NSView) -> NSScrollView? {
        if let scrollView = view as? NSScrollView { return scrollView }
        for child in view.subviews {
            if let scrollView = firstScrollView(in: child) { return scrollView }
        }
        return nil
    }
}
