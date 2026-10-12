import AppKit
import Combine
import os

/// 提醒的投递方（提示音）。抽成协议便于单元测试替换。
@MainActor
protocol ReminderDelivering: AnyObject {
    /// 专注结束：播放提醒音
    func deliverReminder(restDuration: TimeInterval)
    /// 停止正在播放的提醒（用户已经开始休息/跳过/离开/退出）
    func cancelPendingReminders()
    /// 休息完成的提示音
    func playBreakComplete()
}

@MainActor
final class EyeBreakModel: ObservableObject {
    enum Phase: Equatable {
        /// 尚未开始
        case idle
        /// 专注倒计时中
        case working
        /// 专注倒计时被用户暂停
        case paused
        /// 专注结束，等待用户点「开始休息」；期间计时冻结，不会重复提醒
        case awaitingBreak
        /// 休息倒计时中
        case resting
        /// 长时间没有键鼠操作，判定用户离开电脑；计时冻结，回来后开始新一轮
        case away
        /// 不在工作时段内：计时冻结、不提醒，进入工作时段后自动开始新一轮
        case offHours
    }

    /// 用于退出后恢复的计时快照
    struct Snapshot: Codable, Equatable {
        enum SavedPhase: String, Codable {
            case idle, working, paused, awaitingBreak, resting, away, offHours
        }
        var phase: SavedPhase
        /// 专注中：保存时刻的剩余时间；暂停中：暂停时的剩余时间
        var remaining: TimeInterval
        var savedAt: Date
    }

    @Published private(set) var phase: Phase = .idle {
        didSet { if phase != oldValue { persist() } }
    }
    /// 当前阶段要展示的剩余秒数（专注阶段是专注剩余，休息阶段是休息剩余）
    @Published private(set) var remainingSeconds: Int
    @Published private(set) var workInterval: TimeInterval
    @Published private(set) var restDuration: TimeInterval
    /// 当前这一轮是「稍后提醒」推迟出来的短计时
    @Published private(set) var isSnoozing = false
    /// 专注时间已到，但正在开会（麦克风使用中），提醒推迟到会议结束
    @Published private(set) var deferReason: DeferReason?

    /// 到点后推迟提醒的原因
    enum DeferReason: Equatable {
        /// 麦克风被会议软件占用
        case meeting
        /// 正在全屏使用某个 App（看视频、演示等）
        case fullscreen
        /// 处于设置了「暂停休息提醒」的专注模式
        case focus
    }

    /// 系统专注模式的过滤条件要求暂停提醒（由 App Intents 的专注模式过滤条件设置）
    @Published private(set) var isFocusHold = false

    var isDeferredForMeeting: Bool { deferReason == .meeting }
    /// 当前（或即将进行的）休息内容在轮换列表中的序号；每次正常提醒前往后挪一个
    @Published private(set) var exerciseIndex: Int

    var exercise: RestExercise { RestExercise.at(max(0, exerciseIndex)) }

    /// 休息倒计时自然结束时发出（提前结束、跳过不算），界面据此播放撒花动画
    let breakCompleted = PassthroughSubject<Void, Never>()
    /// 用户修改了时长设置，交给外部持久化
    var onPreferencesChanged: ((_ workInterval: TimeInterval, _ restDuration: TimeInterval) -> Void)?
    /// 计时状态变化（以及专注中定期）时发出快照，交给外部持久化
    var onSnapshot: ((Snapshot) -> Void)?

    private let reminder: ReminderDelivering
    private let now: () -> Date
    /// 距离上次键盘鼠标操作过去的秒数
    private let idleTime: () -> TimeInterval
    /// 是否正在开会（麦克风被任意 App 使用）
    private let isInMeeting: () -> Bool
    /// 是否正在全屏使用某个 App
    private let isFullscreen: @MainActor () -> Bool
    /// 当前是否在工作时段内（未启用工作时段时恒为 true）
    private let isWorkTime: () -> Bool
    /// 无操作超过这个时长判定为离开；睡眠超过这个时长也视为已经休息过
    private let awayThreshold: TimeInterval
    private let snoozeInterval: TimeInterval
    /// 当前这一轮专注的总时长（正常是专注时长，稍后提醒时是推迟的时长），用于计算进度
    private var roundTotal: TimeInterval
    private let usesSystemTimer: Bool
    private let logger = Logger(subsystem: "EyeBreak", category: "timer")

    /// 运行中：本阶段结束的绝对时间点。
    /// 用截止时间而不是"每秒减 1"，Timer 回调即使因系统负载延迟，剩余时间也不会累计漂移。
    private var deadline: Date?
    /// 暂停中：保存的专注剩余时间。
    private var pausedRemaining: TimeInterval
    /// 全局唯一的刷新计时器，创建前总会先销毁旧的。
    private var ticker: Timer?
    /// 睡眠前处于专注计时中，唤醒后据此恢复。
    private var resumeAfterWake = false
    /// 睡眠前处于等待休息/休息中：睡眠期间眼睛已离开屏幕，唤醒后直接开始新一轮专注。
    private var newRoundAfterWake = false
    /// 工作时段外用户手动开始了计时：本次时段外不再自动冻结，直到下次进入工作时段
    private var overridesSchedule = false
    /// 上一次检查时是否在工作时段内，用于发现「刚进入工作时段」
    private var wasWorkTime: Bool?
    private var sleepStartedAt: Date?
    /// 退出过程中不再保存快照，避免把退出时的清理状态当成用户状态
    private var isPersistenceEnabled = true
    private var lastPersistedAt: Date?
    private static let persistInterval: TimeInterval = 30
    private var observers: [NSObjectProtocol] = []

    init(
        workInterval: TimeInterval,
        restDuration: TimeInterval,
        reminder: ReminderDelivering,
        now: @escaping () -> Date = Date.init,
        idleTime: @escaping () -> TimeInterval = SystemIdle.seconds,
        isInMeeting: @escaping () -> Bool = MeetingDetector.isInMeeting,
        isFullscreen: @escaping @MainActor () -> Bool = FullscreenDetector.isFrontmostAppFullscreen,
        isWorkTime: @escaping () -> Bool = { true },
        awayThreshold: TimeInterval = EyeBreakConfig.awayThreshold,
        snoozeInterval: TimeInterval = EyeBreakConfig.snoozeInterval,
        exerciseIndex: Int = -1,
        usesSystemTimer: Bool = true
    ) {
        self.exerciseIndex = exerciseIndex
        self.workInterval = workInterval
        self.restDuration = restDuration
        self.reminder = reminder
        self.now = now
        self.idleTime = idleTime
        self.isInMeeting = isInMeeting
        self.isFullscreen = isFullscreen
        self.isWorkTime = isWorkTime
        self.awayThreshold = awayThreshold
        self.snoozeInterval = snoozeInterval
        roundTotal = workInterval
        self.usesSystemTimer = usesSystemTimer
        pausedRemaining = workInterval
        remainingSeconds = Self.displaySeconds(workInterval)
        if usesSystemTimer { observeSystemSleep() }
    }

    var isWorking: Bool { phase == .working }
    var isOnBreak: Bool { phase == .awaitingBreak || phase == .resting }

    var formattedRemaining: String {
        String(format: "%02d:%02d", remainingSeconds / 60, remainingSeconds % 60)
    }

    /// 菜单栏上紧凑显示的剩余时间（分钟不补零，如 "5:00"）；未开始和离开时不显示
    var menuBarText: String? {
        let compact = String(format: "%d:%02d", remainingSeconds / 60, remainingSeconds % 60)
        switch phase {
        case .working, .paused, .resting: return compact
        case .awaitingBreak: return String(localized: "休息")
        case .idle, .away, .offHours: return nil
        }
    }

    /// 当前阶段已经过去的比例，0...1
    var progress: Double {
        let total: TimeInterval
        switch phase {
        case .awaitingBreak, .resting: total = restDuration
        case .working, .paused: total = roundTotal
        case .idle, .away, .offHours: total = workInterval
        }
        guard total > 0 else { return 0 }
        return min(1, max(0, 1 - Double(remainingSeconds) / total))
    }

    // MARK: - 用户操作

    /// 开始 / 继续专注。仅在未开始或暂停时有效，因此连续点击不会产生并行计时。
    func start() {
        switch phase {
        case .idle, .away: beginWorking(remaining: workInterval)
        case .offHours:
            // 工作时段外用户主动开始：本次照常计时，直到下次进入工作时段
            overridesSchedule = true
            beginWorking(remaining: workInterval)
        case .paused: resumeWorking()
        case .working, .awaitingBreak, .resting: return
        }
    }

    func pause() {
        guard phase == .working else { return }
        pausedRemaining = currentRemaining()
        deadline = nil
        stopTicker()
        phase = .paused
        updateDisplay()
    }

    func toggle() {
        phase == .working ? pause() : start()
    }

    /// 重新计时：无论当前处于哪个阶段，都立即开始新一轮完整专注。
    func reset() {
        // 工作时段外手动重来，同样视为主动开始
        if phase == .offHours || !isWorkTime() { overridesSchedule = true }
        reminder.cancelPendingReminders()
        beginWorking(remaining: workInterval)
    }

    func startBreak() {
        guard phase == .awaitingBreak else { return }
        reminder.cancelPendingReminders()
        deadline = now().addingTimeInterval(restDuration)
        phase = .resting
        startTicker()
        updateDisplay()
    }

    /// 立即开始休息（快捷指令用）：不用等专注结束，马上开始一次眺望休息
    func startBreakNow() {
        switch phase {
        case .awaitingBreak:
            startBreak()
        case .idle, .working, .paused, .away, .offHours:
            exerciseIndex += 1
            reminder.cancelPendingReminders()
            deferReason = nil
            deadline = now().addingTimeInterval(restDuration)
            phase = .resting
            startTicker()
            updateDisplay()
        case .resting:
            return
        }
    }

    /// 专注模式开启或关闭：开启「暂停休息提醒」的专注模式期间，到点的提醒推迟到专注模式结束
    func setFocusHold(_ hold: Bool) {
        guard hold != isFocusHold else { return }
        logger.notice("Focus filter hold: \(hold)")
        isFocusHold = hold
    }

    /// 稍后提醒：收起提醒，过一会儿（默认 5 分钟，不超过专注时长）再提醒一次。
    func snooze() {
        guard phase == .awaitingBreak else { return }
        reminder.cancelPendingReminders()
        let interval = min(snoozeInterval, workInterval)
        beginWorking(remaining: interval, roundTotal: interval, snoozing: true)
    }

    /// 跳过本次休息 / 提前结束休息：不播放庆祝，直接开始新一轮专注。
    func skipBreak() {
        guard isOnBreak else { return }
        reminder.cancelPendingReminders()
        beginWorking(remaining: workInterval)
    }

    /// 修改专注时长：未开始时立即生效，其余情况从下一轮开始生效。
    func setWorkInterval(_ interval: TimeInterval) {
        guard interval > 0, interval != workInterval else { return }
        workInterval = interval
        if phase == .idle { pausedRemaining = interval }
        updateDisplay()
        onPreferencesChanged?(workInterval, restDuration)
    }

    /// 修改休息时长：正在休息时本次不变，从下一次休息开始生效。
    func setRestDuration(_ duration: TimeInterval) {
        guard duration > 0, duration != restDuration else { return }
        restDuration = duration
        updateDisplay()
        onPreferencesChanged?(workInterval, restDuration)
    }

    /// 退出前调用：停止计时、撤销提醒、移除系统监听。
    func shutdown() {
        persist()
        isPersistenceEnabled = false
        stopTicker()
        deadline = nil
        resumeAfterWake = false
        newRoundAfterWake = false
        phase = .idle
        reminder.cancelPendingReminders()
        let center = NSWorkspace.shared.notificationCenter
        observers.forEach(center.removeObserver)
        observers.removeAll()
    }

    // MARK: - 状态保存与恢复

    func snapshot() -> Snapshot {
        let saved: Snapshot.SavedPhase
        var remaining: TimeInterval = 0
        switch phase {
        case .idle: saved = .idle
        case .working: saved = .working; remaining = currentRemaining()
        case .paused: saved = .paused; remaining = pausedRemaining
        case .awaitingBreak: saved = .awaitingBreak
        case .resting: saved = .resting
        case .away: saved = .away
        case .offHours: saved = .offHours
        }
        return Snapshot(phase: saved, remaining: remaining, savedAt: now())
    }

    /// 启动时恢复上次退出前的状态。离开超过离开阈值（例如重启电脑）视为已经休息过。
    func restore(_ snapshot: Snapshot) {
        guard phase == .idle else { return }
        let elapsed = max(0, now().timeIntervalSince(snapshot.savedAt))
        let wasAwayLong = elapsed >= awayThreshold
        switch snapshot.phase {
        case .idle:
            return
        case .paused:
            pausedRemaining = min(max(0, snapshot.remaining), workInterval)
            phase = .paused
            updateDisplay()
        case .working:
            beginWorking(remaining: wasAwayLong ? workInterval : max(0, snapshot.remaining - elapsed))
        case .awaitingBreak, .resting:
            if wasAwayLong {
                beginWorking(remaining: workInterval)
            } else {
                // 重新弹出提醒，但不再重复播放提醒音
                deadline = nil
                phase = .awaitingBreak
                startTicker()
                updateDisplay()
            }
        case .away:
            beginWorking(remaining: workInterval)
        case .offHours:
            if isWorkTime() {
                beginWorking(remaining: workInterval)
            } else {
                enterOffHours()
            }
        }
        logger.notice("Restored \(snapshot.phase.rawValue, privacy: .public) after \(elapsed, format: .fixed(precision: 0))s")
    }

    private func persist() {
        guard isPersistenceEnabled else { return }
        lastPersistedAt = now()
        onSnapshot?(snapshot())
    }

    // MARK: - 计时

    func tick() {
        if checkWorkSchedule() { return }

        switch phase {
        case .working, .awaitingBreak:
            // 休息中不检测：眺望时本来就不碰键鼠；开会时盯着屏幕但可能很久不碰键鼠，也不算离开
            if idleTime() >= awayThreshold, currentDeferReason() == nil {
                enterAway()
                return
            }
        case .away:
            if idleTime() < Self.returnThreshold { returnFromAway() }
            return
        case .offHours:
            return
        case .idle, .paused, .resting:
            break
        }

        guard let deadline, now() >= deadline else {
            updateDisplay()
            if phase == .working, now().timeIntervalSince(lastPersistedAt ?? .distantPast) >= Self.persistInterval {
                persist()
            }
            return
        }
        switch phase {
        case .working:
            // 开会或全屏时先不提醒，每秒检查一次，结束后立即提醒
            if let reason = currentDeferReason() {
                if deferReason != reason {
                    logger.notice("Reminder deferred: \(String(describing: reason), privacy: .public)")
                    deferReason = reason
                }
                updateDisplay()
                return
            }
            deferReason = nil
            // 稍后提醒再次到点时保持同一个休息内容，其余情况换下一个
            if !isSnoozing { exerciseIndex += 1 }
            // 先把状态切到"等待休息"并清掉截止时间，再投递提醒：同一轮只可能触发一次，
            // 用户不点「开始休息」时计时保持冻结，也就不会反复提醒。
            // 计时器继续运行，只用于检测用户是否离开。
            self.deadline = nil
            phase = .awaitingBreak
            updateDisplay()
            logger.notice("Work round finished, awaiting break")
            reminder.deliverReminder(restDuration: restDuration)
        case .resting:
            logger.notice("Break completed")
            reminder.playBreakComplete()
            breakCompleted.send()
            beginWorking(remaining: workInterval)
        case .idle, .paused, .awaitingBreak, .away, .offHours:
            updateDisplay()
        }
    }

    /// 处理工作时段的进出；返回 true 表示本次 tick 已处理完毕
    private func checkWorkSchedule() -> Bool {
        let inWorkTime = isWorkTime()
        let justStarted = wasWorkTime == false && inWorkTime
        wasWorkTime = inWorkTime

        if inWorkTime {
            overridesSchedule = false
            if phase == .offHours || (justStarted && phase == .away) {
                logger.notice("Work hours started, starting a new round")
                beginWorking(remaining: workInterval)
                return true
            }
            return false
        }

        // 工作时段外：专注中、等待休息时冻结；暂停、未开始、休息中保持不变（休息结束后再冻结）
        guard !overridesSchedule else { return false }
        if phase == .working || phase == .awaitingBreak || phase == .away {
            enterOffHours()
            return true
        }
        return phase == .offHours
    }

    private func enterOffHours() {
        logger.notice("Outside work hours, pausing")
        deadline = nil
        deferReason = nil
        reminder.cancelPendingReminders()
        phase = .offHours
        startTicker()
        updateDisplay()
    }

    private func currentDeferReason() -> DeferReason? {
        if isFocusHold { return .focus }
        if isInMeeting() { return .meeting }
        if isFullscreen() { return .fullscreen }
        return nil
    }

    /// 回来的判定：最近几秒内有键鼠操作
    private static let returnThreshold: TimeInterval = 3

    private func enterAway() {
        logger.notice("No input for a while, user is away")
        deadline = nil
        reminder.cancelPendingReminders()
        phase = .away
        updateDisplay()
    }

    private func returnFromAway() {
        logger.notice("User is back, starting a new round")
        beginWorking(remaining: workInterval)
    }

    /// 开始新一轮专注计时（默认一整轮）
    private func beginWorking(remaining: TimeInterval, roundTotal total: TimeInterval? = nil, snoozing: Bool = false) {
        roundTotal = total ?? workInterval
        isSnoozing = snoozing
        deferReason = nil
        deadline = now().addingTimeInterval(max(0, remaining))
        phase = .working
        startTicker()
        updateDisplay()
    }

    /// 从暂停处继续，保留本轮的总时长和是否为稍后提醒
    private func resumeWorking() {
        deadline = now().addingTimeInterval(max(0, pausedRemaining))
        phase = .working
        startTicker()
        updateDisplay()
    }

    private func currentRemaining() -> TimeInterval {
        guard let deadline else { return pausedRemaining }
        return max(0, deadline.timeIntervalSince(now()))
    }

    private func updateDisplay() {
        let seconds: TimeInterval
        switch phase {
        case .idle, .away, .offHours: seconds = workInterval
        case .working, .resting: seconds = currentRemaining()
        case .paused: seconds = pausedRemaining
        case .awaitingBreak: seconds = restDuration
        }
        let display = Self.displaySeconds(seconds)
        if display != remainingSeconds { remainingSeconds = display }
    }

    /// 向上取整到秒，并留一点容差，避免 1199.9999 秒仍显示成 20:00。不会出现负数。
    private static func displaySeconds(_ seconds: TimeInterval) -> Int {
        Int(max(0, (seconds - 0.05).rounded(.up)))
    }

    private func startTicker() {
        stopTicker()
        guard usesSystemTimer else { return }
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        timer.tolerance = 0.1
        // .common 模式：面板打开、菜单追踪时也能继续刷新
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }

    private func stopTicker() {
        ticker?.invalidate()
        ticker = nil
    }

    // MARK: - 睡眠与唤醒

    func systemWillSleep() {
        sleepStartedAt = now()
        switch phase {
        case .working:
            logger.notice("System will sleep, pausing work with \(self.currentRemaining(), format: .fixed(precision: 1))s left")
            pause()
            resumeAfterWake = true
        case .awaitingBreak, .resting:
            logger.notice("System will sleep during break")
            stopTicker()
            deadline = nil
            newRoundAfterWake = true
        case .idle, .paused, .away, .offHours:
            break
        }
    }

    func systemDidWake() {
        let sleptLong = sleepStartedAt.map { now().timeIntervalSince($0) >= awayThreshold } ?? false
        sleepStartedAt = nil
        if resumeAfterWake {
            resumeAfterWake = false
            if sleptLong {
                // 睡了很久，眼睛已经休息过，直接开始新一轮
                logger.notice("System did wake after a long sleep, starting a new round")
                beginWorking(remaining: workInterval)
            } else {
                logger.notice("System did wake, resuming work")
                start()
            }
        } else if newRoundAfterWake {
            newRoundAfterWake = false
            logger.notice("System did wake after break, starting a new round")
            reminder.cancelPendingReminders()
            beginWorking(remaining: workInterval)
        }
    }

    private func observeSystemSleep() {
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(
            forName: NSWorkspace.willSleepNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.systemWillSleep() }
        })
        observers.append(center.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.systemDidWake() }
        })
    }
}
