import AppKit
import SwiftUI

/// 只检查 App 持久域，避免系统默认值、注册默认值和启动参数误判为历史使用记录。
enum OnboardingPolicy {
    static let seenKey = "hasSeenOnboarding"

    /// 包括已移除的界面偏好和 Sparkle 历史键，升级后的老用户不再自动看引导。
    static let legacyBusinessKeys: Set<String> = [
        "workMinutes", "restSeconds", "timerSnapshot", "exerciseIndex", "reminderSound",
        "workSchedule", "tomatoCounts", "tomatoTotal", "achievements",
        "showMenuBarTime", "showWeekStats", "showMoreSettings", "enabledExercises",
        "SUHasLaunchedBefore", "SUEnableAutomaticChecks", "SUAutomaticallyUpdate",
        "SULastCheckTime", "SUSkippedVersion"
    ]

    static func shouldPresent(persistentDomain: [String: Any]) -> Bool {
        guard persistentDomain[seenKey] as? Bool != true else { return false }
        return legacyBusinessKeys.isDisjoint(with: persistentDomain.keys)
    }
}

/// 首次引导和「重看引导」共用同一窗口；退出引导不会中断已有计时。
@MainActor
final class OnboardingWindowController: NSWindowController, NSWindowDelegate {
    private let model: EyeBreakModel
    private let defaults: UserDefaults
    private let onFinish: () -> Void
    private var finishedPresentation = false

    init(model: EyeBreakModel, defaults: UserDefaults = .standard, onFinish: @escaping () -> Void = {}) {
        self.model = model
        self.defaults = defaults
        self.onFinish = onFinish
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 400),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = String(localized: "EyeBreak 使用指南")
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        let content = NSHostingController(rootView: OnboardingView(
            model: model,
            begin: { [weak self] in self?.beginOrDismiss() },
            dismiss: { [weak self] in self?.close() }
        ))
        window.contentViewController = content
        // 固定宽度、按本地化文案的实际高度展示，按钮紧接内容且不截断英文。
        window.setContentSize(content.view.fittingSize)
    }

    required init?(coder: NSCoder) { nil }

    func present() {
        guard !EyeBreakConfig.isRunningTests, let window else { return }
        finishedPresentation = false
        window.center()
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        finishPresentation()
    }

    private func beginOrDismiss() {
        // 引导重看时，只负责关闭；暂停、休息等已有阶段也保持原状。
        if model.phase == .idle { model.start() }
        close()
    }

    private func finishPresentation() {
        guard !finishedPresentation else { return }
        finishedPresentation = true
        defaults.set(true, forKey: OnboardingPolicy.seenKey)
        onFinish()
    }
}

struct OnboardingView: View {
    @ObservedObject var model: EyeBreakModel
    var begin: () -> Void
    var dismiss: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            TomatoAvatar(size: 80)
            Text("欢迎来到 EyeBreak")
                .font(Theme.font(23, .bold))
                .foregroundStyle(Theme.ink)
            VStack(alignment: .leading, spacing: 14) {
                instruction("1", text: "我住在菜单栏，点番茄仔查看和调整")
                instruction("2", text: "到点后在屏幕右上角提醒你：开始休息、稍后提醒或跳过")
                instruction("3", text: "开会或全屏时会延后提醒；离开电脑会暂停，回来后重新计时")
            }
            HStack(spacing: 12) {
                Button("稍后", action: dismiss)
                    .buttonStyle(PillButtonStyle(kind: .secondary))
                Button(action: begin) {
                    Text(verbatim: model.phase == .idle ? String(localized: "开始专注") : String(localized: "知道了"))
                }
                .buttonStyle(PillButtonStyle())
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(28)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
        .background(Theme.cream)
    }

    private func instruction(_ number: String, text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(verbatim: number)
                .font(Theme.font(12, .bold))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(Circle().fill(Theme.tomatoFill))
                .accessibilityHidden(true)
            Text(text)
                .font(Theme.font(14))
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
