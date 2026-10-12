import AppKit
import Combine
import UserNotifications
import os

@MainActor
final class NotificationService: NSObject, ObservableObject {
    enum AuthState: Equatable {
        case unknown
        case notDetermined
        case authorized
        /// 已允许通知，但提醒样式被设为「无」，不会弹横幅
        case alertsOff
        case denied
    }

    @Published private(set) var authState: AuthState = .unknown
    @Published private(set) var lastDeliveryError: String?

    /// 用户点了通知本身或通知上的「开始休息」按钮
    var onStartBreak: (() -> Void)?

    private static let reminderID = "eyebreak.reminder"
    private static let categoryID = "EYEBREAK_REMINDER"
    private nonisolated static let startBreakActionID = "START_BREAK"

    private let center = UNUserNotificationCenter.current()
    private let logger = Logger(subsystem: "EyeBreak", category: "notification")
    private var sound: NSSound?

    override init() {
        super.init()
        center.delegate = self
        let startBreak = UNNotificationAction(identifier: Self.startBreakActionID, title: "开始休息", options: [])
        center.setNotificationCategories([
            UNNotificationCategory(identifier: Self.categoryID, actions: [startBreak], intentIdentifiers: [], options: []),
        ])
    }

    /// 首次启动：检查授权状态，尚未决定时请求授权。
    func prepare() async {
        await refreshStatus()
        if authState == .notDetermined {
            await requestAuthorization()
        }
    }

    func refreshStatus() async {
        let settings = await center.notificationSettings()
        let newState: AuthState
        switch settings.authorizationStatus {
        case .authorized, .provisional:
            newState = settings.alertStyle == .none ? .alertsOff : .authorized
        case .denied:
            newState = .denied
        case .notDetermined:
            newState = .notDetermined
        @unknown default:
            newState = .unknown
        }
        if newState != authState {
            logger.notice("Notification auth: \(String(describing: newState))")
            authState = newState
        }
    }

    func requestAuthorization() async {
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound])
            logger.notice("Authorization request finished, granted: \(granted)")
        } catch {
            logger.error("Authorization request failed: \(error.localizedDescription)")
        }
        await refreshStatus()
    }

    func openNotificationSettings() {
        let bundleID = Bundle.main.bundleIdentifier ?? ""
        let candidates = [
            "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=\(bundleID)",
            "x-apple.systempreferences:com.apple.preference.notifications",
        ]
        for string in candidates {
            if let url = URL(string: string), NSWorkspace.shared.open(url) { return }
        }
        // 都打不开时，界面上始终展示着手动路径
        logger.error("Unable to open System Settings")
    }

    // MARK: - 提醒

    /// 系统自带声音，无需额外音频文件；失败时退回系统提示音，不影响后续流程
    private func play(_ name: String) {
        sound?.stop()
        sound = NSSound(named: name)
        if sound?.play() != true {
            NSSound.beep()
        }
    }

    private func postNotification(restSeconds: Int) {
        Task {
            await refreshStatus()
            // 权限被关闭时不发送，也就不会误报"已展示"
            guard authState == .authorized || authState == .alertsOff else {
                logger.notice("Notification skipped: \(String(describing: self.authState))")
                return
            }

            let content = UNMutableNotificationContent()
            content.title = "休息一下眼睛吧"
            content.body = "看看 6 米外，放松 \(restSeconds) 秒"
            content.categoryIdentifier = Self.categoryID
            // 声音已由 NSSound 播放，这里不再重复
            content.sound = nil

            // 固定 identifier：新提醒会替换通知中心里的上一条，不会堆积
            let request = UNNotificationRequest(identifier: Self.reminderID, content: content, trigger: nil)
            do {
                try await center.add(request)
                logger.notice("Notification handed to Notification Center")
                lastDeliveryError = nil
            } catch {
                logger.error("Notification failed: \(error.localizedDescription)")
                lastDeliveryError = error.localizedDescription
                await refreshStatus()
            }
        }
    }
}

extension NotificationService: ReminderDelivering {
    func deliverReminder(restDuration: TimeInterval) {
        play("Glass")
        postNotification(restSeconds: Int(restDuration))
    }

    func cancelPendingReminders() {
        center.removePendingNotificationRequests(withIdentifiers: [Self.reminderID])
        center.removeDeliveredNotifications(withIdentifiers: [Self.reminderID])
    }

    func playBreakComplete() {
        play("Hero")
    }
}

extension NotificationService: UNUserNotificationCenterDelegate {
    /// 菜单面板打开时 App 处于前台，系统默认不弹横幅；这里要求照常展示。
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list]
    }

    /// 点通知本身或「开始休息」按钮，都开始休息
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let action = response.actionIdentifier
        guard action == Self.startBreakActionID || action == UNNotificationDefaultActionIdentifier else { return }
        await MainActor.run { self.onStartBreak?() }
    }
}
