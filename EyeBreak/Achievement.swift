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
