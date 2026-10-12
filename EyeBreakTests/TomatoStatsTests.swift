import Foundation
import Testing
@testable import EyeBreak

@MainActor
struct TomatoStatsTests {
    private let suiteName = "TomatoStatsTests-\(UUID().uuidString)"
    private let defaults: UserDefaults
    private var calendar = Calendar(identifier: .gregorian)
    /// 2026-10-12 10:00 UTC
    private var date = Date(timeIntervalSince1970: 1_791_799_200)

    init() {
        defaults = UserDefaults(suiteName: suiteName)!
        calendar.timeZone = TimeZone(identifier: "UTC")!
    }

    private func makeStats(at date: Date) -> TomatoStats {
        TomatoStats(defaults: defaults, now: { date }, calendar: calendar)
    }

    private func day(_ offset: Int) -> Date {
        calendar.date(byAdding: .day, value: offset, to: date)!
    }

    @Test("没有记录时今日 0 个、连续 0 天")
    func empty() {
        let stats = makeStats(at: date)
        #expect(stats.today == 0)
        #expect(stats.streak == 0)
        defaults.removePersistentDomain(forName: suiteName)
    }

    @Test("同一天休息多次，今日数量累加，连续 1 天")
    func countsToday() {
        let stats = makeStats(at: date)
        stats.recordBreak()
        stats.recordBreak()
        stats.recordBreak()
        #expect(stats.today == 3)
        #expect(stats.streak == 1)
        defaults.removePersistentDomain(forName: suiteName)
    }

    @Test("记录会保存下来，重新打开 App 后还在")
    func persists() {
        makeStats(at: date).recordBreak()
        let reopened = makeStats(at: date)
        #expect(reopened.today == 1)
        defaults.removePersistentDomain(forName: suiteName)
    }

    @Test("连续三天都有休息：连续 3 天")
    func streakAcrossDays() {
        makeStats(at: day(-2)).recordBreak()
        makeStats(at: day(-1)).recordBreak()
        let stats = makeStats(at: date)
        stats.recordBreak()
        #expect(stats.streak == 3)
        defaults.removePersistentDomain(forName: suiteName)
    }

    @Test("今天还没休息时，连续天数从昨天算起，不会零点就清零")
    func streakKeepsUntilTodayEnds() {
        makeStats(at: day(-2)).recordBreak()
        makeStats(at: day(-1)).recordBreak()
        let stats = makeStats(at: date)
        #expect(stats.today == 0)
        #expect(stats.streak == 2)
        defaults.removePersistentDomain(forName: suiteName)
    }

    @Test("中间断了一天，连续天数重新计算")
    func streakBreaks() {
        makeStats(at: day(-3)).recordBreak()
        makeStats(at: day(-1)).recordBreak()
        let stats = makeStats(at: date)
        stats.recordBreak()
        #expect(stats.streak == 2)
        defaults.removePersistentDomain(forName: suiteName)
    }

    @Test("跨过零点后刷新，今日数量归零")
    func newDayResetsToday() {
        var now = date
        let stats = TomatoStats(defaults: defaults, now: { now }, calendar: calendar)
        stats.recordBreak()
        now = day(1)
        stats.refresh()
        #expect(stats.today == 0)
        #expect(stats.streak == 1)
        defaults.removePersistentDomain(forName: suiteName)
    }

    @Test("超过一年的旧记录会被清理")
    func prunesOldRecords() {
        makeStats(at: day(-500)).recordBreak()
        makeStats(at: date).recordBreak()
        let stored = defaults.dictionary(forKey: "tomatoCounts") as? [String: Int] ?? [:]
        #expect(stored.count == 1)
        defaults.removePersistentDomain(forName: suiteName)
    }
}

@MainActor
struct TomatoStatsWeekTests {
    @Test("最近 7 天按时间先后排列，最后一天是今天，没有记录的天数为 0")
    func lastSevenDays() {
        let suite = "TomatoStatsWeekTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let today = Date(timeIntervalSince1970: 1_791_799_200) // 2026-10-12 周一
        let twoDaysAgo = calendar.date(byAdding: .day, value: -2, to: today)!
        let old = calendar.date(byAdding: .day, value: -9, to: today)!

        for (date, times) in [(twoDaysAgo, 2), (old, 5)] {
            let stats = TomatoStats(defaults: defaults, now: { date }, calendar: calendar)
            for _ in 0..<times { stats.recordBreak() }
        }
        let stats = TomatoStats(defaults: defaults, now: { today }, calendar: calendar)
        stats.recordBreak()

        #expect(stats.lastSevenDays.count == 7)
        #expect(stats.lastSevenDays.map(\.count) == [0, 0, 0, 0, 2, 0, 1])
        #expect(stats.lastSevenDays.last?.isToday == true)
        #expect(stats.lastSevenDays.last?.weekday == 2)
        #expect(stats.lastSevenDays.filter(\.isToday).count == 1)
        defaults.removePersistentDomain(forName: suite)
    }
}

@MainActor
struct AchievementTests {
    private func makeDefaults() -> (UserDefaults, String) {
        let suite = "AchievementTests-\(UUID().uuidString)"
        return (UserDefaults(suiteName: suite)!, suite)
    }

    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    private let today = Date(timeIntervalSince1970: 1_791_799_200)

    @Test("第一次休息解锁「第一个番茄」，之后不会重复解锁")
    func firstTomato() {
        let (defaults, suite) = makeDefaults()
        let stats = TomatoStats(defaults: defaults, now: { today }, calendar: calendar)
        stats.recordBreak()
        #expect(stats.justUnlocked == [.firstTomato])
        stats.recordBreak()
        #expect(stats.justUnlocked.isEmpty)
        #expect(stats.unlocked == [.firstTomato])
        defaults.removePersistentDomain(forName: suite)
    }

    @Test("单日第 5 个番茄解锁「单日 5 个」")
    func dailyFive() {
        let (defaults, suite) = makeDefaults()
        let stats = TomatoStats(defaults: defaults, now: { today }, calendar: calendar)
        for _ in 0..<4 { stats.recordBreak() }
        #expect(!stats.unlocked.contains(.dailyFive))
        stats.recordBreak()
        #expect(stats.justUnlocked == [.dailyFive])
        defaults.removePersistentDomain(forName: suite)
    }

    @Test("连续第 3 天解锁「连续 3 天」")
    func streakThree() {
        let (defaults, suite) = makeDefaults()
        let cal = calendar
        for offset in [-2, -1] {
            let d = cal.date(byAdding: .day, value: offset, to: today)!
            TomatoStats(defaults: defaults, now: { d }, calendar: cal).recordBreak()
        }
        let stats = TomatoStats(defaults: defaults, now: { today }, calendar: cal)
        stats.recordBreak()
        #expect(stats.justUnlocked == [.streakThree])
        defaults.removePersistentDomain(forName: suite)
    }

    @Test("累计数和已解锁成就会保存，重新打开后还在")
    func persists() {
        let (defaults, suite) = makeDefaults()
        let stats = TomatoStats(defaults: defaults, now: { today }, calendar: calendar)
        for _ in 0..<3 { stats.recordBreak() }
        let reopened = TomatoStats(defaults: defaults, now: { today }, calendar: calendar)
        #expect(reopened.total == 3)
        #expect(reopened.unlocked == [.firstTomato])
        #expect(reopened.justUnlocked.isEmpty)
        defaults.removePersistentDomain(forName: suite)
    }

    @Test("旧版本升级上来：累计数从已有的每日记录算出")
    func totalMigratesFromDailyCounts() {
        let (defaults, suite) = makeDefaults()
        defaults.set(["2026-10-10": 4, "2026-10-11": 6], forKey: "tomatoCounts")
        let stats = TomatoStats(defaults: defaults, now: { today }, calendar: calendar)
        #expect(stats.total == 10)
        defaults.removePersistentDomain(forName: suite)
    }
}
