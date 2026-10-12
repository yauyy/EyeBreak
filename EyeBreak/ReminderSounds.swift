import AppKit
import Combine

/// 提醒音的可选项，都是系统自带声音，无需额外音频文件
enum ReminderSound: String, CaseIterable, Identifiable {
    case off
    case glass
    case purr
    case pop
    case tink

    var id: String { rawValue }

    var title: String {
        switch self {
        case .off: return String(localized: "关闭")
        case .glass: return String(localized: "清脆")
        case .purr: return String(localized: "轻柔")
        case .pop: return String(localized: "啵")
        case .tink: return String(localized: "叮")
        }
    }

    /// 系统声音名；关闭时为 nil
    var systemName: String? {
        switch self {
        case .off: return nil
        case .glass: return "Glass"
        case .purr: return "Purr"
        case .pop: return "Pop"
        case .tink: return "Tink"
        }
    }
}

/// 提醒与休息完成的提示音。提醒本身由常驻悬浮面板承担，不发送系统通知，
/// 因此 App 不需要申请通知权限。
@MainActor
final class ReminderSounds: ObservableObject, ReminderDelivering {
    /// 提醒音；选择「关闭」时，提醒和休息完成都不出声
    @Published var choice: ReminderSound {
        didSet { onChoiceChanged?(choice) }
    }
    var onChoiceChanged: ((ReminderSound) -> Void)?

    private var sound: NSSound?

    init(choice: ReminderSound = .glass) {
        self.choice = choice
    }

    func deliverReminder(restDuration: TimeInterval) {
        guard let name = choice.systemName else { return }
        play(name)
    }

    func cancelPendingReminders() {
        sound?.stop()
    }

    func playBreakComplete() {
        guard choice != .off else { return }
        play("Hero")
    }

    /// 在设置里切换时试听
    func preview(_ option: ReminderSound) {
        guard let name = option.systemName else {
            sound?.stop()
            return
        }
        play(name)
    }

    /// 失败时退回系统提示音，不影响后续流程
    private func play(_ name: String) {
        sound?.stop()
        sound = NSSound(named: name)
        if sound?.play() != true {
            NSSound.beep()
        }
    }
}
