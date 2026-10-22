import Foundation
import Testing
@testable import EyeBreak

@MainActor
private final class LongBreakReminder: ReminderDelivering {
    var delivered: [TimeInterval] = []
    func deliverReminder(restDuration: TimeInterval) { delivered.append(restDuration) }
    func cancelPendingReminders() {}
    func playBreakComplete() {}
}

@MainActor
private final class LongBreakClock {
    // 2026-10-12 10:00 UTC，便于用 UTC 日历验证「明天」
    var now = Date(timeIntervalSince1970: 1_791_799_200)
    var workTime = true
}

/// 长休息：每 N 轮用一次更长的休息做起身活动
@MainActor
struct LongBreakTests {
    private let clock = LongBreakClock()
    private let spy = LongBreakReminder()
    private let model: EyeBreakModel

    init() {
        let clock = clock
        model = EyeBreakModel(
            workInterval: 20 * 60, restDuration: 20, reminder: spy,
            now: { clock.now }, idleTime: { 0 }, isInMeeting: { false }, isFullscreen: { false },
            isWorkTime: { clock.workTime }, awayThreshold: 5 * 60,
            longBreak: LongBreakSettings(isEnabled: true, everyRounds: 4, minutes: 3),
            usesSystemTimer: false
        )
    }

    private func advance(_ seconds: TimeInterval) {
        clock.now += seconds
        model.tick()
    }

    /// 走完一轮专注到提醒出现
    private func finishRound() {
        model.start()
        advance(20 * 60)
        #expect(model.phase == .awaitingBreak)
    }

    /// 开始并自然完成这次休息
    private func takeBreak() {
        model.startBreak()
        advance(model.currentBreakDuration + 1)
        #expect(model.phase == .working)
    }

    @Test("默认设置：开启，每 4 轮一次，3 分钟")
    func defaults() {
        let settings = LongBreakSettings()
        #expect(settings.isEnabled)
        #expect(settings.everyRounds == 4)
        #expect(settings.minutes == 3)
        #expect(settings.duration == 180)
        #expect(LongBreakSettings(isEnabled: true, everyRounds: 99, minutes: 0).normalized() == LongBreakSettings(isEnabled: true, everyRounds: 8, minutes: 1))
    }

    @Test("前三轮是 20 秒的眼睛动作，第四轮是 3 分钟的起身活动，之后重新计数")
    func everyFourthBreakIsLong() {
        for round in 1...3 {
            finishRound()
            #expect(!model.isLongBreak, "第 \(round) 轮应为短休息")
            #expect(!model.exercise.isBodyActivity)
            #expect(model.plannedBreakDuration == 20)
            #expect(model.remainingSeconds == 20)
            takeBreak()
        }
        finishRound()
        #expect(model.isLongBreak)
        #expect(model.exercise.isBodyActivity)
        #expect(model.plannedBreakDuration == 180)
        #expect(model.remainingSeconds == 180)
        #expect(spy.delivered.last == 180)
        #expect(model.progress == 0)
        takeBreak()
        #expect(!model.isLongBreak)
        #expect(model.roundsSinceLongBreak == 0)

        // 第二个周期：又是三短一长
        for _ in 1...3 {
            finishRound()
            #expect(!model.isLongBreak)
            takeBreak()
        }
        finishRound()
        #expect(model.isLongBreak)
    }

    @Test("长休息的进度和倒计时按 3 分钟计算，眺望时长的修改不影响它")
    func longBreakUsesItsOwnDuration() {
        for _ in 1...3 { finishRound(); takeBreak() }
        finishRound()
        model.startBreak()
        #expect(model.currentBreakDuration == 180)
        advance(90)
        #expect(model.remainingSeconds == 90)
        #expect(abs(model.progress - 0.5) < 0.01)
        model.setRestDuration(60)
        #expect(!model.restDurationChangePending)
        #expect(model.currentBreakDuration == 180)
    }

    @Test("短休息只轮换眼睛动作，起身活动留给长休息")
    func shortBreaksRotateEyeExercisesOnly() {
        var seen: [RestExercise] = []
        for _ in 1...7 {
            finishRound()
            if !model.isLongBreak { seen.append(model.exercise) }
            takeBreak()
        }
        #expect(seen.count == 6)
        #expect(seen.allSatisfy { !$0.isBodyActivity })
        #expect(seen.prefix(4) == [.lookFar, .blink, .closeEyes, .rollEyes])
    }

    @Test("两个起身活动在长休息之间交替")
    func longBreaksAlternateBodyActivities() {
        var longOnes: [RestExercise] = []
        for _ in 1...12 {
            finishRound()
            if model.isLongBreak { longOnes.append(model.exercise) }
            takeBreak()
        }
        #expect(longOnes == [.drinkWater, .walk, .drinkWater])
    }

    @Test("稍后提醒保持同一次长休息，不多算一轮")
    func snoozeKeepsLongBreak() {
        for _ in 1...3 { finishRound(); takeBreak() }
        finishRound()
        #expect(model.isLongBreak)
        let exercise = model.exercise
        model.snooze()
        #expect(model.isLongBreak)
        advance(5 * 60)
        #expect(model.phase == .awaitingBreak)
        #expect(model.isLongBreak)
        #expect(model.exercise == exercise)
        #expect(model.plannedBreakDuration == 180)
        #expect(model.roundsSinceLongBreak == 0)
    }

    @Test("跳过长休息后重新计数，下一轮回到短休息")
    func skippingLongBreakResetsCount() {
        for _ in 1...3 { finishRound(); takeBreak() }
        finishRound()
        #expect(model.isLongBreak)
        model.skipBreak()
        #expect(!model.isLongBreak)
        advance(20 * 60)
        #expect(model.phase == .awaitingBreak)
        #expect(!model.isLongBreak)
        #expect(model.roundsSinceLongBreak == 1)
    }

    @Test("主动「现在休息」按短休息处理，也不消耗长休息轮数")
    func startBreakNowIsAlwaysShort() {
        for _ in 1...3 { finishRound(); takeBreak() }
        model.start()
        advance(60)
        model.startBreakNow()
        #expect(model.phase == .resting)
        #expect(!model.isLongBreak)
        #expect(model.currentBreakDuration == 20)
        #expect(!model.exercise.isBodyActivity)
        advance(21)
        finishRound()
        #expect(model.isLongBreak)
    }

    @Test("关闭长休息后，所有启用的动作一起轮换，休息都是眺望时长")
    func disabledLongBreakRotatesEverything() {
        model.setLongBreak(LongBreakSettings(isEnabled: false, everyRounds: 4, minutes: 3))
        var seen: [RestExercise] = []
        for _ in 1...6 {
            finishRound()
            #expect(!model.isLongBreak)
            #expect(model.plannedBreakDuration == 20)
            seen.append(model.exercise)
            takeBreak()
        }
        #expect(seen == RestExercise.allCases)
    }

    @Test("起身活动全关时，长休息轮到眼睛动作；眼睛动作全关时短休息轮到起身活动")
    func fallsBackWhenCategoryEmpty() {
        model.setEnabledExercises([.lookFar, .blink])
        for _ in 1...3 { finishRound(); takeBreak() }
        finishRound()
        #expect(model.isLongBreak)
        #expect(!model.exercise.isBodyActivity)
        #expect(model.plannedBreakDuration == 180)
        takeBreak()

        model.setEnabledExercises([.walk])
        finishRound()
        #expect(!model.isLongBreak)
        #expect(model.exercise == .walk)
        #expect(model.plannedBreakDuration == 20)
    }

    @Test("修改轮数立即影响下一次到点的判断")
    func changingRoundsAppliesToNextReminder() {
        finishRound(); takeBreak()
        model.setLongBreak(LongBreakSettings(isEnabled: true, everyRounds: 2, minutes: 5))
        finishRound()
        #expect(model.isLongBreak)
        #expect(model.plannedBreakDuration == 300)
        #expect(spy.delivered.last == 300)
    }

    @Test("等待长休息时修改时长，面板显示新时长；已开始的长休息不变")
    func changingMinutesWhileWaiting() {
        for _ in 1...3 { finishRound(); takeBreak() }
        finishRound()
        model.setLongBreak(LongBreakSettings(isEnabled: true, everyRounds: 4, minutes: 5))
        #expect(model.remainingSeconds == 300)
        model.startBreak()
        model.setLongBreak(LongBreakSettings(isEnabled: true, everyRounds: 4, minutes: 1))
        #expect(model.currentBreakDuration == 300)
    }

    @Test("快照保存并恢复长休息计数和待开始的长休息")
    func snapshotRoundTrip() throws {
        for _ in 1...2 { finishRound(); takeBreak() }
        model.start()
        advance(60)
        let snapshot = model.snapshot()
        #expect(snapshot.roundsSinceLongBreak == 2)
        #expect(snapshot.isLongBreak == false)
        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(EyeBreakModel.Snapshot.self, from: data)
        #expect(decoded == snapshot)

        let restored = EyeBreakModel(
            workInterval: 20 * 60, restDuration: 20, reminder: spy,
            now: { [clock] in clock.now }, idleTime: { 0 }, isInMeeting: { false }, isFullscreen: { false },
            longBreak: LongBreakSettings(isEnabled: true, everyRounds: 4, minutes: 3), usesSystemTimer: false
        )
        restored.restore(decoded)
        #expect(restored.roundsSinceLongBreak == 2)
        clock.now += 19 * 60
        restored.tick()
        #expect(restored.phase == .awaitingBreak)
        #expect(!restored.isLongBreak)
        restored.startBreak()
        clock.now += 21
        restored.tick()
        restored.start()
        clock.now += 20 * 60
        restored.tick()
        #expect(restored.isLongBreak)

        // 等待长休息时退出再打开，仍是长休息
        let pending = restored.snapshot()
        #expect(pending.isLongBreak == true)
        let again = EyeBreakModel(
            workInterval: 20 * 60, restDuration: 20, reminder: spy,
            now: { [clock] in clock.now }, idleTime: { 0 }, isInMeeting: { false }, isFullscreen: { false },
            exerciseIndex: restored.exerciseIndex,
            longBreak: LongBreakSettings(isEnabled: true, everyRounds: 4, minutes: 3), usesSystemTimer: false
        )
        again.restore(pending)
        #expect(again.phase == .awaitingBreak)
        #expect(again.isLongBreak)
        #expect(again.plannedBreakDuration == 180)
    }

    @Test("旧版本快照没有长休息字段时按零轮、短休息恢复")
    func legacySnapshotDecodes() throws {
        let json = #"{"phase":"working","remaining":600,"savedAt":813919503.7}"#
        let snapshot = try JSONDecoder().decode(EyeBreakModel.Snapshot.self, from: Data(json.utf8))
        #expect(snapshot.isLongBreak == nil)
        #expect(snapshot.roundsSinceLongBreak == nil)
        #expect(snapshot.pausedUntil == nil)
    }

    @Test("长休息设置写入偏好后能读回，损坏的值夹回范围")
    func configRoundTrip() throws {
        let suite = "EyeBreakTests.longBreak.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(EyeBreakConfig.loadLongBreak(from: defaults) == LongBreakSettings())
        let custom = LongBreakSettings(isEnabled: false, everyRounds: 6, minutes: 10)
        EyeBreakConfig.saveLongBreak(custom, to: defaults)
        #expect(EyeBreakConfig.loadLongBreak(from: defaults) == custom)
        defaults.set(Data(#"{"isEnabled":true,"everyRounds":1,"minutes":60}"#.utf8), forKey: "longBreak")
        #expect(EyeBreakConfig.loadLongBreak(from: defaults) == LongBreakSettings(isEnabled: true, everyRounds: 2, minutes: 15))
        defaults.set(Data("junk".utf8), forKey: "longBreak")
        #expect(EyeBreakConfig.loadLongBreak(from: defaults) == LongBreakSettings())
    }

    @Test("提醒面板文案：整分钟说分钟，其余说秒")
    func panelHints() {
        #expect(BreakPanelView.breakHint(instruction: "起身走一走", duration: 180) == String(localized: "\("起身走一走")，放松 \(3) 分钟"))
        #expect(BreakPanelView.breakHint(instruction: "慢慢眨眨眼", duration: 20) == String(localized: "\("慢慢眨眨眼")，放松 \(20) 秒"))
        #expect(BreakPanelView.breakHint(instruction: "x", duration: 90) == String(localized: "\("x")，放松 \(90) 秒"))
        #expect(BreakPanelView.remainingText(seconds: 150) == String(localized: "还剩 \(2) 分 \(30) 秒"))
        #expect(BreakPanelView.remainingText(seconds: 59) == String(localized: "还剩 \(59) 秒"))
    }
}

/// 暂停一段时间：到点自动继续
@MainActor
struct TimedPauseTests {
    private let clock = LongBreakClock()
    private let spy = LongBreakReminder()
    private let model: EyeBreakModel
    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    init() {
        let clock = clock
        model = EyeBreakModel(
            workInterval: 20 * 60, restDuration: 20, reminder: spy,
            now: { clock.now }, idleTime: { 0 }, isInMeeting: { false }, isFullscreen: { false },
            isWorkTime: { clock.workTime }, awayThreshold: 5 * 60, usesSystemTimer: false
        )
    }

    private func advance(_ seconds: TimeInterval) {
        clock.now += seconds
        model.tick()
    }

    @Test("三个选项的继续时刻：1 小时、2 小时、下一个零点")
    func resumeDates() {
        let now = clock.now
        #expect(TimedPause.oneHour.resumeDate(from: now, calendar: utc) == now.addingTimeInterval(3600))
        #expect(TimedPause.twoHours.resumeDate(from: now, calendar: utc) == now.addingTimeInterval(7200))
        let tomorrow = TimedPause.restOfDay.resumeDate(from: now, calendar: utc)
        #expect(utc.component(.hour, from: tomorrow) == 0)
        #expect(utc.isDate(tomorrow, inSameDayAs: now.addingTimeInterval(86400)))
        #expect(TimedPause.resumeText(for: tomorrow, now: now, calendar: utc) == String(localized: "明天继续"))
        let inAnHour = now.addingTimeInterval(3600)
        #expect(TimedPause.resumeText(for: inAnHour, now: now, calendar: utc) == String(localized: "\(inAnHour.formatted(date: .omitted, time: .shortened)) 继续"))
    }

    @Test("专注中选「2 小时后」：立即暂停，两小时后自动继续并接着原进度")
    func pausesAndAutoResumes() {
        model.start()
        advance(5 * 60)
        model.pause(for: .twoHours)
        #expect(model.phase == .paused)
        #expect(model.timedPause == .twoHours)
        #expect(model.pausedUntil == clock.now.addingTimeInterval(7200))
        #expect(model.timedPauseResumeText != nil)
        #expect(model.formattedRemaining == "15:00")
        advance(7199)
        #expect(model.phase == .paused)
        advance(1)
        #expect(model.phase == .working)
        #expect(model.pausedUntil == nil)
        #expect(model.timedPause == nil)
        #expect(model.timedPauseResumeText == nil)
        #expect(model.formattedRemaining == "15:00")
        advance(15 * 60)
        #expect(model.phase == .awaitingBreak)
    }

    @Test("已暂停时再选时长只改时刻；点「继续」或「重来」会取消自动继续")
    func manualActionsCancelTimedPause() {
        model.start()
        model.pause()
        model.pause(for: .oneHour)
        #expect(model.pausedUntil == clock.now.addingTimeInterval(3600))
        model.pause(for: .twoHours)
        #expect(model.pausedUntil == clock.now.addingTimeInterval(7200))
        model.start()
        #expect(model.phase == .working)
        #expect(model.pausedUntil == nil)

        model.pause(for: .oneHour)
        model.reset()
        #expect(model.phase == .working)
        #expect(model.pausedUntil == nil)

        model.pause(for: .oneHour)
        model.cancelTimedPause()
        #expect(model.phase == .paused)
        #expect(model.pausedUntil == nil)
        advance(2 * 3600)
        #expect(model.phase == .paused)
    }

    @Test("未在计时或休息中时选项无效")
    func ignoredOutsideWorkingOrPaused() {
        model.pause(for: .oneHour)
        #expect(model.phase == .idle)
        #expect(model.pausedUntil == nil)
    }

    @Test("快照保存继续时刻；重开时未到点继续等，已到点接着计时")
    func snapshotRestore() throws {
        model.start()
        advance(60)
        model.pause(for: .oneHour)
        let snapshot = model.snapshot()
        #expect(snapshot.pausedUntil == model.pausedUntil)
        #expect(snapshot.timedPause == .oneHour)
        let decoded = try JSONDecoder().decode(EyeBreakModel.Snapshot.self, from: JSONEncoder().encode(snapshot))

        clock.now += 10 * 60
        let soon = EyeBreakModel(
            workInterval: 20 * 60, restDuration: 20, reminder: spy,
            now: { [clock] in clock.now }, idleTime: { 0 }, isInMeeting: { false }, isFullscreen: { false }, usesSystemTimer: false
        )
        soon.restore(decoded)
        #expect(soon.phase == .paused)
        #expect(soon.timedPause == .oneHour)
        #expect(soon.formattedRemaining == "19:00")
        clock.now += 50 * 60
        soon.tick()
        #expect(soon.phase == .working)

        // 到点很久以后才打开：当作离开过，开始新一轮
        clock.now += 3 * 3600
        let late = EyeBreakModel(
            workInterval: 20 * 60, restDuration: 20, reminder: spy,
            now: { [clock] in clock.now }, idleTime: { 0 }, isInMeeting: { false }, isFullscreen: { false }, usesSystemTimer: false
        )
        late.restore(decoded)
        #expect(late.phase == .working)
        #expect(late.pausedUntil == nil)
        #expect(late.formattedRemaining == "20:00")
    }

    @Test("定时暂停用 30 秒低频计时器，普通暂停不装计时器")
    func tickerInterval() {
        let timed = EyeBreakModel(workInterval: 1200, restDuration: 20, reminder: spy, idleTime: { 0 }, isInMeeting: { false }, isFullscreen: { false })
        defer { timed.shutdown() }
        timed.start()
        timed.pause()
        #expect(timed.activeTimerCount == 0)
        timed.pause(for: .oneHour)
        #expect(timed.activeTimerInterval == 30)
        timed.cancelTimedPause()
        #expect(timed.activeTimerCount == 0)
    }

    @Test("工作时段外到点自动继续不算用户覆盖，会被照常冻结")
    func autoResumeRespectsSchedule() {
        model.start()
        model.pause(for: .oneHour)
        clock.workTime = false
        advance(3600)
        #expect(model.phase == .working)
        advance(1)
        #expect(model.phase == .offHours)
    }
}
