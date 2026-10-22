// 这些界面回归依赖 Debug 专用状态注入；Release 构建仍可单独运行性能基准。
#if DEBUG
import AppKit
import SwiftUI
import Testing
@testable import EyeBreak

@MainActor
private final class LayoutReminder: ReminderDelivering {
    func deliverReminder(restDuration: TimeInterval) {}
    func cancelPendingReminders() {}
    func playBreakComplete() {}
}

@MainActor
private final class LayoutClock {
    var now = Date(timeIntervalSince1970: 1_000_000)
    var isWorkTime = true
}

@MainActor
struct MenuLayoutTests {
    // 1.6 起暂停状态多一行「自动继续」选项（约 32 点），上限从 640 放宽到 672，仍远小于常见最小屏幕约 770 点的可用高度。
    @Test("156 点圆环下菜单本体中英文最坏组合自然高度不超过 672 点", arguments: ["zh-Hans", "en"], ["snooze", "meeting", "fullscreen", "focus", "paused", "pausedTimed", "offHours"])
    func worstNaturalHeight(language: String, state: String) throws {
        let suite = "EyeBreak.MenuLayoutTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let clock = LayoutClock()
        let model = EyeBreakModel(
            workInterval: 1200, restDuration: 20, reminder: LayoutReminder(),
            now: { clock.now }, idleTime: { 0 },
            isInMeeting: { state == "meeting" || state.hasPrefix("paused") }, isFullscreen: { state == "fullscreen" },
            isWorkTime: { clock.isWorkTime },
            usesSystemTimer: false
        )
        if state == "focus" { model.setFocusHold(true) }
        model.start()
        clock.now += 1200
        model.tick()
        if state == "snooze" { model.snooze() }
        switch state {
        case "snooze": #expect(model.isSnoozing)
        case "paused":
            model.pause()
            #expect(model.phase == .paused)
            #expect(model.deferReason == nil)
        case "pausedTimed":
            model.pause(for: .twoHours)
            #expect(model.phase == .paused)
            #expect(model.timedPauseResumeText != nil)
        case "offHours":
            clock.isWorkTime = false
            model.tick()
            #expect(model.phase == .offHours)
        default: #expect(model.deferReason != nil)
        }
        let updates = AppUpdater()
        updates.setAvailableVersionForTesting("1.4.0")
        let stats = TomatoStats(defaults: defaults)
        stats.recordBreak()
        let schedule = WorkScheduleSettings(defaults: defaults)
        schedule.schedule.weekdaysOnly = true
        let content = MenuBody(
            model: model, stats: stats, updates: updates,
            schedule: schedule, showWeekStats: .constant(true),
            openSettings: { _ in }, showsAllPendingHintsForTesting: true
        )
        .environment(\.locale, Locale(identifier: language))
        // 直接测量没有外壳、没有固定高度的 MenuBody，避免把截断误判为合格。
        let host = NSHostingView(rootView: content)
        host.frame.size.width = 280
        let size = host.fittingSize
        print("MenuBody \(language) \(state): \(size.width) × \(size.height) pt")
        #expect(size.width == 280)
        #expect(size.height > 400)
        #expect(size.height <= 672)
    }
}

#endif
