import SwiftUI

struct MenuContentView: View {
    @ObservedObject var model: EyeBreakModel
    @ObservedObject var launchAtLogin: LaunchAtLogin

    var body: some View {
        VStack(spacing: 18) {
            header
            ring
            controls
            settings
        }
        .padding(18)
        .frame(width: 280)
        .background(Theme.cream)
        .environment(\.colorScheme, .light)
        // 用户可能在系统设置里改过登录项
        .onAppear { launchAtLogin.refresh() }
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
            Toggle(isOn: Binding(get: { launchAtLogin.isEnabled }, set: { launchAtLogin.setEnabled($0) })) {
                Text("开机自启")
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
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.creamDeep.opacity(0.6)))
    }
}
