import Foundation
import Testing
@testable import EyeBreak

struct WorkScheduleTests {
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return c
    }()

    /// 2026-10-12 是周一
    private func date(day: Int, hour: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: 30))!
    }

    @Test("未启用时任何时间都算在工作时段内")
    func disabledAlwaysContains() {
        let schedule = WorkSchedule(isEnabled: false)
        #expect(schedule.contains(date(day: 18, hour: 3), calendar: calendar))
    }

    @Test("工作日 9 点到 19 点", arguments: [
        (12, 8, false), (12, 9, true), (12, 18, true), (12, 19, false),
        (17, 10, false), (18, 10, false),
    ])
    func weekdayDaytime(day: Int, hour: Int, expected: Bool) {
        let schedule = WorkSchedule(isEnabled: true, startHour: 9, endHour: 19, weekdaysOnly: true)
        #expect(schedule.contains(date(day: day, hour: hour), calendar: calendar) == expected)
    }

    @Test("不限工作日时，周末也算")
    func includesWeekends() {
        let schedule = WorkSchedule(isEnabled: true, startHour: 9, endHour: 19, weekdaysOnly: false)
        #expect(schedule.contains(date(day: 18, hour: 10), calendar: calendar))
    }

    @Test("跨夜时段：22 点到 6 点", arguments: [(23, true), (2, true), (6, false), (12, false)])
    func overnight(hour: Int, expected: Bool) {
        let schedule = WorkSchedule(isEnabled: true, startHour: 22, endHour: 6, weekdaysOnly: false)
        #expect(schedule.contains(date(day: 13, hour: hour), calendar: calendar) == expected)
    }

    @Test("设置会保存下来")
    @MainActor
    func settingsPersist() {
        let suite = "WorkScheduleTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let settings = WorkScheduleSettings(defaults: defaults)
        settings.schedule.isEnabled = true
        settings.schedule.startHour = 10
        let reopened = WorkScheduleSettings(defaults: defaults)
        #expect(reopened.schedule.isEnabled)
        #expect(reopened.schedule.startHour == 10)
        defaults.removePersistentDomain(forName: suite)
    }
}
