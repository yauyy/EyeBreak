// 这些界面回归依赖 Debug 专用状态注入；Release 构建仍可单独运行性能基准。
#if DEBUG
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
    case settingsLanguagePending = "settings-language-pending"
    case settingsRest = "settings-rest"
    case settingsSchedule = "settings-schedule"
    case settingsAchievements = "settings-achievements"
    case settingsAbout = "settings-about"
    case settingsScheduleEnabled = "settings-schedule-enabled"
    case panelAwaiting = "panel-awaiting"
    case panelAwaitingDrinkWater = "panel-awaiting-drink-water"
    case panelAwaitingWalk = "panel-awaiting-walk"
    case panelResting = "panel-resting"
    case panelCelebrating = "panel-celebrating"
    case onboarding

    var width: CGFloat {
        switch self {
        case .menuCollapsed, .menuWeek, .menuDeferred, .menuSnooze, .menuWorst: 280
        case .settingsGeneral, .settingsLanguagePending, .settingsRest, .settingsSchedule,
             .settingsAchievements, .settingsAbout, .settingsScheduleEnabled: 560
        case .panelAwaiting, .panelAwaitingDrinkWater, .panelAwaitingWalk, .panelResting, .panelCelebrating: 300
        case .onboarding: 460
        }
    }

    var fixedHeight: CGFloat? {
        switch self {
        case .settingsGeneral, .settingsLanguagePending, .settingsRest, .settingsSchedule,
             .settingsAchievements, .settingsAbout, .settingsScheduleEnabled: 480
        case .panelAwaiting, .panelAwaitingDrinkWater, .panelAwaitingWalk, .panelResting, .panelCelebrating: 264
        default: nil
        }
    }

    var exercise: RestExercise {
        switch self {
        case .panelAwaitingDrinkWater: .drinkWater
        case .panelAwaitingWalk: .walk
        default: .lookFar
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
    let appearance: AppearanceSettings
    let language: LanguageSettings
    let launchAtLogin = LaunchAtLogin(refreshesSystemStatus: false)
    let sounds = ReminderSounds(choice: .glass)
    let panelState = BreakPanelController.State()
    let presentation = SettingsPresentation()

    init(scene: SnapshotScene) throws {
        let suite = "EyeBreak.SnapshotTests.\(UUID().uuidString)"
        suiteName = suite
        defaults = try #require(UserDefaults(suiteName: suite))
        appearance = AppearanceSettings(defaults: defaults, appliesToApplication: false)
        language = LanguageSettings(
            defaults: defaults, domainName: suite, runningLanguage: SnapshotEnvironment.language,
            systemLanguages: { [SnapshotEnvironment.language] }
        )
        if scene == .settingsLanguagePending {
            language.choice = SnapshotEnvironment.language == "en" ? .simplifiedChinese : .english
            #expect(language.restartRequired)
        } else {
            #expect(!language.restartRequired)
        }
        let initialDate = Date(timeIntervalSince1970: 1_791_799_200) // 2026-10-12 10:00 UTC
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        // 本周柱状图、连续天数、累计和成就均为固定值。
        defaults.set([
            "2026-10-06": 2, "2026-10-07": 4, "2026-10-08": 1,
            "2026-10-09": 5, "2026-10-10": 3, "2026-10-11": 2, "2026-10-12": 8
        ], forKey: "tomatoCounts")
        defaults.set(72, forKey: "tomatoTotal")
        defaults.set([Achievement.firstTomato, .dailyFive, .streakThree, .streakSeven, .totalFifty].map(\.rawValue), forKey: "achievements")
        defaults.set(false, forKey: EyeBreakConfig.showMenuBarTimeKey)
        stats = TomatoStats(defaults: defaults, now: { initialDate }, calendar: calendar)
        schedule = WorkScheduleSettings(defaults: defaults)
        schedule.schedule = WorkSchedule(isEnabled: scene == .settingsScheduleEnabled, startHour: 9, endHour: 19, weekdaysOnly: true)
        // 提醒前固定轮换位置，动作专用场景直接选中对应动作。
        let clock = SnapshotClock(now: initialDate)
        model = EyeBreakModel(
            workInterval: 1200, restDuration: 20, reminder: SnapshotReminder(),
            now: { clock.now }, idleTime: { 0 },
            isInMeeting: { scene == .menuDeferred }, isFullscreen: { false },
            isWorkTime: { true },
            exerciseIndex: scene.exercise.rawValue - 1,
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
        case .panelAwaiting, .panelAwaitingDrinkWater, .panelAwaitingWalk, .panelResting, .panelCelebrating:
            model.start()
            clock.now += 1200
            model.tick()
            #expect(model.exercise == scene.exercise)
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
        case .settingsGeneral, .settingsLanguagePending, .settingsRest, .settingsSchedule,
             .settingsAchievements, .settingsAbout, .settingsScheduleEnabled:
            switch scene {
            case .settingsRest: presentation.section = .rest
            case .settingsSchedule, .settingsScheduleEnabled: presentation.section = .schedule
            case .settingsAchievements: presentation.section = .achievements
            case .settingsAbout: presentation.section = .about
            default: presentation.section = .general
            }
            return AnyView(SettingsContentView(
                model: model, launchAtLogin: launchAtLogin, stats: stats, sounds: sounds,
                updates: updates, schedule: schedule, appearance: appearance, language: language,
                presentation: presentation, onReplayOnboarding: {}
            ))
        case .panelAwaiting, .panelAwaitingDrinkWater, .panelAwaitingWalk, .panelResting, .panelCelebrating:
            return AnyView(BreakPanelView(
                model: model, state: panelState, stats: stats,
                animationTime: scene == .panelAwaitingWalk ? 0.45 : (scene == .panelAwaitingDrinkWater ? 1.4 : 1.8)
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
    @Test("五个设置标签的中英文完整文字在 560 点窗口内有足够空间", arguments: ["zh-Hans", "en"])
    private func settingsTabsHaveRoom(language: String) throws {
        let titles: [String]
        if language == "en" {
            let path = try #require(Bundle.main.path(forResource: "en", ofType: "lproj"))
            let bundle = try #require(Bundle(path: path))
            titles = ["通用", "休息", "工作时段", "成就", "关于"].map {
                bundle.localizedString(forKey: $0, value: nil, table: nil)
            }
        } else {
            titles = ["通用", "休息", "工作时段", "成就", "关于"]
        }
        #expect(SettingsSection.allCases.count == 5)
        // 按产品使用的圆体字号测量完整标签，预留每项左右 8 点、外框和标签间距。
        let textWidths = titles.map { title in
            let label = NSHostingView(rootView: Text(verbatim: title)
                .font(Theme.font(13, .semibold))
                .fixedSize(horizontal: true, vertical: false))
            return ceil(label.fittingSize.width)
        }
        let requiredWidth = textWidths.reduce(0, +) + CGFloat(titles.count) * 16
            + CGFloat(titles.count - 1) * Theme.Spacing.segmented + Theme.Spacing.segmented * 2
        let availableWidth: CGFloat = 560 - 18 * 2
        #expect(requiredWidth <= availableWidth)
        print("Settings 标签 \(language)：完整文字与内边距共 \(requiredWidth) pt，可用 \(availableWidth) pt")
    }

    @Test("通用、语言待生效和成就页保持固定窗口并在内部滚动", arguments: [
        SnapshotScene.settingsGeneral, .settingsLanguagePending, .settingsAchievements
    ], SnapshotAppearance.allCases)
    private func enhancedSettingsKeepFixedWindow(scene: SnapshotScene, appearance: SnapshotAppearance) async throws {
        let fixture = try SnapshotFixture(scene: scene)
        defer { fixture.cleanUp() }
        let content = fixture.content(for: scene)
            .environment(\.ringSnapshotRendering, true)
            .defaultAppStorage(fixture.defaults)
            .environment(\.locale, Locale(identifier: SnapshotEnvironment.language))
            .environment(\.colorScheme, appearance.colorScheme)
            .transaction { $0.disablesAnimations = true }
        let host = NSHostingView(rootView: content)
        host.appearance = NSAppearance(named: appearance.name)
        host.frame = NSRect(x: 0, y: 0, width: 560, height: 480)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = host.appearance
        window.contentView = host
        defer { window.close() }
        // 传统滚动条（「始终显示滚动条」）出现后，内容要再排一次版才会收窄到可见宽度；等尺寸稳定再测量。
        var lastWidth: CGFloat = -1
        for _ in 0..<10 {
            host.layoutSubtreeIfNeeded()
            await Task.yield()
            host.layoutSubtreeIfNeeded()
            let width = firstScrollView(in: host)?.documentView?.bounds.width ?? 0
            if width == lastWidth { break }
            lastWidth = width
        }

        let scrollView = try #require(firstScrollView(in: host))
        let document = try #require(scrollView.documentView)
        let visibleSize = scrollView.contentView.bounds.size
        #expect(host.bounds.size == NSSize(width: 560, height: 480))
        #expect(document.bounds.width <= visibleSize.width + 1)
        #expect(document.bounds.height > 0)
        if scene == .settingsAchievements {
            #expect(document.bounds.height > visibleSize.height)
            // 滚到内容末端，确认最后一排成就可达，同时窗口保持固定尺寸。
            scrollView.contentView.scroll(to: NSPoint(x: 0, y: document.bounds.maxY - visibleSize.height))
            scrollView.reflectScrolledClipView(scrollView.contentView)
            #expect(scrollView.contentView.bounds.maxY >= document.bounds.maxY - 1)
            #expect(host.bounds.size == NSSize(width: 560, height: 480))
        }
        #expect(fixture.language.restartRequired == (scene == .settingsLanguagePending))
    }

    @Test("560 × 480 休息页的六个开关及单动作提示完整可达", arguments: [false, true], SnapshotAppearance.allCases)
    private func restSettingsFitWindow(onlyWalk: Bool, appearance: SnapshotAppearance) async throws {
        let fixture = try SnapshotFixture(scene: .settingsRest)
        defer { fixture.cleanUp() }
        if onlyWalk {
            for exercise in RestExercise.allCases where exercise != .walk {
                fixture.model.setExercise(exercise, enabled: false)
            }
            #expect(fixture.model.enabledExercises == [.walk])
        }
        let content = fixture.content(for: .settingsRest)
            .defaultAppStorage(fixture.defaults)
            .environment(\.locale, Locale(identifier: SnapshotEnvironment.language))
            .environment(\.colorScheme, appearance.colorScheme)
            .transaction { $0.disablesAnimations = true }
        let host = NSHostingView(rootView: content)
        host.appearance = NSAppearance(named: appearance.name)
        host.frame = NSRect(x: 0, y: 0, width: 560, height: 480)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = host.appearance
        window.contentView = host
        defer { window.close() }
        // 传统滚动条出现后会收窄内容，等待真实可见宽度稳定。
        var lastWidth: CGFloat = -1
        for _ in 0..<10 {
            host.layoutSubtreeIfNeeded()
            await Task.yield()
            host.layoutSubtreeIfNeeded()
            let width = firstScrollView(in: host)?.documentView?.bounds.width ?? 0
            if width == lastWidth { break }
            lastWidth = width
        }

        // 窗口始终固定；内容超高时可滚到底部，让最后一个开关和单动作提示完整可达。
        let scrollView = try #require(firstScrollView(in: host))
        let document = try #require(scrollView.documentView)
        let visibleSize = scrollView.contentView.bounds.size
        #expect(document.bounds.height > 200)
        #expect(document.bounds.width <= visibleSize.width + 1)
        #expect(host.bounds.size == NSSize(width: 560, height: 480))
        let bottomOffset = max(0, document.bounds.maxY - visibleSize.height)
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: bottomOffset))
        scrollView.reflectScrolledClipView(scrollView.contentView)
        #expect(scrollView.contentView.bounds.maxY >= document.bounds.maxY - 1)
        #expect(host.bounds.size == NSSize(width: 560, height: 480))

        // 用实际字号测完整动作名称，为卡片边距、40 点开关和行内间距留足空间，防止中英文截断。
        let availableTitleWidth = visibleSize.width - 44 - Theme.Spacing.card * 2 - 40 - 16
        for exercise in RestExercise.allCases {
            let label = NSHostingView(rootView: Text(verbatim: exercise.title)
                .font(Theme.font(14, .medium))
                .fixedSize(horizontal: true, vertical: false))
            #expect(ceil(label.fittingSize.width) <= availableTitleWidth)
        }
        print("Settings 休息页 \(SnapshotEnvironment.language) \(appearance.rawValue)，\(RestExercise.allCases.count) 个开关，仅走一走=\(onlyWalk)：内容 \(document.bounds.size)，可见 \(visibleSize)")
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
            .environment(\.ringSnapshotRendering, true)
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

#endif
