import AppKit
import Combine
import Foundation
import Testing
@testable import EyeBreak

@MainActor
struct MenuBarLabelTests {
    @Test("关闭菜单栏倒计时时每秒 tick 不发布标签变化")
    func hiddenTimeDoesNotPublishSeconds() {
        let fixture = Fixture()
        fixture.model.start()
        let state = MenuBarLabelState(model: fixture.model, showsTime: false)
        var updates = 0
        let subscription = state.objectWillChange.sink { updates += 1 }
        defer { subscription.cancel() }

        for _ in 0..<60 { fixture.advance(1) }

        #expect(updates == 0)
        #expect(state.presentation.assetName == "MenuBarWorking")
        #expect(state.presentation.text == nil)
        #expect(state.presentation.accessibility == "EyeBreak " + String(localized: "专注中"))
    }

    @Test("倒计时仅在显示秒数变化时发布，切换偏好读取最新秒数")
    func shownTimePublishesOnlyChangedText() {
        let fixture = Fixture()
        fixture.model.start()
        let state = MenuBarLabelState(model: fixture.model, showsTime: false)
        fixture.advance(5)
        var updates = 0
        let subscription = state.objectWillChange.sink { updates += 1 }
        defer { subscription.cancel() }

        state.setShowsTime(true)
        #expect(state.presentation.text == "19:55")
        #expect(updates == 1)
        fixture.model.tick()
        #expect(updates == 1)
        fixture.advance(1)
        #expect(state.presentation.text == "19:54")
        #expect(updates == 2)
        state.setShowsTime(true)
        #expect(updates == 2)
        state.setShowsTime(false)
        #expect(updates == 3)
        fixture.advance(1)
        #expect(updates == 3)
    }

    @Test("标签使用发布的新阶段，等待休息与休息中图标、文案一致")
    func phaseTransitionsKeepCorrectPresentation() {
        let fixture = Fixture()
        let state = MenuBarLabelState(model: fixture.model, showsTime: true)
        fixture.model.start()
        #expect(state.presentation.assetName == "MenuBarWorking")
        fixture.advance(1200)
        #expect(state.presentation.assetName == "MenuBarAwaiting")
        #expect(state.presentation.text == String(localized: "休息"))
        fixture.model.startBreak()
        #expect(state.presentation.assetName == "MenuBarResting")
        #expect(state.presentation.text == "0:20")
        fixture.advance(1)
        #expect(state.presentation.text == "0:19")
    }

    @Test("标签销毁后取消订阅，不被计时模型持有")
    func labelStateCanBeReleased() {
        let fixture = Fixture()
        var state: MenuBarLabelState? = MenuBarLabelState(model: fixture.model, showsTime: true)
        weak let weakState = state
        #expect(weakState != nil)
        state = nil
        #expect(weakState == nil)
        fixture.model.start()
        fixture.advance(1)
    }

    @Test("相同菜单栏显示复用图片，倒计时关后复用模板原图")
    func iconResourcesAreReused() {
        let first = MenuBarIcon.compose(assetName: "MenuBarWorking", text: "19:59")
        #expect(first === MenuBarIcon.compose(assetName: "MenuBarWorking", text: "19:59"))
        #expect(first.isTemplate)
        let icon = MenuBarIcon.compose(assetName: "MenuBarWorking", text: nil)
        #expect(icon === MenuBarIcon.compose(assetName: "MenuBarWorking", text: nil))
        #expect(icon.isTemplate)
        #expect(icon.size == NSSize(width: 18, height: 18))
        #expect(first.size.width > icon.size.width)
    }

    @MainActor
    private final class Fixture {
        let model: EyeBreakModel
        private let clock: Clock

        init() {
            let clock = Clock()
            self.clock = clock
            model = EyeBreakModel(
                workInterval: 1200, restDuration: 20, reminder: SilentReminder(),
                now: { clock.now }, idleTime: { 0 }, isInMeeting: { false }, isFullscreen: { false },
                usesSystemTimer: false
            )
        }

        func advance(_ seconds: TimeInterval) {
            clock.now += seconds
            model.tick()
        }
    }

    @MainActor
    private final class Clock {
        var now = Date(timeIntervalSince1970: 1_000_000)
    }

    @MainActor
    private final class SilentReminder: ReminderDelivering {
        func deliverReminder(restDuration: TimeInterval) {}
        func cancelPendingReminders() {}
        func playBreakComplete() {}
    }
}
