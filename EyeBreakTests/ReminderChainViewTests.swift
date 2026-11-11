import AppKit
import SwiftUI
import Testing
@testable import EyeBreak

@MainActor
@Suite(.serialized)
struct ReminderChainViewTests {
    nonisolated private static let snapshotDirectory = ProcessInfo.processInfo.environment["EYEBREAK_SNAPSHOT_DIR"]
        ?? ProcessInfo.processInfo.environment["TEST_RUNNER_EYEBREAK_SNAPSHOT_DIR"]

    @Test("编辑框的非整数、空白、零和溢出输入不能保存旧间隔", arguments: ["abc", "", "  ", "0", "-5", "1.5", "999999999999999999999999999"])
    func invalidIntervalTextIsRejected(text: String) {
        var draft = ReminderChainDraft(chain: ReminderChain(title: "第一次提醒", steps: [ReminderChainStep(title: "第二次提醒")]))
        draft.steps[0].intervalText = text
        #expect(draft.chain == nil)
        #expect(draft.validationMessage() != nil)
        #expect(draft.preview(for: draft.steps[0].id) == nil)
    }

    @Test("编辑草稿可以连续添加和删除，取消时不改变原始计划")
    func editingIsIsolatedAndStepsStayOrdered() throws {
        let original = ReminderChain(title: "首次提醒")
        var draft = ReminderChainDraft(chain: original)
        draft.addStep()
        draft.steps[0].title = "五分钟后"
        let firstID = draft.steps[0].id
        draft.addStep()
        draft.steps[1].title = "再十分钟后"
        draft.steps[1].intervalText = "10"
        #expect(original.steps.isEmpty)
        let saved = try #require(draft.chain)
        #expect(saved.steps.map(\.intervalMinutes) == [5, 10])
        #expect(saved.totalIntervalMinutes == 15)
        draft.steps.removeAll { $0.id == firstID }
        #expect(draft.chain?.steps.map(\.title) == ["再十分钟后"])
        #expect(draft.chain?.totalIntervalMinutes == 10)
        #expect(original.title == "首次提醒")
    }

    @Test("累计预览按主时刻加每步间隔，跨日清楚且不预览越界步骤")
    func cumulativePreviewAndBoundary() throws {
        let calendar = Self.utcCalendar
        let now = Self.date(2026, 11, 8, 22, 0)
        var draft = ReminderChainDraft(chain: ReminderChain(title: "第一步", hour: 23, minute: 50, steps: [
            ReminderChainStep(title: "第二步", intervalMinutes: 5),
            ReminderChainStep(title: "第三步", intervalMinutes: 10)
        ]))
        #expect(draft.preview(for: draft.steps[0].id, after: now, calendar: calendar) == Self.date(2026, 11, 8, 23, 55))
        #expect(draft.preview(for: draft.steps[1].id, after: now, calendar: calendar) == Self.date(2026, 11, 9, 0, 5))
        #expect(draft.validationMessage(calendar: calendar, now: now) == nil)
        draft.steps[1].intervalText = "1435"
        #expect(draft.validationMessage(calendar: calendar, now: now) != nil)
        #expect(draft.preview(for: draft.steps[1].id, after: now, calendar: calendar) == nil)
        draft.steps[1].intervalText = String(Int.max)
        #expect(draft.preview(for: draft.steps[1].id, after: now, calendar: calendar) == nil)
    }

    @Test("真实连环提醒面板到点显示，确认卸载内容，下一步重新挂载")
    func panelLifecycle() async throws {
        try #require(NSScreen.main != nil, "需要可用的图形会话")
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let existing = Set(NSApp.windows.map(ObjectIdentifier.init))
        let controller = ReminderChainPanelController(scheduler: fixture.scheduler)
        defer { controller.shutdown() }
        fixture.scheduler.start()
        #expect(fixture.scheduler.pending.isEmpty)
        fixture.clock.now = Self.date(2026, 11, 8, 8, 0)
        fixture.scheduler.tick()
        let first = try #require(fixture.scheduler.pending.first)
        let panel = try #require(NSApp.windows.compactMap { $0 as? NSPanel }.first {
            !existing.contains(ObjectIdentifier($0)) && $0.contentView is NSHostingView<ReminderChainPanelView>
        })
        #expect(panel.isVisible)
        let host = try #require(panel.contentView as? NSHostingView<ReminderChainPanelView>)
        #expect(host.rootView.presentation.pending.first?.title == fixture.chain.title)
        // 调用真实按钮绑定的 action，证明点击会从调度器确认，并卸载面板内容。
        host.rootView.acknowledge(first.id)
        #expect(fixture.scheduler.pending.isEmpty)
        #expect(!panel.isVisible)
        #expect(panel.contentView == nil)
        fixture.clock.now = Self.date(2026, 11, 8, 8, 5)
        fixture.scheduler.tick()
        #expect(panel.isVisible)
        #expect(panel.contentView !== host)
        let reopened = try #require(panel.contentView as? NSHostingView<ReminderChainPanelView>)
        #expect(reopened.rootView.presentation.pending.first?.title == "第二件事")
        fixture.scheduler.tick()
        #expect(fixture.scheduler.pending.count == 1)
        try fixture.store.setEnabled(false, id: fixture.chain.id)
        #expect(!panel.isVisible)
        #expect(panel.contentView == nil)
    }

    @Test("长标题和多步骤编辑器在固定设置宽度下仍可纵向滚动")
    func longEditorStaysWithinWidth() async throws {
        let chain = ReminderChain(title: String(repeating: "很长的提醒内容", count: 12), steps: (0..<8).map {
            ReminderChainStep(title: "第 \($0 + 1) 步" + String(repeating: "详细内容", count: 12), intervalMinutes: 5)
        })
        let host = NSHostingView(rootView: editorContent(chain))
        host.frame = NSRect(x: 0, y: 0, width: 560, height: 480)
        let window = makeWindow(host)
        defer { window.close() }
        for _ in 0..<10 {
            host.layoutSubtreeIfNeeded()
            await Task.yield()
        }
        let scroll = try #require(firstScrollView(in: host))
        let document = try #require(scroll.documentView)
        #expect(document.bounds.height > scroll.contentView.bounds.height)
        #expect(document.bounds.width <= scroll.contentView.bounds.width + 1)
        let end = max(0, document.bounds.maxY - scroll.contentView.bounds.height)
        scroll.contentView.scroll(to: NSPoint(x: 0, y: end))
        scroll.reflectScrolledClipView(scroll.contentView)
        #expect(scroll.contentView.bounds.maxY >= document.bounds.maxY - 1)
        #expect(host.bounds.size == NSSize(width: 560, height: 480))
    }

    @Test("生成连环提醒编辑、边界错误和面板截图", .enabled(if: snapshotDirectory?.isEmpty == false), arguments: [false, true])
    func snapshots(dark: Bool) async throws {
        let normal = ReminderChain(title: "第一件事", steps: [
            ReminderChainStep(title: "第二件事", intervalMinutes: 5),
            ReminderChainStep(title: "第三件事", intervalMinutes: 10)
        ])
        try await capture(editorContent(normal), name: "routine-editor-valid", dark: dark, size: NSSize(width: 560, height: 480))
        let invalid = ReminderChain(title: "第一件事", steps: [ReminderChainStep(title: "时间超出下一轮", intervalMinutes: 1440)])
        try await capture(editorContent(invalid), name: "routine-editor-invalid", dark: dark, size: NSSize(width: 560, height: 480), scrollToEnd: true)
        let presentation = ReminderChainPanelPresentation()
        let start = Self.date(2026, 11, 8, 8, 0)
        presentation.presentedAt = start.addingTimeInterval(7 * 60)
        presentation.pending = [ReminderChainOccurrence(id: "snapshot", chainID: normal.id, chainTitle: normal.title,
            title: "第二件事", scheduledAt: start.addingTimeInterval(5 * 60), cycleStart: start, cycleEnd: start.addingTimeInterval(86400))]
        try await capture(ReminderChainPanelView(presentation: presentation, acknowledge: { _ in }), name: "routine-panel",
            dark: dark, size: ReminderChainPanelController.panelSize)
        // 最紧凑的情况：两行长标题、所属计划副标题，并且还有积压。
        let crowded = ReminderChainPanelPresentation()
        crowded.presentedAt = start.addingTimeInterval(5 * 60)
        crowded.pending = [presentation.pending[0], ReminderChainOccurrence(id: "crowded", chainID: UUID(), chainTitle: "晚间安排",
            title: "把明天要带的药和水杯都放进包里再出门", scheduledAt: start.addingTimeInterval(5 * 60), cycleStart: start,
            cycleEnd: start.addingTimeInterval(86400))]
        try await capture(ReminderChainPanelView(presentation: crowded, acknowledge: { _ in }), name: "routine-panel-crowded",
            dark: dark, size: ReminderChainPanelController.panelSize)
    }

    private func editorContent(_ chain: ReminderChain) -> some View {
        GeometryReader { viewport in
            ScrollView {
                ReminderChainEditorView(chain: chain, onCancel: {}, onSave: { _ in })
                    .frame(width: max(0, viewport.size.width - reservedScrollerWidth - 44), alignment: .leading)
                    .padding(22)
            }
        }
        .background(Theme.cream)
    }

    private var reservedScrollerWidth: CGFloat {
        NSScroller.preferredScrollerStyle == .legacy ? NSScroller.scrollerWidth(for: .regular, scrollerStyle: .legacy) : 0
    }

    private func makeWindow(_ host: NSView) -> NSWindow {
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        return window
    }

    private func firstScrollView(in view: NSView) -> NSScrollView? {
        if let scroll = view as? NSScrollView { return scroll }
        return view.subviews.lazy.compactMap { firstScrollView(in: $0) }.first
    }

    private func capture<Content: View>(_ content: Content, name: String, dark: Bool, size: NSSize, scrollToEnd: Bool = false) async throws {
        let language = Bundle.main.preferredLocalizations.first?.hasPrefix("en") == true ? "en" : "zh-Hans"
        let host = NSHostingView(rootView: content.environment(\.locale, Locale(identifier: language))
            .environment(\.colorScheme, dark ? .dark : .light).transaction { $0.disablesAnimations = true })
        host.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        host.frame = NSRect(origin: .zero, size: size)
        let window = makeWindow(host)
        window.appearance = host.appearance
        defer { window.close() }
        for _ in 0..<10 { host.layoutSubtreeIfNeeded(); await Task.yield() }
        if scrollToEnd, let scroll = firstScrollView(in: host), let document = scroll.documentView {
            scroll.contentView.scroll(to: NSPoint(x: 0, y: max(0, document.bounds.maxY - scroll.contentView.bounds.height)))
            scroll.reflectScrolledClipView(scroll.contentView)
        }
        host.layoutSubtreeIfNeeded()
        host.displayIfNeeded()
        let bitmap = try #require(NSBitmapImageRep(bitmapDataPlanes: nil,
            pixelsWide: Int(size.width * 2), pixelsHigh: Int(size.height * 2), bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        bitmap.size = size
        host.effectiveAppearance.performAsCurrentDrawingAppearance { host.cacheDisplay(in: host.bounds, to: bitmap) }
        let data = try #require(bitmap.representation(using: .png, properties: [:]))
        let path = try #require(Self.snapshotDirectory)
        let temporary = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().standardizedFileURL
        let output = (path.hasPrefix("/") ? URL(fileURLWithPath: path, isDirectory: true) : temporary.appendingPathComponent(path, isDirectory: true))
            .resolvingSymlinksInPath().standardizedFileURL
        guard output.path == temporary.path || output.path.hasPrefix(temporary.path + "/") else { throw CocoaError(.fileWriteNoPermission) }
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let file = output.appendingPathComponent("\(name)-\(language)-\(dark ? "dark" : "light").png")
        try data.write(to: file, options: .atomic)
        print("EyeBreak 截图：\(file.path)")
    }

    private static var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private static func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
        utcCalendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    @MainActor
    private final class Clock {
        var now = ReminderChainViewTests.date(2026, 11, 8, 7, 59)
    }

    @MainActor
    private final class Fixture {
        let suite = "EyeBreak.ReminderChainViewTests.\(UUID().uuidString)"
        let defaults: UserDefaults
        let clock = Clock()
        let chain = ReminderChain(title: "第一件事", steps: [ReminderChainStep(title: "第二件事", intervalMinutes: 5)])
        let store: ReminderChainStore
        let scheduler: ReminderChainScheduler

        init() throws {
            defaults = try #require(UserDefaults(suiteName: suite))
            let clock = self.clock
            store = ReminderChainStore(defaults: defaults, now: { clock.now }, calendar: { ReminderChainViewTests.utcCalendar })
            scheduler = ReminderChainScheduler(store: store, defaults: defaults, now: { clock.now }, calendar: { ReminderChainViewTests.utcCalendar }, usesSystemTimer: false)
            try store.save(chain)
        }

        func cleanUp() {
            scheduler.shutdown()
            defaults.removePersistentDomain(forName: suite)
        }
    }
}
