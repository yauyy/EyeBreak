import AppKit
import Combine
import SwiftUI

/// 设置分区由窗口和菜单入口共同选择，始终使用同一组运行对象。
enum SettingsSection: CaseIterable, Hashable {
    case general
    case rest
    case schedule
    case achievements
    case about

    var title: String {
        switch self {
        case .general: return String(localized: "通用")
        case .rest: return String(localized: "休息")
        case .schedule: return String(localized: "工作时段")
        case .achievements: return String(localized: "成就")
        case .about: return String(localized: "关于")
        }
    }
}

@MainActor
final class SettingsPresentation: ObservableObject {
    @Published var section: SettingsSection = .general
    @Published var diagnosticText: String?
}

/// 在窗口层处理关闭快捷键，不依赖 LSUIElement 应用不可见的主菜单。
@MainActor
private final class SettingsWindow: NSWindow {
    var onEscape: (() -> Void)?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection([.command, .shift, .option, .control])
        if modifiers == .command, event.charactersIgnoringModifiers?.lowercased() == "w" {
            performClose(nil)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, event.keyCode == 53 {
            onEscape?()
            return
        }
        super.sendEvent(event)
    }

    override func cancelOperation(_ sender: Any?) {
        onEscape?()
    }
}

/// AppDelegate 持有唯一实例；关闭时只保留窗口位置和分区，卸载整个 SwiftUI 内容。
@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private let presentation: SettingsPresentation
    private let launchAtLogin: LaunchAtLogin
    private let stats: TomatoStats
    private let language: LanguageSettings
    private let makeContent: () -> NSViewController
    private var hasShown = false
    private var closedFrame: NSRect?

    init(
        model: EyeBreakModel,
        launchAtLogin: LaunchAtLogin,
        stats: TomatoStats,
        sounds: ReminderSounds,
        updates: AppUpdater,
        schedule: WorkScheduleSettings,
        appearance: AppearanceSettings,
        language: LanguageSettings,
        onReplayOnboarding: @escaping () -> Void
    ) {
        self.launchAtLogin = launchAtLogin
        self.stats = stats
        self.language = language
        let presentation = SettingsPresentation()
        self.presentation = presentation
        // 工厂只保留操作入口和设置数据，不提前创建或缓存视图树。
        makeContent = {
            NSHostingController(rootView: SettingsContentView(
                model: model, launchAtLogin: launchAtLogin, stats: stats,
                sounds: sounds, updates: updates, schedule: schedule,
                appearance: appearance, language: language, presentation: presentation,
                onReplayOnboarding: onReplayOnboarding
            ))
        }
        let window = SettingsWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 480),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        super.init(window: window)
        window.title = String(localized: "EyeBreak 设置")
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.setContentSize(NSSize(width: 560, height: 480))
        window.onEscape = { [weak self] in
            guard let self else { return }
            if self.presentation.diagnosticText != nil {
                self.presentation.diagnosticText = nil
            } else {
                self.close()
            }
        }
    }

    required init?(coder: NSCoder) { nil }

    func show(section: SettingsSection? = nil) {
        guard let window else { return }
        presentation.diagnosticText = nil
        if let section { presentation.section = section }
        launchAtLogin.refresh()
        stats.refresh()
        language.refreshSystemLanguage()
        if window.contentViewController == nil {
            // 重建内容可能改变约束，保留关闭前的完整窗口矩形，重开不重新居中。
            let frame = closedFrame ?? window.frame
            window.contentViewController = makeContent()
            window.setFrame(frame, display: false)
        }
        NSApp.activate(ignoringOtherApps: true)
        if !hasShown {
            window.center()
            hasShown = true
        }
        showWindow(nil)
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        // ⌘W、Esc、关闭按钮以及控制器 close() 都经过同一个释放入口。
        closedFrame = window?.frame
        window?.contentViewController = nil
        window?.contentView = nil
        presentation.diagnosticText = nil
    }
}

struct SettingsContentView: View {
    // 仅在点击诊断按钮时读取快照，计时变化不应使整个设置页失效。
    let model: EyeBreakModel
    @ObservedObject var launchAtLogin: LaunchAtLogin
    @ObservedObject var stats: TomatoStats
    @ObservedObject var sounds: ReminderSounds
    @ObservedObject var updates: AppUpdater
    @ObservedObject var schedule: WorkScheduleSettings
    @ObservedObject var appearance: AppearanceSettings
    @ObservedObject var language: LanguageSettings
    @ObservedObject var presentation: SettingsPresentation
    let onReplayOnboarding: () -> Void

    @AppStorage(EyeBreakConfig.showMenuBarTimeKey) private var showMenuBarTime = false
    private let topAnchor = "settingsTop"

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                sectionTabs
                    .padding(.horizontal, 18)
                    .padding(.top, 18)
                    .padding(.bottom, 14)
                GeometryReader { viewport in
                    ScrollViewReader { proxy in
                        ScrollView {
                            // 传统滚动条会占用裁剪区宽度，网格必须按实际可见宽度排两列。
                            sectionContent
                                .id(topAnchor)
                                .frame(width: max(0, viewport.size.width - reservedScrollerWidth - 44), alignment: .leading)
                                .padding(.horizontal, 22)
                                .padding(.bottom, 22)
                        }
                        .onChange(of: presentation.section) { _ in
                            proxy.scrollTo(topAnchor, anchor: .top)
                        }
                    }
                }
            }
            .disabled(presentation.diagnosticText != nil)
            .accessibilityHidden(presentation.diagnosticText != nil)
            if let text = presentation.diagnosticText {
                diagnosticPreview(text)
            }
        }
        .frame(width: 560, height: 480)
        .background(Theme.cream)
    }

    private var reservedScrollerWidth: CGFloat {
        guard NSScroller.preferredScrollerStyle == .legacy else { return 0 }
        return NSScroller.scrollerWidth(for: .regular, scrollerStyle: .legacy)
    }

    private var sectionTabs: some View {
        HStack(spacing: Theme.Spacing.segmented) {
            ForEach(SettingsSection.allCases, id: \.self) { section in
                let selected = section == presentation.section
                Button {
                    presentation.section = section
                } label: {
                    Text(verbatim: section.title)
                        .font(Theme.font(13, .semibold))
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        .padding(.horizontal, 8)
                        .foregroundStyle(selected ? .white : Theme.ink)
                        .frame(maxWidth: .infinity)
                        .frame(height: Theme.controlHeight)
                        .background(
                            RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous)
                                .fill(selected ? Theme.tomatoFill : .clear)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(verbatim: section.title))
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(Theme.Spacing.segmented)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.segmented, style: .continuous).fill(Theme.creamDeep))
    }

    @ViewBuilder
    private var sectionContent: some View {
        switch presentation.section {
        case .general: generalSettings
        case .rest: RestExerciseSettings(model: model).settingsCard()
        case .schedule: scheduleSettings
        case .achievements: AchievementsView(stats: stats)
        case .about: aboutSettings
        }
    }

    private var generalSettings: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                settingTitle("外观")
                TomatoSegmentedPicker(
                    options: AppearanceMode.allCases, selection: appearance.mode,
                    title: { $0.title }, onSelect: { appearance.mode = $0 }
                )
                .accessibilityLabel("外观")
            }
            VStack(alignment: .leading, spacing: 8) {
                settingTitle("语言")
                TomatoSegmentedPicker(
                    options: LanguageChoice.allCases, selection: language.choice,
                    title: { $0.title }, onSelect: { language.choice = $0 }
                )
                .accessibilityLabel("语言")
                .disabled(language.isReopening)
                if language.restartRequired {
                    HStack(spacing: 12) {
                        Text("重新打开 EyeBreak 后生效")
                            .font(Theme.font(12))
                            .foregroundStyle(Theme.inkSoft)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                        Button("立即重新打开", action: language.reopen)
                            .buttonStyle(PillButtonStyle(kind: .plain))
                            .disabled(language.isReopening)
                    }
                }
                if let error = language.reopenError {
                    Text(verbatim: error)
                        .font(Theme.font(12))
                        .foregroundStyle(Theme.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                settingTitle("提示音")
                SoundPicker(selection: sounds.choice) { sound in
                    sounds.choice = sound
                    sounds.preview(sound)
                }
            }
            Toggle(isOn: $showMenuBarTime) { settingTitle("菜单栏显示倒计时") }
                .toggleStyle(CuteToggleStyle())
            Toggle(isOn: Binding(get: { launchAtLogin.isEnabled }, set: { launchAtLogin.setEnabled($0) })) {
                settingTitle("开机自启")
            }
            .toggleStyle(CuteToggleStyle())
            if launchAtLogin.needsApproval || launchAtLogin.failed {
                HStack(alignment: .top) {
                    (launchAtLogin.failed ? Text("设置失败，可在系统设置里手动添加") : Text("需要在系统设置里允许"))
                        .font(Theme.font(12))
                        .foregroundStyle(Theme.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Button("去设置", action: launchAtLogin.openLoginItemsSettings)
                        .buttonStyle(PillButtonStyle(kind: .plain))
                }
            }
            if updates.isConfigured {
                Toggle(isOn: $updates.automaticChecks) { settingTitle("自动检查更新") }
                    .toggleStyle(CuteToggleStyle())
            }
        }
        .settingsCard()
    }

    private var scheduleSettings: some View {
        VStack(alignment: .leading, spacing: 18) {
            Toggle(isOn: $schedule.schedule.isEnabled) { settingTitle("只在工作时段提醒") }
                .toggleStyle(CuteToggleStyle())
            if schedule.schedule.isEnabled {
                CuteStepper(title: "开始", unit: String(localized: "点"), value: $schedule.schedule.startHour, range: WorkSchedule.hourRange, step: 1)
                CuteStepper(title: "结束", unit: String(localized: "点"), value: $schedule.schedule.endHour, range: WorkSchedule.hourRange, step: 1)
                Toggle(isOn: $schedule.schedule.weekdaysOnly) { settingTitle("仅工作日") }
                    .toggleStyle(CuteToggleStyle())
            }
        }
        .settingsCard()
    }

    private var aboutSettings: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                TomatoAvatar(size: 44)
                VStack(alignment: .leading, spacing: 3) {
                    Text("EyeBreak")
                        .font(Theme.font(19, .bold))
                        .foregroundStyle(Theme.ink)
                    Text("版本 \(updates.currentVersion)")
                        .font(Theme.font(12))
                        .foregroundStyle(Theme.inkSoft)
                }
            }
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                Button("反馈") { NSWorkspace.shared.open(AppLinks.newIssue()) }
                    .help("在 GitHub 上反馈问题")
                Button("许可") {
                    if let notices = AppLinks.thirdPartyNotices { NSWorkspace.shared.open(notices) }
                }
                .disabled(AppLinks.thirdPartyNotices == nil)
                .help("查看开源许可")
                Button("重看引导", action: onReplayOnboarding)
                Button("复制诊断信息") {
                    let snapshot = DiagnosticSnapshot.capture(
                        model: model, sounds: sounds, launchAtLogin: launchAtLogin,
                        updates: updates, schedule: schedule
                    )
                    presentation.diagnosticText = DiagnosticReport.text(from: snapshot)
                }
            }
            .buttonStyle(PillButtonStyle(kind: .secondary))
        }
    }

    private func diagnosticPreview(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("诊断信息预览")
                .font(Theme.font(18, .bold))
                .foregroundStyle(Theme.ink)
            Text("确认后将以下信息复制到剪贴板。")
                .font(Theme.font(12))
                .foregroundStyle(Theme.inkSoft)
            ScrollView {
                Text(verbatim: text)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Theme.ink)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
            .background(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).fill(Theme.surface))
            HStack(spacing: 12) {
                Button("取消") { presentation.diagnosticText = nil }
                    .buttonStyle(PillButtonStyle(kind: .secondary))
                Button("确认复制") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                    presentation.diagnosticText = nil
                }
                .buttonStyle(PillButtonStyle())
            }
        }
        .padding(22)
        .background(Theme.cream)
    }

    private func settingTitle(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(Theme.font(14, .medium))
            .foregroundStyle(Theme.ink)
    }
}

/// 只发布动作集合；即使设置页可见，也不订阅每秒变化的计时状态。
@MainActor
final class SettingsExerciseSelection: ObservableObject {
    @Published private(set) var enabledExercises: Set<RestExercise>
    private let model: EyeBreakModel
    private var subscription: AnyCancellable?

    init(model: EyeBreakModel) {
        self.model = model
        enabledExercises = model.enabledExercises
        subscription = model.$enabledExercises.removeDuplicates().sink { [weak self] enabled in
            MainActor.assumeIsolated {
                guard let self, self.enabledExercises != enabled else { return }
                self.enabledExercises = enabled
            }
        }
    }

    func setExercise(_ exercise: RestExercise, enabled: Bool) {
        model.setExercise(exercise, enabled: enabled)
    }
}

private struct RestExerciseSettings: View {
    @StateObject private var selection: SettingsExerciseSelection

    init(model: EyeBreakModel) {
        _selection = StateObject(wrappedValue: SettingsExerciseSelection(model: model))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("启用的动作")
                .font(Theme.font(14, .medium))
                .foregroundStyle(Theme.ink)
            ForEach(RestExercise.allCases, id: \.self) { exercise in
                let enabled = selection.enabledExercises.contains(exercise)
                Toggle(isOn: Binding(
                    get: { selection.enabledExercises.contains(exercise) },
                    set: { selection.setExercise(exercise, enabled: $0) }
                )) {
                    Text(verbatim: exercise.title)
                        .font(Theme.font(14, .medium))
                        .foregroundStyle(Theme.ink)
                }
                .toggleStyle(CuteToggleStyle())
                .disabled(enabled && selection.enabledExercises.count == 1)
            }
            if selection.enabledExercises.count == 1 {
                Text("至少保留一个动作")
                    .font(Theme.font(12))
                    .foregroundStyle(Theme.inkSoft)
            }
        }
    }
}

private extension View {
    func settingsCard() -> some View {
        padding(Theme.Spacing.card)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).fill(Theme.creamDeep.opacity(0.6)))
    }
}
