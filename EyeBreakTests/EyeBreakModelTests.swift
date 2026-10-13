import Combine
import Foundation
import Testing
@testable import EyeBreak

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
        model.setRestDuration(60)
        advance(15)
        #expect(model.phase == .working)
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

    @Test("第一次休息是看看远处，之后依次轮换并循环")
    func exercisesRotate() {
        var seen: [RestExercise] = []
        model.start()
        for _ in 0..<5 {
            advance(20 * 60)
            seen.append(model.exercise)
            // 跳过休息会直接开始新一轮专注
            model.skipBreak()
        }
        #expect(seen == [.lookFar, .blink, .closeEyes, .rollEyes, .lookFar])
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
        advance(1)
        #expect(model.phase == .offHours)
        #expect(spy.breakCompleteSounds == 1)
    }

    // MARK: - 状态保存与恢复

    /// 用同一个时钟新建一个模型，模拟重新打开 App
    private func relaunch() -> EyeBreakModel {
        let clock = clock
        return EyeBreakModel(
            workInterval: 20 * 60, restDuration: 20, reminder: spy,
            now: { clock.now }, idleTime: { clock.idle }, isInMeeting: { clock.inMeeting }, isFullscreen: { clock.fullscreen }, isWorkTime: { clock.workTime }, awayThreshold: 5 * 60,
            usesSystemTimer: false
        )
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
