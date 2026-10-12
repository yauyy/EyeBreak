import AppKit
import Combine
import SwiftUI

/// 休息提醒的悬浮面板：专注结束后一直停留在屏幕右上角，直到用户开始休息或跳过；
/// 休息中显示倒计时，休息完成后撒花庆祝，然后自动收起。
@MainActor
final class BreakPanelController {
    final class State: ObservableObject {
        @Published var celebrating = false
    }

    static let panelSize = NSSize(width: 300, height: 264)
    private static let celebrationDuration: UInt64 = 2_800_000_000

    private let model: EyeBreakModel
    private let stats: TomatoStats
    private let state = State()
    private var panel: NSPanel?
    private var cancellables: Set<AnyCancellable> = []
    private var celebrationTask: Task<Void, Never>?

    init(model: EyeBreakModel, stats: TomatoStats) {
        self.model = model
        self.stats = stats
        model.$phase
            .removeDuplicates()
            .sink { [weak self] phase in
                MainActor.assumeIsolated { self?.phaseChanged(to: phase) }
            }
            .store(in: &cancellables)
        model.breakCompleted
            .sink { [weak self] in
                MainActor.assumeIsolated { self?.celebrate() }
            }
            .store(in: &cancellables)
    }

    private func phaseChanged(to phase: EyeBreakModel.Phase) {
        switch phase {
        case .awaitingBreak, .resting:
            cancelCelebration()
            show()
        case .idle, .working, .paused, .away, .offHours:
            // 休息自然结束时 breakCompleted 先于阶段切换发出，此时正在撒花，稍后再收起
            if !state.celebrating { hide() }
        }
    }

    private func celebrate() {
        state.celebrating = true
        show()
        celebrationTask?.cancel()
        celebrationTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.celebrationDuration)
            guard !Task.isCancelled, let self else { return }
            self.state.celebrating = false
            if !self.model.isOnBreak { self.hide() }
        }
    }

    private func cancelCelebration() {
        celebrationTask?.cancel()
        celebrationTask = nil
        state.celebrating = false
    }

    private func show() {
        let panel = self.panel ?? makePanel()
        self.panel = panel
        guard !panel.isVisible else { return }
        position(panel)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            panel.animator().alphaValue = 1
        }
    }

    private func hide() {
        guard let panel, panel.isVisible else { return }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.2
            panel.animator().alphaValue = 0
        }, completionHandler: {
            MainActor.assumeIsolated {
                // 动画期间可能又需要显示（例如刚跳过又重新计时到点），此时不要收起
                if panel.alphaValue == 0 { panel.orderOut(nil) }
            }
        })
    }

    /// 多显示器时出现在鼠标所在的屏幕上，也就是用户正在看的那块
    private func position(_ panel: NSPanel) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main ?? NSScreen.screens.first
        guard let screen else { return }
        let frame = screen.visibleFrame
        panel.setFrameOrigin(NSPoint(x: frame.maxX - Self.panelSize.width - 16, y: frame.maxY - Self.panelSize.height - 12))
    }

    private func makePanel() -> NSPanel {
        let panel = FloatingPanel(
            contentRect: NSRect(origin: .zero, size: Self.panelSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        // 所有桌面空间、全屏应用之上都能看到
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.contentView = NSHostingView(rootView: BreakPanelView(model: model, state: state, stats: stats))
        return panel
    }
}

/// 不抢焦点的面板，但仍允许点击其中的按钮
private final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

private struct BreakPanelView: View {
    @ObservedObject var model: EyeBreakModel
    @ObservedObject var state: BreakPanelController.State
    @ObservedObject var stats: TomatoStats
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            PolkaDots()

            Group {
                if state.celebrating {
                    CelebrationContent(todayCount: stats.today, unlocked: stats.justUnlocked)
                } else if model.phase == .resting {
                    resting
                } else {
                    awaiting
                }
            }
            .padding(.top, 22)
            .padding([.horizontal, .bottom], Theme.Spacing.panel)
            .transition(.opacity.combined(with: .scale(scale: 0.96)))

            if state.celebrating && !reduceMotion {
                ConfettiView()
                    .allowsHitTesting(false)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: state.celebrating)
        .animation(.easeInOut(duration: 0.25), value: model.phase)
        .frame(width: BreakPanelController.panelSize.width, height: BreakPanelController.panelSize.height)
        .background(Theme.cream)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous)
                .strokeBorder(Theme.creamDeep, lineWidth: 2)
        )
        .environment(\.colorScheme, .light)
    }

    private var awaiting: some View {
        VStack(spacing: 0) {
            BobbingTomato(size: 76)
            Text("休息一下眼睛吧")
                .font(Theme.font(19, .bold))
                .foregroundStyle(Theme.ink)
                .padding(.top, 10)
            Text("\(model.exercise.instruction)，放松 \(Int(model.restDuration)) 秒")
                .font(Theme.font(13))
                .foregroundStyle(Theme.inkSoft)
                .padding(.top, 4)
            Spacer(minLength: 12)
            BreakChoices(model: model)
        }
    }

    private var resting: some View {
        VStack(spacing: 0) {
            RingView(remaining: 1 - model.progress, color: Theme.leaf, lineWidth: 10) {
                TomatoCharacter(motion: model.exercise.motion, size: 82)
            }
            .frame(width: 124, height: 124)
            Text(model.exercise.title)
                .font(Theme.font(18, .bold))
                .foregroundStyle(Theme.ink)
                .padding(.top, 12)
            Text("还剩 \(model.remainingSeconds) 秒")
                .font(Theme.font(13, .medium))
                .monospacedDigit()
                .foregroundStyle(Theme.inkSoft)
                .padding(.top, 2)
            Spacer(minLength: 6)
            Button("提前结束", action: model.skipBreak)
                .buttonStyle(PillButtonStyle(kind: .plain))
        }
    }
}

/// 等待休息时的三个选择：底部一排两个胶囊按钮（与面板圆角同心），跳过作为次要的文字按钮放在上方
struct BreakChoices: View {
    @ObservedObject var model: EyeBreakModel

    var body: some View {
        VStack(spacing: 8) {
            Button("跳过这次", action: model.skipBreak)
                .buttonStyle(PillButtonStyle(kind: .plain))
            HStack(spacing: 10) {
                Button(action: model.snooze) { Text(verbatim: snoozeTitle) }
                    .buttonStyle(PillButtonStyle(kind: .secondary))
                Button("开始休息", action: model.startBreak)
                    .buttonStyle(PillButtonStyle())
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    private var snoozeTitle: String {
        let seconds = Int(min(EyeBreakConfig.snoozeInterval, model.workInterval))
        return seconds >= 60 ? String(localized: "\(seconds / 60) 分钟后") : String(localized: "\(seconds) 秒后")
    }
}

/// 轻轻上下浮动的番茄仔
private struct BobbingTomato: View {
    var size: CGFloat
    @State private var up = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TomatoAvatar(size: size)
            .offset(y: reduceMotion ? 0 : (up ? -4 : 3))
            .animation(reduceMotion ? nil : .easeInOut(duration: 1.1).repeatForever(autoreverses: true), value: up)
            .onAppear { up = true }
    }
}

/// 休息完成：番茄仔弹出来 + 一句话
private struct CelebrationContent: View {
    var todayCount: Int
    var unlocked: [Achievement]
    @State private var popped = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 10) {
            TomatoAvatar(size: 84)
                .scaleEffect(popped ? 1 : 0.3)
                .rotationEffect(.degrees(popped ? 0 : -25))
            Text("休息完成！")
                .font(Theme.font(22, .bold))
                .foregroundStyle(Theme.ink)
            Text("今天第 \(todayCount) 个番茄")
                .font(Theme.font(13, .medium))
                .foregroundStyle(Theme.tomato)
            if let achievement = unlocked.last {
                Text("解锁成就：\(achievement.title)")
                    .font(Theme.font(12, .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Theme.leaf))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            if reduceMotion {
                popped = true
            } else {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.5)) { popped = true }
            }
        }
    }
}

/// 与图标呼应的白色波点底纹
private struct PolkaDots: View {
    var body: some View {
        Canvas { context, size in
            let spacing: CGFloat = 26
            var row = 0
            var y: CGFloat = 12
            while y < size.height {
                var x: CGFloat = row.isMultiple(of: 2) ? 12 : 12 + spacing / 2
                while x < size.width {
                    context.fill(Path(ellipseIn: CGRect(x: x - 2.5, y: y - 2.5, width: 5, height: 5)), with: .color(.white.opacity(0.9)))
                    x += spacing
                }
                y += spacing
                row += 1
            }
        }
        .background(LinearGradient(colors: [Theme.cream, Theme.creamDeep], startPoint: .top, endPoint: .bottom))
    }
}
