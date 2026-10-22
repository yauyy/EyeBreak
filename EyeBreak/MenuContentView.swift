import Combine
import SwiftUI

struct MenuContentView: View {
    // 外壳只负责窗口和自然高度，不随每秒倒计时重新测量。
    let model: EyeBreakModel
    let launchAtLogin: LaunchAtLogin
    let stats: TomatoStats
    let sounds: ReminderSounds
    let updates: AppUpdater
    let schedule: WorkScheduleSettings
    var openSettings: (Bool) -> Void
    var menuWindowChanged: (NSWindow?) -> Void
    // 窗口测试覆盖可用高度，默认仍跟随菜单所在屏幕。
    var heightLimitOverride: CGFloat? = nil

    @AppStorage(EyeBreakConfig.showWeekStatsKey) private var showWeekStats = false
    @State private var naturalHeight: CGFloat?
    @State private var screenHeight: CGFloat = .greatestFiniteMagnitude
    @StateObject private var visibility = MenuWindowVisibility()

    var body: some View {
        ScrollView(.vertical) {
            MenuBody(model: model, stats: stats, updates: updates, schedule: schedule,
                     showWeekStats: $showWeekStats, openSettings: openSettings,
                     windowVisibility: visibility)
                // 先让内容按 280 点宽度自由排版，再用外壳限制高度。
                .frame(width: 280)
                .fixedSize(horizontal: false, vertical: true)
                .background(GeometryReader { proxy in
                    Color.clear.preference(key: MenuHeightKey.self, value: proxy.size.height)
                })
                .onPreferenceChange(MenuHeightKey.self) { height in
                    if height > 0 { naturalHeight = ceil(height) }
                }
        }
        .scrollIndicators(.never)
        // 首次测量前不指定高度，避免先显示任意占位高度再跳到内容高度。
        .frame(width: 280, height: naturalHeight.map { min($0, heightLimitOverride ?? screenHeight) })
        .background(Theme.cream)
        .background(MenuWindowReader { window in
            visibility.track(window)
            menuWindowChanged(window)
            if let screen = window?.screen {
                screenHeight = max(1, screen.visibleFrame.height - 40)
            }
        })
        .onAppear {
            launchAtLogin.refresh()
            stats.refresh()
        }
    }
}

/// 不含滚动壳的菜单内容，测试直接测量它的自然高度。
struct MenuBody: View {
    @StateObject private var modelChanges: MenuModelChanges
    var model: EyeBreakModel { modelChanges.model }
    @ObservedObject var stats: TomatoStats
    @ObservedObject var updates: AppUpdater
    @ObservedObject var schedule: WorkScheduleSettings
    @Binding var showWeekStats: Bool
    var openSettings: (Bool) -> Void
    var windowVisibility: MenuWindowVisibility?
    #if DEBUG
    // 两条时长提示在真实状态下互斥，测试合成最坏排版时同时显示。
    var showsAllPendingHintsForTesting = false
    #endif

    init(
        model: EyeBreakModel, stats: TomatoStats, updates: AppUpdater,
        schedule: WorkScheduleSettings, showWeekStats: Binding<Bool>,
        openSettings: @escaping (Bool) -> Void, windowVisibility: MenuWindowVisibility? = nil
    ) {
        _modelChanges = StateObject(wrappedValue: MenuModelChanges(model: model))
        self.stats = stats
        self.updates = updates
        self.schedule = schedule
        _showWeekStats = showWeekStats
        self.openSettings = openSettings
        self.windowVisibility = windowVisibility
    }

    #if DEBUG
    init(
        model: EyeBreakModel, stats: TomatoStats, updates: AppUpdater,
        schedule: WorkScheduleSettings, showWeekStats: Binding<Bool>,
        openSettings: @escaping (Bool) -> Void, showsAllPendingHintsForTesting: Bool
    ) {
        self.init(model: model, stats: stats, updates: updates, schedule: schedule,
                  showWeekStats: showWeekStats, openSettings: openSettings)
        self.showsAllPendingHintsForTesting = showsAllPendingHintsForTesting
    }
    #endif

    var body: some View {
        VStack(spacing: 12) {
            header
            if let version = updates.availableVersion {
                UpdateBanner(version: version, update: updates.checkForUpdates)
            }
            VStack(spacing: 12) {
                MenuCountdownRing(model: model, schedule: schedule, windowVisibility: windowVisibility)
                Button { showWeekStats.toggle() } label: {
                    HStack(spacing: 6) {
                        TomatoTally(today: stats.today, streak: stats.streak)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Theme.inkSoft)
                            .rotationEffect(.degrees(showWeekStats ? 180 : 0))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("查看本周番茄")
                if showWeekStats {
                    VStack(spacing: 6) {
                        WeekChart(days: stats.lastSevenDays)
                        Button { openSettings(true) } label: {
                            HStack {
                                Text("成就 \(stats.unlocked.count)/\(Achievement.allCases.count)")
                                Spacer()
                                Image(systemName: "chevron.right").accessibilityHidden(true)
                            }
                            .font(Theme.font(12, .semibold))
                            .foregroundStyle(Theme.inkSoft)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("打开成就页")
                    }
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: Theme.Radius.card).fill(Theme.creamDeep.opacity(0.6)))
                }
            }
            controls
            settings
            VersionFooter(updates: updates) { openSettings(false) }
        }
        .padding(16)
        .frame(width: 280)
        .background(Theme.cream)
    }

    private var header: some View {
        HStack(spacing: 8) {
            TomatoAvatar(size: 28)
            Text("EyeBreak")
                .font(Theme.font(15, .bold))
                .foregroundStyle(Theme.ink)
            Spacer()
            Button("退出") { NSApp.terminate(nil) }
                .buttonStyle(PillButtonStyle(kind: .plain))
                .keyboardShortcut("q")
        }
    }

    private var controls: some View {
        VStack(spacing: 10) {
            controlButtons
            if model.phase == .paused {
                // 暂停后才出现：顺手选一个自动继续的时刻，不用记得回来点「继续」
                TimedPauseRow(model: model)
            }
        }
    }

    private var controlButtons: some View {
        HStack(spacing: 10) {
            switch model.phase {
            case .offHours:
                Button("仍要开始", action: model.start)
                    .buttonStyle(PillButtonStyle(kind: .secondary))
            case .idle, .away:
                Button("开始", action: model.start)
                    .buttonStyle(PillButtonStyle())
                    .keyboardShortcut(.defaultAction)
            case .working where model.deferReason != nil:
                // 推迟时保留一行操作，优先提供立即休息入口。
                Button("暂停", action: model.pause)
                    .buttonStyle(PillButtonStyle(kind: .secondary))
                Button("现在休息", action: model.startBreakNow)
                    .buttonStyle(PillButtonStyle())
                    .keyboardShortcut(.defaultAction)
            case .working, .paused:
                Button("重来", action: model.reset)
                    .buttonStyle(PillButtonStyle(kind: .secondary))
                Button(model.phase == .working ? "暂停" : "继续", action: model.toggle)
                    .buttonStyle(PillButtonStyle())
                    .keyboardShortcut(.defaultAction)
            case .awaitingBreak:
                BreakChoices(model: model)
            case .resting:
                Button("提前结束", action: model.skipBreak)
                    .buttonStyle(PillButtonStyle(kind: .secondary))
            }
        }
    }

    private var workHintVisible: Bool {
        #if DEBUG
        if showsAllPendingHintsForTesting { return true }
        #endif
        return model.workIntervalChangePending
    }

    private var restHintVisible: Bool {
        #if DEBUG
        if showsAllPendingHintsForTesting { return true }
        #endif
        return model.restDurationChangePending
    }

    private var settings: some View {
        VStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                CuteStepper(
                    title: "专注", unit: String(localized: "分钟"),
                    value: Binding(
                        get: { Int(model.workInterval / 60) },
                        set: { model.setWorkInterval(TimeInterval($0 * 60)) }
                    ),
                    range: EyeBreakConfig.workMinutesRange, step: 5
                )
                if workHintVisible {
                    Text("下一轮生效")
                        .font(Theme.font(11))
                        .foregroundStyle(Theme.inkSoft)
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                CuteStepper(
                    title: "眺望", unit: String(localized: "秒"),
                    value: Binding(
                        get: { Int(model.restDuration) },
                        set: { model.setRestDuration(TimeInterval($0)) }
                    ),
                    range: EyeBreakConfig.restSecondsRange, step: 5
                )
                if restHintVisible {
                    Text("下次休息生效")
                        .font(Theme.font(11))
                        .foregroundStyle(Theme.inkSoft)
                }
            }
        }
        .padding(Theme.Spacing.card)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).fill(Theme.creamDeep.opacity(0.6)))
    }
}

/// 仅把影响菜单布局和操作的状态变化传给主体；秒数只由圆环区域观察。
@MainActor
final class MenuModelChanges: ObservableObject {
    let model: EyeBreakModel
    @Published private var revision = 0
    private var cancellables: Set<AnyCancellable> = []

    init(model: EyeBreakModel) {
        self.model = model
        Publishers.MergeMany([
            // 同一专注阶段「重来」也会改变本轮总时长，不能过滤重复的 phase。
            model.$phase.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            model.$deferReason.removeDuplicates().dropFirst().map { _ in () }.eraseToAnyPublisher(),
            model.$isSnoozing.removeDuplicates().dropFirst().map { _ in () }.eraseToAnyPublisher(),
            model.$workInterval.removeDuplicates().dropFirst().map { _ in () }.eraseToAnyPublisher(),
            model.$restDuration.removeDuplicates().dropFirst().map { _ in () }.eraseToAnyPublisher(),
            model.$timedPause.removeDuplicates().dropFirst().map { _ in () }.eraseToAnyPublisher()
        ])
        .sink { [weak self] in self?.revision &+= 1 }
        .store(in: &cancellables)
    }
}

/// 菜单隐藏后取消整个模型订阅，并保留最后一帧；菜单栏标签仍使用自己的秒数订阅。
@MainActor
final class MenuCountdownState: ObservableObject {
    struct Snapshot: Equatable {
        let phase: EyeBreakModel.Phase
        let remainingSeconds: Int
        let remaining: Double
        let duration: TimeInterval
        let workInterval: TimeInterval
        let deferReason: EyeBreakModel.DeferReason?
        let isSnoozing: Bool
        let isLongBreak: Bool
        /// 定时暂停时显示的「几点继续」
        let resumeText: String?

        @MainActor init(model: EyeBreakModel) {
            phase = model.phase
            remainingSeconds = model.remainingSeconds
            remaining = 1 - model.progress
            duration = model.phase == .resting ? model.currentBreakDuration : model.currentRoundTotal
            workInterval = model.workInterval
            deferReason = model.deferReason
            isSnoozing = model.isSnoozing
            isLongBreak = model.isLongBreak
            resumeText = model.timedPauseResumeText
        }
    }

    @Published private(set) var isVisible: Bool
    private(set) var activationID = 0
    private let model: EyeBreakModel
    private var frozenSnapshot: Snapshot
    private var subscription: AnyCancellable?
    private var visibilitySubscription: AnyCancellable?

    var snapshot: Snapshot { isVisible ? Snapshot(model: model) : frozenSnapshot }

    init(model: EyeBreakModel, isVisible: Bool) {
        self.model = model
        self.isVisible = isVisible
        frozenSnapshot = Snapshot(model: model)
        if isVisible { observeModel() }
    }

    convenience init(model: EyeBreakModel, windowVisibility: MenuWindowVisibility?) {
        self.init(model: model, isVisible: windowVisibility?.isVisible ?? true)
        // 直接响应宿主通知，不依赖隐藏 SwiftUI 视图是否及时执行 body 或 onChange。
        visibilitySubscription = windowVisibility?.$isVisible.removeDuplicates().sink { [weak self] visible in
            MainActor.assumeIsolated { self?.setVisible(visible) }
        }
    }

    func setVisible(_ visible: Bool) {
        guard isVisible != visible else { return }
        if !visible {
            frozenSnapshot = Snapshot(model: model)
            subscription = nil
        } else {
            activationID &+= 1
        }
        isVisible = visible
        if visible { observeModel() }
    }

    private func observeModel() {
        // 转发 willChange，让 SwiftUI 在本轮修改完成后读取一致快照，避免读取 @Published 的旧值。
        subscription = model.objectWillChange.sink { [weak self] in
            MainActor.assumeIsolated { self?.objectWillChange.send() }
        }
    }
}

/// 每秒变化限制在固定尺寸的圆环和文字内，不重建菜单操作、统计或高度测量外壳。
private struct MenuCountdownRing: View {
    @StateObject private var countdown: MenuCountdownState
    @ObservedObject var schedule: WorkScheduleSettings

    init(model: EyeBreakModel, schedule: WorkScheduleSettings, windowVisibility: MenuWindowVisibility?) {
        _countdown = StateObject(wrappedValue: MenuCountdownState(model: model, windowVisibility: windowVisibility))
        self.schedule = schedule
    }

    private var snapshot: MenuCountdownState.Snapshot { countdown.snapshot }

    var body: some View {
        RingView(
            remaining: snapshot.remaining, color: phaseColor, phase: snapshot.phase,
            duration: snapshot.duration, isActive: countdown.isVisible, animationResetID: countdown.activationID
        ) {
            VStack(spacing: 2) {
                Text(String(format: "%02d:%02d", snapshot.remainingSeconds / 60, snapshot.remainingSeconds % 60))
                    .font(Theme.font(36, .bold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.ink)
                Text(status)
                    .font(Theme.font(13, .medium))
                    .foregroundStyle(statusColor)
                if snapshot.phase == .offHours {
                    Text(verbatim: schedule.schedule.rangeText + (schedule.schedule.weekdaysOnly ? " · " + String(localized: "工作日") : ""))
                        .font(Theme.font(11))
                        .foregroundStyle(Theme.inkSoft)
                }
                if let resumeText = snapshot.resumeText {
                    Text(verbatim: resumeText)
                        .font(Theme.font(11))
                        .foregroundStyle(Theme.inkSoft)
                }
                if let test = EyeBreakConfig.testWorkInterval, snapshot.workInterval == test {
                    Text("测试 \(Int(test)) 秒")
                        .font(Theme.font(11))
                        .foregroundStyle(Theme.inkSoft)
                }
            }
        }
        .frame(width: 156, height: 156)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(status)，剩余 \(snapshot.remainingSeconds / 60) 分 \(snapshot.remainingSeconds % 60) 秒"))
    }

    private var status: String {
        switch snapshot.phase {
        case .idle: return String(localized: "准备好了吗")
        case .working:
            switch snapshot.deferReason {
            case .meeting: return String(localized: "会议结束后提醒")
            case .fullscreen: return String(localized: "退出全屏后提醒")
            case .focus: return String(localized: "专注模式结束后提醒")
            case nil: break
            }
            return snapshot.isSnoozing ? String(localized: "稍后提醒") : String(localized: "专注中")
        case .paused: return String(localized: "已暂停")
        case .awaitingBreak: return snapshot.isLongBreak ? String(localized: "该活动啦") : String(localized: "该休息啦")
        case .resting: return snapshot.isLongBreak ? String(localized: "长休息中") : String(localized: "休息中")
        case .away: return String(localized: "离开中")
        case .offHours: return String(localized: "工作时段外")
        }
    }

    private var phaseColor: Color {
        switch snapshot.phase {
        case .working, .awaitingBreak: return Theme.tomato
        case .resting: return Theme.leaf
        case .idle, .paused, .away, .offHours: return Theme.tomatoSoft
        }
    }

    private var statusColor: Color {
        [.idle, .paused, .away, .offHours].contains(snapshot.phase) ? Theme.inkSoft : phaseColor
    }

}

/// 暂停后的「自动继续」选项：选中的胶囊高亮，再点一次取消自动继续。英文放不下时换成两行。
private struct TimedPauseRow: View {
    let model: EyeBreakModel

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 6) {
                label
                Spacer(minLength: 4)
                options
            }
            VStack(alignment: .leading, spacing: 6) {
                label
                options
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var label: some View {
        Text("自动继续")
            .font(Theme.font(12))
            .foregroundStyle(Theme.inkSoft)
            .fixedSize()
    }

    private var options: some View {
        HStack(spacing: 5) {
            ForEach(TimedPause.allCases, id: \.self) { option in
                let selected = model.timedPause == option
                Button {
                    if selected { model.cancelTimedPause() } else { model.pause(for: option) }
                } label: {
                    Text(verbatim: option.title)
                        .font(Theme.font(11, .semibold))
                        .lineLimit(1)
                        .fixedSize()
                        .foregroundStyle(selected ? .white : Theme.inkSoft)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(selected ? Theme.tomatoFill : Theme.ink.opacity(0.07)))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("自动继续：\(option.title)"))
                .accessibilityHint(selected ? Text("取消自动继续") : Text(""))
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }
}

/// 今日收集的番茄：最多画 8 个小番茄，多出来的用 +N 表示
private struct TomatoTally: View {
    let today: Int
    let streak: Int
    private let maxIcons = 8

    var body: some View {
        HStack(spacing: 6) {
            if today == 0 {
                Text("休息一次，收集今天的第一个番茄")
                    .font(Theme.font(12))
                    .foregroundStyle(Theme.inkSoft)
            } else {
                HStack(spacing: -3) {
                    ForEach(0..<min(today, maxIcons), id: \.self) { _ in
                        TomatoAvatar(size: 18)
                    }
                }
                if today > maxIcons {
                    Text("+\(today - maxIcons)")
                        .font(Theme.font(12, .semibold))
                        .foregroundStyle(Theme.tomato)
                }
            }
            if streak > 1 {
                Text("连续 \(streak) 天")
                    .font(Theme.font(12, .semibold))
                    .foregroundStyle(Theme.leaf)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Theme.leaf.opacity(0.12)))
            }
        }
        .frame(height: 20)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("今天收集了 \(today) 个番茄，连续 \(streak) 天")
    }
}

/// 提示音选择：macOS 分段控件样式，选中项为番茄红。外框圆角 8 = 选项圆角 6 + 内边距 2
struct SoundPicker: View {
    let selection: ReminderSound
    let onSelect: (ReminderSound) -> Void

    var body: some View {
        TomatoSegmentedPicker(
            options: ReminderSound.allCases, selection: selection,
            title: { $0.title }, onSelect: onSelect
        )
    }
}

/// 有新版本时出现在菜单顶部的提示条
private struct UpdateBanner: View {
    let version: String
    let update: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Text("有新版本 \(version)")
                .font(Theme.font(13, .semibold))
                .foregroundStyle(Theme.ink)
            Spacer()
            Button("更新", action: update)
                .buttonStyle(PillButtonStyle())
                .fixedSize()
        }
        .padding(.leading, 12)
        .padding([.vertical, .trailing], 4)
        .background(
            // 外框圆角 12 = 按钮圆角 8 + 内边距 4
            RoundedRectangle(cornerRadius: Theme.Radius.control + 4, style: .continuous)
                .fill(Theme.tomato.opacity(0.1))
        )
    }
}

/// 窄菜单中优先同行显示，英文放不下时让版本号独占一行。
private struct VersionFooter: View {
    @ObservedObject var updates: AppUpdater
    var openSettings: () -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 4) {
                version
                Spacer(minLength: 0)
                actions
            }
            VStack(spacing: 2) {
                version.frame(maxWidth: .infinity, alignment: .leading)
                HStack { Spacer(); actions }
            }
        }
    }

    private var version: some View {
        Text("版本 \(updates.currentVersion)")
            .font(Theme.font(12))
            .foregroundStyle(Theme.inkSoft)
            .fixedSize()
    }

    private var actions: some View {
        HStack(spacing: 4) {
            Button("设置…", action: openSettings)
                .buttonStyle(PillButtonStyle(kind: .plain, small: true))
            if updates.isConfigured {
                Button("检查更新", action: updates.checkForUpdates)
                    .buttonStyle(PillButtonStyle(kind: .plain, small: true))
                    .disabled(!updates.canCheckForUpdates)
            }
        }
        .fixedSize()
    }
}

/// 最近 7 天的番茄柱状图：今天是番茄红，其他天是浅色
private struct WeekChart: View {
    let days: [TomatoStats.Day]
    private let maxBarHeight: CGFloat = 28

    var body: some View {
        let peak = max(days.map(\.count).max() ?? 0, 1)
        HStack(alignment: .bottom, spacing: 8) {
            ForEach(days) { day in
                VStack(spacing: 4) {
                    Text(day.count > 0 ? "\(day.count)" : " ")
                        .font(Theme.font(10, .semibold))
                        .monospacedDigit()
                        .foregroundStyle(day.isToday ? Theme.tomato : Theme.inkSoft)
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(barColor(day))
                        .frame(height: max(4, maxBarHeight * CGFloat(day.count) / CGFloat(peak)))
                    Text(verbatim: day.isToday ? String(localized: "今") : Self.weekdayLabel(day.weekday))
                        .font(Theme.font(11, day.isToday ? .semibold : .regular))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .foregroundStyle(day.isToday ? Theme.ink : Theme.inkSoft)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("最近 7 天共收集 \(days.map(\.count).reduce(0, +)) 个番茄")

    }

    private func barColor(_ day: TomatoStats.Day) -> Color {
        if day.count == 0 { return Theme.ink.opacity(0.08) }
        return day.isToday ? Theme.tomato : Theme.tomatoSoft
    }

    /// 公历 weekday：1 是周日
    static func weekdayLabel(_ weekday: Int) -> String {
        [String(localized: "日"), String(localized: "一"), String(localized: "二"), String(localized: "三"), String(localized: "四"), String(localized: "五"), String(localized: "六")][(weekday - 1 + 7) % 7]
    }
}

private struct MenuHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

/// orderOut 会保留菜单宿主，必须读取实际遮挡状态，不能用 SwiftUI 的 onDisappear 判断。
@MainActor
final class MenuWindowVisibility: NSObject, ObservableObject {
    @Published private(set) var isVisible = false
    private weak var window: NSWindow?

    func track(_ window: NSWindow?) {
        guard self.window !== window else {
            refresh()
            return
        }
        NotificationCenter.default.removeObserver(self)
        self.window = window
        if let window {
            for name in [
                NSWindow.didChangeOcclusionStateNotification,
                NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification,
                NSWindow.didMiniaturizeNotification, NSWindow.didDeminiaturizeNotification,
                NSWindow.didExposeNotification
            ] {
                NotificationCenter.default.addObserver(self, selector: #selector(refresh), name: name, object: window)
            }
            NotificationCenter.default.addObserver(
                self, selector: #selector(windowWillClose), name: NSWindow.willCloseNotification, object: window
            )
        }
        refresh()
    }

    @objc private func refresh() {
        let visible = window.map { $0.isVisible && $0.occlusionState.contains(.visible) } ?? false
        if visible != isVisible { isVisible = visible }
    }

    @objc private func windowWillClose() {
        if isVisible { isVisible = false }
    }

    deinit { NotificationCenter.default.removeObserver(self) }
}

/// 从实际宿主窗口读取屏幕；切换显示器、改变屏幕排列后重新计算可用高度。
private struct MenuWindowReader: NSViewRepresentable {
    var onChange: (NSWindow?) -> Void

    func makeNSView(context: Context) -> ScreenObserverView {
        let view = ScreenObserverView()
        view.onChange = onChange
        return view
    }

    func updateNSView(_ nsView: ScreenObserverView, context: Context) {
        nsView.onChange = onChange
    }

    final class ScreenObserverView: NSView {
        var onChange: ((NSWindow?) -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            NotificationCenter.default.removeObserver(self)
            if let window {
                NotificationCenter.default.addObserver(self, selector: #selector(screenChanged), name: NSWindow.didChangeScreenNotification, object: window)
                NotificationCenter.default.addObserver(self, selector: #selector(screenChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)
            }
            // 避开 SwiftUI 更新视图的调用栈，再写入测量状态。
            DispatchQueue.main.async { [weak self] in self?.screenChanged() }
        }

        @objc private func screenChanged() { onChange?(window) }
        deinit { NotificationCenter.default.removeObserver(self) }
    }
}
