import Combine
import Foundation

/// 番茄收集：每完整休息一次收集一个番茄，按天记录在本机
@MainActor
final class TomatoStats: ObservableObject {
    /// 今天收集的番茄数
    @Published private(set) var today = 0
    /// 连续有休息记录的天数；今天还没休息时从昨天算起，避免零点一过就清零
    @Published private(set) var streak = 0
    /// 最近 7 天（含今天，按时间先后）每天收集的番茄
    @Published private(set) var lastSevenDays: [Day] = []

    struct Day: Equatable, Identifiable {
        let date: Date
        let count: Int
        /// 公历 weekday：1 是周日，7 是周六
        let weekday: Int
        let isToday: Bool
        var id: Date { date }
    }

    private static let storageKey = "tomatoCounts"
    private static let keepDays = 400

    private let defaults: UserDefaults
    private let now: () -> Date
    private let calendar: Calendar
    /// "yyyy-MM-dd" → 当天收集数
    private var counts: [String: Int]

    init(defaults: UserDefaults = .standard, now: @escaping () -> Date = Date.init, calendar: Calendar = .current) {
        self.defaults = defaults
        self.now = now
        self.calendar = calendar
        counts = defaults.dictionary(forKey: Self.storageKey) as? [String: Int] ?? [:]
        refresh()
    }

    func recordBreak() {
        counts[key(for: now()), default: 0] += 1
        prune()
        defaults.set(counts, forKey: Self.storageKey)
        refresh()
    }

    /// 重新计算今日数量和连续天数（跨过零点后打开菜单时调用）
    func refresh() {
        let todayDate = now()
        today = counts[key(for: todayDate)] ?? 0

        var day = today > 0 ? todayDate : calendar.date(byAdding: .day, value: -1, to: todayDate)!
        var days = 0
        while (counts[key(for: day)] ?? 0) > 0 {
            days += 1
            day = calendar.date(byAdding: .day, value: -1, to: day)!
        }
        streak = days

        lastSevenDays = (0..<7).reversed().map { offset in
            let date = calendar.date(byAdding: .day, value: -offset, to: todayDate)!
            return Day(
                date: calendar.startOfDay(for: date),
                count: counts[key(for: date)] ?? 0,
                weekday: calendar.component(.weekday, from: date),
                isToday: offset == 0
            )
        }
    }

    private func key(for date: Date) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    private func prune() {
        guard let cutoff = calendar.date(byAdding: .day, value: -Self.keepDays, to: now()) else { return }
        let cutoffKey = key(for: cutoff)
        counts = counts.filter { $0.key >= cutoffKey }
    }
}
