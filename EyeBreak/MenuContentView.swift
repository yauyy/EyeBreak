import SwiftUI

struct MenuContentView: View {
    @ObservedObject var model: EyeBreakModel
    @ObservedObject var launchAtLogin: LaunchAtLogin
    @ObservedObject var stats: TomatoStats
    @ObservedObject var sounds: ReminderSounds
    @ObservedObject var updates: AppUpdater
    @ObservedObject var schedule: WorkScheduleSettings

    var body: some View {
        VStack(spacing: 18) {
            header
            if let version = updates.availableVersion {
                UpdateBanner(version: version, update: updates.checkForUpdates)
            }
            VStack(spacing: 10) {
                ring
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { showWeekStats.toggle() }
                } label: {
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
                    WeekChart(days: stats.lastSevenDays, unlocked: stats.unlocked)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            controls
            settings
            VersionFooter(updates: updates)
        }
        .padding(18)
        .frame(width: 280)
        .background(Theme.cream)
        .environment(\.colorScheme, .light)
        // 用户可能在系统设置里改过登录项
        .onAppear {
            launchAtLogin.refresh()
            stats.refresh()
        }
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
                    Text(schedule.schedule.rangeText + (schedule.schedule.weekdaysOnly ? " · 工作日" : ""))
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
        .accessibilityElement(children: .combine)
    }

    private var status: String {
        switch model.phase {
        case .idle: return "准备好了吗"
        case .working:
            switch model.deferReason {
            case .meeting: return "会议结束后提醒"
            case .fullscreen: return "退出全屏后提醒"
            case nil: break
            }
            return model.isSnoozing ? "稍后提醒" : "专注中"
        case .paused: return "已暂停"
        case .awaitingBreak: return "该休息啦"
        case .resting: return "休息中"
        case .away: return "离开中"
        case .offHours: return "工作时段外"
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

    @AppStorage(EyeBreakConfig.showMoreSettingsKey) private var showMoreSettings = false
    @AppStorage(EyeBreakConfig.showWeekStatsKey) private var showWeekStats = false
    @AppStorage(EyeBreakConfig.showMenuBarTimeKey) private var showMenuBarTime = false

    private var settings: some View {
        VStack(spacing: 10) {
            CuteStepper(
                title: "专注", unit: "分钟",
                value: Binding(
                    get: { Int(model.workInterval / 60) },
                    set: { model.setWorkInterval(TimeInterval($0 * 60)) }
                ),
                range: EyeBreakConfig.workMinutesRange, step: 5
            )
            CuteStepper(
                title: "眺望", unit: "秒",
                value: Binding(
                    get: { Int(model.restDuration) },
                    set: { model.setRestDuration(TimeInterval($0)) }
                ),
                range: EyeBreakConfig.restSecondsRange, step: 5
            )

            Button {
                withAnimation(.easeInOut(duration: 0.2)) { showMoreSettings.toggle() }
            } label: {
                HStack {
                    Text("更多设置")
                        .font(Theme.font(13, .medium))
                        .foregroundStyle(Theme.inkSoft)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Theme.inkSoft)
                        .rotationEffect(.degrees(showMoreSettings ? 180 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.top, 2)

            if showMoreSettings {
                moreSettings
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(Theme.Spacing.card)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).fill(Theme.creamDeep.opacity(0.6)))
    }

    @ViewBuilder
    private var moreSettings: some View {
        VStack(alignment: .leading, spacing: 8) {
            settingTitle("提示音")
            SoundPicker(selection: sounds.choice) { option in
                sounds.choice = option
                sounds.preview(option)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        Toggle(isOn: $showMenuBarTime) { settingTitle("菜单栏显示倒计时") }
            .toggleStyle(CuteToggleStyle())
        Toggle(isOn: Binding(get: { launchAtLogin.isEnabled }, set: { launchAtLogin.setEnabled($0) })) {
            settingTitle("开机自启")
        }
        .toggleStyle(CuteToggleStyle())
        if launchAtLogin.needsApproval || launchAtLogin.failed {
            HStack {
                Text(launchAtLogin.failed ? "设置失败，可在系统设置里手动添加" : "需要在系统设置里允许")
                    .font(Theme.font(12))
                    .foregroundStyle(Theme.inkSoft)
                Spacer()
                Button("去设置", action: launchAtLogin.openLoginItemsSettings)
                    .buttonStyle(PillButtonStyle(kind: .plain))
            }
        }
        if updates.isConfigured {
            Toggle(isOn: $updates.automaticChecks) { settingTitle("自动检查更新") }
                .toggleStyle(CuteToggleStyle())
        }
        Toggle(isOn: $schedule.schedule.isEnabled) { settingTitle("只在工作时段提醒") }
            .toggleStyle(CuteToggleStyle())
        if schedule.schedule.isEnabled {
            CuteStepper(title: "开始", unit: "点", value: $schedule.schedule.startHour, range: WorkSchedule.hourRange, step: 1)
            CuteStepper(title: "结束", unit: "点", value: $schedule.schedule.endHour, range: WorkSchedule.hourRange, step: 1)
            Toggle(isOn: $schedule.schedule.weekdaysOnly) { settingTitle("仅工作日") }
                .toggleStyle(CuteToggleStyle())
        }
    }

    private func settingTitle(_ title: String) -> some View {
        Text(title)
            .font(Theme.font(14, .medium))
            .foregroundStyle(Theme.ink)
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
private struct SoundPicker: View {
    let selection: ReminderSound
    let onSelect: (ReminderSound) -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(ReminderSound.allCases) { option in
                let isSelected = option == selection
                Button {
                    onSelect(option)
                } label: {
                    Text(option.title)
                        .font(Theme.font(12, .semibold))
                        .foregroundStyle(isSelected ? .white : Theme.ink)
                        .frame(maxWidth: .infinity)
                        .frame(height: Theme.smallControlSize - Theme.Spacing.segmented * 2)
                        .background(
                            RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous)
                                .fill(isSelected ? Theme.tomato : .clear)
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
                .fill(.white)
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

/// 菜单底部：当前版本号与手动检查更新
private struct VersionFooter: View {
    @ObservedObject var updates: AppUpdater

    var body: some View {
        HStack {
            Text("版本 \(updates.currentVersion)")
                .font(Theme.font(12))
                .foregroundStyle(Theme.inkSoft)
            Spacer()
            Button("反馈") { NSWorkspace.shared.open(AppLinks.newIssue()) }
                .buttonStyle(PillButtonStyle(kind: .plain))
                .help("在 GitHub 上反馈问题")
            if let notices = AppLinks.thirdPartyNotices {
                Button("许可") { NSWorkspace.shared.open(notices) }
                    .buttonStyle(PillButtonStyle(kind: .plain))
                    .help("查看开源许可")
            }
            if updates.isConfigured {
                Button("检查更新", action: updates.checkForUpdates)
                    .buttonStyle(PillButtonStyle(kind: .plain))
                    .disabled(!updates.canCheckForUpdates)
            }
        }
    }
}

/// 最近 7 天的番茄柱状图：今天是番茄红，其他天是浅色
private struct WeekChart: View {
    let days: [TomatoStats.Day]
    let unlocked: Set<Achievement>
    private let maxBarHeight: CGFloat = 44

    var body: some View {
        let peak = max(days.map(\.count).max() ?? 0, 1)
        VStack(alignment: .leading, spacing: 12) {
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
                    Text(day.isToday ? "今" : Self.weekdayLabel(day.weekday))
                        .font(Theme.font(11, day.isToday ? .semibold : .regular))
                        .foregroundStyle(day.isToday ? Theme.ink : Theme.inkSoft)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("最近 7 天共收集 \(days.map(\.count).reduce(0, +)) 个番茄")

        VStack(alignment: .leading, spacing: 6) {
            Text("成就 \(unlocked.count)/\(Achievement.allCases.count)")
                .font(Theme.font(12, .semibold))
                .foregroundStyle(Theme.inkSoft)
            FlowLayout(spacing: 5) {
                ForEach(Achievement.allCases) { achievement in
                    let earned = unlocked.contains(achievement)
                    Text(achievement.title)
                        .font(Theme.font(11, .semibold))
                        .foregroundStyle(earned ? .white : Theme.inkSoft)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(earned ? Theme.tomato : Theme.ink.opacity(0.07)))
                        .accessibilityLabel(earned ? "已解锁：\(achievement.title)" : "未解锁：\(achievement.title)")
                }
            }
        }
        }
        .padding(Theme.Spacing.card)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).fill(Theme.creamDeep.opacity(0.6)))
    }

    private func barColor(_ day: TomatoStats.Day) -> Color {
        if day.count == 0 { return Theme.ink.opacity(0.08) }
        return day.isToday ? Theme.tomato : Theme.tomatoSoft
    }

    /// 公历 weekday：1 是周日
    static func weekdayLabel(_ weekday: Int) -> String {
        ["日", "一", "二", "三", "四", "五", "六"][(weekday - 1 + 7) % 7]
    }
}
