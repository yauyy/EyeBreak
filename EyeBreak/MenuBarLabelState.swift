import Combine
import Foundation

/// 菜单栏只观察自己的显示状态，关闭倒计时时连剩余秒数的订阅也取消。
@MainActor
final class MenuBarLabelState: ObservableObject {
    struct Presentation: Equatable {
        let assetName: String
        let text: String?
        let accessibility: String

        init(phase: EyeBreakModel.Phase, remainingSeconds: Int, showsTime: Bool) {
            let state: String
            switch phase {
            case .working:
                assetName = "MenuBarWorking"
                state = String(localized: "专注中")
            case .awaitingBreak:
                assetName = "MenuBarAwaiting"
                state = String(localized: "等待休息")
            case .resting:
                assetName = "MenuBarResting"
                state = String(localized: "休息中")
            case .away:
                assetName = "MenuBarIdle"
                state = String(localized: "离开中")
            case .offHours:
                assetName = "MenuBarIdle"
                state = String(localized: "工作时段外")
            case .idle, .paused:
                assetName = "MenuBarIdle"
                state = String(localized: "未在计时")
            }
            if showsTime {
                switch phase {
                case .working, .paused, .resting:
                    text = String(format: "%d:%02d", remainingSeconds / 60, remainingSeconds % 60)
                case .awaitingBreak:
                    text = String(localized: "休息")
                case .idle, .away, .offHours:
                    text = nil
                }
            } else {
                text = nil
            }
            // 关闭倒计时后只播报阶段，避免不可见的秒数引起无障碍标签每秒失效。
            if let text, phase != .awaitingBreak {
                accessibility = String(localized: "EyeBreak \(state)，剩余 \(text)")
            } else {
                accessibility = "EyeBreak " + state
            }
        }
    }

    @Published private(set) var presentation: Presentation
    private let model: EyeBreakModel
    private var phase: EyeBreakModel.Phase
    private var showsTime: Bool
    private var phaseSubscription: AnyCancellable?
    private var secondsSubscription: AnyCancellable?

    init(model: EyeBreakModel, showsTime: Bool) {
        self.model = model
        phase = model.phase
        self.showsTime = showsTime
        presentation = Presentation(phase: model.phase, remainingSeconds: model.remainingSeconds, showsTime: showsTime)
        phaseSubscription = model.$phase
            .removeDuplicates()
            .sink { [weak self] phase in
                MainActor.assumeIsolated {
                    // @Published 在 willSet 发出新值，不能在此重新读取 model.phase。
                    self?.phase = phase
                    self?.refresh()
                }
            }
        if showsTime { observeSeconds() }
    }

    func setShowsTime(_ showsTime: Bool) {
        guard self.showsTime != showsTime else { return }
        self.showsTime = showsTime
        if showsTime {
            observeSeconds()
        } else {
            secondsSubscription = nil
            refresh()
        }
    }

    private func observeSeconds() {
        secondsSubscription = model.$remainingSeconds
            .removeDuplicates()
            .sink { [weak self] seconds in
                MainActor.assumeIsolated { self?.refresh(remainingSeconds: seconds) }
            }
    }

    private func refresh(remainingSeconds: Int? = nil) {
        let next = Presentation(
            phase: phase, remainingSeconds: remainingSeconds ?? model.remainingSeconds, showsTime: showsTime
        )
        guard next != presentation else { return }
        presentation = next
    }
}
