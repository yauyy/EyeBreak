import AppIntents

/// App Intents 通过它找到正在运行的计时模型
@MainActor
final class IntentHub {
    static let shared = IntentHub()
    weak var model: EyeBreakModel?
}

enum EyeBreakIntentError: Error, CustomLocalizedStringResourceConvertible {
    case notRunning

    var localizedStringResource: LocalizedStringResource {
        "EyeBreak 还没有启动"
    }
}

@MainActor
private func runningModel() throws -> EyeBreakModel {
    guard let model = IntentHub.shared.model else { throw EyeBreakIntentError.notRunning }
    return model
}

// MARK: - 快捷指令动作

struct StartFocusIntent: AppIntent {
    static let title: LocalizedStringResource = "开始专注"
    static let description = IntentDescription("开始或继续 EyeBreak 的专注计时。")

    @MainActor
    func perform() async throws -> some IntentResult {
        try runningModel().start()
        return .result()
    }
}

struct PauseTimerIntent: AppIntent {
    static let title: LocalizedStringResource = "暂停计时"
    static let description = IntentDescription("暂停 EyeBreak 的专注计时。")

    @MainActor
    func perform() async throws -> some IntentResult {
        try runningModel().pause()
        return .result()
    }
}

struct StartBreakIntent: AppIntent {
    static let title: LocalizedStringResource = "开始休息"
    static let description = IntentDescription("立即开始一次眺望休息，不用等专注结束。")

    @MainActor
    func perform() async throws -> some IntentResult {
        try runningModel().startBreakNow()
        return .result()
    }
}

struct SkipBreakIntent: AppIntent {
    static let title: LocalizedStringResource = "跳过休息"
    static let description = IntentDescription("跳过这次休息，直接开始新一轮专注。")

    @MainActor
    func perform() async throws -> some IntentResult {
        try runningModel().skipBreak()
        return .result()
    }
}

struct EyeBreakShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: StartFocusIntent(), phrases: ["用\(.applicationName)开始专注"])
        AppShortcut(intent: PauseTimerIntent(), phrases: ["用\(.applicationName)暂停计时"])
        AppShortcut(intent: StartBreakIntent(), phrases: ["用\(.applicationName)开始休息"])
        AppShortcut(intent: SkipBreakIntent(), phrases: ["用\(.applicationName)跳过休息"])
    }
}

// MARK: - 专注模式过滤条件

/// 在「系统设置 → 专注模式」里给某个专注模式添加 EyeBreak 过滤条件：
/// 打开「暂停休息提醒」后，进入这个专注模式时提醒推迟，退出后再提醒。
struct EyeBreakFocusFilter: SetFocusFilterIntent {
    static let title: LocalizedStringResource = "EyeBreak"
    static let description: IntentDescription? = IntentDescription("在这个专注模式下暂停 EyeBreak 的休息提醒，退出后再提醒。")

    /// 专注模式结束时系统会用默认值调用 perform，所以默认值必须是「不暂停」
    @Parameter(title: "暂停休息提醒", default: false)
    var pauseReminders: Bool

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: pauseReminders ? "暂停休息提醒" : "照常提醒")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        IntentHub.shared.model?.setFocusHold(pauseReminders)
        return .result()
    }
}
