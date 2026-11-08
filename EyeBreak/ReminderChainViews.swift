import AppKit
import Combine
import SwiftUI

/// 编辑期间保留原始文本：无效数字不能悄悄回退为上一次合法的间隔。
struct ReminderChainDraft: Equatable {
    struct Step: Identifiable, Equatable {
        var id: UUID
        var title: String
        var intervalText: String
    }

    var id: UUID
    var title: String
    var hour: Int
    var minute: Int
    var isEnabled: Bool
    var steps: [Step]

    init(chain: ReminderChain) {
        id = chain.id
        title = chain.title
        hour = chain.hour
        minute = chain.minute
        isEnabled = chain.isEnabled
        steps = chain.steps.map { Step(id: $0.id, title: $0.title, intervalText: String($0.intervalMinutes)) }
    }

    var chain: ReminderChain? {
        var parsed: [ReminderChainStep] = []
        for step in steps {
            guard let minutes = Int(step.intervalText.trimmingCharacters(in: .whitespacesAndNewlines)), minutes > 0 else { return nil }
            parsed.append(ReminderChainStep(id: step.id, title: step.title, intervalMinutes: minutes))
        }
        return ReminderChain(id: id, title: title, hour: hour, minute: minute, isEnabled: isEnabled, steps: parsed)
    }

    func validationMessage(calendar: Calendar = .current, now: Date = Date()) -> String? {
        guard let chain else { return String(localized: "每一步的间隔都需要填写正整数分钟。") }
        return chain.validationMessage(calendar: calendar, now: now)
    }

    mutating func addStep() {
        steps.append(Step(id: UUID(), title: "", intervalText: "5"))
    }

    /// 只预览下一轮实际日历时间，越界或溢出时不生成误导性的时刻。
    func preview(for stepID: UUID, after now: Date = Date(), calendar: Calendar = .current) -> Date? {
        guard let chain, let start = chain.nextMainDate(after: now, calendar: calendar),
              let next = chain.nextMainDate(after: start, calendar: calendar) else { return nil }
        var cumulative = 0
        for step in chain.steps {
            let sum = cumulative.addingReportingOverflow(step.intervalMinutes)
            guard !sum.overflow, sum.partialValue > 0, sum.partialValue < 1440 else { return nil }
            cumulative = sum.partialValue
            let date = start.addingTimeInterval(TimeInterval(cumulative) * 60)
            guard date < next else { return nil }
            if step.id == stepID { return date }
        }
        return nil
    }
}

struct ReminderChainSettingsView: View {
    @ObservedObject var store: ReminderChainStore
    @Environment(\.locale) private var locale
    @State private var editing: ReminderChain?
    @State private var deleting: ReminderChain?
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let loadError = store.loadError { errorText(loadError) }
            if let chain = editing {
                ReminderChainEditorView(chain: chain, onCancel: { editing = nil }) { saved in
                    try store.save(saved)
                    editing = nil
                }
                .id(chain.id)
            } else {
                HStack {
                    Text("连环提醒")
                        .font(Theme.font(18, .bold))
                    Spacer()
                    Button {
                        errorMessage = nil
                        editing = ReminderChain(title: "")
                    } label: {
                        Label("新增提醒", systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.tomatoFill)
                }
                Text("设定每天的首次时间，再添加间隔提醒。吃药、做饭或其他事情，都可以安排成一串。")
                    .font(Theme.font(12))
                    .foregroundStyle(Theme.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
                if store.chains.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "alarm")
                            .font(.system(size: 30))
                            .foregroundStyle(Theme.tomato)
                        Text("还没有连环提醒")
                            .font(Theme.font(15, .semibold))
                        Text("例如：08:00 第一件事 → 5 分钟后第二件事 → 再过 10 分钟第三件事")
                            .font(Theme.font(12))
                            .multilineTextAlignment(.center)
                            .foregroundStyle(Theme.inkSoft)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(24)
                    .background(cardBackground)
                } else {
                    TimelineView(.periodic(from: .now, by: 60)) { context in
                        VStack(spacing: 12) {
                            ForEach(store.chains) { chain in
                                chainCard(chain, now: context.date)
                            }
                        }
                    }
                }
                if let errorMessage { errorText(errorMessage) }
                Text("连环提醒独立于护眼计时，不受工作时段或暂停影响。请保持 EyeBreak 运行；睡眠或退出期间无法准时提醒，恢复后只补本轮最近的一条。")
                    .font(Theme.font(11))
                    .foregroundStyle(Theme.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .foregroundStyle(Theme.ink)
        .confirmationDialog("删除这组连环提醒？", isPresented: Binding(
            get: { deleting != nil }, set: { if !$0 { deleting = nil } }
        ), titleVisibility: .visible) {
            Button("删除", role: .destructive) {
                if let deleting { store.delete(id: deleting.id) }
                deleting = nil
            }
            Button("取消", role: .cancel) { deleting = nil }
        } message: {
            Text("这组尚未触发和待确认的提醒也会一并取消。")
        }
    }

    private func chainCard(_ chain: ReminderChain, now: Date) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(isOn: Binding(
                get: { chain.isEnabled },
                set: { enabled in
                    do {
                        try store.setEnabled(enabled, id: chain.id)
                        errorMessage = nil
                    } catch { errorMessage = error.localizedDescription }
                }
            )) {
                Text(verbatim: chain.title)
                    .font(Theme.font(15, .semibold))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .toggleStyle(CuteToggleStyle())
            HStack(alignment: .firstTextBaseline) {
                Text("每天 \(Self.clockText(hour: chain.hour, minute: chain.minute)) · \(chain.steps.count) 条后续提醒")
                    .font(Theme.font(12))
                    .foregroundStyle(Theme.inkSoft)
                Spacer(minLength: 4)
                Button("编辑") { errorMessage = nil; editing = chain }
                    .buttonStyle(.borderless)
                Button("删除", role: .destructive) { deleting = chain }
                    .buttonStyle(.borderless)
            }
            if chain.isEnabled, let next = chain.nextMainDate(after: now) {
                Text("下一轮：\(next.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(locale)))")
                    .font(Theme.font(11))
                    .foregroundStyle(Theme.inkSoft)
            }
            if let warning = chain.validationMessage(now: now) { errorText(warning) }
        }
        .padding(Theme.Spacing.card)
        .background(cardBackground)
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).fill(Theme.creamDeep)
    }

    private func errorText(_ text: String) -> some View {
        Label { Text(verbatim: text) } icon: { Image(systemName: "exclamationmark.circle") }
            .font(Theme.font(12))
            .foregroundStyle(Theme.tomato)
            .fixedSize(horizontal: false, vertical: true)
    }

    static func clockText(hour: Int, minute: Int) -> String {
        String(format: "%02d:%02d", hour, minute)
    }
}

struct ReminderChainEditorView: View {
    @Environment(\.locale) private var locale
    @State private var draft: ReminderChainDraft
    @State private var saveError: String?
    let onCancel: () -> Void
    let onSave: (ReminderChain) throws -> Void

    init(chain: ReminderChain, onCancel: @escaping () -> Void, onSave: @escaping (ReminderChain) throws -> Void) {
        _draft = State(initialValue: ReminderChainDraft(chain: chain))
        self.onCancel = onCancel
        self.onSave = onSave
    }

    private var selectedTime: Binding<Date> {
        Binding(get: {
            let calendar = Calendar.current
            return calendar.date(bySettingHour: draft.hour, minute: draft.minute, second: 0, of: Date()) ?? Date()
        }, set: {
            let parts = Calendar.current.dateComponents([.hour, .minute], from: $0)
            draft.hour = parts.hour ?? 8
            draft.minute = parts.minute ?? 0
        })
    }

    var body: some View {
        let validation = draft.validationMessage()
        return VStack(alignment: .leading, spacing: 16) {
            Text("编辑连环提醒")
                .font(Theme.font(18, .bold))
            VStack(alignment: .leading, spacing: 12) {
                DatePicker("每天首次提醒", selection: selectedTime, displayedComponents: .hourAndMinute)
                    .datePickerStyle(.field)
                    .font(Theme.font(14, .semibold))
                TextField("首次提醒内容", text: $draft.title)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("首次提醒内容")
                Text("首次时间是整组提醒的起点。保存或重新启用后，从下一次首次提醒开始。")
                    .font(Theme.font(11))
                    .foregroundStyle(Theme.inkSoft)
            }
            .padding(Theme.Spacing.card)
            .background(cardBackground)

            VStack(alignment: .leading, spacing: 6) {
                Text("后续提醒")
                    .font(Theme.font(14, .semibold))
                Text("每一步填写与上一步的间隔，时间从首次提醒累计；点击“知道了”不会推迟后续提醒。")
                    .font(Theme.font(11))
                    .foregroundStyle(Theme.inkSoft)
            }
            ForEach($draft.steps) { $step in
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        TextField("提醒内容", text: $step.title)
                            .textFieldStyle(.roundedBorder)
                            .accessibilityLabel("后续提醒内容")
                        Button {
                            draft.steps.removeAll { $0.id == step.id }
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("删除这一步")
                        .help("删除这一步")
                    }
                    HStack {
                        Text("在上一步")
                        TextField("分钟数", text: $step.intervalText)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 70)
                            .multilineTextAlignment(.trailing)
                            .accessibilityLabel("与上一步间隔的分钟数")
                        Text("分钟后")
                    }
                    .font(Theme.font(12))
                    if let preview = draft.preview(for: step.id) {
                        Text("预计：\(preview.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(locale)))")
                            .font(Theme.font(11))
                            .foregroundStyle(Theme.inkSoft)
                    }
                }
                .padding(Theme.Spacing.card)
                .background(cardBackground)
            }
            Button {
                draft.addStep()
            } label: {
                Label("添加后续提醒", systemImage: "plus.circle")
            }
            .buttonStyle(.borderless)
            Text("后续间隔之和必须小于下一轮首次提醒的间隔；相等也不允许。跨到次日可以，但不能进入下一轮。")
                .font(Theme.font(11))
                .foregroundStyle(Theme.inkSoft)
            if let message = saveError ?? validation {
                Label { Text(verbatim: message) } icon: { Image(systemName: "exclamationmark.circle") }
                    .font(Theme.font(12))
                    .foregroundStyle(Theme.tomato)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 12) {
                Button("取消", action: onCancel)
                    .buttonStyle(PillButtonStyle(kind: .secondary))
                Button("保存") {
                    guard let chain = draft.chain, draft.validationMessage() == nil else { return }
                    do { try onSave(chain) } catch { saveError = error.localizedDescription }
                }
                .buttonStyle(PillButtonStyle())
                .disabled(validation != nil)
                .opacity(validation == nil ? 1 : 0.5)
            }
        }
        .foregroundStyle(Theme.ink)
        .onChange(of: draft) { _ in saveError = nil }
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).fill(Theme.creamDeep)
    }
}

@MainActor
final class ReminderChainPanelPresentation: ObservableObject {
    @Published var pending: [ReminderChainOccurrence] = []
    var presentedAt = Date()
}

@MainActor
final class ReminderChainPanelController {
    static let panelSize = NSSize(width: 340, height: 340)
    private let scheduler: ReminderChainScheduler
    private let presentation = ReminderChainPanelPresentation()
    private var subscription: AnyCancellable?
    private var panel: NSPanel?

    init(scheduler: ReminderChainScheduler) {
        self.scheduler = scheduler
        subscription = scheduler.$pending
            .removeDuplicates()
            .sink { [weak self] pending in
                MainActor.assumeIsolated { self?.synchronize(pending) }
            }
    }

    func shutdown() {
        subscription?.cancel()
        subscription = nil
        panel?.orderOut(nil)
        panel?.contentView = nil
        panel?.close()
        panel = nil
    }

    private func synchronize(_ pending: [ReminderChainOccurrence]) {
        presentation.presentedAt = Date()
        presentation.pending = pending
        guard !pending.isEmpty else {
            panel?.orderOut(nil)
            panel?.contentView = nil
            return
        }
        let panel = self.panel ?? makePanel()
        self.panel = panel
        if panel.contentView == nil {
            panel.contentView = NSHostingView(rootView: ReminderChainPanelView(presentation: presentation) { [weak scheduler] id in
                scheduler?.acknowledge(id: id)
            })
        }
        guard !panel.isVisible else { return }
        let mouse = NSEvent.mouseLocation
        if let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) ?? NSScreen.main {
            panel.setFrameOrigin(NSPoint(x: screen.visibleFrame.minX + 16, y: screen.visibleFrame.maxY - Self.panelSize.height - 12))
        }
        panel.orderFrontRegardless()
        NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested, userInfo: [
            .announcement: String(localized: "连环提醒"),
            .priority: NSAccessibilityPriorityLevel.medium.rawValue
        ])
    }

    private func makePanel() -> NSPanel {
        let panel = ReminderChainFloatingPanel(contentRect: NSRect(origin: .zero, size: Self.panelSize),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.isReleasedWhenClosed = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        // NSPanel 初始化时已带有空白 NSView；清掉它，让首次显示也挂载真正的提醒内容。
        panel.contentView = nil
        return panel
    }
}

private final class ReminderChainFloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

struct ReminderChainPanelView: View {
    @ObservedObject var presentation: ReminderChainPanelPresentation
    @Environment(\.locale) private var locale
    let acknowledge: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "alarm.fill")
                    .foregroundStyle(Theme.tomato)
                Text("连环提醒")
                    .font(Theme.font(16, .bold))
                Spacer()
                Text("待确认 \(presentation.pending.count) 条")
                    .font(Theme.font(11))
                    .foregroundStyle(Theme.inkSoft)
            }
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(presentation.pending.reversed()) { occurrence in
                        VStack(alignment: .leading, spacing: 8) {
                            if occurrence.title != occurrence.chainTitle {
                                Text(verbatim: occurrence.chainTitle)
                                    .font(Theme.font(11))
                                    .foregroundStyle(Theme.inkSoft)
                            }
                            Text(verbatim: occurrence.title)
                                .font(Theme.font(17, .semibold))
                                .fixedSize(horizontal: false, vertical: true)
                                .textSelection(.enabled)
                            Text("计划时间：\(occurrence.scheduledAt.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(locale)))")
                                .font(Theme.font(11))
                                .foregroundStyle(Theme.inkSoft)
                            if presentation.presentedAt.timeIntervalSince(occurrence.scheduledAt) >= 60 {
                                Text("已错过计划时间，请根据实际情况处理。")
                                    .font(Theme.font(11))
                                    .foregroundStyle(Theme.tomato)
                            }
                            Button("知道了") { acknowledge(occurrence.id) }
                                .buttonStyle(PillButtonStyle())
                                .accessibilityHint(Text(verbatim: occurrence.title))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(Theme.Spacing.card)
                        .background(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).fill(Theme.creamDeep))
                    }
                }
            }
        }
        .foregroundStyle(Theme.ink)
        .padding(Theme.Spacing.panel)
        .frame(width: ReminderChainPanelController.panelSize.width, height: ReminderChainPanelController.panelSize.height)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous).fill(Theme.cream))
    }
}
