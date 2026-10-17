import AppKit
import Combine
import SwiftUI

/// 设置分区由窗口和菜单入口共同选择，始终使用同一组运行对象。
enum SettingsSection: CaseIterable, Hashable {
    case general
    case rest
    case schedule
    case about

    var title: String {
        switch self {
        case .general: return String(localized: "通用")
        case .rest: return String(localized: "休息")
        case .schedule: return String(localized: "工作时段")
        case .about: return String(localized: "关于")
        }
    }
}

@MainActor
final class SettingsPresentation: ObservableObject {
    @Published var section: SettingsSection = .general
    @Published var diagnosticText: String?
    @Published var achievementRequest = 0
    var focusAchievements = false
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

/// AppDelegate 持有唯一实例；关闭时保留窗口和当前位置。
@MainActor
final class SettingsWindowController: NSWindowController {
    private let presentation = SettingsPresentation()
    private let launchAtLogin: LaunchAtLogin
    private let stats: TomatoStats
    private var hasShown = false

    init(
        model: EyeBreakModel,
        launchAtLogin: LaunchAtLogin,
        stats: TomatoStats,
        sounds: ReminderSounds,
        updates: AppUpdater,
        schedule: WorkScheduleSettings,
        onReplayOnboarding: @escaping () -> Void
    ) {
        self.launchAtLogin = launchAtLogin
        self.stats = stats
        let window = SettingsWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 480),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        super.init(window: window)
        window.title = String(localized: "EyeBreak 设置")
        window.isReleasedWhenClosed = false
        window.contentViewController = NSHostingController(rootView: SettingsContentView(
            model: model,
            launchAtLogin: launchAtLogin,
            stats: stats,
            sounds: sounds,
            updates: updates,
            schedule: schedule,
            presentation: presentation,
            onReplayOnboarding: onReplayOnboarding
        ))
        window.setContentSize(NSSize(width: 520, height: 480))
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

    func show(section: SettingsSection? = nil, focusAchievements: Bool = false) {
        guard let window else { return }
        presentation.diagnosticText = nil
        presentation.focusAchievements = focusAchievements
        if let section { presentation.section = section }
        if focusAchievements { presentation.achievementRequest += 1 }
        launchAtLogin.refresh()
        stats.refresh()
        NSApp.activate(ignoringOtherApps: true)
        if !hasShown {
            window.center()
            hasShown = true
        }
        showWindow(nil)
        window.makeKeyAndOrderFront(nil)
    }
}

struct SettingsContentView: View {
    @ObservedObject var model: EyeBreakModel
    @ObservedObject var launchAtLogin: LaunchAtLogin
    @ObservedObject var stats: TomatoStats
    @ObservedObject var sounds: ReminderSounds
    @ObservedObject var updates: AppUpdater
    @ObservedObject var schedule: WorkScheduleSettings
    @ObservedObject var presentation: SettingsPresentation
    let onReplayOnboarding: () -> Void

    @AppStorage(EyeBreakConfig.showMenuBarTimeKey) private var showMenuBarTime = false
    private let topAnchor = "settingsTop"
    private let achievementAnchor = "achievements"

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                sectionTabs
                    .padding(.horizontal, 18)
                    .padding(.top, 18)
                    .padding(.bottom, 14)
                ScrollViewReader { proxy in
                    ScrollView {
                        // 直接以分区内容作为顶部锚点，避免零高度视图仍产生额外间距。
                        sectionContent
                            .id(topAnchor)
                            .padding(.horizontal, 22)
                            .padding(.bottom, 22)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .onChange(of: presentation.section) { _ in
                        proxy.scrollTo(topAnchor, anchor: .top)
                    }
                    .task(id: presentation.achievementRequest) {
                        guard presentation.focusAchievements, presentation.section == .about else { return }
                        // 等待关于分区插入并注册锚点；重复打开成就入口也会发出新请求。
                        await Task.yield()
                        guard !Task.isCancelled else { return }
                        proxy.scrollTo(achievementAnchor, anchor: .top)
                    }
                }
            }
            .disabled(presentation.diagnosticText != nil)
            .accessibilityHidden(presentation.diagnosticText != nil)
            if let text = presentation.diagnosticText {
                diagnosticPreview(text)
            }
        }
        .frame(width: 520, height: 480)
        .background(Theme.cream)
    }

    private var sectionTabs: some View {
        HStack(spacing: Theme.Spacing.segmented) {
            ForEach(SettingsSection.allCases, id: \.self) { section in
                let selected = section == presentation.section
                Button {
                    presentation.focusAchievements = false
                    presentation.section = section
                } label: {
                    Text(verbatim: section.title)
                        .font(Theme.font(13, .semibold))
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
        case .rest: restSettings
        case .schedule: scheduleSettings
        case .about: aboutSettings
        }
    }

    private var generalSettings: some View {
        VStack(alignment: .leading, spacing: 18) {
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

    private var restSettings: some View {
        VStack(alignment: .leading, spacing: 18) {
            settingTitle("启用的动作")
            ForEach(RestExercise.allCases, id: \.self) { exercise in
                let enabled = model.enabledExercises.contains(exercise)
                Toggle(isOn: Binding(
                    get: { model.enabledExercises.contains(exercise) },
                    set: { model.setExercise(exercise, enabled: $0) }
                )) {
                    Text(verbatim: exercise.title)
                        .font(Theme.font(14, .medium))
                        .foregroundStyle(Theme.ink)
                }
                .toggleStyle(CuteToggleStyle())
                .disabled(enabled && model.enabledExercises.count == 1)
            }
            if model.enabledExercises.count == 1 {
                Text("至少保留一个动作")
                    .font(Theme.font(12))
                    .foregroundStyle(Theme.inkSoft)
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
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    settingTitle("成就墙")
                    Spacer()
                    Text(verbatim: "\(stats.unlocked.count)/\(Achievement.allCases.count)")
                        .font(Theme.font(12, .semibold))
                        .foregroundStyle(Theme.inkSoft)
                }
                FlowLayout(spacing: 8) {
                    ForEach(Achievement.allCases) { achievement in
                        let earned = stats.unlocked.contains(achievement)
                        Text(verbatim: achievement.title)
                            .font(Theme.font(12, .semibold))
                            .foregroundStyle(earned ? .white : Theme.inkSoft)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(earned ? Theme.tomatoFill : Theme.ink.opacity(0.07)))
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(earned ? Text("已解锁：\(achievement.title)") : Text("未解锁：\(achievement.title)"))
                    }
                }
            }
            .settingsCard()
            .id(achievementAnchor)
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

private extension View {
    func settingsCard() -> some View {
        padding(Theme.Spacing.card)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).fill(Theme.creamDeep.opacity(0.6)))
    }
}
