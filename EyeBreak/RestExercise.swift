import Foundation

/// 休息时轮换的护眼小动作
enum RestExercise: Int, CaseIterable, Sendable {
    case lookFar = 0
    case blink = 1
    case closeEyes = 2
    case rollEyes = 3
    case drinkWater = 4
    case walk = 5

    static func at(_ index: Int) -> RestExercise {
        allCases[((index % allCases.count) + allCases.count) % allCases.count]
    }

    /// 旧偏好损坏或所有动作都关闭时，仍至少保留「看看远处」。
    static func normalized(_ exercises: Set<RestExercise>) -> Set<RestExercise> {
        exercises.isEmpty ? [.lookFar] : exercises
    }

    /// 休息倒计时中显示的标题
    var title: String {
        switch self {
        case .lookFar: return String(localized: "看看远处")
        case .blink: return String(localized: "眨眨眼")
        case .closeEyes: return String(localized: "闭眼放松")
        case .rollEyes: return String(localized: "转转眼球")
        case .drinkWater: return String(localized: "喝口水")
        case .walk: return String(localized: "走一走")
        }
    }

    /// 提醒时的说明，后面接「放松 N 秒」
    var instruction: String {
        switch self {
        case .lookFar: return String(localized: "看看 6 米外")
        case .blink: return String(localized: "慢慢眨眨眼")
        case .closeEyes: return String(localized: "轻轻闭上眼睛")
        case .rollEyes: return String(localized: "眼球慢慢画圈")
        case .drinkWater: return String(localized: "起身喝几口水")
        case .walk: return String(localized: "起身走一走")
        }
    }
}
