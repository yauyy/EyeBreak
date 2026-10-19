import Combine
import Foundation
import Testing
@testable import EyeBreak

@MainActor
struct PerformanceObservationTests {
    @Test("隐藏菜单取消秒数订阅，重开立即读取最新一帧")
    func hiddenMenuFreezesCountdownInvalidations() {
        let fixture = Fixture()
        fixture.model.start()
        let countdown = MenuCountdownState(model: fixture.model, isVisible: true)
        var updates = 0
        let subscription = countdown.objectWillChange.sink { updates += 1 }
        defer { subscription.cancel() }

        fixture.advance(1)
        #expect(updates == 1)
        #expect(countdown.snapshot.remainingSeconds == 1199)
        countdown.setVisible(false)
        let frozen = countdown.snapshot
        updates = 0
        for _ in 0..<60 { fixture.advance(1) }
        #expect(updates == 0)
        #expect(countdown.snapshot == frozen)
        #expect(fixture.model.remainingSeconds == 1139)

        countdown.setVisible(true)
        #expect(countdown.snapshot.remainingSeconds == 1139)
        updates = 0
        fixture.advance(1)
        #expect(updates == 1)
        #expect(countdown.snapshot.remainingSeconds == 1138)

        countdown.setVisible(false)
        updates = 0
        fixture.advance(1)
        #expect(updates == 0)
    }

    @Test("菜单初始不可见时不观察模型，转发器也能随视图释放")
    func hiddenMenuStartsUnsubscribedAndReleasesObserver() {
        let fixture = Fixture()
        var countdown: MenuCountdownState? = MenuCountdownState(model: fixture.model, isVisible: false)
        weak let weakCountdown = countdown
        var updates = 0
        let subscription = countdown?.objectWillChange.sink { updates += 1 }
        fixture.model.start()
        fixture.advance(1)
        #expect(updates == 0)
        countdown?.setVisible(true)
        #expect(countdown?.snapshot.phase == .working)
        #expect(countdown?.snapshot.remainingSeconds == 1199)
        subscription?.cancel()
        countdown = nil
        #expect(weakCountdown == nil)
    }

    @Test("秒级计时不通知菜单主体或面板静态内容")
    func countdownDoesNotInvalidateStaticContent() {
        let fixture = Fixture()
        fixture.model.start()
        let menu = MenuModelChanges(model: fixture.model)
        let panel = BreakPanelPresentation(model: fixture.model)
        var menuUpdates = 0
        var panelUpdates = 0
        let menuSubscription = menu.objectWillChange.sink { menuUpdates += 1 }
        let panelSubscription = panel.objectWillChange.sink { panelUpdates += 1 }
        defer {
            menuSubscription.cancel()
            panelSubscription.cancel()
        }

        for _ in 0..<60 { fixture.advance(1) }
        #expect(fixture.model.remainingSeconds == 1140)
        #expect(menuUpdates == 0)
        #expect(panelUpdates == 0)

        fixture.advance(1140)
        fixture.model.startBreak()
        #expect(panel.configuration.phase == .resting)
        #expect(panel.configuration.exercise == .lookFar)
        menuUpdates = 0
        panelUpdates = 0
        for _ in 0..<5 { fixture.advance(1) }
        #expect(fixture.model.remainingSeconds == 15)
        #expect(menuUpdates == 0)
        #expect(panelUpdates == 0)
    }

    @Test("同阶段重来仍刷新菜单的下一轮生效提示")
    func resetRefreshesPendingDurationHint() {
        let fixture = Fixture()
        fixture.model.start()
        let menu = MenuModelChanges(model: fixture.model)
        var updates = 0
        let subscription = menu.objectWillChange.sink { updates += 1 }
        defer { subscription.cancel() }

        fixture.model.setWorkInterval(1500)
        #expect(fixture.model.workIntervalChangePending)
        let beforeReset = updates
        fixture.model.reset()
        #expect(fixture.model.phase == .working)
        #expect(!fixture.model.workIntervalChangePending)
        #expect(updates > beforeReset)
    }

    @Test("面板配置及时采用发布的新值，观察器可随视图释放")
    func panelConfigurationAndLifetime() {
        let fixture = Fixture()
        var panel: BreakPanelPresentation? = BreakPanelPresentation(model: fixture.model)
        weak let weakPanel = panel
        fixture.model.setRestDuration(30)
        #expect(panel?.configuration.restDuration == 30)
        fixture.model.start()
        fixture.advance(1200)
        #expect(panel?.configuration.phase == .awaitingBreak)
        #expect(panel?.configuration.exercise == .lookFar)
        panel = nil
        #expect(weakPanel == nil)
    }

    @Test("首次显示发生在阶段 willSet 回调中时采用传入的新阶段")
    func presentationCreatedDuringPhaseDelivery() {
        let fixture = Fixture()
        var panel: BreakPanelPresentation?
        let subscription = fixture.model.$phase.sink { phase in
            guard phase == .resting else { return }
            let created = BreakPanelPresentation(model: fixture.model)
            created.synchronizePhase(phase)
            panel = created
        }
        defer { subscription.cancel() }
        fixture.model.start()
        fixture.advance(1200)
        fixture.model.startBreak()
        #expect(panel?.configuration.phase == .resting)
    }

    @MainActor
    private final class Fixture {
        let clock = Clock()
        let model: EyeBreakModel

        init() {
            let clock = self.clock
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
