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
