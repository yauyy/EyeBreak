import Foundation

/// 番茄收集的小成就，从容易到难排列
enum Achievement: String, CaseIterable, Codable, Identifiable {
    case firstTomato
    case dailyFive
    case dailyTen
    case streakThree
    case streakSeven
    case streakThirty
    case totalFifty
    case totalHundred

    var id: String { rawValue }

    var title: String {
        switch self {
        case .firstTomato: return String(localized: "第一个番茄")
        case .dailyFive: return String(localized: "单日 5 个")
        case .dailyTen: return String(localized: "单日 10 个")
        case .streakThree: return String(localized: "连续 3 天")
        case .streakSeven: return String(localized: "连续 7 天")
        case .streakThirty: return String(localized: "连续 30 天")
        case .totalFifty: return String(localized: "累计 50 个")
        case .totalHundred: return String(localized: "累计 100 个")
        }
    }

    /// 达成条件与标题分开，卡片和辅助功能可以各自使用完整文案。
    var detail: String {
        switch self {
        case .firstTomato: return String(localized: "收集第一个番茄")
        case .dailyFive: return String(localized: "一天内收集 5 个番茄")
        case .dailyTen: return String(localized: "一天内收集 10 个番茄")
        case .streakThree: return String(localized: "连续 3 天都有番茄")
        case .streakSeven: return String(localized: "连续 7 天都有番茄")
        case .streakThirty: return String(localized: "连续 30 天都有番茄")
        case .totalFifty: return String(localized: "累计收集 50 个番茄")
        case .totalHundred: return String(localized: "累计收集 100 个番茄")
        }
    }

    struct Progress: Equatable {
        enum Metric: Equatable { case today, streak, total }

        let current: Int
        let target: Int
        let metric: Metric
        let isUnlocked: Bool

        /// 限制异常旧数据的范围，进度条始终留在卡片内部。
        var fraction: Double {
            min(Double(current) / Double(target), 1)
        }

        var text: String {
            if isUnlocked { return String(localized: "已解锁") }
            switch metric {
            case .today: return String(localized: "今天 \(current)/\(target)")
            case .streak: return String(localized: "连续 \(current)/\(target) 天")
            case .total: return String(localized: "累计 \(current)/\(target)")
            }
        }
    }

    /// 已解锁记录独立于当前进度，跨日和连续天数重置后仍保留成就。
    func progress(today: Int, streak: Int, total: Int, earned: Bool) -> Progress {
        let current: Int
        let target: Int
        let metric: Progress.Metric
        switch self {
        case .firstTomato: (current, target, metric) = (total, 1, .total)
        case .dailyFive: (current, target, metric) = (today, 5, .today)
        case .dailyTen: (current, target, metric) = (today, 10, .today)
        case .streakThree: (current, target, metric) = (streak, 3, .streak)
        case .streakSeven: (current, target, metric) = (streak, 7, .streak)
        case .streakThirty: (current, target, metric) = (streak, 30, .streak)
        case .totalFifty: (current, target, metric) = (total, 50, .total)
        case .totalHundred: (current, target, metric) = (total, 100, .total)
        }
        return Progress(current: max(current, 0), target: target, metric: metric, isUnlocked: earned)
    }

    func accessibilityText(progress: Progress) -> String {
        let title = self.title
        if progress.isUnlocked { return String(localized: "已解锁：\(title)") }
        let text = progress.text
        return String(localized: "未解锁：\(title)，\(text)")
    }

    /// 按今日数量、连续天数、累计数量判断是否达成
    func isMet(today: Int, streak: Int, total: Int) -> Bool {
        switch self {
        case .firstTomato: return total >= 1
        case .dailyFive: return today >= 5
        case .dailyTen: return today >= 10
        case .streakThree: return streak >= 3
        case .streakSeven: return streak >= 7
        case .streakThirty: return streak >= 30
        case .totalFifty: return total >= 50
        case .totalHundred: return total >= 100
        }
    }
}
