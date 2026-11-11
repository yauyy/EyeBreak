import AppKit
import Combine

struct ReminderChainStep: Identifiable, Codable, Equatable {
    var id = UUID()
    var title: String
    /// 距上一步的实际分钟数；所有步骤最终锚定在本轮主提醒的计划时间。
    var intervalMinutes = 5
}

struct ReminderChain: Identifiable, Codable, Equatable {
    var id = UUID()
    var title: String
    var hour = 8
    var minute = 0
    var isEnabled = true
    var steps: [ReminderChainStep] = []

    var totalIntervalMinutes: Int {
        steps.reduce(0) { total, step in
            let result = total.addingReportingOverflow(step.intervalMinutes)
            return result.overflow ? Int.max : result.partialValue
        }
    }

    fileprivate var basicValidationMessage: String? {
        if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return String(localized: "请输入主提醒内容。")
        }
        guard (0...23).contains(hour), (0...59).contains(minute) else {
            return String(localized: "请选择有效的主提醒时间。")
        }
        guard Set(steps.map(\.id)).count == steps.count else {
            return String(localized: "提醒步骤重复，请重新添加。")
        }
        var total = 0
        for step in steps {
            if step.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return String(localized: "请输入每一步的提醒内容。")
            }
            guard step.intervalMinutes > 0, step.intervalMinutes < 1440 else {
                return String(localized: "每一步的间隔须为 1–1439 分钟。")
            }
            let addition = total.addingReportingOverflow(step.intervalMinutes)
            guard !addition.overflow, addition.partialValue < 1440 else {
                return String(localized: "累计间隔必须小于下一次主提醒的间隔。")
            }
            total = addition.partialValue
        }
        return nil
    }

    func nextMainDate(after date: Date, calendar: Calendar = .current) -> Date? {
        guard (0...23).contains(hour), (0...59).contains(minute) else { return nil }
        var day = calendar.startOfDay(for: date)
        // 从本地日开头找第一次匹配，避免在夏令时回拨的重复小时中间启用时
        // nextDate(after: 当前时刻) 意外返回当天第二个同名时刻。
        for _ in 0..<3 {
            guard let candidate = calendar.nextDate(
                after: day.addingTimeInterval(-1),
                matching: DateComponents(hour: hour, minute: minute, second: 0),
                matchingPolicy: .nextTime, repeatedTimePolicy: .first
            ) else { return nil }
            if candidate > date { return candidate }
            guard let nextDay = calendar.date(byAdding: .day, value: 1, to: day), nextDay > day else { return nil }
            day = nextDay
        }
        return nil
    }

    func validationMessage(calendar: Calendar = .current, now: Date = Date()) -> String? {
        if let message = basicValidationMessage { return message }
        let totalSeconds = TimeInterval(totalIntervalMinutes) * 60
        // 每天的实际长度不一定是 24 小时。提前检查一年内的短日，运行时仍逐轮兜底。
        guard var start = nextMainDate(after: now.addingTimeInterval(-2 * 86400), calendar: calendar) else {
            return String(localized: "无法计算下一次主提醒，请检查系统日期。")
        }
        for _ in 0..<372 {
            guard let end = nextMainDate(after: start, calendar: calendar), end > start else {
                return String(localized: "无法计算下一次主提醒，请检查系统日期。")
            }
            if totalSeconds >= end.timeIntervalSince(start) {
                let minutes = Int(end.timeIntervalSince(start) / 60)
                return String(localized: "当前时区存在不足 24 小时的提醒周期，累计间隔须少于 \(minutes) 分钟。")
            }
            start = end
        }
        return nil
    }

    fileprivate func cycle(containing date: Date, calendar: Calendar) -> (start: Date, end: Date)? {
        let day = calendar.startOfDay(for: date)
        guard let today = nextMainDate(after: day.addingTimeInterval(-1), calendar: calendar) else { return nil }
        let start: Date
        if today <= date {
            start = today
        } else {
            guard let previousDay = calendar.date(byAdding: .day, value: -1, to: day),
                  let previous = nextMainDate(after: previousDay.addingTimeInterval(-1), calendar: calendar),
                  previous <= date else { return nil }
            start = previous
        }
        guard let end = nextMainDate(after: start, calendar: calendar), start <= date, date < end else { return nil }
        return (start, end)
    }
}

struct ReminderChainValidationError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

@MainActor
final class ReminderChainStore: ObservableObject {
    fileprivate struct Entry: Codable, Equatable {
        var chain: ReminderChain
        var revision: UUID
        /// 只提醒计划时间晚于此时刻的步骤：保存、修改或重新启用后，本轮剩余步骤仍会提醒。
        var startsAfter: Date
    }

    private struct Archive: Codable {
        var version = 1
        var entries: [Entry]
    }

    static let storageKey = "reminderChains.v1"
    static let recoveryBackupKey = "reminderChains.recoveryBackup.v1"
    @Published private(set) var chains: [ReminderChain] = []
    @Published private(set) var loadError: String?
    fileprivate private(set) var entries: [Entry] = []
    fileprivate let changes = PassthroughSubject<Void, Never>()
    private let defaults: UserDefaults
    private let now: () -> Date
    private let calendar: () -> Calendar
    private var unreadableValue: Any?

    init(
        defaults: UserDefaults = .standard,
        now: @escaping () -> Date = Date.init,
        calendar: @escaping () -> Calendar = { .current }
    ) {
        self.defaults = defaults
        self.now = now
        self.calendar = calendar
        reload()
    }

    /// 语言重新打开时，新进程可能早于旧进程最后一次保存创建本对象。
    func reload() {
        guard let storedValue = defaults.object(forKey: Self.storageKey) else {
            entries = []
            unreadableValue = nil
            loadError = nil
            publish()
            return
        }
        guard let data = storedValue as? Data,
              let archive = try? JSONDecoder().decode(Archive.self, from: data),
              archive.version == 1 else {
            entries = []
            unreadableValue = storedValue
            loadError = String(localized: "连环提醒数据无法读取。新建提醒时会先保留原数据备份。")
            publish()
            return
        }
        unreadableValue = nil
        loadError = nil
        var seen = Set<UUID>()
        entries = archive.entries.filter { seen.insert($0.chain.id).inserted }
        publish()
    }

    func save(_ chain: ReminderChain) throws {
        let date = now()
        if let message = chain.validationMessage(calendar: calendar(), now: date) {
            throw ReminderChainValidationError(message: message)
        }
        var cleaned = chain
        cleaned.title = cleaned.title.trimmingCharacters(in: .whitespacesAndNewlines)
        cleaned.steps = cleaned.steps.map { step in
            var step = step
            step.title = step.title.trimmingCharacters(in: .whitespacesAndNewlines)
            return step
        }
        if let index = entries.firstIndex(where: { $0.chain.id == cleaned.id }) {
            guard entries[index].chain != cleaned else { return }
            entries[index] = Entry(chain: cleaned, revision: UUID(), startsAfter: date)
        } else {
            entries.append(Entry(chain: cleaned, revision: UUID(), startsAfter: date))
        }
        persistAndPublish()
    }

    func delete(id: UUID) {
        entries.removeAll { $0.chain.id == id }
        persistAndPublish()
    }

    func setEnabled(_ enabled: Bool, id: UUID) throws {
        guard let index = entries.firstIndex(where: { $0.chain.id == id }),
              entries[index].chain.isEnabled != enabled else { return }
        if enabled {
            var chain = entries[index].chain
            chain.isEnabled = true
            try save(chain)
        } else {
            // 损坏或过时的计划也必须可以关闭。
            entries[index].chain.isEnabled = false
            entries[index].revision = UUID()
            entries[index].startsAfter = now()
            persistAndPublish()
        }
    }

    private func persistAndPublish() {
        if let data = try? JSONEncoder().encode(Archive(entries: entries)) {
            if let unreadableValue {
                defaults.set(unreadableValue, forKey: Self.recoveryBackupKey)
                self.unreadableValue = nil
                loadError = nil
            }
            defaults.set(data, forKey: Self.storageKey)
        }
        publish()
    }

    private func publish() {
        chains = entries.map(\.chain)
        // 在 @Published 的 willSet 结束后发送，调度器能同步读到新配置。
        changes.send()
    }
}

struct ReminderChainOccurrence: Identifiable, Codable, Equatable {
    var id: String
    var chainID: UUID
    var chainTitle: String
    var title: String
    var scheduledAt: Date
    var cycleStart: Date
    var cycleEnd: Date
}

@MainActor
final class ReminderChainScheduler: ObservableObject {
    private struct CycleDelivery: Codable, Equatable {
        var cycleStart: Date
        var lastDeliveredAt: Date
    }

    private struct DeliveryState: Codable, Equatable {
        var revision: UUID
        // 按处理顺序保留最近 400 轮；误调未来日期不会压住当前日期的后续提醒。
        var cycles: [CycleDelivery] = []
    }

    private struct Archive: Codable {
        var version = 1
        var deliveries: [String: DeliveryState]
        var pending: [ReminderChainOccurrence]
    }

    static let storageKey = "reminderChainRuntime.v1"
    @Published private(set) var pending: [ReminderChainOccurrence] = []
    var onReminder: (() -> Void)?
    private let store: ReminderChainStore
    private let defaults: UserDefaults
    private let now: () -> Date
    private let calendar: () -> Calendar
    private let usesSystemTimer: Bool
    private var deliveries: [String: DeliveryState] = [:]
    private var restoredPending: [ReminderChainOccurrence]?
    private var timer: Timer?
    private var timerDate: Date?
    private var configurationSubscription: AnyCancellable?
    private var workspaceObservers: [NSObjectProtocol] = []
    private var timeObservers: [NSObjectProtocol] = []
    private var isRunning = false

    var activeTimerCount: Int { timer?.isValid == true ? 1 : 0 }
    private(set) var timerStartCount = 0

    init(
        store: ReminderChainStore,
        defaults: UserDefaults = .standard,
        now: @escaping () -> Date = Date.init,
        calendar: @escaping () -> Calendar = { .current },
        usesSystemTimer: Bool = true
    ) {
        self.store = store
        self.defaults = defaults
        self.now = now
        self.calendar = calendar
        self.usesSystemTimer = usesSystemTimer
        configurationSubscription = store.changes.sink { [weak self] in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    func start() {
        guard !isRunning else { return }
        store.reload()
        if let data = defaults.data(forKey: Self.storageKey),
           let archive = try? JSONDecoder().decode(Archive.self, from: data), archive.version == 1 {
            deliveries = archive.deliveries
            restoredPending = archive.pending
        } else {
            deliveries = [:]
            restoredPending = []
        }
        isRunning = true
        tick()
        guard usesSystemTimer else { return }
        observeSystemEvents()
    }

    func shutdown() {
        guard isRunning else { return }
        persist(pending: pending)
        isRunning = false
        timer?.invalidate()
        timer = nil
        timerDate = nil
        workspaceObservers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        timeObservers.forEach { NotificationCenter.default.removeObserver($0) }
        workspaceObservers.removeAll()
        timeObservers.removeAll()
    }

    func acknowledge(id: String) {
        let remaining = pending.filter { $0.id != id }
        guard remaining != pending else { return }
        persist(pending: remaining)
        pending = remaining
    }

    func systemTimeDidChange() {
        // 单次 Timer 使用相对等待时长；即使下个 Date 没变，墙钟调整后也须重新装表。
        timer?.invalidate()
        timer = nil
        timerDate = nil
        tick()
    }

    func tick() {
        guard isRunning else { return }
        let date = now()
        let calendar = calendar()
        let previousDeliveries = deliveries
        // 恢复的数据先参与当前配置/日期校验，绝不先发布过期面板再将其隐藏。
        let previousPending = restoredPending ?? pending
        restoredPending = nil
        var validIDs = Set<String>()
        var nextPending: [ReminderChainOccurrence] = []
        var shouldPlaySound = false
        for entry in store.entries {
            let chain = entry.chain
            let key = chain.id.uuidString
            validIDs.insert(key)
            if deliveries[key]?.revision != entry.revision {
                deliveries[key] = DeliveryState(revision: entry.revision)
            }
            guard chain.isEnabled, chain.basicValidationMessage == nil,
                  let cycle = chain.cycle(containing: date, calendar: calendar),
                  cycle.end > entry.startsAfter,
                  TimeInterval(chain.totalIntervalMinutes) * 60 < cycle.end.timeIntervalSince(cycle.start) else { continue }

            // 保存或启用时已过去的步骤不补；本轮尚未到的步骤照常提醒。
            let occurrences = occurrences(for: entry, start: cycle.start, end: cycle.end)
                .filter { $0.scheduledAt > entry.startsAfter }
            let due = occurrences.filter { $0.scheduledAt <= date }
            guard let latest = due.last else { continue }
            let watermark = deliveries[key]?.cycles.first(where: { $0.cycleStart == cycle.start })?.lastDeliveredAt ?? .distantPast
            if latest.scheduledAt > watermark {
                // 跳过已错过的旧步骤，仅呈现本轮最新一条；先持久化再让界面和声音可见。
                var state = deliveries[key] ?? DeliveryState(revision: entry.revision)
                state.cycles.removeAll { $0.cycleStart == cycle.start }
                state.cycles.append(CycleDelivery(cycleStart: cycle.start, lastDeliveredAt: latest.scheduledAt))
                if state.cycles.count > 400 { state.cycles.removeFirst(state.cycles.count - 400) }
                deliveries[key] = state
                nextPending.append(latest)
                shouldPlaySound = true
            } else if let previous = previousPending.first(where: { $0.chainID == chain.id }),
                      due.contains(previous) {
                nextPending.append(previous)
            }
        }
        deliveries = deliveries.filter { validIDs.contains($0.key) }
        nextPending.sort {
            $0.scheduledAt == $1.scheduledAt ? $0.id < $1.id : $0.scheduledAt < $1.scheduledAt
        }
        if deliveries != previousDeliveries || nextPending != pending {
            persist(pending: nextPending)
            if nextPending != pending { pending = nextPending }
        }
        scheduleNextTimer(after: date, calendar: calendar)
        if shouldPlaySound { onReminder?() }
    }

    private func occurrences(for entry: ReminderChainStore.Entry, start: Date, end: Date) -> [ReminderChainOccurrence] {
        let chain = entry.chain
        let prefix = "\(chain.id.uuidString)/\(entry.revision.uuidString)/\(start.timeIntervalSince1970.bitPattern)"
        var result = [ReminderChainOccurrence(
            id: prefix + "/main", chainID: chain.id, chainTitle: chain.title,
            title: chain.title, scheduledAt: start, cycleStart: start, cycleEnd: end
        )]
        var minutes = 0
        for step in chain.steps {
            minutes += step.intervalMinutes // 调用前已校验总和 < 1440。
            result.append(ReminderChainOccurrence(
                id: prefix + "/" + step.id.uuidString, chainID: chain.id, chainTitle: chain.title,
                title: step.title, scheduledAt: start.addingTimeInterval(TimeInterval(minutes) * 60),
                cycleStart: start, cycleEnd: end
            ))
        }
        return result
    }

    private func persist(pending: [ReminderChainOccurrence]) {
        guard let data = try? JSONEncoder().encode(Archive(deliveries: deliveries, pending: pending)) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }

    /// 只为最近一步或下一轮装一个单次计时器；无启用计划时不唤醒主线程。
    private func scheduleNextTimer(after date: Date, calendar: Calendar) {
        guard usesSystemTimer else { return }
        var next: Date?
        for entry in store.entries where entry.chain.isEnabled && entry.chain.basicValidationMessage == nil {
            let chain = entry.chain
            if let main = chain.nextMainDate(after: max(date, entry.startsAfter), calendar: calendar) {
                next = min(next ?? main, main)
            }
            if let cycle = chain.cycle(containing: date, calendar: calendar),
               TimeInterval(chain.totalIntervalMinutes) * 60 < cycle.end.timeIntervalSince(cycle.start),
               let step = occurrences(for: entry, start: cycle.start, end: cycle.end)
                .first(where: { $0.scheduledAt > max(date, entry.startsAfter) }) {
                next = min(next ?? step.scheduledAt, step.scheduledAt)
            }
        }
        if next == timerDate, timer?.isValid == true { return }
        timer?.invalidate()
        timer = nil
        timerDate = next
        guard let next else { return }
        let timer = Timer(timeInterval: max(0.1, next.timeIntervalSince(date)), repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.timer = nil
                self?.timerDate = nil
                self?.tick()
            }
        }
        timer.tolerance = 0.1
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        timerStartCount += 1
    }

    private func observeSystemEvents() {
        workspaceObservers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.systemTimeDidChange() }
        })
        for name in [Notification.Name.NSSystemClockDidChange, .NSSystemTimeZoneDidChange, .NSCalendarDayChanged] {
            timeObservers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.systemTimeDidChange() }
            })
        }
    }
}
