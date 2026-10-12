import AppKit
import Combine
import os

/// 提醒的投递方（提示音 + 系统通知）。抽成协议便于单元测试替换。
@MainActor
protocol ReminderDelivering: AnyObject {
    /// 专注结束：播放提示音并发送带「开始休息」按钮的系统通知
    func deliverReminder(restDuration: TimeInterval)
    /// 撤销尚未展示的提醒，并收起已展示的那条（用户已经开始休息/跳过/退出）
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
    }

    @Published private(set) var phase: Phase = .idle
    /// 当前阶段要展示的剩余秒数（专注阶段是专注剩余，休息阶段是休息剩余）
    @Published private(set) var remainingSeconds: Int
    @Published private(set) var workInterval: TimeInterval
    @Published private(set) var restDuration: TimeInterval

    /// 休息倒计时自然结束时发出（提前结束、跳过不算），界面据此播放撒花动画
    let breakCompleted = PassthroughSubject<Void, Never>()
    /// 用户修改了时长设置，交给外部持久化
    var onPreferencesChanged: ((_ workInterval: TimeInterval, _ restDuration: TimeInterval) -> Void)?

    private let reminder: ReminderDelivering
    private let now: () -> Date
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
    private var observers: [NSObjectProtocol] = []

    init(
        workInterval: TimeInterval,
        restDuration: TimeInterval,
        reminder: ReminderDelivering,
        now: @escaping () -> Date = Date.init,
        usesSystemTimer: Bool = true
    ) {
        self.workInterval = workInterval
        self.restDuration = restDuration
        self.reminder = reminder
        self.now = now
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

    /// 当前阶段已经过去的比例，0...1
    var progress: Double {
        let total = isOnBreak ? restDuration : workInterval
        guard total > 0 else { return 0 }
        return min(1, max(0, 1 - Double(remainingSeconds) / total))
    }

    // MARK: - 用户操作

    /// 开始 / 继续专注。仅在未开始或暂停时有效，因此连续点击不会产生并行计时。
    func start() {
        switch phase {
        case .idle: beginWorking(remaining: workInterval)
        case .paused: beginWorking(remaining: pausedRemaining)
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

    // MARK: - 计时

    func tick() {
        guard let deadline, now() >= deadline else {
            updateDisplay()
            return
        }
        switch phase {
        case .working:
            // 先把状态切到"等待休息"并停表，再投递提醒：同一轮只可能触发一次，
            // 用户不点「开始休息」时计时保持冻结，也就不会反复提醒。
            self.deadline = nil
            stopTicker()
            phase = .awaitingBreak
            updateDisplay()
            logger.notice("Work round finished, awaiting break")
            reminder.deliverReminder(restDuration: restDuration)
        case .resting:
            logger.notice("Break completed")
            reminder.playBreakComplete()
            breakCompleted.send()
            beginWorking(remaining: workInterval)
        case .idle, .paused, .awaitingBreak:
            updateDisplay()
        }
    }

    private func beginWorking(remaining: TimeInterval) {
        deadline = now().addingTimeInterval(max(0, remaining))
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
        case .idle: seconds = workInterval
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
        case .idle, .paused:
            break
        }
    }

    func systemDidWake() {
        if resumeAfterWake {
            resumeAfterWake = false
            logger.notice("System did wake, resuming work")
            start()
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
