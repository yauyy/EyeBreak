import Foundation

enum EyeBreakConfig {
    static let defaultWorkMinutes = 20
    static let defaultRestSeconds = 20
    static let workMinutesRange = 5...180
    static let restSecondsRange = 5...600
    /// 超过这么久没有键鼠操作，判定为离开电脑（默认 5 分钟）。
    /// 仅 Debug 构建可用 `-EyeBreakTestAway 10` 缩短为秒级，便于手动测试。
    static var awayThreshold: TimeInterval {
        #if DEBUG
        let override = UserDefaults.standard.double(forKey: "EyeBreakTestAway")
        if override >= 1 { return override }
        #endif
        return 5 * 60
    }

    private static let workMinutesKey = "workMinutes"
    private static let restSecondsKey = "restSeconds"

    /// 启动时使用的专注时长：用户上次设置的值，默认 20 分钟。
    ///
    /// 仅 Debug 构建支持通过启动参数改成秒级间隔，便于快速验证提醒流程：
    /// `-EyeBreakTestInterval 10`（Xcode Scheme 中已预置，勾选即可）。
    static var workInterval: TimeInterval {
        if let test = testWorkInterval { return test }
        let minutes = UserDefaults.standard.integer(forKey: workMinutesKey)
        return TimeInterval(workMinutesRange.contains(minutes) ? minutes : defaultWorkMinutes) * 60
    }

    /// 启动时使用的眺望休息时长：用户上次设置的值，默认 20 秒。
    static var restDuration: TimeInterval {
        let seconds = UserDefaults.standard.integer(forKey: restSecondsKey)
        return TimeInterval(restSecondsRange.contains(seconds) ? seconds : defaultRestSeconds)
    }

    static func save(workInterval: TimeInterval, restDuration: TimeInterval) {
        // 测试间隔只是临时覆盖，不写入用户设置
        if workInterval >= 60, workInterval.truncatingRemainder(dividingBy: 60) == 0 {
            UserDefaults.standard.set(Int(workInterval / 60), forKey: workMinutesKey)
        }
        UserDefaults.standard.set(Int(restDuration), forKey: restSecondsKey)
    }

    /// 「稍后提醒」推迟的时长
    static let snoozeInterval: TimeInterval = 5 * 60

    /// 菜单栏是否在番茄仔旁边显示剩余时间（默认关闭）
    static let showMenuBarTimeKey = "showMenuBarTime"
    /// 菜单里的本周统计是否展开
    static let showWeekStatsKey = "showWeekStats"

    private static let snapshotKey = "timerSnapshot"
    private static let exerciseIndexKey = "exerciseIndex"
    private static let reminderSoundKey = "reminderSound"
    private static let enabledExercisesKey = "enabledExercises"
    private static let disabledExercisesKey = "disabledExercises"

    /// 持久化关闭的动作，让首次使用和升级后新增的动作默认开启。
    static var enabledExercises: Set<RestExercise> {
        get { loadEnabledExercises(from: .standard) }
        set { saveEnabledExercises(newValue, to: .standard) }
    }

    /// 独立偏好域便于测试，未知动作忽略，全关时回退为「看看远处」。
    static func loadEnabledExercises(from defaults: UserDefaults) -> Set<RestExercise> {
        let allExercises = Set(RestExercise.allCases)
        let disabled: Set<RestExercise>
        if defaults.object(forKey: disabledExercisesKey) != nil {
            let saved = defaults.array(forKey: disabledExercisesKey) as? [Int] ?? []
            disabled = Set(saved.compactMap(RestExercise.init(rawValue:)))
        } else if let saved = defaults.array(forKey: enabledExercisesKey) as? [Int] {
            // 1.4 只有前四项；固定迁移范围，新增动作不算作用户曾关闭的动作。
            let legacyExercises: Set<RestExercise> = [.lookFar, .blink, .closeEyes, .rollEyes]
            disabled = legacyExercises.subtracting(saved.compactMap(RestExercise.init(rawValue:)))
            // 保留旧键，回退旧版本时仍能读取原来的选择。
            defaults.set(disabled.map(\.rawValue).sorted(), forKey: disabledExercisesKey)
        } else {
            disabled = []
        }
        return RestExercise.normalized(allExercises.subtracting(disabled))
    }

    static func saveEnabledExercises(_ exercises: Set<RestExercise>, to defaults: UserDefaults) {
        let disabled = Set(RestExercise.allCases).subtracting(RestExercise.normalized(exercises))
        defaults.set(disabled.map(\.rawValue).sorted(), forKey: disabledExercisesKey)
    }

    private static let longBreakKey = "longBreak"

    /// 长休息设置，默认开启：每 4 轮一次、3 分钟。
    static var longBreak: LongBreakSettings {
        get { loadLongBreak(from: .standard) }
        set { saveLongBreak(newValue, to: .standard) }
    }

    static func loadLongBreak(from defaults: UserDefaults) -> LongBreakSettings {
        guard let data = defaults.data(forKey: longBreakKey),
              let saved = try? JSONDecoder().decode(LongBreakSettings.self, from: data) else {
            return LongBreakSettings()
        }
        return saved.normalized()
    }

    static func saveLongBreak(_ settings: LongBreakSettings, to defaults: UserDefaults) {
        guard let data = try? JSONEncoder().encode(settings.normalized()) else { return }
        defaults.set(data, forKey: longBreakKey)
    }

    /// 提醒音选择，默认「清脆」（Glass）
    static var reminderSound: ReminderSound {
        get { UserDefaults.standard.string(forKey: reminderSoundKey).flatMap(ReminderSound.init(rawValue:)) ?? .glass }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: reminderSoundKey) }
    }

    /// 上次轮到的休息内容序号；从未休息过时为 -1，第一次休息从「看看远处」开始
    static var exerciseIndex: Int {
        get { UserDefaults.standard.object(forKey: exerciseIndexKey) as? Int ?? -1 }
        set { UserDefaults.standard.set(newValue, forKey: exerciseIndexKey) }
    }

    static func saveSnapshot(_ snapshot: EyeBreakModel.Snapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        UserDefaults.standard.set(data, forKey: snapshotKey)
    }

    static func loadSnapshot() -> EyeBreakModel.Snapshot? {
        guard let data = UserDefaults.standard.data(forKey: snapshotKey) else { return nil }
        return try? JSONDecoder().decode(EyeBreakModel.Snapshot.self, from: data)
    }

    static var testWorkInterval: TimeInterval? {
        #if DEBUG
        let override = UserDefaults.standard.double(forKey: "EyeBreakTestInterval")
        if override >= 1 { return override }
        #endif
        return nil
    }

    /// 仅 Debug：启动后自动开始计时，便于无需点击界面即可验证提醒流程（`-EyeBreakAutoStart YES`）
    static var autoStart: Bool {
        #if DEBUG
        return UserDefaults.standard.bool(forKey: "EyeBreakAutoStart")
        #else
        return false
        #endif
    }

    static var isRunningTests: Bool {
        let env = ProcessInfo.processInfo.environment
        return env["XCTestConfigurationFilePath"] != nil
            || env["XCTestBundlePath"] != nil
            || env["XCTestSessionIdentifier"] != nil
    }
}
