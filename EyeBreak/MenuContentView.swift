import SwiftUI

struct MenuContentView: View {
    @ObservedObject var model: EyeBreakModel
    @ObservedObject var launchAtLogin: LaunchAtLogin
    @ObservedObject var stats: TomatoStats
    @ObservedObject var sounds: ReminderSounds
    @ObservedObject var updates: AppUpdater
    @ObservedObject var schedule: WorkScheduleSettings
    var openSettings: (Bool) -> Void
    var menuWindowChanged: (NSWindow?) -> Void

    @AppStorage(EyeBreakConfig.showWeekStatsKey) private var showWeekStats = false
    @State private var naturalHeight: CGFloat = 400
    @State private var screenHeight: CGFloat = .greatestFiniteMagnitude

    var body: some View {
        ScrollView(.vertical) {
            MenuBody(model: model, stats: stats, updates: updates, schedule: schedule,
                     showWeekStats: $showWeekStats, openSettings: openSettings)
                // 先让内容按 280 点宽度自由排版，再用外壳限制高度。
                .fixedSize(horizontal: false, vertical: true)
                .background(GeometryReader { proxy in
                    Color.clear.preference(key: MenuHeightKey.self, value: proxy.size.height)
                })
        }
        .scrollIndicators(.never)
        .frame(width: 280, height: min(naturalHeight, screenHeight))
        .background(Theme.cream)
        .background(MenuWindowReader { window in
            menuWindowChanged(window)
            if let screen = window?.screen {
                screenHeight = max(1, screen.visibleFrame.height - 40)
            }
        })
        .onPreferenceChange(MenuHeightKey.self) { height in
            if height > 0 { naturalHeight = ceil(height) }
        }
        .onAppear {
            launchAtLogin.refresh()
            stats.refresh()
        }
    }
}

/// 不含滚动壳的菜单内容，测试直接测量它的自然高度。
struct MenuBody: View {
    @ObservedObject var model: EyeBreakModel
    @ObservedObject var stats: TomatoStats
    @ObservedObject var updates: AppUpdater
    @ObservedObject var schedule: WorkScheduleSettings
    @Binding var showWeekStats: Bool
    var openSettings: (Bool) -> Void
    #if DEBUG
    // 两条时长提示在真实状态下互斥，测试合成最坏排版时同时显示。
    var showsAllPendingHintsForTesting = false
    #endif

    var body: some View {
        VStack(spacing: 12) {
            header
            if let version = updates.availableVersion {
                UpdateBanner(version: version, update: updates.checkForUpdates)
            }
            VStack(spacing: 12) {
                ring
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
                        .accessibilityHint("打开成就墙")
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

    private var ring: some View {
        RingView(remaining: 1 - model.progress, color: phaseColor) {
            VStack(spacing: 2) {
                Text(model.formattedRemaining)
                    .font(Theme.font(36, .bold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.ink)
                Text(status)
                    .font(Theme.font(13, .medium))
                    .foregroundStyle(statusColor)
                if model.phase == .offHours {
                    Text(verbatim: schedule.schedule.rangeText + (schedule.schedule.weekdaysOnly ? " · " + String(localized: "工作日") : ""))
                        .font(Theme.font(11))
                        .foregroundStyle(Theme.inkSoft)
                }
                if let test = EyeBreakConfig.testWorkInterval, model.workInterval == test {
                    Text("测试 \(Int(test)) 秒")
                        .font(Theme.font(11))
                        .foregroundStyle(Theme.inkSoft)
                }
            }
        }
        .frame(width: 156, height: 156)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(status)，剩余 \(model.remainingSeconds / 60) 分 \(model.remainingSeconds % 60) 秒"))
    }

    private var status: String {
        switch model.phase {
        case .idle: return String(localized: "准备好了吗")
        case .working:
            switch model.deferReason {
            case .meeting: return String(localized: "会议结束后提醒")
            case .fullscreen: return String(localized: "退出全屏后提醒")
            case .focus: return String(localized: "专注模式结束后提醒")
            case nil: break
            }
            return model.isSnoozing ? String(localized: "稍后提醒") : String(localized: "专注中")
        case .paused: return String(localized: "已暂停")
        case .awaitingBreak: return String(localized: "该休息啦")
        case .resting: return String(localized: "休息中")
        case .away: return String(localized: "离开中")
        case .offHours: return String(localized: "工作时段外")
        }
    }

    private var phaseColor: Color {
        switch model.phase {
        case .working, .awaitingBreak: return Theme.tomato
        case .resting: return Theme.leaf
        case .idle, .paused, .away, .offHours: return Theme.tomatoSoft
        }
    }

    private var statusColor: Color {
        [.idle, .paused, .away, .offHours].contains(model.phase) ? Theme.inkSoft : phaseColor
    }

    private var controls: some View {
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
        HStack(spacing: 0) {
            ForEach(ReminderSound.allCases) { option in
                let isSelected = option == selection
                Button {
                    onSelect(option)
                } label: {
                    Text(verbatim: option.title)
                        .font(Theme.font(12, .semibold))
                        .foregroundStyle(isSelected ? .white : Theme.ink)
                        .frame(maxWidth: .infinity)
                        .frame(height: Theme.smallControlSize - Theme.Spacing.segmented * 2)
                        .background(
                            RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous)
                                .fill(isSelected ? Theme.tomatoFill : .clear)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(Theme.Spacing.segmented)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.segmented, style: .continuous)
                .fill(Theme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.segmented, style: .continuous)
                .strokeBorder(Theme.creamDeep, lineWidth: 1)
        )
        .animation(.easeOut(duration: 0.15), value: selection)
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
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
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
