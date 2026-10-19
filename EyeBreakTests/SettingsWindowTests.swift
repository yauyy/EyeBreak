import AppKit
import Combine
import SwiftUI
import Testing
@testable import EyeBreak

@MainActor
@Suite(.serialized)
struct SettingsWindowTests {
    @Test("各关闭入口释放设置宿主，重开保留所选分区", arguments: ["button", "commandW", "escape", "controller"])
    func closingReleasesContentAndRestoresPresentation(method: String) async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let controller = fixture.controller
        let window = try #require(controller.window)
        #expect(window.contentViewController == nil)
        controller.show(section: .rest)
        weak var previousHost: NSViewController?
        weak var previousView: NSView?
        try autoreleasepool {
            let host = try #require(window.contentViewController as? NSHostingController<SettingsContentView>)
            host.view.layoutSubtreeIfNeeded()
            // 模拟用户点击分区，状态应由控制器保留，不依赖旧视图存活。
            host.rootView.presentation.section = .about
            previousHost = host
            previousView = host.view
        }
        switch method {
        case "button": window.performClose(nil)
        case "commandW":
            let event = try #require(NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: .command,
                timestamp: 0, windowNumber: window.windowNumber, context: nil,
                characters: "w", charactersIgnoringModifiers: "w", isARepeat: false, keyCode: 13
            ))
            #expect(window.performKeyEquivalent(with: event))
        case "escape": window.cancelOperation(nil)
        default: controller.close()
        }
        #expect(!window.isVisible)
        #expect(window.contentViewController == nil)
        // AppKit 可在本轮事件结束后才归还临时引用，同时检查宿主控制器和实际视图。
        for _ in 0..<100 {
            if previousHost == nil && previousView == nil { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(previousHost == nil)
        #expect(previousView == nil)
        controller.show()
        let reopened = try #require(window.contentViewController as? NSHostingController<SettingsContentView>)
        #expect(controller.window === window)
        #expect(reopened.rootView.presentation.section == .about)
        #expect(window.isVisible)
        controller.close()
    }

    @Test("关闭时卸载内容后，重开保留上次窗口位置")
    func reopeningPreservesWindowPosition() throws {
        let screen = try #require(NSScreen.main, "窗口位置测试需要可用的图形会话")
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let window = try #require(fixture.controller.window)
        fixture.controller.show()
        let frame = screen.visibleFrame
        window.setFrameOrigin(NSPoint(
            x: frame.midX - window.frame.width / 2 + 20,
            y: frame.midY - window.frame.height / 2
        ))
        let originalFrame = window.frame
        fixture.controller.close()
        fixture.controller.show()
        #expect(window.frame == originalFrame)
    }

    @Test("动作设置只发布动作集合变化，专注每秒 tick 不通知设置视图")
    func exerciseSelectionDoesNotObserveCountdown() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let selection = SettingsExerciseSelection(model: fixture.model)
        var updates = 0
        let subscription = selection.objectWillChange.sink { updates += 1 }
        defer { subscription.cancel() }
        fixture.model.start()
        for _ in 0..<60 { fixture.advance() }
        #expect(fixture.model.remainingSeconds == 1140)
        #expect(updates == 0)
        selection.setExercise(.lookFar, enabled: false)
        #expect(!selection.enabledExercises.contains(.lookFar))
        #expect(updates == 1)
        selection.setExercise(.lookFar, enabled: false)
        #expect(updates == 1)
    }

    @Test("动作观察对象可以释放，不被模型订阅保留")
    func exerciseObserverIsReleased() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        var selection: SettingsExerciseSelection? = SettingsExerciseSelection(model: fixture.model)
        weak let reference = selection
        selection = nil
        #expect(reference == nil)
    }

    @MainActor
    private final class Clock {
        var now = Date(timeIntervalSince1970: 1_791_799_200)
    }

    @MainActor
    private final class Fixture {
        let suiteName = "EyeBreak.SettingsWindowTests.\(UUID().uuidString)"
        let defaults: UserDefaults
        let clock = Clock()
        let model: EyeBreakModel
        let controller: SettingsWindowController

        init() throws {
            defaults = try #require(UserDefaults(suiteName: suiteName))
            let clock = self.clock
            let sounds = ReminderSounds(choice: .off)
            model = EyeBreakModel(
                workInterval: 1200, restDuration: 20, reminder: sounds,
                now: { clock.now }, idleTime: { 0 }, isInMeeting: { false },
                isFullscreen: { false }, usesSystemTimer: false
            )
            controller = SettingsWindowController(
                model: model, launchAtLogin: LaunchAtLogin(refreshesSystemStatus: false),
                stats: TomatoStats(defaults: defaults, now: { clock.now }), sounds: sounds,
                updates: AppUpdater(), schedule: WorkScheduleSettings(defaults: defaults),
                appearance: AppearanceSettings(defaults: defaults, appliesToApplication: false),
                language: LanguageSettings(defaults: defaults, domainName: suiteName),
                onReplayOnboarding: {}
            )
        }

        func advance() {
            clock.now += 1
            model.tick()
        }

        func cleanUp() {
            controller.close()
            model.shutdown()
            defaults.removePersistentDomain(forName: suiteName)
        }
    }
}
