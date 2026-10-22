import Foundation

/// 长休息：每隔几轮专注，用一次更长的休息做起身活动（喝水、走路）。
/// 开启后短休息只轮换眼睛动作；关闭时所有启用的动作一起轮换，和 1.5 一样。
struct LongBreakSettings: Codable, Equatable, Sendable {
    var isEnabled = true
    /// 每隔几轮专注来一次长休息
    var everyRounds = 4
    var minutes = 3

    static let roundsRange = 2...8
    static let minutesRange = 1...15

    var duration: TimeInterval { TimeInterval(minutes * 60) }

    /// 偏好损坏或越界时夹回范围，界面和计时都不会读到非法值。
    func normalized() -> LongBreakSettings {
        LongBreakSettings(
            isEnabled: isEnabled,
            everyRounds: min(max(everyRounds, Self.roundsRange.lowerBound), Self.roundsRange.upperBound),
            minutes: min(max(minutes, Self.minutesRange.lowerBound), Self.minutesRange.upperBound)
        )
    }
}

/// 「暂停一段时间」的选项：到点自动继续计时，不用记得回来点「继续」。
enum TimedPause: String, CaseIterable, Codable, Sendable {
    case oneHour
    case twoHours
    case restOfDay

    var title: String {
        switch self {
        case .oneHour: return String(localized: "1 小时后")
        case .twoHours: return String(localized: "2 小时后")
        case .restOfDay: return String(localized: "明天")
        }
    }

    /// 从现在算起的自动继续时刻；「明天」取下一个本地零点，夜里回到电脑会被判定为离开，不会白跑计时。
    func resumeDate(from now: Date, calendar: Calendar = .current) -> Date {
        switch self {
        case .oneHour: return now.addingTimeInterval(3600)
        case .twoHours: return now.addingTimeInterval(7200)
        case .restOfDay:
            let tomorrow = calendar.date(byAdding: .day, value: 1, to: now) ?? now.addingTimeInterval(86400)
            return calendar.startOfDay(for: tomorrow)
        }
    }

    /// 菜单里显示的继续时刻；不在同一天时只说「明天」，不显示零点时间。
    static func resumeText(for date: Date, now: Date, calendar: Calendar = .current) -> String {
        guard calendar.isDate(date, inSameDayAs: now) else { return String(localized: "明天继续") }
        let time = date.formatted(date: .omitted, time: .shortened)
        return String(localized: "\(time) 继续")
    }
}
