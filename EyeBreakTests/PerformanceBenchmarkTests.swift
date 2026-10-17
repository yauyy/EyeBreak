import AppKit
import Darwin
import SwiftUI
import Testing
@testable import EyeBreak

private enum PerformanceEnvironment {
    /// TEST_RUNNER_ 前缀使 xcodebuild 能将开关传给独立测试宿主。
    static let isEnabled = ["EYEBREAK_PERF", "TEST_RUNNER_EYEBREAK_PERF"].contains {
        ProcessInfo.processInfo.environment[$0] == "1"
    }
}

@MainActor
private final class PerformanceReminder: ReminderDelivering {
    func deliverReminder(restDuration: TimeInterval) {}
    func cancelPendingReminders() {}
    func playBreakComplete() {}
}

@MainActor
private final class PerformanceClock {
    var now = Date(timeIntervalSince1970: 1_791_799_200)
}

/// 每个场景独立创建数据，不读取用户偏好、不启动系统计时器、声音或更新检查。
@MainActor
private final class PerformanceFixture {
    let suiteName: String
    let defaults: UserDefaults
    let clock = PerformanceClock()
    let model: EyeBreakModel
    let stats: TomatoStats
    let updates = AppUpdater()
    let schedule: WorkScheduleSettings
    let panelState = BreakPanelController.State()

    init(showMenuBarTime: Bool = false) throws {
        suiteName = "EyeBreak.PerformanceBenchmarkTests.\(UUID().uuidString)"
        defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.set(showMenuBarTime, forKey: EyeBreakConfig.showMenuBarTimeKey)
        defaults.set(false, forKey: EyeBreakConfig.showWeekStatsKey)
        let clock = self.clock
        model = EyeBreakModel(
            workInterval: 1200, restDuration: 20, reminder: PerformanceReminder(),
            now: { clock.now }, idleTime: { 0 }, isInMeeting: { false },
            isFullscreen: { false }, isWorkTime: { true },
            exerciseIndex: -1, usesSystemTimer: false
        )
        stats = TomatoStats(defaults: defaults, now: { clock.now })
        schedule = WorkScheduleSettings(defaults: defaults)
        model.start()
    }

    func advanceOneSecond() {
        clock.now += 1
        model.tick()
    }

    func presentReminder(startBreak: Bool) {
        clock.now += 1200
        model.tick()
        if startBreak { model.startBreak() }
        panelState.isPresented = true
    }

    func cleanUp() {
        model.shutdown()
        defaults.removePersistentDomain(forName: suiteName)
    }
}

private struct PerformanceSample {
    let name: String
    let cpuSeconds: Double
    let wallSeconds: Double

    /// 单核满载计为 100%，与 top 中该进程的 CPU 百分比含义一致。
    var percent: Double { cpuSeconds / wallSeconds * 100 }

    var description: String {
        "\(name): \(String(format: "%.3f", cpuSeconds))s CPU / "
        + "\(String(format: "%.3f", wallSeconds))s = \(String(format: "%.2f", percent))%"
    }
}

@MainActor
@Suite(.serialized)
struct PerformanceBenchmarkTests {
    @Test(
        "真实窗口中按秒推进计时，测量菜单、休息面板、提醒动画和菜单栏标签 CPU",
        .enabled(if: PerformanceEnvironment.isEnabled, "设置 EYEBREAK_PERF=1 后才运行性能基准")
    )
    func measureVisibleScenes() async throws {
        try #require(!NSWorkspace.shared.accessibilityDisplayShouldReduceMotion, "播放基准需要先在系统设置中关闭减少动态效果")
        // 在同一个测试内依次执行，避免并行窗口、动画或后台场景互相污染进程 CPU。
        print("EyeBreak 性能基准：保持屏幕解锁且窗口可见；结果包含测试宿主开销，不扣除空白窗口基线。")
        let baseline = try await measure(
            "空白窗口基线", seconds: 3, warmup: 1,
            size: NSSize(width: 280, height: 400), content: Color.clear, tick: {}
        )
        report(baseline)
        try await measureMenu()
        try await measureRestingPanel()
        try await measureReminderAnimation()
        try await measureMenuBarLabel(showTime: false)
        try await measureMenuBarLabel(showTime: true)
    }

    private func measureMenu() async throws {
        let fixture = try PerformanceFixture()
        defer { fixture.cleanUp() }
        let menu = MenuBody(
            model: fixture.model, stats: fixture.stats, updates: fixture.updates,
            schedule: fixture.schedule, showWeekStats: .constant(false), openSettings: { _ in }
        )
        .frame(width: 280)
        .fixedSize(horizontal: false, vertical: true)
        .defaultAppStorage(fixture.defaults)
        let sample = try await measure(
            "菜单打开、专注中", seconds: 10, warmup: 1,
            size: NSSize(width: 280, height: 1), fitsHeight: true,
            content: menu, tick: fixture.advanceOneSecond
        )
        report(sample)
        #expect(fixture.model.phase == .working)
        #expect(sample.percent <= 2, "菜单 CPU 回归：\(sample.description)，上限 2%")
    }

    private func measureRestingPanel() async throws {
        let fixture = try PerformanceFixture()
        defer { fixture.cleanUp() }
        fixture.presentReminder(startBreak: true)
        // 假时钟在预热期间保持不变；真实动画播完后，再测八次按秒刷新的成本。
        let warmup = TomatoPlayback.duration(for: fixture.model.exercise.motion, loops: 2) + 0.75
        let sample = try await measure(
            "休息面板、番茄仔停止后", seconds: 8, warmup: warmup,
            size: BreakPanelController.panelSize,
            content: BreakPanelView(model: fixture.model, state: fixture.panelState, stats: fixture.stats),
            tick: fixture.advanceOneSecond
        )
        report(sample)
        #expect(fixture.model.phase == .resting)
        #expect(fixture.model.remainingSeconds == 12)
        #expect(sample.percent <= 2, "静止休息面板 CPU 回归：\(sample.description)，上限 2%")
    }

    private func measureReminderAnimation() async throws {
        let fixture = try PerformanceFixture()
        defer { fixture.cleanUp() }
        fixture.presentReminder(startBreak: false)
        #expect(fixture.model.exercise == .lookFar)
        // 看远处两轮共八秒，短暂预热后连续七秒都处于真实播放阶段。
        let sample = try await measure(
            "提醒面板、番茄仔播放期间", seconds: 7, warmup: 0.25,
            size: BreakPanelController.panelSize,
            content: BreakPanelView(model: fixture.model, state: fixture.panelState, stats: fixture.stats),
            tick: fixture.advanceOneSecond
        )
        report(sample)
        #expect(fixture.model.phase == .awaitingBreak)
        // 测试宿主自身有额外开销（本机约 9%）；真实 App 中 30fps 播放约 6%，优化前约 11%。
        #expect(sample.percent <= 12, "提醒动画 CPU 回归：\(sample.description)，上限 12%")
    }

    private func measureMenuBarLabel(showTime: Bool) async throws {
        let fixture = try PerformanceFixture(showMenuBarTime: showTime)
        defer { fixture.cleanUp() }
        let sample = try await measure(
            "菜单栏标签、倒计时\(showTime ? "开" : "关")", seconds: 10, warmup: 1,
            size: NSSize(width: 120, height: 26),
            content: MenuBarLabel(model: fixture.model).defaultAppStorage(fixture.defaults),
            tick: fixture.advanceOneSecond
        )
        report(sample)
        #expect(fixture.model.remainingSeconds == 1190)
        let limit = showTime ? 1.0 : 0.5
        #expect(sample.percent <= limit, "菜单栏标签 CPU 回归：\(sample.description)，上限 \(limit)%")
    }

    private func measure<Content: View>(
        _ name: String, seconds: Int, warmup: TimeInterval, size: NSSize,
        fitsHeight: Bool = false, content: Content, tick: () -> Void
    ) async throws -> PerformanceSample {
        let screen = try #require(NSScreen.main, "性能基准需要可用的图形会话")
        let root = AnyView(content)
        let host = NSHostingView(rootView: root)
        host.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.level = NSWindow.Level.floating
        // 不允许鼠标悬停触发重播，使测量只包含该场景指定的动作。
        window.ignoresMouseEvents = true
        window.contentView = host
        defer {
            // orderOut 本身未必卸载 SwiftUI；清空根视图，确保时间线及结束任务都被取消。
            host.rootView = AnyView(EmptyView())
            window.contentView = nil
            window.close()
        }
        host.layoutSubtreeIfNeeded()
        if fitsHeight {
            window.setContentSize(NSSize(width: size.width, height: ceil(host.fittingSize.height)))
        }
        let visible = screen.visibleFrame
        window.setFrameOrigin(NSPoint(x: visible.midX - window.frame.width / 2, y: visible.midY - window.frame.height / 2))
        window.orderFrontRegardless()
        #expect(window.isVisible)
        // 异步让出主执行器，允许 AppKit 提交绘制以及番茄仔的一次性停止任务按时执行。
        try await Task.sleep(for: .seconds(warmup))

        let clock = ContinuousClock()
        let wallStart = clock.now
        let cpuStart = try processCPUSeconds()
        for second in 1...seconds {
            tick()
            // 使用单调时钟的绝对截止时间，避免累积休眠误差；每秒只推进一次假时钟。
            try await clock.sleep(until: wallStart.advanced(by: .seconds(second)), tolerance: .milliseconds(2))
        }
        let cpuUsed = try processCPUSeconds() - cpuStart
        let duration = wallStart.duration(to: clock.now).components
        let wallUsed = Double(duration.seconds) + Double(duration.attoseconds) / 1e18
        return PerformanceSample(name: name, cpuSeconds: cpuUsed, wallSeconds: wallUsed)
    }

    private func processCPUSeconds() throws -> Double {
        var usage = rusage()
        try #require(getrusage(RUSAGE_SELF, &usage) == 0)
        return Double(usage.ru_utime.tv_sec) + Double(usage.ru_utime.tv_usec) / 1e6
            + Double(usage.ru_stime.tv_sec) + Double(usage.ru_stime.tv_usec) / 1e6
    }

    private func report(_ sample: PerformanceSample) {
        print("EYEBREAK_PERF \(sample.description)")
    }
}
