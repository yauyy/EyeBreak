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
    @State private var editing: ReminderChain?
    @State private var deleting: ReminderChain?
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if let loadError = store.loadError { ReminderChainErrorText(text: loadError) }
            if let chain = editing {
                ReminderChainEditorView(
                    chain: chain, isNew: !store.chains.contains { $0.id == chain.id },
                    onCancel: { editing = nil }
                ) { saved in
                    try store.save(saved)
                    editing = nil
                }
                .id(chain.id)
            } else {
                if store.chains.isEmpty {
                    emptyState
                } else {
                    ForEach(store.chains) { chainCard($0) }
                    addButton
                }
                if let errorMessage { ReminderChainErrorText(text: errorMessage) }
            }
        }
        .foregroundStyle(Theme.ink)
        .confirmationDialog(
            Text("删除「\(deleting?.title ?? "")」？"),
            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
            titleVisibility: .visible
        ) {
            Button("删除", role: .destructive) {
                if let deleting { store.delete(id: deleting.id) }
                deleting = nil
            }
            Button("取消", role: .cancel) { deleting = nil }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            TomatoAvatar(size: 56)
            Text("还没有连环提醒")
                .font(Theme.font(15, .semibold))
            Text("比如 8:00 点眼药水，5 分钟后再点一次")
                .font(Theme.font(12))
                .foregroundStyle(Theme.inkSoft)
                .multilineTextAlignment(.center)
            addButton
                .frame(width: 160)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .settingsCard()
    }

    private var addButton: some View {
        Button {
            errorMessage = nil
            editing = ReminderChain(title: "")
        } label: {
            Label("新增提醒", systemImage: "plus")
        }
        .buttonStyle(PillButtonStyle(kind: store.chains.isEmpty ? .primary : .secondary))
    }

    private func chainCard(_ chain: ReminderChain) -> some View {
        VStack(alignment: .leading, spacing: 12) {
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
                    .font(Theme.font(14, .semibold))
                    .lineLimit(2)
            }
            .toggleStyle(CuteToggleStyle())
            ReminderChainTimeline(chain: chain)
                .opacity(chain.isEnabled ? 1 : 0.5)
            HStack(spacing: 4) {
                if chain.isEnabled, let warning = chain.validationMessage() {
                    ReminderChainErrorText(text: warning)
                }
                Spacer(minLength: 0)
                Button("编辑") { errorMessage = nil; editing = chain }
                Button("删除") { deleting = chain }
            }
            .buttonStyle(PillButtonStyle(kind: .plain, small: true))
        }
        .settingsCard()
    }

    static func clockText(hour: Int, minute: Int) -> String {
        String(format: "%02d:%02d", hour, minute)
    }

    /// 列表展示用：按每天的主时间加累计分钟，跨过零点标「次日」。
    static func clockText(hour: Int, minute: Int, offset: Int) -> String {
        let total = hour * 60 + minute + offset
        let text = clockText(hour: (total / 60) % 24, minute: total % 60)
        return total >= 1440 ? String(localized: "次日 \(text)") : text
    }
}

/// 一组提醒的时间线：每行「时刻 + 内容」，比一句摘要更直观。
private struct ReminderChainTimeline: View {
    let chain: ReminderChain

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                HStack(spacing: 10) {
                    Circle()
                        .fill(index == 0 ? Theme.tomato : Theme.tomatoSoft)
                        .frame(width: 6, height: 6)
                    Text(verbatim: row.time)
                        .font(Theme.font(12, .semibold))
                        .monospacedDigit()
                        .frame(minWidth: 40, alignment: .leading)
                    Text(verbatim: row.title)
                        .font(Theme.font(12))
                        .foregroundStyle(Theme.inkSoft)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var rows: [(time: String, title: String)] {
        var offset = 0
        var result = [(ReminderChainSettingsView.clockText(hour: chain.hour, minute: chain.minute), chain.title)]
        for step in chain.steps {
            let sum = offset.addingReportingOverflow(step.intervalMinutes)
            guard !sum.overflow, sum.partialValue < 2880 else { break }
            offset = sum.partialValue
            result.append((ReminderChainSettingsView.clockText(hour: chain.hour, minute: chain.minute, offset: offset), step.title))
        }
        return result
    }
}

private struct ReminderChainErrorText: View {
    let text: String

    var body: some View {
        Label { Text(verbatim: text) } icon: { Image(systemName: "exclamationmark.circle") }
            .font(Theme.font(12))
            .foregroundStyle(Theme.tomato)
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct ReminderChainEditorView: View {
    @State private var draft: ReminderChainDraft
    @State private var saveError: String?
    let isNew: Bool
    let onCancel: () -> Void
    let onSave: (ReminderChain) throws -> Void

    init(
        chain: ReminderChain, isNew: Bool = false,
        onCancel: @escaping () -> Void, onSave: @escaping (ReminderChain) throws -> Void
    ) {
        _draft = State(initialValue: ReminderChainDraft(chain: chain))
        self.isNew = isNew
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

    /// 只缺内容时禁用保存即可，不必再用一行红字提醒。
    private var hasBlankTitle: Bool {
        draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || draft.steps.contains { $0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    var body: some View {
        let validation = draft.validationMessage()
        let shownError = saveError ?? (hasBlankTitle ? nil : validation)
        return VStack(alignment: .leading, spacing: 18) {
            Text(isNew ? "新增提醒" : "编辑提醒")
                .font(Theme.font(18, .bold))

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("每天")
                        .font(Theme.font(14, .medium))
                    Spacer()
                    DatePicker("每天", selection: selectedTime, displayedComponents: .hourAndMinute)
                        .datePickerStyle(.field)
                        .labelsHidden()
                }
                TextField("提醒内容，比如：点眼药水", text: $draft.title)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("首次提醒内容")
            }
            .settingsCard()

            VStack(alignment: .leading, spacing: 12) {
                Text("之后")
                    .font(Theme.font(14, .medium))
                ForEach($draft.steps) { $step in
                    HStack(spacing: 8) {
                        TextField(text: $step.intervalText, prompt: Text(verbatim: "5")) { EmptyView() }
                            .textFieldStyle(.roundedBorder)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 48)
                            .accessibilityLabel("与上一步间隔的分钟数")
                        Text("分钟后")
                            .font(Theme.font(12))
                            .foregroundStyle(Theme.inkSoft)
                            .fixedSize()
                        TextField("提醒内容", text: $step.title)
                            .textFieldStyle(.roundedBorder)
                            .accessibilityLabel("后续提醒内容")
                        Text(verbatim: previewText(for: step.id))
                            .font(Theme.font(12, .medium))
                            .monospacedDigit()
                            .foregroundStyle(Theme.inkSoft)
                            .frame(minWidth: 40, alignment: .trailing)
                            .fixedSize()
                        Button {
                            draft.steps.removeAll { $0.id == step.id }
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .foregroundStyle(Theme.inkSoft)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("删除这一步")
                        .help("删除这一步")
                    }
                }
                Button {
                    draft.addStep()
                } label: {
                    Label("添加后续提醒", systemImage: "plus.circle.fill")
                }
                .buttonStyle(PillButtonStyle(kind: .plain))
                .foregroundStyle(Theme.tomato)
            }
            .settingsCard()

            if let shownError { ReminderChainErrorText(text: shownError) }
            HStack(spacing: 12) {
                Button("取消", action: onCancel)
                    .buttonStyle(PillButtonStyle(kind: .secondary))
                Button("保存") {
                    guard let chain = draft.chain, draft.validationMessage() == nil else { return }
                    do { try onSave(chain) } catch { saveError = error.localizedDescription }
                }
                .buttonStyle(PillButtonStyle())
                .keyboardShortcut(.defaultAction)
                .disabled(validation != nil)
                .opacity(validation == nil ? 1 : 0.5)
            }
        }
        .foregroundStyle(Theme.ink)
        .onChange(of: draft) { _ in saveError = nil }
    }

    /// 只显示时刻；跨过零点时加「次日」，无效间隔时显示占位。
    private func previewText(for stepID: UUID) -> String {
        let calendar = Calendar.current
        guard let date = draft.preview(for: stepID, calendar: calendar),
              let start = draft.chain?.nextMainDate(after: Date(), calendar: calendar) else { return "--:--" }
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        let text = ReminderChainSettingsView.clockText(hour: parts.hour ?? 0, minute: parts.minute ?? 0)
        return calendar.isDate(date, inSameDayAs: start) ? text : String(localized: "次日 \(text)")
    }
}

@MainActor
final class ReminderChainPanelPresentation: ObservableObject {
    @Published var pending: [ReminderChainOccurrence] = []
    var presentedAt = Date()
}

@MainActor
final class ReminderChainPanelController {
    static let panelSize = NSSize(width: 300, height: 236)
    private let scheduler: ReminderChainScheduler
    private let presentation = ReminderChainPanelPresentation()
    private var subscription: AnyCancellable?
    private var panel: ReminderChainFloatingPanel?

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
        // 与休息面板同高，放在左上角，两者同时出现时互不遮挡。
        let mouse = NSEvent.mouseLocation
        if let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) ?? NSScreen.main {
            panel.setFrameOrigin(NSPoint(x: screen.visibleFrame.minX + 16, y: screen.visibleFrame.maxY - Self.panelSize.height - 12))
        }
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            panel.animator().alphaValue = 1
        }
        NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested, userInfo: [
            .announcement: pending.last?.title ?? String(localized: "连环提醒"),
            .priority: NSAccessibilityPriorityLevel.medium.rawValue
        ])
    }

    private func makePanel() -> ReminderChainFloatingPanel {
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
        panel.onEscape = { [weak self] in
            guard let self, let current = self.presentation.pending.last else { return }
            self.scheduler.acknowledge(id: current.id)
        }
        // NSPanel 初始化时已带有空白 NSView；清掉它，让首次显示也挂载真正的提醒内容。
        panel.contentView = nil
        return panel
    }
}

private final class ReminderChainFloatingPanel: NSPanel {
    var onEscape: (() -> Void)?

    override var canBecomeKey: Bool { true }

    override func sendEvent(_ event: NSEvent) {
        // 与休息面板一致：面板获焦后按 Esc 确认当前这条。
        if isKeyWindow, event.type == .keyDown, event.keyCode == 53 {
            onEscape?()
            return
        }
        super.sendEvent(event)
    }

    override func cancelOperation(_ sender: Any?) {
        onEscape?()
    }
}

/// 与休息提醒同一套外观：波点底、番茄仔、一句话和一个按钮。
/// 多组同时到期时先显示最新一条，确认后再显示下一条。
struct ReminderChainPanelView: View {
    @ObservedObject var presentation: ReminderChainPanelPresentation
    @Environment(\.locale) private var locale
    let acknowledge: (String) -> Void

    var body: some View {
        ZStack {
            PolkaDots()
            if let current = presentation.pending.last {
                content(current)
                    .padding(.top, 20)
                    .padding([.horizontal, .bottom], Theme.Spacing.panel)
            }
        }
        .foregroundStyle(Theme.ink)
        .frame(width: ReminderChainPanelController.panelSize.width, height: ReminderChainPanelController.panelSize.height)
        .background(Theme.cream)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous)
                .strokeBorder(Theme.creamDeep, lineWidth: 2)
        )
    }

    private func content(_ occurrence: ReminderChainOccurrence) -> some View {
        let missed = presentation.presentedAt.timeIntervalSince(occurrence.scheduledAt) >= 60
        let remaining = presentation.pending.count - 1
        return VStack(spacing: 0) {
            TomatoAvatar(size: 76)
                .overlay(alignment: .bottomTrailing) {
                    Image(systemName: "bell.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(Theme.tomatoFill))
                        .overlay(Circle().strokeBorder(Theme.cream, lineWidth: 2))
                        .offset(x: 2, y: 0)
                }
            Text(verbatim: occurrence.title)
                .font(Theme.font(19, .bold))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .padding(.top, 10)
            Text(verbatim: subtitle(occurrence, missed: missed))
                .font(Theme.font(13))
                .foregroundStyle(missed ? Theme.tomato : Theme.inkSoft)
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.top, 4)
            Spacer(minLength: 8)
            Button("知道了") { acknowledge(occurrence.id) }
                .buttonStyle(PillButtonStyle())
                .keyboardShortcut(.defaultAction)
                .accessibilityHint(Text(verbatim: occurrence.title))
        }
        .overlay(alignment: .topTrailing) {
            // 积压的其它提醒用角标表示，不占用正文高度。
            if remaining > 0 {
                Text("还有 \(remaining) 条")
                    .font(Theme.font(11, .semibold))
                    .foregroundStyle(Theme.tomato)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Theme.surface))
                    .offset(y: -8)
            }
        }
    }

    /// 「08:55 · 所属计划」；错过时写成「原定 08:55」。
    private func subtitle(_ occurrence: ReminderChainOccurrence, missed: Bool) -> String {
        let time = occurrence.scheduledAt.formatted(Date.FormatStyle(date: .omitted, time: .shortened).locale(locale))
        let when = missed ? String(localized: "原定 \(time)") : time
        return occurrence.title == occurrence.chainTitle ? when : "\(when) · \(occurrence.chainTitle)"
    }
}
