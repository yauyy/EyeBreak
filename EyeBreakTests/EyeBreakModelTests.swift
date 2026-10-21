import Combine
import Foundation
import Testing
@testable import EyeBreak

struct EnabledExercisesConfigTests {
    @Test("新增走一走保留已有五个动作的持久化序号")
    func exerciseRawValuesStayCompatible() {
        #expect(RestExercise.allCases.map(\.rawValue) == [0, 1, 2, 3, 4, 5])
        #expect(RestExercise.drinkWater.rawValue == 4)
        #expect(RestExercise.walk.rawValue == 5)
    }

    @Test("新安装未保存动作偏好时默认全部开启")
    func defaultsToAllExercises() {
        let suiteName = "EyeBreakTests.enabledExercises.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        #expect(EyeBreakConfig.loadEnabledExercises(from: defaults) == Set(RestExercise.allCases))
    }

    @Test("动作偏好保存后读取一致，不写入其它偏好")
    func savedExercisesRoundTrip() {
        let suiteName = "EyeBreakTests.enabledExercises.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        EyeBreakConfig.saveEnabledExercises([.blink, .closeEyes], to: defaults)
        #expect(EyeBreakConfig.loadEnabledExercises(from: defaults) == [.blink, .closeEyes])
        #expect(defaults.array(forKey: "disabledExercises") as? [Int] == RestExercise.allCases.filter { ![.blink, .closeEyes].contains($0) }.map(\.rawValue))
        #expect(Set((defaults.persistentDomain(forName: suiteName) ?? [:]).keys) == ["disabledExercises"])
    }

    @Test("旧偏好只迁移 1.4 的关闭动作，喝水和走一走默认开启且保留旧键", arguments: [[0, 2], [0, 2, -1, 99]])
    func legacyPreferencesMigrate(saved: [Int]) {
        let suiteName = "EyeBreakTests.enabledExercises.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(saved, forKey: "enabledExercises")
        let migrated = EyeBreakConfig.loadEnabledExercises(from: defaults)
        #expect(migrated == [.lookFar, .closeEyes, .drinkWater, .walk])
        #expect(migrated.contains(.walk))
        #expect(defaults.array(forKey: "disabledExercises") as? [Int] == [1, 3])
        #expect(defaults.array(forKey: "enabledExercises") as? [Int] == saved)
    }

    @Test("旧偏好全部开启时升级后全部动作全开")
    func allLegacyExercisesEnabled() {
        let suiteName = "EyeBreakTests.enabledExercises.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set([0, 1, 2, 3], forKey: "enabledExercises")
        #expect(EyeBreakConfig.loadEnabledExercises(from: defaults) == Set(RestExercise.allCases))
        #expect(defaults.array(forKey: "disabledExercises") as? [Int] == [])
    }

    @Test("旧偏好全关或只有未知值时，新增喝水和走一走仍默认开启", arguments: [[], [-1, 99]])
    func emptyLegacyPreferencesStillEnableNewExercise(saved: [Int]) {
        let suiteName = "EyeBreakTests.enabledExercises.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(saved, forKey: "enabledExercises")
        #expect(EyeBreakConfig.loadEnabledExercises(from: defaults) == [.drinkWater, .walk])
        #expect(defaults.array(forKey: "disabledExercises") as? [Int] == [0, 1, 2, 3])
    }

    @Test("1.5 用户只关闭眨眼时，升级后走一走默认开启")
    func existingDisabledPreferencesEnableWalk() {
        let suiteName = "EyeBreakTests.enabledExercises.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set([1], forKey: "disabledExercises")

        let loaded = EyeBreakConfig.loadEnabledExercises(from: defaults)
        #expect(loaded == Set(RestExercise.allCases).subtracting([.blink]))
        #expect(loaded.contains(.walk))
        #expect(defaults.array(forKey: "disabledExercises") as? [Int] == [1])
    }

    @Test("已有关闭列表时忽略旧启用列表，包括空的关闭列表", arguments: [[], [1, 4]])
    func disabledPreferencesTakePrecedence(saved: [Int]) {
        let suiteName = "EyeBreakTests.enabledExercises.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set([], forKey: "enabledExercises")
        defaults.set(saved, forKey: "disabledExercises")
        let disabled = Set(saved.compactMap(RestExercise.init(rawValue:)))
        #expect(EyeBreakConfig.loadEnabledExercises(from: defaults) == Set(RestExercise.allCases).subtracting(disabled))
        #expect(defaults.array(forKey: "disabledExercises") as? [Int] == saved)
    }

    @Test("关闭列表里的未知动作忽略", arguments: [[-1, 99], [1, -1, 99]])
    func unknownDisabledExercisesAreIgnored(saved: [Int]) {
        let suiteName = "EyeBreakTests.enabledExercises.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(saved, forKey: "disabledExercises")
        let expected = saved.contains(1) ? Set(RestExercise.allCases).subtracting([.blink]) : Set(RestExercise.allCases)
        #expect(EyeBreakConfig.loadEnabledExercises(from: defaults) == expected)
    }

    @Test("关闭列表全关时回退为只有看看远处")
    func allDisabledExercisesFallBack() {
        let suiteName = "EyeBreakTests.enabledExercises.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(RestExercise.allCases.map(\.rawValue), forKey: "disabledExercises")
        #expect(EyeBreakConfig.loadEnabledExercises(from: defaults) == [.lookFar])
        EyeBreakConfig.saveEnabledExercises([], to: defaults)
        #expect(defaults.array(forKey: "disabledExercises") as? [Int] == RestExercise.allCases.filter { $0 != .lookFar }.map(\.rawValue))
        #expect(EyeBreakConfig.loadEnabledExercises(from: defaults) == [.lookFar])
    }

    @Test("保存新动作偏好时不改写旧键，回退版本仍保留原选择")
    func savingPreservesLegacyPreferences() {
        let suiteName = "EyeBreakTests.enabledExercises.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set([0, 2], forKey: "enabledExercises")
        EyeBreakConfig.saveEnabledExercises([.drinkWater], to: defaults)
        #expect(EyeBreakConfig.loadEnabledExercises(from: defaults) == [.drinkWater])
        #expect(defaults.array(forKey: "disabledExercises") as? [Int] == RestExercise.allCases.filter { $0 != .drinkWater }.map(\.rawValue))
        #expect(defaults.array(forKey: "enabledExercises") as? [Int] == [0, 2])
    }
}

@MainActor
private final class SpyReminder: ReminderDelivering {
    var delivered: [TimeInterval] = []
    var cancelled = 0
    var breakCompleteSounds = 0
    func deliverReminder(restDuration: TimeInterval) { delivered.append(restDuration) }
    func cancelPendingReminders() { cancelled += 1 }
    func playBreakComplete() { breakCompleteSounds += 1 }
}

@MainActor
private final class FakeClock {
    var now = Date(timeIntervalSince1970: 1_000_000)
    /// 模拟距离上次键鼠操作的秒数，默认一直在操作
    var idle: TimeInterval = 0
    /// 模拟麦克风是否被会议软件占用
    var inMeeting = false
    /// 模拟当前是否在工作时段内
    var workTime = true
    /// 模拟前台 App 是否全屏
    var fullscreen = false
    func advance(_ seconds: TimeInterval) { now += seconds }
}

@MainActor
struct EyeBreakModelTests {
    private let clock = FakeClock()
    private let spy = SpyReminder()
    private let model: EyeBreakModel

    init() {
        let clock = clock
        model = EyeBreakModel(
            workInterval: 20 * 60, restDuration: 20, reminder: spy,
            now: { clock.now }, idleTime: { clock.idle }, isInMeeting: { clock.inMeeting }, isFullscreen: { clock.fullscreen }, isWorkTime: { clock.workTime }, awayThreshold: 5 * 60,
            usesSystemTimer: false
        )
    }

    private func advance(_ seconds: TimeInterval) {
        clock.advance(seconds)
        model.tick()
    }

    /// 从开始专注一直走到等待休息
    private func finishWorkRound() {
        finishWorkRoundOf(20 * 60)
    }

    private func finishWorkRoundOf(_ seconds: TimeInterval) {
        model.start()
        advance(seconds)
    }

    // MARK: - 专注计时

    @Test("TC-02 初始显示 20:00，开始后从 20:00 计时")
    func initialState() {
        #expect(model.phase == .idle)
        #expect(model.formattedRemaining == "20:00")
        model.start()
        #expect(model.phase == .working)
        #expect(model.formattedRemaining == "20:00")
    }

    @Test("TC-03 倒计时递减")
    func countsDown() {
        model.start()
        advance(1)
        #expect(model.formattedRemaining == "19:59")
        advance(60)
        #expect(model.formattedRemaining == "18:59")
    }

    @Test("TC-04/05 暂停时间不变，继续从暂停处恢复")
    func pauseAndResume() {
        model.start()
        advance(100)
        model.pause()
        #expect(model.phase == .paused)
        #expect(model.formattedRemaining == "18:20")

        advance(500)
        #expect(model.formattedRemaining == "18:20")

        model.start()
        advance(20)
        #expect(model.formattedRemaining == "18:00")
    }

    @Test("TC-06 重新计时恢复 20:00 并开始新一轮")
    func reset() {
        model.start()
        advance(300)
        model.pause()
        model.reset()
        #expect(model.phase == .working)
        #expect(model.formattedRemaining == "20:00")
        advance(1)
        #expect(model.formattedRemaining == "19:59")
    }

    @Test("TC-12 重复点击开始不会重置或叠加计时")
    func repeatedStartIsNoop() {
        model.start()
        advance(100)
        model.start()
        model.start()
        advance(0)
        #expect(model.formattedRemaining == "18:20")
    }

    // MARK: - 菜单栏文字

    @Test("菜单栏文字：专注、暂停、休息时显示紧凑的剩余时间，等待休息时显示「休息」")
    func menuBarText() {
        #expect(model.menuBarText == nil)
        model.start()
        advance(15 * 60)
        #expect(model.menuBarText == "5:00")
        model.pause()
        #expect(model.menuBarText == "5:00")
        model.start()
        advance(5 * 60)
        #expect(model.menuBarText == String(localized: "休息"))
        model.startBreak()
        advance(8)
        #expect(model.menuBarText == "0:12")
    }

    @Test("离开时菜单栏不显示时间")
    func menuBarTextWhenAway() {
        model.start()
        clock.idle = 3600
        advance(1)
        #expect(model.menuBarText == nil)
    }

    // MARK: - 提醒与休息

    @Test("TC-07 专注结束只提醒一次，进入等待休息并冻结计时")
    func workEndAwaitsBreak() {
        model.start()
        advance(1199)
        #expect(spy.delivered.isEmpty)
        #expect(model.formattedRemaining == "00:01")

        advance(1)
        #expect(model.phase == .awaitingBreak)
        #expect(spy.delivered == [20])
        // 等待休息时展示的是休息时长
        #expect(model.formattedRemaining == "00:20")
    }

    @Test("不点开始休息时，无论过多久都不会重复提醒")
    func awaitingBreakDoesNotRepeat() {
        finishWorkRound()
        advance(3 * 3600)
        model.tick()
        #expect(model.phase == .awaitingBreak)
        #expect(spy.delivered.count == 1)
    }

    @Test("计时器严重迟到时也只提醒一次，且不出现负数")
    func lateTickFiresOnlyOnce() {
        model.start()
        advance(5 * 1200 + 37)
        #expect(spy.delivered.count == 1)
        #expect(model.remainingSeconds >= 0)
        model.tick()
        #expect(spy.delivered.count == 1)
    }

    @Test("开始休息后倒计时，结束时庆祝并自动开始下一轮专注")
    func breakCompletesAndResumesWork() {
        var celebrations = 0
        let subscription = model.breakCompleted.sink { celebrations += 1 }
        defer { subscription.cancel() }

        finishWorkRound()
        model.startBreak()
        #expect(model.phase == .resting)
        #expect(model.formattedRemaining == "00:20")
        #expect(spy.cancelled >= 1)

        advance(5)
        #expect(model.formattedRemaining == "00:15")

        advance(15)
        #expect(celebrations == 1)
        #expect(spy.breakCompleteSounds == 1)
        #expect(model.phase == .working)
        #expect(model.formattedRemaining == "20:00")
    }

    @Test("跳过本次休息：不庆祝，直接开始新一轮专注")
    func skipBreak() {
        var celebrations = 0
        let subscription = model.breakCompleted.sink { celebrations += 1 }
        defer { subscription.cancel() }

        finishWorkRound()
        model.skipBreak()
        #expect(model.phase == .working)
        #expect(model.formattedRemaining == "20:00")
        #expect(celebrations == 0)
    }

    @Test("休息中提前结束：不庆祝，直接开始新一轮专注")
    func endBreakEarly() {
        var celebrations = 0
        let subscription = model.breakCompleted.sink { celebrations += 1 }
        defer { subscription.cancel() }

        finishWorkRound()
        model.startBreak()
        advance(8)
        model.skipBreak()
        #expect(model.phase == .working)
        #expect(celebrations == 0)
        #expect(spy.breakCompleteSounds == 0)
    }

    @Test("稍后提醒：收起提醒，5 分钟后再提醒一次，进度按 5 分钟计算")
    func snoozeRemindsAgain() {
        finishWorkRound()
        model.snooze()
        #expect(model.phase == .working)
        #expect(model.isSnoozing)
        #expect(model.formattedRemaining == "05:00")
        #expect(model.progress == 0)

        advance(150)
        #expect(model.progress == 0.5)

        advance(150)
        #expect(model.phase == .awaitingBreak)
        #expect(spy.delivered.count == 2)
    }

    @Test("稍后提醒期间暂停再继续，仍按稍后提醒计算")
    func snoozePauseResume() {
        finishWorkRound()
        model.snooze()
        advance(60)
        model.pause()
        model.start()
        #expect(model.isSnoozing)
        #expect(model.formattedRemaining == "04:00")
    }

    @Test("稍后提醒结束后开始休息、休息完成，下一轮恢复正常专注时长")
    func snoozeThenNormalRound() {
        finishWorkRound()
        model.snooze()
        advance(300)
        model.startBreak()
        advance(20)
        #expect(model.phase == .working)
        #expect(!model.isSnoozing)
        #expect(model.formattedRemaining == "20:00")
    }

    @Test("专注时长比推迟时长还短时，按专注时长推迟")
    func snoozeNeverLongerThanWork() {
        model.setWorkInterval(3 * 60)
        finishWorkRoundOf(3 * 60)
        model.snooze()
        #expect(model.formattedRemaining == "03:00")
    }

    @Test("只有等待休息时才能稍后提醒")
    func snoozeOnlyWhenAwaiting() {
        model.start()
        model.snooze()
        #expect(!model.isSnoozing)
        #expect(model.formattedRemaining == "20:00")
    }

    @Test("等待休息/休息中，开始、暂停、开始休息等无关操作无效")
    func irrelevantActionsIgnored() {
        finishWorkRound()
        model.start()
        model.pause()
        #expect(model.phase == .awaitingBreak)

        model.startBreak()
        model.startBreak()
        advance(5)
        model.start()
        model.pause()
        #expect(model.phase == .resting)
        #expect(model.formattedRemaining == "00:15")
    }

    // MARK: - 自定义时长

    @Test("未开始时修改专注时长立即生效，并通知持久化")
    func changeWorkIntervalWhenIdle() {
        var saved: (TimeInterval, TimeInterval)?
        model.onPreferencesChanged = { saved = ($0, $1) }
        model.setWorkInterval(25 * 60)
        #expect(model.formattedRemaining == "25:00")
        #expect(saved?.0 == TimeInterval(25 * 60))
        #expect(saved?.1 == TimeInterval(20))
    }

    @Test("专注中修改专注时长，本轮不变，下一轮生效")
    func changeWorkIntervalWhileWorking() {
        model.start()
        advance(60)
        model.setWorkInterval(30 * 60)
        #expect(model.formattedRemaining == "19:00")

        advance(19 * 60)
        #expect(model.phase == .awaitingBreak)
        model.skipBreak()
        #expect(model.formattedRemaining == "30:00")
    }

    @Test("自定义休息时长用于提醒文案和休息倒计时")
    func customRestDuration() {
        model.setRestDuration(45)
        finishWorkRound()
        #expect(spy.delivered == [45])
        model.startBreak()
        #expect(model.formattedRemaining == "00:45")
        advance(45)
        #expect(model.phase == .working)
    }

    @Test("休息中修改休息时长，本次不变")
    func changeRestWhileResting() {
        finishWorkRound()
        model.startBreak()
        advance(5)
        #expect(model.progress == 0.25)
        model.setRestDuration(60)
        #expect(model.formattedRemaining == "00:15")
        #expect(model.progress == 0.25)
        advance(15)
        #expect(model.phase == .working)

        advance(20 * 60)
        model.startBreak()
        #expect(model.formattedRemaining == "01:00")
        advance(15)
        #expect(model.progress == 0.25)
    }

    @Test("等待休息时修改时长，显示和即将开始的休息立即生效")
    func changeRestWhileAwaitingBreak() {
        finishWorkRound()
        model.setRestDuration(60)
        #expect(model.formattedRemaining == "01:00")
        #expect(model.progress == 0)

        model.startBreak()
        #expect(model.formattedRemaining == "01:00")
        advance(15)
        #expect(model.formattedRemaining == "00:45")
        #expect(model.progress == 0.25)
    }

    @Test("专注或暂停中的专注设置只有不同于本轮时长时才提示下一轮生效", arguments: [false, true])
    func workIntervalChangePendingWhileFocusing(paused: Bool) {
        #expect(!model.workIntervalChangePending)
        #expect(!model.restDurationChangePending)
        model.start()
        if paused { model.pause() }
        #expect(model.currentRoundTotal == 1200)
        #expect(!model.workIntervalChangePending)

        model.setWorkInterval(1800)
        #expect(model.workIntervalChangePending)
        #expect(model.currentRoundTotal == 1200)
        model.setWorkInterval(1200)
        #expect(!model.workIntervalChangePending)
        model.setRestDuration(60)
        #expect(!model.restDurationChangePending)
    }

    @Test("稍后提醒的专注和暂停状态按本次短轮时长判断下一轮提示", arguments: [false, true])
    func workIntervalChangePendingWhileSnoozing(paused: Bool) {
        finishWorkRound()
        model.snooze()
        if paused { model.pause() }
        #expect(model.currentRoundTotal == 300)
        #expect(model.workIntervalChangePending)

        model.setWorkInterval(300)
        #expect(!model.workIntervalChangePending)
        model.setWorkInterval(1200)
        #expect(model.workIntervalChangePending)
        #expect(model.currentRoundTotal == 300)
    }

    @Test("休息设置只有休息中且不同于本次实际时长时才提示下次休息生效")
    func restDurationChangePendingWhileResting() {
        model.startBreakNow()
        #expect(model.currentBreakDuration == 20)
        #expect(!model.restDurationChangePending)
        model.setRestDuration(60)
        #expect(model.restDurationChangePending)
        #expect(model.currentBreakDuration == 20)
        model.setRestDuration(20)
        #expect(!model.restDurationChangePending)
        model.setWorkInterval(1800)
        #expect(!model.workIntervalChangePending)
    }

    @Test("专注和等待休息时修改休息设置不提示下一轮，接下来开始休息立即采用新值", arguments: [false, true])
    func restDurationChangeIsImmediateBeforeBreak(awaitingBreak: Bool) {
        model.start()
        model.setWorkInterval(1800)
        if awaitingBreak { advance(1200) }
        model.setRestDuration(60)
        #expect(!model.restDurationChangePending)
        if !awaitingBreak { advance(1200) }
        #expect(model.phase == .awaitingBreak)
        #expect(!model.workIntervalChangePending)
        #expect(!model.restDurationChangePending)

        model.startBreak()
        #expect(model.currentBreakDuration == 60)
        #expect(model.remainingSeconds == 60)
        #expect(!model.workIntervalChangePending)
        #expect(!model.restDurationChangePending)
    }

    @Test("未开始、离开电脑和工作时段外均隐藏下一轮生效提示")
    func durationChangeHintsHiddenWhileInactive() {
        model.setWorkInterval(1800)
        model.setRestDuration(60)
        #expect(model.phase == .idle)
        #expect(!model.workIntervalChangePending)
        #expect(!model.restDurationChangePending)

        model.start()
        model.setWorkInterval(1200)
        #expect(model.workIntervalChangePending)
        clock.idle = 600
        advance(1)
        #expect(model.phase == .away)
        #expect(!model.workIntervalChangePending)
        #expect(!model.restDurationChangePending)

        clock.workTime = false
        advance(1)
        #expect(model.phase == .offHours)
        #expect(!model.workIntervalChangePending)
        #expect(!model.restDurationChangePending)
    }

    // MARK: - 睡眠与退出

    @Test("TC-10/11 专注中短暂睡眠：暂停并保存，唤醒后从原剩余时间继续，不补发提醒")
    func shortSleepWhileWorking() {
        model.start()
        advance(100)
        model.systemWillSleep()
        #expect(model.phase == .paused)

        clock.advance(60)
        model.systemDidWake()
        #expect(model.phase == .working)
        model.tick()
        #expect(model.formattedRemaining == "18:20")
        #expect(spy.delivered.isEmpty)
    }

    @Test("专注中长时间睡眠：睡眠算作休息，唤醒后开始新一轮完整专注")
    func longSleepWhileWorking() {
        model.start()
        advance(100)
        model.systemWillSleep()
        clock.advance(8 * 3600)
        model.systemDidWake()
        #expect(model.phase == .working)
        #expect(model.formattedRemaining == "20:00")
        #expect(spy.delivered.isEmpty)
    }

    // MARK: - 离开电脑

    @Test("专注中超过 5 分钟没有操作：进入离开状态，计时冻结、不提醒")
    func goesAwayWhileWorking() {
        model.start()
        advance(60)
        clock.idle = 5 * 60
        advance(1)
        #expect(model.phase == .away)
        #expect(model.formattedRemaining == "20:00")

        // 离开期间即使过了专注时长也不会提醒
        advance(3600)
        #expect(model.phase == .away)
        #expect(spy.delivered.isEmpty)
    }

    @Test("离开后回来：开始新一轮完整专注")
    func returnsFromAway() {
        model.start()
        clock.idle = 10 * 60
        advance(1)
        #expect(model.phase == .away)

        clock.idle = 1
        advance(1)
        #expect(model.phase == .working)
        #expect(model.formattedRemaining == "20:00")
    }

    @Test("没超过 5 分钟的短暂无操作不算离开")
    func shortIdleIsNotAway() {
        model.start()
        clock.idle = 4 * 60
        advance(30)
        #expect(model.phase == .working)
    }

    @Test("等待休息时离开：离开算作休息过，回来后开始新一轮")
    func goesAwayWhileAwaitingBreak() {
        finishWorkRound()
        #expect(model.phase == .awaitingBreak)
        clock.idle = 6 * 60
        advance(1)
        #expect(model.phase == .away)

        clock.idle = 0
        advance(1)
        #expect(model.phase == .working)
        #expect(spy.delivered.count == 1)
    }

    @Test("休息中长时间不操作不算离开（眺望时本来就不碰键鼠）")
    func restingIgnoresIdle() {
        model.setRestDuration(600)
        finishWorkRound()
        model.startBreak()
        clock.idle = 9 * 60
        advance(9 * 60)
        #expect(model.phase == .resting)
    }

    @Test("暂停中长时间不操作，保持暂停")
    func pausedIgnoresIdle() {
        model.start()
        model.pause()
        clock.idle = 3600
        advance(3600)
        #expect(model.phase == .paused)
    }

    @Test("离开中点开始：立即开始新一轮")
    func startWhileAway() {
        model.start()
        clock.idle = 3600
        advance(1)
        model.start()
        #expect(model.phase == .working)
        #expect(model.formattedRemaining == "20:00")
    }

    @Test("TC-11 暂停中睡眠：唤醒后仍保持暂停")
    func sleepWhilePausedStaysPaused() {
        model.start()
        advance(100)
        model.pause()
        model.systemWillSleep()
        model.systemDidWake()
        #expect(model.phase == .paused)
        #expect(model.formattedRemaining == "18:20")
    }

    @Test("未开始时睡眠唤醒不会自动开始")
    func sleepWhileIdleStaysIdle() {
        model.systemWillSleep()
        model.systemDidWake()
        #expect(model.phase == .idle)
    }

    @Test("等待休息时睡眠：睡眠算作休息，唤醒后开始新一轮专注")
    func sleepWhileAwaitingBreak() {
        finishWorkRound()
        model.systemWillSleep()
        clock.advance(600)
        model.systemDidWake()
        #expect(model.phase == .working)
        #expect(model.formattedRemaining == "20:00")
        #expect(spy.delivered.count == 1)
    }

    @Test("休息中睡眠：唤醒后开始新一轮专注，不重复庆祝")
    func sleepWhileResting() {
        var celebrations = 0
        let subscription = model.breakCompleted.sink { celebrations += 1 }
        defer { subscription.cancel() }

        finishWorkRound()
        model.startBreak()
        advance(5)
        model.systemWillSleep()
        clock.advance(600)
        model.tick()
        model.systemDidWake()
        #expect(model.phase == .working)
        #expect(celebrations == 0)
    }

    // MARK: - 休息内容轮换

    @Test("第一次休息是看看远处，之后六个动作依次轮换并循环")
    func exercisesRotate() {
        var seen: [RestExercise] = []
        model.start()
        for _ in 0...RestExercise.allCases.count {
            advance(20 * 60)
            seen.append(model.exercise)
            // 跳过休息会直接开始新一轮专注
            model.skipBreak()
        }
        #expect(seen == [.lookFar, .blink, .closeEyes, .rollEyes, .drinkWater, .walk, .lookFar])
    }

    @Test("关闭喝水后跳过第五项，其余动作继续依次循环")
    func exercisesSkipDisabledDrinkWater() {
        model.setExercise(.drinkWater, enabled: false)
        var seen: [RestExercise] = []
        model.start()
        for _ in 0..<RestExercise.allCases.count {
            advance(20 * 60)
            seen.append(model.exercise)
            model.skipBreak()
        }
        #expect(seen == [.lookFar, .blink, .closeEyes, .rollEyes, .walk, .lookFar])
    }

    @Test("关闭走一走后跳过第六项，已有五个动作继续依次循环")
    func exercisesSkipDisabledWalk() {
        model.setExercise(.walk, enabled: false)
        var seen: [RestExercise] = []
        model.start()
        for _ in 0..<RestExercise.allCases.count {
            advance(20 * 60)
            seen.append(model.exercise)
            model.skipBreak()
        }
        #expect(seen == [.lookFar, .blink, .closeEyes, .rollEyes, .drinkWater, .lookFar])
    }

    @Test("动作轮换跳过关闭的动作，按原有顺序循环启用项")
    func exercisesSkipDisabledChoices() {
        model.setEnabledExercises([.blink, .rollEyes])
        var seen: [RestExercise] = []
        model.start()
        for _ in 0..<5 {
            advance(20 * 60)
            seen.append(model.exercise)
            model.skipBreak()
        }
        #expect(seen == [.blink, .rollEyes, .blink, .rollEyes, .blink])
    }

    @Test("模型读到全关动作时回退为只有看看远处")
    func disabledExercisesFallBackToLookFar() {
        let clock = clock
        let fallback = EyeBreakModel(
            workInterval: 60, restDuration: 20, reminder: spy,
            now: { clock.now }, idleTime: { 0 }, isInMeeting: { false }, isFullscreen: { false },
            exerciseIndex: 1, enabledExercises: [], usesSystemTimer: false
        )
        #expect(fallback.enabledExercises == [.lookFar])
        fallback.startBreakNow()
        #expect(fallback.exercise == .lookFar)

        model.setEnabledExercises([.blink])
        model.setEnabledExercises([])
        #expect(model.enabledExercises == [.lookFar])
        model.startBreakNow()
        #expect(model.exercise == .lookFar)
    }

    @Test("关闭最后一个启用动作时回退为看看远处", arguments: RestExercise.allCases)
    func disablingLastExerciseFallsBack(lastExercise: RestExercise) {
        model.setEnabledExercises([lastExercise])
        model.setExercise(lastExercise, enabled: false)
        #expect(model.enabledExercises == [.lookFar])
        model.startBreakNow()
        #expect(model.exercise == .lookFar)
    }

    @Test("动作开关变化通知持久化，重复设置不重复保存")
    func exercisePreferencesNotifyPersistence() {
        var saved: [Set<RestExercise>] = []
        model.onEnabledExercisesChanged = { saved.append($0) }
        model.setExercise(.blink, enabled: false)
        model.setExercise(.blink, enabled: false)
        #expect(saved == [Set(RestExercise.allCases).subtracting([.blink])])
        model.setExercise(.blink, enabled: true)
        #expect(saved.last == Set(RestExercise.allCases))
    }

    @Test("首次提醒后修改动作开关，等待、稍后提醒和本次休息的动作都不变")
    func exercisePreferencesDoNotChangeCurrentReminder() {
        finishWorkRound()
        #expect(model.exercise == .lookFar)
        model.setEnabledExercises([.blink])
        #expect(model.exercise == .lookFar)
        model.snooze()
        #expect(model.exercise == .lookFar)
        advance(300)
        #expect(model.exercise == .lookFar)
        model.startBreak()
        model.setEnabledExercises([.closeEyes])
        #expect(model.exercise == .lookFar)
        advance(20)
        advance(20 * 60)
        #expect(model.exercise == .closeEyes)
    }

    @Test("稍后提醒期间现在休息继续原动作，暂停后也一样", arguments: [false, true])
    func startBreakNowWhileSnoozingKeepsExercise(paused: Bool) {
        finishWorkRound()
        let exercise = model.exercise
        model.snooze()
        model.setEnabledExercises([.blink])
        advance(60)
        if paused { model.pause() }
        let remindersBeforeBreak = spy.delivered.count
        model.startBreakNow()
        #expect(model.phase == .resting)
        #expect(model.exercise == exercise)
        #expect(spy.delivered.count == remindersBeforeBreak)
    }

    @Test("稍后提醒后离开或进入非工作时段，再手动休息时选择新动作", arguments: [false, true])
    func startBreakNowAfterSnoozeRoundEndedChoosesNextExercise(offHours: Bool) {
        finishWorkRound()
        #expect(model.exercise == .lookFar)
        model.snooze()
        if offHours {
            clock.workTime = false
        } else {
            clock.idle = 5 * 60
        }
        advance(1)
        #expect(model.phase == (offHours ? .offHours : .away))

        model.startBreakNow()
        #expect(model.phase == .resting)
        #expect(model.exercise == .blink)
        #expect(spy.delivered.count == 1)
    }

    @Test("稍后提醒再次到点时，休息内容保持不变")
    func snoozeKeepsExercise() {
        finishWorkRound()
        let first = model.exercise
        model.snooze()
        advance(300)
        #expect(model.phase == .awaitingBreak)
        #expect(model.exercise == first)
    }

    @Test("从上次的轮换位置继续")
    func exerciseResumesFromSavedIndex() {
        let clock = clock
        let resumed = EyeBreakModel(
            workInterval: 60, restDuration: 20, reminder: spy,
            now: { clock.now }, idleTime: { 0 }, isInMeeting: { false },
            exerciseIndex: 1, usesSystemTimer: false
        )
        resumed.start()
        clock.advance(60)
        resumed.tick()
        #expect(resumed.exercise == .closeEyes)
    }

    // MARK: - 会议

    @Test("专注到点时正在开会：先不提醒，会议结束立即提醒")
    func deferReminderDuringMeeting() {
        model.start()
        clock.inMeeting = true
        advance(20 * 60)
        #expect(model.phase == .working)
        #expect(model.deferReason == .meeting)
        #expect(model.formattedRemaining == "00:00")
        #expect(spy.delivered.isEmpty)

        advance(600)
        #expect(spy.delivered.isEmpty)

        clock.inMeeting = false
        advance(1)
        #expect(model.phase == .awaitingBreak)
        #expect(model.deferReason == nil)
        #expect(spy.delivered.count == 1)
    }

    @Test("开会时长时间不碰键鼠不算离开")
    func meetingIsNotAway() {
        model.start()
        clock.inMeeting = true
        clock.idle = 30 * 60
        advance(60)
        #expect(model.phase == .working)
    }

    @Test("会议结束后仍然没人操作，才判定为离开")
    func awayAfterMeetingEnds() {
        model.start()
        clock.inMeeting = true
        clock.idle = 30 * 60
        advance(60)
        clock.inMeeting = false
        advance(1)
        #expect(model.phase == .away)
    }

    @Test("专注到点时正在全屏：先不提醒，退出全屏后立即提醒")
    func deferReminderWhileFullscreen() {
        model.start()
        clock.fullscreen = true
        advance(20 * 60)
        #expect(model.deferReason == .fullscreen)
        #expect(spy.delivered.isEmpty)
        clock.fullscreen = false
        advance(1)
        #expect(model.phase == .awaitingBreak)
        #expect(model.deferReason == nil)
        #expect(spy.delivered.count == 1)
    }

    @Test("全屏看视频时长时间不碰键鼠不算离开")
    func fullscreenIsNotAway() {
        model.start()
        clock.fullscreen = true
        clock.idle = 30 * 60
        advance(60)
        #expect(model.phase == .working)
    }

    // MARK: - 快捷指令与专注模式

    @Test("立即开始休息：专注中也能直接开始，休息完成后开始新一轮")
    func startBreakNow() {
        model.start()
        advance(300)
        model.startBreakNow()
        #expect(model.phase == .resting)
        #expect(model.formattedRemaining == "00:20")
        advance(20)
        #expect(model.phase == .working)
        #expect(model.formattedRemaining == "20:00")
        #expect(spy.breakCompleteSounds == 1)
    }

    @Test("立即开始休息：等待休息时等同于点「开始休息」，休息中不重复开始")
    func startBreakNowWhileAwaiting() {
        finishWorkRound()
        let exercise = model.exercise
        model.startBreakNow()
        #expect(model.phase == .resting)
        #expect(model.exercise == exercise)
        advance(5)
        model.startBreakNow()
        #expect(model.formattedRemaining == "00:15")
    }

    @Test("推迟状态现在休息直接进入休息并清除原因，不经过等待休息", arguments: ["meeting", "fullscreen", "focus"])
    func startBreakNowWhileDeferred(reason: String) {
        model.setEnabledExercises([.blink])
        model.start()
        switch reason {
        case "meeting": clock.inMeeting = true
        case "fullscreen": clock.fullscreen = true
        default: model.setFocusHold(true)
        }
        advance(20 * 60)
        #expect(model.phase == .working)
        #expect(model.deferReason != nil)
        var phases: [EyeBreakModel.Phase] = []
        let subscription = model.$phase.dropFirst().sink { phases.append($0) }
        defer { subscription.cancel() }

        model.startBreakNow()
        #expect(model.phase == .resting)
        #expect(model.deferReason == nil)
        #expect(model.exercise == .blink)
        #expect(phases == [.resting])
        #expect(spy.delivered.isEmpty)
        #expect(model.remainingSeconds == 20)
    }

    @Test("推迟期间暂停清除原因，继续后重新判断提醒", arguments: ["meeting", "fullscreen", "focus"])
    func pauseWhileDeferred(reason: String) {
        clock.inMeeting = reason == "meeting"
        clock.fullscreen = reason == "fullscreen"
        model.setFocusHold(reason == "focus")
        model.start()
        advance(20 * 60)
        #expect(model.deferReason != nil)

        model.pause()
        #expect(model.phase == .paused)
        #expect(model.deferReason == nil)
        advance(600)
        #expect(model.phase == .paused)
        #expect(model.deferReason == nil)
        #expect(spy.delivered.isEmpty)

        model.start()
        advance(1)
        #expect(model.phase == .working)
        #expect(model.deferReason != nil)
        clock.inMeeting = false
        clock.fullscreen = false
        model.setFocusHold(false)
        advance(1)
        #expect(model.phase == .awaitingBreak)
        #expect(model.deferReason == nil)
        #expect(spy.delivered.count == 1)
    }

    @Test("稍后提醒被推迟时现在休息仍保留首次提醒的动作")
    func startBreakNowWhileDeferredSnoozeKeepsExercise() {
        finishWorkRound()
        let exercise = model.exercise
        model.snooze()
        model.setEnabledExercises([.blink])
        clock.inMeeting = true
        advance(300)
        #expect(model.deferReason == .meeting)
        model.startBreakNow()
        #expect(model.phase == .resting)
        #expect(model.deferReason == nil)
        #expect(model.exercise == exercise)
        #expect(spy.delivered.count == 1)
    }

    @Test("专注模式要求暂停时：到点的提醒推迟到专注模式结束")
    func focusHoldDefersReminder() {
        model.start()
        model.setFocusHold(true)
        advance(20 * 60)
        #expect(model.deferReason == .focus)
        #expect(spy.delivered.isEmpty)
        model.setFocusHold(false)
        advance(1)
        #expect(model.phase == .awaitingBreak)
        #expect(spy.delivered.count == 1)
    }

    @Test("专注模式期间离开电脑：照常判定为离开")
    func focusHoldDoesNotBlockAway() {
        model.start()
        model.setFocusHold(true)
        clock.idle = 30 * 60
        advance(1)
        #expect(model.phase == .away)
    }

    @Test("稍后提醒的实际时长不超过专注时长")
    func effectiveSnoozeInterval() {
        #expect(model.effectiveSnoozeInterval == 5 * 60)
        model.setWorkInterval(3 * 60)
        #expect(model.effectiveSnoozeInterval == 3 * 60)
    }

    @Test("工作时段外手动开始后重启 App：恢复后不会被重新冻结")
    func overrideSurvivesRelaunch() {
        model.start()
        clock.workTime = false
        advance(1)
        model.start()
        advance(60)
        let snapshot = model.snapshot()
        clock.advance(10)
        let clock = clock
        let reopened = EyeBreakModel(
            workInterval: 20 * 60, restDuration: 20, reminder: spy,
            now: { clock.now }, idleTime: { 0 }, isInMeeting: { false }, isFullscreen: { false },
            isWorkTime: { clock.workTime }, awayThreshold: 5 * 60, usesSystemTimer: false
        )
        reopened.restore(snapshot)
        reopened.tick()
        #expect(reopened.phase == .working)
    }

    // MARK: - 工作时段

    @Test("只有工作时段外使用 30 秒间隔，其余阶段保持 1 秒")
    func tickIntervalsByPhase() {
        #expect(EyeBreakModel.tickInterval(for: .offHours) == 30)
        for phase: EyeBreakModel.Phase in [.idle, .working, .paused, .awaitingBreak, .resting, .away] {
            #expect(EyeBreakModel.tickInterval(for: phase) == 1)
        }
    }

    /// 使用假时钟检查真实 Timer 的安装和销毁，全程同步执行，不等待系统计时器触发。
    private func makeSystemTimerModel() -> EyeBreakModel {
        let clock = clock
        return EyeBreakModel(
            workInterval: 20 * 60, restDuration: 20, reminder: spy,
            now: { clock.now }, idleTime: { clock.idle }, isInMeeting: { clock.inMeeting },
            isFullscreen: { clock.fullscreen }, isWorkTime: { clock.workTime }, awayThreshold: 5 * 60
        )
    }

    @Test("进出工作时段外重建唯一 Timer，稳定阶段不重复安装")
    func offHoursRebuildsOnlyOneTimer() {
        let timedModel = makeSystemTimerModel()
        defer { timedModel.shutdown() }
        #expect(timedModel.activeTimerCount == 0)
        timedModel.startAutomatically()
        #expect(timedModel.activeTimerInterval == 1)
        #expect(timedModel.tickerStartCount == 1)
        for transition in 1...3 {
            clock.workTime = false
            timedModel.tick()
            #expect(timedModel.phase == .offHours)
            #expect(timedModel.activeTimerCount == 1)
            #expect(timedModel.activeTimerInterval == 30)
            #expect(timedModel.tickerStartCount == transition * 2)
            clock.advance(30)
            timedModel.tick()
            #expect(timedModel.tickerStartCount == transition * 2)

            clock.workTime = true
            timedModel.tick()
            #expect(timedModel.phase == .working)
            #expect(timedModel.activeTimerCount == 1)
            #expect(timedModel.activeTimerInterval == 1)
            #expect(timedModel.tickerStartCount == transition * 2 + 1)
            timedModel.tick()
            #expect(timedModel.tickerStartCount == transition * 2 + 1)
        }
        timedModel.shutdown()
        #expect(timedModel.activeTimerCount == 0)
        #expect(timedModel.activeTimerInterval == nil)
    }

    @Test("离开电脑仍使用 1 秒检查，最近 3 秒输入能够恢复专注")
    func awayKeepsOneSecondTimer() {
        let timedModel = makeSystemTimerModel()
        defer { timedModel.shutdown() }
        timedModel.start()
        clock.idle = 600
        timedModel.tick()
        #expect(timedModel.phase == .away)
        #expect(timedModel.activeTimerCount == 1)
        #expect(timedModel.activeTimerInterval == 1)
        clock.idle = 2.9
        timedModel.tick()
        #expect(timedModel.phase == .working)
        #expect(timedModel.activeTimerInterval == 1)
    }

    @Test("系统时钟和时区通知立即退出工作时段外，无需等待 30 秒", arguments: [
        Notification.Name.NSSystemClockDidChange, .NSSystemTimeZoneDidChange
    ])
    func timeNotificationsImmediatelyRecalculateSchedule(notification: Notification.Name) {
        let timedModel = makeSystemTimerModel()
        defer { timedModel.shutdown() }
        clock.workTime = false
        timedModel.startAutomatically()
        timedModel.tick()
        #expect(timedModel.phase == .offHours)
        #expect(timedModel.activeTimerInterval == 30)

        clock.workTime = true
        NotificationCenter.default.post(name: notification, object: nil)
        #expect(timedModel.phase == .working)
        #expect(timedModel.remainingSeconds == 1200)
        #expect(timedModel.activeTimerCount == 1)
        #expect(timedModel.activeTimerInterval == 1)

        // 仍在工作时段的重复通知只刷新状态，不再创建计时器。
        let starts = timedModel.tickerStartCount
        NotificationCenter.default.post(name: notification, object: nil)
        #expect(timedModel.tickerStartCount == starts)
    }

    @Test("工作时段外唤醒立即恢复新一轮专注")
    func wakeImmediatelyRecalculatesOffHours() {
        clock.workTime = false
        model.startAutomatically()
        model.tick()
        #expect(model.phase == .offHours)
        model.systemWillSleep()
        clock.advance(60)
        clock.workTime = true
        model.systemDidWake()
        #expect(model.phase == .working)
        #expect(model.remainingSeconds == 1200)
        #expect(!model.isOverridingSchedule)
    }

    @Test("修改工作时段后同步读取新设置并恢复专注，不重复通知")
    func scheduleSettingsImmediatelyRecalculate() {
        let suiteName = "EyeBreakTests.scheduleChange.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = WorkScheduleSettings(defaults: defaults)
        // 假时钟位于 UTC 13 点，9 点至 10 点的设置使模型进入工作时段外。
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        settings.schedule = WorkSchedule(isEnabled: true, startHour: 9, endHour: 10, weekdaysOnly: false)
        let clock = clock
        let scheduledModel = EyeBreakModel(
            workInterval: 1200, restDuration: 20, reminder: spy,
            now: { clock.now }, idleTime: { 0 }, isInMeeting: { false }, isFullscreen: { false },
            isWorkTime: { settings.schedule.contains(clock.now, calendar: calendar) }, usesSystemTimer: false
        )
        var changes = 0
        settings.onScheduleChanged = { [weak scheduledModel] in
            changes += 1
            scheduledModel?.workScheduleDidChange()
        }
        scheduledModel.startAutomatically()
        scheduledModel.tick()
        #expect(scheduledModel.phase == .offHours)

        settings.schedule.isEnabled = false
        #expect(changes == 1)
        #expect(scheduledModel.phase == .working)
        #expect(scheduledModel.remainingSeconds == 1200)
        #expect(!WorkScheduleSettings(defaults: defaults).schedule.isEnabled)
        settings.schedule.isEnabled = false
        #expect(changes == 1)
    }

    @Test("手动覆盖工作时段后，时间、设置和唤醒重算不会重新冻结")
    func immediateScheduleChecksPreserveManualOverride() {
        clock.workTime = false
        model.startAutomatically()
        model.tick()
        model.start()
        #expect(model.phase == .working)
        model.systemTimeDidChange()
        model.workScheduleDidChange()
        #expect(model.phase == .working)
        #expect(model.isOverridingSchedule)
        model.systemWillSleep()
        clock.advance(60)
        model.systemDidWake()
        #expect(model.phase == .working)
        #expect(model.isOverridingSchedule)
        model.pause()
        model.start()
        model.workScheduleDidChange()
        advance(1)
        #expect(model.phase == .working)
        #expect(model.remainingSeconds == 1199)
    }

    @Test("工作时段外从未开始点开始：视为用户覆盖，不被下一次刷新冻结")
    func startFromIdleOutsideWorkHours() {
        clock.workTime = false
        model.start()
        advance(1)
        #expect(model.phase == .working)
        #expect(model.remainingSeconds == 1199)
        #expect(model.snapshot().overridesSchedule == true)
    }

    @Test("工作时段外从暂停点继续：保留剩余时间并视为用户覆盖")
    func resumeFromPausedOutsideWorkHours() {
        model.start()
        advance(100)
        model.pause()
        clock.workTime = false
        advance(1)
        model.start()
        advance(1)
        #expect(model.phase == .working)
        #expect(model.remainingSeconds == 1099)
        #expect(model.snapshot().overridesSchedule == true)
    }

    @Test("工作时段外手动重来：视为用户覆盖")
    func resetOutsideWorkHours() {
        clock.workTime = false
        model.reset()
        advance(1)
        #expect(model.phase == .working)
        #expect(model.snapshot().overridesSchedule == true)
    }

    @Test("工作时段外立即开始休息：覆盖贯穿休息和自然开始的下一轮")
    func immediateBreakOutsideWorkHoursOverridesSchedule() {
        clock.workTime = false
        model.startBreakNow()
        #expect(model.phase == .resting)
        #expect(model.snapshot().overridesSchedule == true)
        advance(20)
        advance(1)
        #expect(model.phase == .working)
        #expect(model.snapshot().overridesSchedule == true)
    }

    @Test("工作时段外主动开始休息、跳过或稍后提醒都视为用户覆盖", arguments: ["startBreak", "skipBreak", "snooze"])
    func breakActionsOutsideWorkHoursOverrideSchedule(action: String) {
        finishWorkRound()
        clock.workTime = false
        switch action {
        case "startBreak": model.startBreak()
        case "skipBreak": model.skipBreak()
        default: model.snooze()
        }
        advance(1)
        #expect(model.phase == (action == "startBreak" ? .resting : .working))
        #expect(model.snapshot().overridesSchedule == true)
    }

    @Test("工作时段外自动启动：不设置用户覆盖并正常冻结")
    func automaticStartDoesNotOverrideSchedule() {
        clock.workTime = false
        model.startAutomatically()
        #expect(model.snapshot().overridesSchedule == false)
        advance(1)
        #expect(model.phase == .offHours)
    }

    @Test("睡眠唤醒的自动恢复不设置用户覆盖", arguments: [60.0, 600.0])
    func automaticWakeDoesNotOverrideSchedule(sleepDuration: TimeInterval) {
        model.start()
        advance(100)
        model.systemWillSleep()
        clock.workTime = false
        clock.advance(sleepDuration)
        model.systemDidWake()
        #expect(model.snapshot().overridesSchedule == false)
        model.tick()
        #expect(model.phase == .offHours)
    }

    @Test("离开后自动回来不创建用户覆盖")
    func automaticReturnDoesNotOverrideSchedule() {
        model.start()
        clock.idle = 600
        advance(1)
        clock.idle = 0
        advance(1)
        #expect(model.phase == .working)
        #expect(model.snapshot().overridesSchedule == false)
        clock.workTime = false
        advance(1)
        #expect(model.phase == .offHours)
    }

    @Test("进入工作时段自动开始的一轮不创建用户覆盖")
    func automaticScheduleStartDoesNotOverrideSchedule() {
        clock.workTime = false
        model.startAutomatically()
        advance(1)
        clock.workTime = true
        advance(1)
        #expect(model.phase == .working)
        #expect(model.snapshot().overridesSchedule == false)
        clock.workTime = false
        advance(1)
        #expect(model.phase == .offHours)
    }

    @Test("专注中离开工作时段：冻结计时、不提醒")
    func leavesWorkHoursWhileWorking() {
        model.start()
        advance(60)
        clock.workTime = false
        advance(1)
        #expect(model.phase == .offHours)
        advance(3 * 3600)
        #expect(model.phase == .offHours)
        #expect(spy.delivered.isEmpty)
        #expect(model.menuBarText == nil)
    }

    @Test("进入工作时段：自动开始新一轮")
    func workHoursStartNewRound() {
        model.start()
        clock.workTime = false
        advance(1)
        clock.workTime = true
        advance(1)
        #expect(model.phase == .working)
        #expect(model.formattedRemaining == "20:00")
    }

    @Test("等待休息时离开工作时段：收起提醒")
    func leavesWorkHoursWhileAwaitingBreak() {
        finishWorkRound()
        clock.workTime = false
        advance(1)
        #expect(model.phase == .offHours)
        #expect(spy.cancelled >= 1)
    }

    @Test("工作时段外手动开始：照常计时直到下次进入工作时段")
    func manualStartOutsideWorkHours() {
        model.start()
        clock.workTime = false
        advance(1)
        model.start()
        #expect(model.phase == .working)
        advance(60)
        #expect(model.phase == .working)
        advance(19 * 60)
        #expect(model.phase == .awaitingBreak)
        #expect(spy.delivered.count == 1)
    }

    @Test("工作时段外手动开始后，下一个工作时段结束时照常冻结")
    func overrideEndsWithNextWorkPeriod() {
        model.start()
        clock.workTime = false
        advance(1)
        model.start()
        advance(60)
        clock.workTime = true
        advance(1)
        clock.workTime = false
        advance(1)
        #expect(model.phase == .offHours)
    }

    @Test("暂停中离开工作时段：保持暂停")
    func pausedStaysPausedOutsideWorkHours() {
        model.start()
        model.pause()
        clock.workTime = false
        advance(1)
        #expect(model.phase == .paused)
    }

    @Test("休息中离开工作时段：先让本次休息结束，之后再冻结")
    func restFinishesBeforeOffHours() {
        finishWorkRound()
        model.startBreak()
        clock.workTime = false
        advance(5)
        #expect(model.phase == .resting)
        advance(15)
        #expect(model.phase == .working)
        #expect(model.snapshot().overridesSchedule == false)
        advance(1)
        #expect(model.phase == .offHours)
        #expect(spy.breakCompleteSounds == 1)
    }

    // MARK: - 状态保存与恢复

    /// 用同一个时钟新建一个模型，模拟重新打开 App
    private func relaunch() -> EyeBreakModel {
        let clock = clock
        return EyeBreakModel(
            workInterval: model.workInterval, restDuration: model.restDuration, reminder: spy,
            now: { clock.now }, idleTime: { clock.idle }, isInMeeting: { clock.inMeeting }, isFullscreen: { clock.fullscreen }, isWorkTime: { clock.workTime }, awayThreshold: 5 * 60,
            exerciseIndex: model.exerciseIndex, usesSystemTimer: false
        )
    }

    @Test("稍后提醒中重启：恢复短计时进度，到点不额外轮换休息动作")
    func restoreSnoozingWhileWorking() {
        finishWorkRound()
        model.snooze()
        advance(60)
        let snapshot = model.snapshot()
        #expect(snapshot.isSnoozing == true)
        #expect(snapshot.roundTotal == 300)
        clock.advance(30)

        let reopened = relaunch()
        reopened.restore(snapshot)
        #expect(reopened.phase == .working)
        #expect(reopened.isSnoozing)
        #expect(reopened.remainingSeconds == 210)
        #expect(abs(reopened.progress - 0.3) < 0.000_001)
        #expect(reopened.currentRoundTotal == 300)
        #expect(reopened.workIntervalChangePending)
        let exerciseIndex = reopened.exerciseIndex
        clock.advance(210)
        reopened.tick()
        #expect(reopened.phase == .awaitingBreak)
        #expect(reopened.exerciseIndex == exerciseIndex)
    }

    @Test("暂停中的稍后提醒重启：长时间后仍保留短计时进度和休息动作")
    func restoreSnoozingWhilePaused() {
        finishWorkRound()
        model.snooze()
        advance(60)
        model.pause()
        let snapshot = model.snapshot()
        clock.advance(3600)

        let reopened = relaunch()
        reopened.restore(snapshot)
        #expect(reopened.phase == .paused)
        #expect(reopened.isSnoozing)
        #expect(reopened.remainingSeconds == 240)
        #expect(abs(reopened.progress - 0.2) < 0.000_001)
        #expect(reopened.currentRoundTotal == 300)
        #expect(reopened.workIntervalChangePending)
        let exerciseIndex = reopened.exerciseIndex
        reopened.start()
        clock.advance(240)
        reopened.tick()
        #expect(reopened.phase == .awaitingBreak)
        #expect(reopened.exerciseIndex == exerciseIndex)
    }

    @Test("稍后提醒中退出很久再打开：视为已经休息，恢复普通完整专注")
    func restoreSnoozingAfterLongGap() {
        finishWorkRound()
        model.snooze()
        let snapshot = model.snapshot()
        clock.advance(600)
        let reopened = relaunch()
        reopened.restore(snapshot)
        #expect(reopened.phase == .working)
        #expect(!reopened.isSnoozing)
        #expect(reopened.remainingSeconds == 1200)
        #expect(reopened.progress == 0)
    }

    @Test("旧版本缺少稍后提醒和本轮总时长字段的快照按普通专注恢复", arguments: [false, true])
    func restoreLegacySnapshot(paused: Bool) throws {
        let data = try JSONSerialization.data(withJSONObject: [
            "phase": paused ? "paused" : "working",
            "remaining": 240,
            "savedAt": clock.now.timeIntervalSinceReferenceDate
        ])
        let snapshot = try JSONDecoder().decode(EyeBreakModel.Snapshot.self, from: data)
        #expect(snapshot.isSnoozing == nil)
        #expect(snapshot.roundTotal == nil)

        let reopened = relaunch()
        reopened.restore(snapshot)
        #expect(reopened.phase == (paused ? .paused : .working))
        #expect(!reopened.isSnoozing)
        #expect(reopened.remainingSeconds == 240)
        #expect(reopened.progress == 0.8)
        reopened.start()
        clock.advance(240)
        reopened.tick()
        #expect(reopened.phase == .awaitingBreak)
        #expect(reopened.exerciseIndex == 0)
    }

    @Test("本轮专注中改短设置再重启：保留原有总时长和剩余时间", arguments: [false, true])
    func restoreRoundTotalAfterPreferenceChange(paused: Bool) {
        model.start()
        advance(100)
        model.setWorkInterval(600)
        if paused { model.pause() }
        let snapshot = model.snapshot()
        let reopened = relaunch()
        reopened.restore(snapshot)
        #expect(reopened.remainingSeconds == 1100)
        #expect(abs(reopened.progress - 100.0 / 1200) < 0.000_001)
        #expect(!reopened.isSnoozing)
        #expect(reopened.currentRoundTotal == 1200)
        #expect(reopened.workIntervalChangePending)
        reopened.setWorkInterval(1200)
        #expect(!reopened.workIntervalChangePending)
    }

    @Test("休息中改时长后重启：重新等待休息时使用新设置，不沿用旧休息进度")
    func restoreRestingWithChangedDuration() {
        finishWorkRound()
        model.startBreak()
        advance(5)
        model.setRestDuration(60)
        let snapshot = model.snapshot()
        clock.advance(10)

        let reopened = relaunch()
        reopened.restore(snapshot)
        #expect(reopened.phase == .awaitingBreak)
        #expect(reopened.remainingSeconds == 60)
        #expect(reopened.progress == 0)
        #expect(!reopened.restDurationChangePending)
        #expect(spy.delivered.count == 1)
        reopened.startBreak()
        #expect(reopened.currentBreakDuration == 60)
        #expect(!reopened.restDurationChangePending)
        clock.advance(15)
        reopened.tick()
        #expect(reopened.remainingSeconds == 45)
        #expect(reopened.progress == 0.25)
    }

    @Test("退出时保存的是退出前的真实状态，而不是清理后的未开始")
    func shutdownSavesRealState() {
        var saved: [EyeBreakModel.Snapshot] = []
        model.onSnapshot = { saved.append($0) }
        model.start()
        advance(100)
        model.shutdown()
        #expect(saved.last?.phase == .working)
        #expect(saved.last?.remaining == 1100)
    }

    @Test("专注中退出、1 分钟内重新打开：扣掉中间的时间继续")
    func restoreWorkingShortGap() {
        model.start()
        advance(100)
        let snapshot = model.snapshot()
        clock.advance(60)
        let reopened = relaunch()
        reopened.restore(snapshot)
        #expect(reopened.phase == .working)
        #expect(reopened.formattedRemaining == "17:20")
        #expect(reopened.currentRoundTotal == 1200)
        #expect(!reopened.workIntervalChangePending)
    }

    @Test("专注中退出、隔了很久（如重启）再打开：开始新一轮")
    func restoreWorkingLongGap() {
        model.start()
        advance(100)
        let snapshot = model.snapshot()
        clock.advance(3600)
        let reopened = relaunch()
        reopened.restore(snapshot)
        #expect(reopened.phase == .working)
        #expect(reopened.formattedRemaining == "20:00")
    }

    @Test("暂停中退出：无论隔多久都保持暂停和剩余时间")
    func restorePaused() {
        model.start()
        advance(100)
        model.pause()
        let snapshot = model.snapshot()
        clock.advance(3 * 86400)
        let reopened = relaunch()
        reopened.restore(snapshot)
        #expect(reopened.phase == .paused)
        #expect(reopened.formattedRemaining == "18:20")
    }

    @Test("等待休息时退出、很快重新打开：重新弹出提醒，但不重复响铃")
    func restoreAwaitingShortGap() {
        finishWorkRound()
        let snapshot = model.snapshot()
        clock.advance(30)
        let reopened = relaunch()
        reopened.restore(snapshot)
        #expect(reopened.phase == .awaitingBreak)
        #expect(spy.delivered.count == 1)
    }

    @Test("休息中退出、隔了很久再打开：算已经休息过，开始新一轮")
    func restoreRestingLongGap() {
        finishWorkRound()
        model.startBreak()
        let snapshot = model.snapshot()
        clock.advance(3600)
        let reopened = relaunch()
        reopened.restore(snapshot)
        #expect(reopened.phase == .working)
        #expect(reopened.formattedRemaining == "20:00")
    }

    @Test("未开始时退出：重新打开仍是未开始")
    func restoreIdle() {
        let reopened = relaunch()
        reopened.restore(model.snapshot())
        #expect(reopened.phase == .idle)
    }

    @Test("快照可以编码再解码")
    func snapshotCodable() throws {
        model.start()
        advance(42)
        let snapshot = model.snapshot()
        let decoded = try JSONDecoder().decode(EyeBreakModel.Snapshot.self, from: JSONEncoder().encode(snapshot))
        #expect(decoded == snapshot)
    }

    @Test("TC-13 退出后不再触发提醒")
    func shutdownStopsReminders() {
        model.start()
        model.shutdown()
        advance(3600)
        #expect(spy.delivered.isEmpty)
        #expect(spy.cancelled >= 1)
        #expect(model.phase == .idle)
    }
}
