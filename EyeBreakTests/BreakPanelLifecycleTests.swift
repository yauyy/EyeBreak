import AppKit
import SwiftUI
import Testing
@testable import EyeBreak

@MainActor
private final class LifecycleReminder: ReminderDelivering {
    func deliverReminder(restDuration: TimeInterval) {}
    func cancelPendingReminders() {}
    func playBreakComplete() {}
}

@MainActor
private final class LifecycleClock {
    var now = Date(timeIntervalSince1970: 1_791_799_200)
}

@MainActor
@Suite(.serialized)
struct BreakPanelLifecycleTests {
    @Test("真实提醒面板提前结束休息后卸载倒计时，再次显示创建新内容")
    func skippedRestUnloadsCountdown() async throws {
        try #require(NSScreen.main != nil, "面板生命周期测试需要可用的图形会话")
        let suiteName = "EyeBreak.BreakPanelLifecycleTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let clock = LifecycleClock()
        let model = EyeBreakModel(
            workInterval: 1200, restDuration: 20, reminder: LifecycleReminder(),
            now: { clock.now }, idleTime: { 0 }, isInMeeting: { false },
            isFullscreen: { false }, isWorkTime: { true },
            exerciseIndex: -1, usesSystemTimer: false
        )
        defer { model.shutdown() }
        let stats = TomatoStats(defaults: defaults, now: { clock.now })
        let existingWindows = Set(NSApplication.shared.windows.map(ObjectIdentifier.init))
        let controller = BreakPanelController(model: model, stats: stats)
        model.start()
        clock.now += 1200
        model.tick()
        #expect(model.phase == .awaitingBreak)
        let panel = try #require(NSApp.windows.compactMap { $0 as? NSPanel }.first {
            !existingWindows.contains(ObjectIdentifier($0))
                && $0.contentView is NSHostingView<BreakPanelView>
        })
        defer {
            // 即使断言提前抛错也关闭真实窗口，避免影响后续界面与 CPU 基准。
            panel.orderOut(nil)
            panel.contentView = nil
            panel.close()
            withExtendedLifetime(controller) {}
        }
        let host = try #require(panel.contentView)
        #expect(panel.isVisible)
        model.startBreak()
        #expect(model.phase == .resting)
        let rendered = try await waitForUpdate(panel: panel) { firstRing(in: host) != nil }
        try #require(rendered, "休息倒计时未在真实面板中创建")
        weak let restingRing = firstRing(in: host)
        try #require(restingRing != nil)

        model.skipBreak()
        #expect(model.phase == .working)
        // 等待真实 0.2 秒淡出及 SwiftUI 卸载，不能只用 orderOut 证明内容已经停止。
        let unloaded = try await waitForUpdate(panel: panel) {
            !panel.isVisible && firstRing(in: host) == nil
        }
        #expect(unloaded, "隐藏后倒计时原生视图仍留在面板内容树中")
        #expect(restingRing == nil || restingRing?.superview == nil)
        for _ in 0..<5 {
            clock.now += 1
            model.tick()
        }
        #expect(firstRing(in: host) == nil)

        // Controller 仍持有原面板；再次休息应挂载新倒计时，而非保留上一轮隐藏内容。
        clock.now += 1200
        model.tick()
        model.startBreak()
        let reopened = try await waitForUpdate(panel: panel) {
            panel.isVisible && firstRing(in: host) != nil
        }
        try #require(reopened)
        #expect(firstRing(in: host) !== restingRing)
        model.skipBreak()
        let hiddenAgain = try await waitForUpdate(panel: panel) {
            !panel.isVisible && firstRing(in: host) == nil
        }
        #expect(hiddenAgain)
    }

    private func firstRing(in view: NSView) -> RingProgressNSView? {
        if let ring = view as? RingProgressNSView { return ring }
        for child in view.subviews {
            if let ring = firstRing(in: child) { return ring }
        }
        return nil
    }

    private func waitForUpdate(panel: NSPanel, until condition: () -> Bool) async throws -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(3))
        while clock.now < deadline {
            panel.contentView?.layoutSubtreeIfNeeded()
            if condition() { return true }
            try await Task.sleep(for: .milliseconds(20))
        }
        return condition()
    }
}
