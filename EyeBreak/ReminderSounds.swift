import AppKit

/// 提醒与完成的提示音。提醒本身由常驻悬浮面板承担，不再发送系统通知，
/// 因此 App 不需要申请通知权限。
@MainActor
final class ReminderSounds: ReminderDelivering {
    private var sound: NSSound?

    func deliverReminder(restDuration: TimeInterval) {
        play("Glass")
    }

    func cancelPendingReminders() {
        sound?.stop()
    }

    func playBreakComplete() {
        play("Hero")
    }

    /// 系统自带声音，无需额外音频文件；失败时退回系统提示音，不影响后续流程
    private func play(_ name: String) {
        sound?.stop()
        sound = NSSound(named: name)
        if sound?.play() != true {
            NSSound.beep()
        }
    }
}
