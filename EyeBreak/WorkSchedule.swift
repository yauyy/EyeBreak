import Combine
import Foundation

/// 工作时段：只在设定的整点时间段（以及可选的工作日）内提醒
struct WorkSchedule: Codable, Equatable {
    var isEnabled = false
    var startHour = 9
    var endHour = 19
    var weekdaysOnly = true

    static let hourRange = 0...23

    /// 某个时刻是否在工作时段内；未启用时任何时刻都算在内
    func contains(_ date: Date, calendar: Calendar = .current) -> Bool {
        guard isEnabled else { return true }
        let parts = calendar.dateComponents([.weekday, .hour], from: date)
        // 公历中 weekday 1 是周日，7 是周六
        if weekdaysOnly, parts.weekday == 1 || parts.weekday == 7 { return false }
        let hour = parts.hour ?? 0
        if startHour == endHour { return true }
        if startHour < endHour { return hour >= startHour && hour < endHour }
        // 跨夜，例如 22 点到 6 点
        return hour >= startHour || hour < endHour
    }

    /// 菜单里显示的时间段，例如 "9:00–19:00"
    var rangeText: String {
        "\(startHour):00–\(endHour):00"
    }
}

/// 工作时段设置，保存在本机
@MainActor
final class WorkScheduleSettings: ObservableObject {
    @Published var schedule: WorkSchedule {
        didSet {
            save()
            if schedule != oldValue { onScheduleChanged?() }
        }
    }

    /// 在新设置已经可读时通知模型，避免 @Published 的 willSet 读到旧时段。
    var onScheduleChanged: (() -> Void)?

    private static let storageKey = "workSchedule"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.storageKey),
           let saved = try? JSONDecoder().decode(WorkSchedule.self, from: data) {
            schedule = saved
        } else {
            schedule = WorkSchedule()
        }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(schedule) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }
}
