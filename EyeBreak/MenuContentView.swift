import SwiftUI

struct MenuContentView: View {
    @ObservedObject var model: EyeBreakModel
    @ObservedObject var launchAtLogin: LaunchAtLogin
    @ObservedObject var stats: TomatoStats
    @ObservedObject var sounds: ReminderSounds
    @ObservedObject var updates: UpdateChecker

    var body: some View {
        VStack(spacing: 18) {
            header
            if let release = updates.available {
                UpdateBanner(version: release.version, download: updates.openDownloadPage)
            }
            VStack(spacing: 10) {
                ring
                TomatoTally(today: stats.today, streak: stats.streak)
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
            if model.isDeferredForMeeting { return "会议结束后提醒" }
            return model.isSnoozing ? "稍后提醒" : "专注中"
        case .paused: return "已暂停"
        case .awaitingBreak: return "该休息啦"
        case .resting: return "休息中"
        case .away: return "离开中"
        }
    }

    private var phaseColor: Color {
        switch model.phase {
        case .working, .awaitingBreak: return Theme.tomato
        case .resting: return Theme.leaf
        case .idle, .paused, .away: return Theme.tomatoSoft
        }
    }

    private var statusColor: Color {
        [.idle, .paused, .away].contains(model.phase) ? Theme.inkSoft : phaseColor
    }

    private var controls: some View {
        HStack(spacing: 10) {
            switch model.phase {
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
            VStack(alignment: .leading, spacing: 8) {
                Text("提示音")
                    .font(Theme.font(14, .medium))
                    .foregroundStyle(Theme.ink)
                SoundPicker(selection: sounds.choice) { option in
                    sounds.choice = option
                    sounds.preview(option)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Toggle(isOn: Binding(get: { launchAtLogin.isEnabled }, set: { launchAtLogin.setEnabled($0) })) {
                Text("开机自启")
                    .font(Theme.font(14, .medium))
                    .foregroundStyle(Theme.ink)
            }
            .toggleStyle(CuteToggleStyle())
            Toggle(isOn: $updates.automaticChecks) {
                Text("自动检查更新")
                    .font(Theme.font(14, .medium))
                    .foregroundStyle(Theme.ink)
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
    let download: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Text("有新版本 \(version)")
                .font(Theme.font(13, .semibold))
                .foregroundStyle(Theme.ink)
            Spacer()
            Button("下载", action: download)
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
    @ObservedObject var updates: UpdateChecker

    var body: some View {
        HStack {
            Text("版本 \(updates.currentVersion)")
                .font(Theme.font(12))
                .foregroundStyle(Theme.inkSoft)
            Spacer()
            Button(title) {
                Task { await updates.check() }
            }
            .buttonStyle(PillButtonStyle(kind: .plain))
            .disabled(updates.status == .checking)
        }
    }

    private var title: String {
        switch updates.status {
        case .idle: return "检查更新"
        case .checking: return "检查中…"
        case .upToDate: return updates.available == nil ? "已是最新版本" : "检查更新"
        case .failed: return "检查失败，点此重试"
        }
    }
}
