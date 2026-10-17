import AppKit
import SwiftUI
import Testing
@testable import EyeBreak

@MainActor
private final class MenuWindowFixture {
    let suiteName: String
    let defaults: UserDefaults
    let model: EyeBreakModel
    let stats: TomatoStats
    let updates = AppUpdater()
    let schedule: WorkScheduleSettings
    let launchAtLogin = LaunchAtLogin(refreshesSystemStatus: false)
    let sounds = ReminderSounds(choice: .off)
    // String(localized:) 跟随宿主语言，中英文完整测试分别启动进程。
    let language = Bundle.main.preferredLocalizations.first ?? "zh-Hans"

    init() throws {
        suiteName = "EyeBreak.MenuWindowTests.\(UUID().uuidString)"
        defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.set(false, forKey: EyeBreakConfig.showWeekStatsKey)
        defaults.set([
            "2026-10-06": 2, "2026-10-07": 4, "2026-10-08": 1,
            "2026-10-09": 5, "2026-10-10": 3, "2026-10-11": 2, "2026-10-12": 8
        ], forKey: "tomatoCounts")
        defaults.set(25, forKey: "tomatoTotal")
        defaults.set([String](), forKey: "achievements")
        let date = Date(timeIntervalSince1970: 1_791_799_200)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        stats = TomatoStats(defaults: defaults, now: { date }, calendar: calendar)
        schedule = WorkScheduleSettings(defaults: defaults)
        schedule.schedule = WorkSchedule(isEnabled: false, startHour: 9, endHour: 19, weekdaysOnly: true)
        model = EyeBreakModel(
            workInterval: 1200, restDuration: 20, reminder: sounds,
            now: { date }, idleTime: { 0 }, isInMeeting: { false },
            isFullscreen: { false }, isWorkTime: { true },
            exerciseIndex: 0, usesSystemTimer: false
        )
        model.start()
        updates.setAvailableVersionForTesting("1.4.0")
    }

    func cleanUp() {
        model.shutdown()
        defaults.removePersistentDomain(forName: suiteName)
    }

    func shell(heightLimit: CGFloat) -> some View {
        MenuContentView(
            model: model, launchAtLogin: launchAtLogin, stats: stats, sounds: sounds,
            updates: updates, schedule: schedule, openSettings: { _ in },
            menuWindowChanged: { _ in }, heightLimitOverride: heightLimit
        )
        .defaultAppStorage(defaults)
        .environment(\.locale, Locale(identifier: language))
        .transaction { $0.disablesAnimations = true }
    }

    func naturalHeight(showWeekStats: Bool) -> CGFloat {
        let content = MenuBody(
            model: model, stats: stats, updates: updates, schedule: schedule,
            showWeekStats: .constant(showWeekStats), openSettings: { _ in }
        )
        .frame(width: 280)
        .fixedSize(horizontal: false, vertical: true)
        .environment(\.locale, Locale(identifier: language))
        let host = NSHostingView(rootView: content)
        let size = host.fittingSize
        #expect(abs(size.width - 280) <= 1)
        return ceil(size.height)
    }
}

@MainActor
@Suite(.serialized)
struct MenuWindowTests {
    @Test("菜单外壳在同一窗口随本周收起、展开、再收起自动调整高度")
    func shellTracksNaturalHeightInSameWindow() throws {
        let fixture = try MenuWindowFixture()
        defer { fixture.cleanUp() }
        let host = NSHostingView(rootView: fixture.shell(heightLimit: 10_000))
        let window = makeWindow(host: host)
        defer { window.close() }

        let collapsedHeight = fixture.naturalHeight(showWeekStats: false)
        let collapsedSize = waitForStableSize(host: host, window: window, expectedHeight: collapsedHeight)
        expectSize(collapsedSize, height: collapsedHeight)

        fixture.defaults.set(true, forKey: EyeBreakConfig.showWeekStatsKey)
        let expandedHeight = fixture.naturalHeight(showWeekStats: true)
        let expandedSize = waitForStableSize(host: host, window: window, expectedHeight: expandedHeight)
        expectSize(expandedSize, height: expandedHeight)
        #expect(expandedSize.height > collapsedSize.height)

        fixture.defaults.set(false, forKey: EyeBreakConfig.showWeekStatsKey)
        let restoredHeight = fixture.naturalHeight(showWeekStats: false)
        let restoredSize = waitForStableSize(host: host, window: window, expectedHeight: restoredHeight)
        expectSize(restoredSize, height: restoredHeight)
        #expect(abs(restoredSize.height - collapsedSize.height) <= 1)
    }

    @Test("菜单外壳达到 300 点上限时保留更高的自然内容")
    func shellCapsHeight() throws {
        let fixture = try MenuWindowFixture()
        defer { fixture.cleanUp() }
        fixture.defaults.set(true, forKey: EyeBreakConfig.showWeekStatsKey)
        let naturalHeight = fixture.naturalHeight(showWeekStats: true)
        #expect(naturalHeight > 300)
        let host = NSHostingView(rootView: fixture.shell(heightLimit: 300))
        let window = makeWindow(host: host)
        defer { window.close() }

        let size = waitForStableSize(host: host, window: window, expectedHeight: 300)
        expectSize(size, height: 300)
    }

    private func makeWindow<Content: View>(host: NSHostingView<Content>) -> NSWindow {
        // 仅提供初始矩形，后续完全由宿主约束调整窗口，不在测试中设置内容尺寸。
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 280, height: 1),
            styleMask: [.borderless], backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        host.sizingOptions = [.minSize, .intrinsicContentSize, .maxSize]
        window.contentView = host
        return window
    }

    private func waitForStableSize<Content: View>(
        host: NSHostingView<Content>, window: NSWindow, expectedHeight: CGFloat
    ) -> NSSize {
        let deadline = Date().addingTimeInterval(3)
        var previousSize = NSSize.zero
        var stableSamples = 0
        while Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
            host.layoutSubtreeIfNeeded()
            let size = host.bounds.size
            let windowSize = window.contentLayoutRect.size
            // 连续五次达到预期且窗口与宿主一致，避免把更新前的旧尺寸误判为稳定。
            if abs(size.width - 280) <= 1,
               abs(size.height - expectedHeight) <= 1,
               abs(windowSize.width - size.width) <= 1,
               abs(windowSize.height - size.height) <= 1,
               abs(previousSize.width - size.width) < 0.01,
               abs(previousSize.height - size.height) < 0.01 {
                stableSamples += 1
                if stableSamples >= 5 {
                    print("MenuContentView \(window.contentLayoutRect.size), host: \(size)")
                    return size
                }
            } else {
                stableSamples = 0
            }
            previousSize = size
        }
        Issue.record("菜单窗口尺寸未稳定：host=\(host.bounds.size)，window=\(window.contentLayoutRect.size)，预期 280 × \(expectedHeight)")
        return host.bounds.size
    }

    private func expectSize(_ size: NSSize, height: CGFloat) {
        #expect(abs(size.width - 280) <= 1)
        #expect(abs(size.height - height) <= 1)
    }
}
