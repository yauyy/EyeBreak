import Darwin
import Foundation

/// 诊断仅接收明确列出的运行信息；统计、成就和偏好原始内容不进入此类型。
struct DiagnosticSnapshot {
    let appVersion: String
    let buildNumber: String
    let macOSVersion: String
    let chip: String
    let isTranslated: Bool
    let interfaceLanguage: String
    let appearanceMode: String
    let languageSetting: String
    let phase: String
    let deferReason: String
    let isSnoozing: Bool
    let overridesSchedule: Bool
    let workSeconds: Int
    let restSeconds: Int
    let enabledExercises: [String]
    let reminderSound: String
    let schedule: WorkSchedule
    let launchAtLogin: String
    let automaticUpdates: Bool
    let lastUpdateCheck: Date?
}

/// 纯文本生成器：白名单之外没有任何数据来源，也不会读取或导出 UserDefaults。
enum DiagnosticReport {
    static func text(from snapshot: DiagnosticSnapshot) -> String {
        let schedule = snapshot.schedule
        let lastCheck = snapshot.lastUpdateCheck.map { ISO8601DateFormatter().string(from: $0) }
            ?? String(localized: "未知")
        let fields: [(String, String)] = [
            (String(localized: "App 版本"), snapshot.appVersion),
            (String(localized: "构建号"), snapshot.buildNumber),
            (String(localized: "macOS 版本"), snapshot.macOSVersion),
            (String(localized: "芯片"), snapshot.chip),
            (String(localized: "Rosetta 转译"), yesNo(snapshot.isTranslated)),
            (String(localized: "界面语言"), snapshot.interfaceLanguage),
            (String(localized: "外观"), snapshot.appearanceMode),
            (String(localized: "语言设置"), snapshot.languageSetting),
            (String(localized: "当前阶段"), snapshot.phase),
            (String(localized: "推迟原因"), snapshot.deferReason),
            (String(localized: "稍后提醒中"), yesNo(snapshot.isSnoozing)),
            (String(localized: "覆盖工作时段"), yesNo(snapshot.overridesSchedule)),
            (String(localized: "专注时长（秒）"), String(snapshot.workSeconds)),
            (String(localized: "眺望时长（秒）"), String(snapshot.restSeconds)),
            (String(localized: "启用的动作"), snapshot.enabledExercises.joined(separator: ", ")),
            (String(localized: "提示音"), snapshot.reminderSound),
            (String(localized: "工作时段已启用"), yesNo(schedule.isEnabled)),
            (String(localized: "工作开始时间"), "\(schedule.startHour):00"),
            (String(localized: "工作结束时间"), "\(schedule.endHour):00"),
            (String(localized: "仅工作日"), yesNo(schedule.weekdaysOnly)),
            (String(localized: "开机自启"), snapshot.launchAtLogin),
            (String(localized: "自动检查更新"), yesNo(snapshot.automaticUpdates)),
            (String(localized: "上次检查更新时间"), lastCheck),
        ]
        return fields.map { "\($0.0): \($0.1)" }.joined(separator: "\n")
    }

    private static func yesNo(_ value: Bool) -> String {
        value ? String(localized: "是") : String(localized: "否")
    }

    /// Sparkle 使用 NSDate 保存此键；未检查过时保持未知。
    static func lastUpdateCheck(defaults: UserDefaults) -> Date? {
        defaults.object(forKey: "SULastCheckTime") as? Date
    }
}

extension DiagnosticSnapshot {
    /// 在主线程收集共享对象的当前值，只读取显式允许的 Sparkle 时间键。
    @MainActor
    static func capture(
        model: EyeBreakModel,
        sounds: ReminderSounds,
        launchAtLogin: LaunchAtLogin,
        updates: AppUpdater,
        schedule: WorkScheduleSettings,
        defaults: UserDefaults = .standard,
        bundle: Bundle = .main,
        domainName: String? = nil
    ) -> DiagnosticSnapshot {
        let phase: String
        switch model.phase {
        case .idle: phase = String(localized: "未在计时")
        case .working: phase = String(localized: "专注中")
        case .paused: phase = String(localized: "已暂停")
        case .awaitingBreak: phase = String(localized: "等待休息")
        case .resting: phase = String(localized: "休息中")
        case .away: phase = String(localized: "离开中")
        case .offHours: phase = String(localized: "工作时段外")
        }
        let reason: String
        switch model.deferReason {
        case .meeting: reason = String(localized: "会议")
        case .fullscreen: reason = String(localized: "全屏")
        case .focus: reason = String(localized: "专注模式")
        case nil: reason = String(localized: "无")
        }
        let loginStatus: String
        if launchAtLogin.failed {
            loginStatus = String(localized: "设置失败")
        } else if launchAtLogin.needsApproval {
            loginStatus = String(localized: "等待授权")
        } else {
            loginStatus = launchAtLogin.isEnabled ? String(localized: "已开启") : String(localized: "已关闭")
        }
        return DiagnosticSnapshot(
            appVersion: bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0",
            buildNumber: bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0",
            macOSVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            chip: systemFlag("hw.optional.arm64") ? "Apple Silicon" : "Intel",
            isTranslated: systemFlag("sysctl.proc_translated"),
            interfaceLanguage: bundle.preferredLocalizations.first ?? Locale.current.identifier,
            appearanceMode: AppearancePreference.read(from: defaults).title,
            languageSetting: LanguagePreference.read(
                from: defaults, domainName: domainName ?? bundle.bundleIdentifier ?? "EyeBreak"
            ).title,
            phase: phase,
            deferReason: reason,
            isSnoozing: model.isSnoozing,
            overridesSchedule: model.isOverridingSchedule,
            workSeconds: Int(model.workInterval),
            restSeconds: Int(model.restDuration),
            enabledExercises: RestExercise.allCases.filter { model.enabledExercises.contains($0) }.map(\.title),
            reminderSound: sounds.choice.title,
            schedule: schedule.schedule,
            launchAtLogin: loginStatus,
            automaticUpdates: updates.automaticChecks,
            lastUpdateCheck: DiagnosticReport.lastUpdateCheck(defaults: defaults)
        )
    }

    private static func systemFlag(_ name: String) -> Bool {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        return sysctlbyname(name, &value, &size, nil, 0) == 0 && value == 1
    }
}
