import Combine
import Foundation
import Testing
@testable import EyeBreak

@MainActor
private final class ChainTestContext {
    let suite = "ReminderChainsTests.\(UUID().uuidString)"
    let defaults: UserDefaults
    var calendar: Calendar
    var now: Date
    lazy var store = ReminderChainStore(defaults: defaults, now: { [unowned self] in now }, calendar: { [unowned self] in calendar })
    lazy var scheduler = makeScheduler()

    init(timeZone: String = "Asia/Taipei") {
        defaults = UserDefaults(suiteName: suite)!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timeZone)!
        self.calendar = calendar
        now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 8, hour: 7, minute: 55))!
    }

    func date(month: Int = 11, day: Int = 8, hour: Int, minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour, minute: minute))!
    }

    func makeScheduler(usesSystemTimer: Bool = false) -> ReminderChainScheduler {
        ReminderChainScheduler(
            store: store, defaults: defaults, now: { [unowned self] in now },
            calendar: { [unowned self] in calendar }, usesSystemTimer: usesSystemTimer
        )
    }

    @discardableResult
    func saveExample() throws -> ReminderChain {
        let chain = ReminderChain(title: "第一步", steps: [
            ReminderChainStep(title: "第二步", intervalMinutes: 5),
            ReminderChainStep(title: "第三步", intervalMinutes: 10)
        ])
        try store.save(chain)
        return chain
    }

    func clean() {
        scheduler.shutdown()
        defaults.removePersistentDomain(forName: suite)
    }
}

@MainActor
struct ReminderChainsTests {
    @Test("累计时间以主提醒为锚点，未确认不推迟下一步，同链只显示最新一条")
    func cumulativeSchedule() throws {
        let context = ChainTestContext()
        defer { context.clean() }
        try context.saveExample()
        var sounds = 0
        context.scheduler.onReminder = { sounds += 1 }
        context.scheduler.start()
        context.now = context.date(hour: 8)
        context.scheduler.tick()
        #expect(context.scheduler.pending.map(\.title) == ["第一步"])
        context.scheduler.tick()
        #expect(sounds == 1)
        context.now = context.date(hour: 8, minute: 5)
        context.scheduler.tick()
        #expect(context.scheduler.pending.map(\.title) == ["第二步"])
        #expect(context.scheduler.pending.first?.scheduledAt == context.date(hour: 8, minute: 5))
        context.now = context.date(hour: 8, minute: 14)
        context.scheduler.tick()
        #expect(sounds == 2)
        context.now = context.date(hour: 8, minute: 15)
        context.scheduler.tick()
        #expect(context.scheduler.pending.map(\.title) == ["第三步"])
        #expect(sounds == 3)
    }

    @Test("零、负值、整数极值和累计达到下一轮均拒绝", arguments: [0, -1, 1440, Int.max, Int.min])
    func rejectsInvalidIntervals(minutes: Int) {
        let context = ChainTestContext()
        defer { context.clean() }
        let chain = ReminderChain(title: "主提醒", steps: [ReminderChainStep(title: "后续", intervalMinutes: minutes)])
        #expect(chain.validationMessage(calendar: context.calendar, now: context.now) != nil)
        #expect(throws: ReminderChainValidationError.self) { try context.store.save(chain) }
        #expect(context.store.chains.isEmpty)
    }

    @Test("普通每日周期累计 1439 分钟允许、分步累计 1440 分钟拒绝")
    func cumulativeBoundary() {
        let context = ChainTestContext()
        defer { context.clean() }
        var chain = ReminderChain(title: "主提醒", steps: [ReminderChainStep(title: "后续", intervalMinutes: 1439)])
        #expect(chain.validationMessage(calendar: context.calendar, now: context.now) == nil)
        chain.steps.append(ReminderChainStep(title: "跨轮", intervalMinutes: 1))
        #expect(chain.totalIntervalMinutes == 1440)
        #expect(chain.validationMessage(calendar: context.calendar, now: context.now) != nil)
        chain.steps = [ReminderChainStep(title: "溢出一", intervalMinutes: Int.max), ReminderChainStep(title: "溢出二", intervalMinutes: Int.max)]
        #expect(chain.totalIntervalMinutes == Int.max)
        #expect(chain.validationMessage(calendar: context.calendar, now: context.now) != nil)
    }

    @Test("单主提醒合法，空白标题、无效主时间和重复步骤 ID 不合法")
    func validatesDefinitions() {
        let context = ChainTestContext()
        defer { context.clean() }
        #expect(ReminderChain(title: "单次主提醒").validationMessage(calendar: context.calendar, now: context.now) == nil)
        #expect(ReminderChain(title: " \n ").validationMessage() != nil)
        #expect(ReminderChain(title: "主提醒", hour: 24).validationMessage() != nil)
        #expect(ReminderChain(title: "主提醒", minute: -1).validationMessage() != nil)
        let step = ReminderChainStep(title: "后续")
        #expect(ReminderChain(title: "主提醒", steps: [step, step]).validationMessage() != nil)
        #expect(ReminderChain(title: "主提醒", steps: [ReminderChainStep(title: " ")]).validationMessage() != nil)
    }

    @Test("主时间之后新增，不补已过的主提醒，本轮剩余步骤照常提醒")
    func creationKeepsRemainingSteps() throws {
        let context = ChainTestContext()
        defer { context.clean() }
        context.now = context.date(hour: 8, minute: 2)
        try context.saveExample()
        context.scheduler.start()
        #expect(context.scheduler.pending.isEmpty)
        context.now = context.date(hour: 8, minute: 5)
        context.scheduler.tick()
        #expect(context.scheduler.pending.map(\.title) == ["第二步"])
        context.now = context.date(hour: 8, minute: 15)
        context.scheduler.tick()
        #expect(context.scheduler.pending.map(\.title) == ["第三步"])
        context.now = context.date(day: 9, hour: 8)
        context.scheduler.tick()
        #expect(context.scheduler.pending.map(\.title) == ["第一步"])
    }

    @Test("恰好主时间保存时不补当前主提醒")
    func exactMainCreationStartsTomorrow() throws {
        let context = ChainTestContext()
        defer { context.clean() }
        context.now = context.date(hour: 8)
        let chain = try context.saveExample()
        #expect(chain.nextMainDate(after: context.now, calendar: context.calendar) == context.date(day: 9, hour: 8))
        context.scheduler.start()
        #expect(context.scheduler.pending.isEmpty)
    }

    @Test("编辑、禁用与删除同步撤销该链消息，修改或重新启用后本轮剩余步骤继续")
    func configurationChangesCancelCurrentCycle() throws {
        let context = ChainTestContext()
        defer { context.clean() }
        var chain = try context.saveExample()
        context.scheduler.start()
        context.now = context.date(hour: 8)
        context.scheduler.tick()
        chain.title = "修改后"
        try context.store.save(chain)
        #expect(context.scheduler.pending.isEmpty)
        context.now = context.date(hour: 8, minute: 15)
        context.scheduler.tick()
        #expect(context.scheduler.pending.map(\.title) == ["第三步"])
        context.now = context.date(day: 9, hour: 8)
        context.scheduler.tick()
        #expect(context.scheduler.pending.map(\.title) == ["修改后"])
        try context.store.setEnabled(false, id: chain.id)
        #expect(context.scheduler.pending.isEmpty)
        context.now = context.date(day: 9, hour: 8, minute: 1)
        try context.store.setEnabled(true, id: chain.id)
        #expect(context.scheduler.pending.isEmpty)
        context.now = context.date(day: 9, hour: 8, minute: 15)
        context.scheduler.tick()
        #expect(context.scheduler.pending.map(\.title) == ["第三步"])
        context.now = context.date(day: 10, hour: 8)
        context.scheduler.tick()
        #expect(context.scheduler.pending.count == 1)
        context.store.delete(id: chain.id)
        #expect(context.scheduler.pending.isEmpty)
    }

    @Test("唤醒或延迟回调只补本轮最新一步，并保留原计划时间")
    func delayedTickOnlyShowsLatest() throws {
        let context = ChainTestContext()
        defer { context.clean() }
        try context.saveExample()
        var sounds = 0
        context.scheduler.onReminder = { sounds += 1 }
        context.scheduler.start()
        context.now = context.date(hour: 8, minute: 12)
        context.scheduler.systemTimeDidChange()
        #expect(context.scheduler.pending.map(\.title) == ["第二步"])
        #expect(context.scheduler.pending.first?.scheduledAt == context.date(hour: 8, minute: 5))
        #expect(sounds == 1)
        context.scheduler.systemTimeDidChange()
        #expect(sounds == 1)
    }

    @Test("重启恢复待确认消息不重复响铃，确认后重启也不重弹")
    func persistenceAndAcknowledgment() throws {
        let context = ChainTestContext()
        defer { context.clean() }
        try context.saveExample()
        context.scheduler.start()
        context.now = context.date(hour: 8)
        context.scheduler.tick()
        let original = try #require(context.scheduler.pending.first)
        context.scheduler.shutdown()
        context.now = context.date(hour: 8, minute: 1)
        let reopened = context.makeScheduler()
        var sounds = 0
        reopened.onReminder = { sounds += 1 }
        reopened.start()
        #expect(reopened.pending == [original])
        #expect(sounds == 0)
        reopened.acknowledge(id: original.id)
        reopened.shutdown()
        let again = context.makeScheduler()
        defer { again.shutdown() }
        again.onReminder = { sounds += 1 }
        again.start()
        #expect(again.pending.isEmpty)
        #expect(sounds == 0)
    }

    @Test("跨多日重启只呈现当前轮，不先发布旧归档消息")
    func staleArchiveIsNeverPublished() throws {
        let context = ChainTestContext()
        defer { context.clean() }
        try context.saveExample()
        context.scheduler.start()
        context.now = context.date(hour: 8)
        context.scheduler.tick()
        context.scheduler.shutdown()
        context.now = context.date(day: 10, hour: 8, minute: 7)
        let reopened = context.makeScheduler()
        defer { reopened.shutdown() }
        var publications: [[ReminderChainOccurrence]] = []
        let subscription = reopened.$pending.dropFirst().sink { publications.append($0) }
        reopened.start()
        #expect(publications.count == 1)
        #expect(publications.first?.first?.cycleStart == context.date(day: 10, hour: 8))
        #expect(reopened.pending.map(\.title) == ["第二步"])
        withExtendedLifetime(subscription) {}
    }

    @Test("下一轮替换旧轮消息，时钟回拨和重启不重发已触发步骤")
    func clockRollbackDoesNotRepeat() throws {
        let context = ChainTestContext()
        defer { context.clean() }
        try context.saveExample()
        context.scheduler.start()
        context.now = context.date(hour: 8, minute: 5)
        context.scheduler.tick()
        context.scheduler.acknowledge(id: try #require(context.scheduler.pending.first?.id))
        context.now = context.date(hour: 8, minute: 1)
        context.scheduler.systemTimeDidChange()
        #expect(context.scheduler.pending.isEmpty)
        context.now = context.date(hour: 8, minute: 5)
        context.scheduler.tick()
        #expect(context.scheduler.pending.isEmpty)
        context.now = context.date(day: 9, hour: 8)
        context.scheduler.tick()
        #expect(context.scheduler.pending.first?.cycleStart == context.date(day: 9, hour: 8))
        context.scheduler.acknowledge(id: try #require(context.scheduler.pending.first?.id))
        context.scheduler.shutdown()
        context.now = context.date(hour: 8, minute: 15)
        let reopened = context.makeScheduler()
        defer { reopened.shutdown() }
        reopened.start()
        #expect(reopened.pending.map(\.title) == ["第三步"])
    }

    @Test("误调未来一个月后纠正日期，当前轮不重响且次日正常提醒")
    func futureClockJumpDoesNotSuppressFollowingDays() throws {
        let context = ChainTestContext()
        defer { context.clean() }
        try context.store.save(ReminderChain(title: "每日提醒"))
        var sounds = 0
        context.scheduler.onReminder = { sounds += 1 }
        context.scheduler.start()
        context.now = context.date(hour: 8)
        context.scheduler.tick()
        context.scheduler.acknowledge(id: try #require(context.scheduler.pending.first?.id))
        #expect(sounds == 1)
        context.now = context.date(month: 12, hour: 8)
        context.scheduler.systemTimeDidChange()
        context.scheduler.acknowledge(id: try #require(context.scheduler.pending.first?.id))
        #expect(sounds == 2)
        context.now = context.date(hour: 8, minute: 1)
        context.scheduler.systemTimeDidChange()
        #expect(context.scheduler.pending.isEmpty)
        #expect(sounds == 2)
        context.now = context.date(day: 9, hour: 8)
        context.scheduler.tick()
        #expect(context.scheduler.pending.map(\.title) == ["每日提醒"])
        #expect(sounds == 3)
    }

    @Test("不同链消息并存，确认一条不影响另一条")
    func independentChains() throws {
        let context = ChainTestContext()
        defer { context.clean() }
        let first = try context.saveExample()
        try context.store.save(ReminderChain(title: "煮饭"))
        context.scheduler.start()
        context.now = context.date(hour: 8)
        context.scheduler.tick()
        #expect(context.scheduler.pending.count == 2)
        context.scheduler.acknowledge(id: try #require(context.scheduler.pending.first(where: { $0.chainID == first.id })?.id))
        #expect(context.scheduler.pending.map(\.title) == ["煮饭"])
    }

    @Test("跨午夜仍可属于上一轮，累计 1439 分钟在下一主时间前触发")
    func overnightSequence() throws {
        let context = ChainTestContext()
        defer { context.clean() }
        try context.store.save(ReminderChain(title: "主提醒", steps: [ReminderChainStep(title: "最后一步", intervalMinutes: 1439)]))
        context.scheduler.start()
        context.now = context.date(day: 9, hour: 7, minute: 59)
        context.scheduler.tick()
        #expect(context.scheduler.pending.map(\.title) == ["最后一步"])
        #expect(context.scheduler.pending.first?.cycleStart == context.date(hour: 8))
        context.now = context.date(day: 9, hour: 8)
        context.scheduler.tick()
        #expect(context.scheduler.pending.map(\.title) == ["主提醒"])
        #expect(context.scheduler.pending.first?.cycleStart == context.date(day: 9, hour: 8))
    }

    @Test("夏令时短日按实际 23 小时边界校验")
    func daylightSavingShortDay() {
        let context = ChainTestContext(timeZone: "America/New_York")
        defer { context.clean() }
        context.now = context.date(month: 3, day: 7, hour: 7)
        let valid = ReminderChain(title: "主提醒", steps: [ReminderChainStep(title: "后续", intervalMinutes: 1379)])
        var invalid = valid
        invalid.steps[0].intervalMinutes = 1380
        #expect(valid.validationMessage(calendar: context.calendar, now: context.now) == nil)
        #expect(invalid.validationMessage(calendar: context.calendar, now: context.now) != nil)
    }

    @Test("时区变化使当前轮变短时，运行时阻断不合法的整轮")
    func runtimeCycleBoundary() throws {
        let context = ChainTestContext()
        defer { context.clean() }
        context.now = context.date(month: 3, day: 7, hour: 7)
        try context.store.save(ReminderChain(title: "主提醒", steps: [ReminderChainStep(title: "后续", intervalMinutes: 1380)]))
        context.scheduler.start()
        context.calendar.timeZone = TimeZone(identifier: "America/New_York")!
        context.now = context.date(month: 3, day: 7, hour: 8)
        context.scheduler.systemTimeDidChange()
        #expect(context.scheduler.pending.isEmpty)
        context.now = context.date(month: 3, day: 8, hour: 8)
        context.scheduler.tick()
        #expect(context.scheduler.pending.map(\.title) == ["主提醒"])
    }

    @Test("夏令时回拨重复小时中创建或启用，不补已过的主提醒", arguments: [false, true])
    func repeatedHourStartsFollowingDay(reenable: Bool) throws {
        let context = ChainTestContext(timeZone: "America/New_York")
        defer { context.clean() }
        let repeatedHour = context.date(day: 1, hour: 0).addingTimeInterval(2 * 3600)
        var chain = ReminderChain(title: "主提醒", hour: 1, minute: 30, isEnabled: !reenable)
        if reenable {
            context.now = repeatedHour.addingTimeInterval(-86400)
            try context.store.save(chain)
            context.now = repeatedHour
            try context.store.setEnabled(true, id: chain.id)
            chain.isEnabled = true
        } else {
            context.now = repeatedHour
            try context.store.save(chain)
        }
        #expect(chain.nextMainDate(after: repeatedHour, calendar: context.calendar) == context.date(day: 2, hour: 1, minute: 30))
        context.scheduler.start()
        context.now = repeatedHour.addingTimeInterval(30 * 60)
        context.scheduler.tick()
        #expect(context.scheduler.pending.isEmpty)
        context.now = context.date(day: 2, hour: 1, minute: 30)
        context.scheduler.tick()
        #expect(context.scheduler.pending.map(\.title) == ["主提醒"])
    }

    @Test("损坏配置可见且保留原值，新建前备份；损坏运行快照不崩溃")
    func corruptStorageRecoversWithBackup() throws {
        let context = ChainTestContext()
        defer { context.clean() }
        let original = Data("broken archive".utf8)
        context.defaults.set(original, forKey: ReminderChainStore.storageKey)
        #expect(context.store.loadError != nil)
        #expect(context.store.chains.isEmpty)
        #expect(context.defaults.data(forKey: ReminderChainStore.storageKey) == original)
        try context.saveExample()
        #expect(context.store.loadError == nil)
        #expect(context.defaults.data(forKey: ReminderChainStore.recoveryBackupKey) == original)
        context.defaults.set(original, forKey: ReminderChainScheduler.storageKey)
        context.scheduler.start()
        context.now = context.date(hour: 8)
        context.scheduler.tick()
        #expect(context.scheduler.pending.count == 1)
    }

    @Test("反序列化的非法步骤不会参与调度，也可直接禁用")
    func invalidSavedDefinitionDoesNotRun() throws {
        let context = ChainTestContext()
        defer { context.clean() }
        let chain = try context.saveExample()
        let data = try #require(context.defaults.data(forKey: ReminderChainStore.storageKey))
        var archive = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var entries = try #require(archive["entries"] as? [[String: Any]])
        var storedChain = try #require(entries[0]["chain"] as? [String: Any])
        var steps = try #require(storedChain["steps"] as? [[String: Any]])
        steps[0]["intervalMinutes"] = -1
        storedChain["steps"] = steps
        entries[0]["chain"] = storedChain
        archive["entries"] = entries
        context.defaults.set(try JSONSerialization.data(withJSONObject: archive), forKey: ReminderChainStore.storageKey)
        context.scheduler.start()
        context.now = context.date(hour: 8)
        context.scheduler.tick()
        #expect(context.scheduler.pending.isEmpty)
        try context.store.setEnabled(false, id: chain.id)
        #expect(context.store.chains.first?.isEnabled == false)
    }

    @Test("start 重新加载旧进程写入的配置，不提前启动计时")
    func startReloadsPreferences() throws {
        let context = ChainTestContext()
        defer { context.clean() }
        let scheduler = context.scheduler
        #expect(context.store.chains.isEmpty)
        let otherStore = ReminderChainStore(defaults: context.defaults, now: { context.now }, calendar: { context.calendar })
        try otherStore.save(ReminderChain(title: "旧进程保存"))
        #expect(context.store.chains.isEmpty)
        context.now = context.date(hour: 8)
        scheduler.start()
        #expect(context.store.chains.map(\.title) == ["旧进程保存"])
        #expect(scheduler.pending.map(\.title) == ["旧进程保存"])
    }

    @Test("无计划不装表，有计划只装一个单次表，时钟变化强制重装")
    func timerLifecycle() throws {
        let context = ChainTestContext()
        defer { context.clean() }
        let scheduler = context.makeScheduler(usesSystemTimer: true)
        defer { scheduler.shutdown() }
        scheduler.start()
        #expect(scheduler.activeTimerCount == 0)
        let chain = try context.saveExample()
        #expect(scheduler.activeTimerCount == 1)
        let starts = scheduler.timerStartCount
        scheduler.start()
        scheduler.tick()
        #expect(scheduler.timerStartCount == starts)
        context.now = context.now.addingTimeInterval(-60)
        scheduler.systemTimeDidChange()
        #expect(scheduler.activeTimerCount == 1)
        #expect(scheduler.timerStartCount == starts + 1)
        try context.store.setEnabled(false, id: chain.id)
        #expect(scheduler.activeTimerCount == 0)
        scheduler.shutdown()
        #expect(scheduler.activeTimerCount == 0)
    }
}
