import SwiftUI

struct MenuContentView: View {
    @ObservedObject var model: EyeBreakModel
    @ObservedObject var notifications: NotificationService

    var body: some View {
        VStack(spacing: 18) {
            header
            ring
            controls
            settings
            NotificationNotice(notifications: notifications)
        }
        .padding(18)
        .frame(width: 280)
        .background(Theme.cream)
        .environment(\.colorScheme, .light)
        .task { await notifications.refreshStatus() }
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
        case .working: return "专注中"
        case .paused: return "已暂停"
        case .awaitingBreak: return "该休息啦"
        case .resting: return "休息中"
        }
    }

    private var phaseColor: Color {
        switch model.phase {
        case .working, .awaitingBreak: return Theme.tomato
        case .resting: return Theme.leaf
        case .idle, .paused: return Theme.tomatoSoft
        }
    }

    private var statusColor: Color {
        model.phase == .idle || model.phase == .paused ? Theme.inkSoft : phaseColor
    }

    private var controls: some View {
        HStack(spacing: 10) {
            switch model.phase {
            case .idle:
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
                Button("跳过", action: model.skipBreak)
                    .buttonStyle(PillButtonStyle(kind: .secondary))
                Button("开始休息", action: model.startBreak)
                    .buttonStyle(PillButtonStyle())
                    .keyboardShortcut(.defaultAction)
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
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.creamDeep.opacity(0.6)))
    }
}

/// 只在通知不可用时出现的小提示条；一切正常时不占位置
private struct NotificationNotice: View {
    @ObservedObject var notifications: NotificationService

    var body: some View {
        if let notice {
            HStack(spacing: 8) {
                Text(notice.message)
                    .font(Theme.font(12))
                    .foregroundStyle(Theme.ink)
                Spacer(minLength: 4)
                Button(notice.action, action: notice.perform)
                    .buttonStyle(PillButtonStyle(kind: .plain))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.tomato.opacity(0.1)))
        }
    }

    private struct Notice {
        let message: String
        let action: String
        let perform: () -> Void
    }

    private var notice: Notice? {
        if notifications.lastDeliveryError != nil {
            return Notice(message: "通知发送失败，只会响铃", action: "去设置", perform: notifications.openNotificationSettings)
        }
        switch notifications.authState {
        case .notDetermined:
            return Notice(message: "还没允许通知", action: "允许") {
                Task { await notifications.requestAuthorization() }
            }
        case .denied:
            return Notice(message: "通知已关闭，只会响铃", action: "去开启", perform: notifications.openNotificationSettings)
        case .alertsOff:
            return Notice(message: "通知样式为「无」，不会弹横幅", action: "去设置", perform: notifications.openNotificationSettings)
        case .authorized, .unknown:
            return nil
        }
    }
}
