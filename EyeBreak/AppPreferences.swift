import AppKit
import Combine
import CoreFoundation
import SwiftUI

enum AppearanceMode: String, CaseIterable, Identifiable, Sendable {
    case system
    case light
    case dark

    var id: Self { self }

    var title: String {
        switch self {
        case .system: return String(localized: "跟随系统")
        case .light: return String(localized: "浅色")
        case .dark: return String(localized: "深色")
        }
    }

    var appearanceName: NSAppearance.Name? {
        switch self {
        case .system: return nil
        case .light: return .aqua
        case .dark: return .darkAqua
        }
    }
}

/// 偏好读写与 AppKit 分离，测试使用独立的 UserDefaults 域。
enum AppearancePreference {
    static let key = "appearanceMode"

    static func read(from defaults: UserDefaults) -> AppearanceMode {
        defaults.string(forKey: key).flatMap(AppearanceMode.init(rawValue:)) ?? .system
    }

    static func write(_ mode: AppearanceMode, to defaults: UserDefaults) {
        defaults.set(mode.rawValue, forKey: key)
    }
}

@MainActor
final class AppearanceSettings: ObservableObject {
    @Published private var currentMode: AppearanceMode

    var mode: AppearanceMode {
        get { currentMode }
        set {
            guard newValue != currentMode else { return }
            currentMode = newValue
            AppearancePreference.write(newValue, to: defaults)
            if appliesToApplication { apply() }
        }
    }

    private let defaults: UserDefaults
    private let appliesToApplication: Bool
    private var preferenceChanges: AnyCancellable?

    init(
        defaults: UserDefaults = .standard,
        appliesToApplication: Bool = true,
        notificationCenter: NotificationCenter = .default
    ) {
        self.defaults = defaults
        self.appliesToApplication = appliesToApplication
        currentMode = AppearancePreference.read(from: defaults)
        // AppDelegate 创建其他状态对象、窗口和面板之前就确定外观。
        if appliesToApplication { apply() }
        preferenceChanges = notificationCenter.publisher(for: UserDefaults.didChangeNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    // 计时快照和统计也会写偏好，只比较外观这一项，未变化时不发布。
                    let saved = AppearancePreference.read(from: self.defaults)
                    if self.mode != saved { self.mode = saved }
                }
            }
    }

    private func apply() {
        let application = NSApplication.shared
        application.appearance = mode.appearanceName.flatMap(NSAppearance.init(named:))
        // 窗口继承 NSApplication 的有效外观；现有窗口也立刻重新绘制动态颜色和阴影。
        for window in application.windows {
            window.contentView?.needsDisplay = true
            window.invalidateShadow()
            window.displayIfNeeded()
        }
    }
}

enum LanguageChoice: String, CaseIterable, Identifiable, Sendable {
    case system
    case simplifiedChinese
    case english

    var id: Self { self }

    var title: String {
        switch self {
        case .system: return String(localized: "跟随系统")
        case .simplifiedChinese: return "简体中文"
        case .english: return "English"
        }
    }

    var languageCode: String? {
        switch self {
        case .system: return nil
        case .simplifiedChinese: return "zh-Hans"
        case .english: return "en"
        }
    }
}

enum LanguagePreference {
    static let key = "AppleLanguages"
    static let appDomain = Bundle.main.bundleIdentifier ?? "EyeBreak"

    /// 不能使用 stringArray(forKey:)：它还会查全局域、注册默认值和启动参数。
    static func read(from defaults: UserDefaults, domainName: String = appDomain) -> LanguageChoice {
        choice(for: storedLanguages(domainName: domainName))
    }

    /// CFPreferences 按域读取单键，既不合并全局/注册域，也不复制整份计时和统计偏好。
    static func storedLanguages(domainName: String) -> [String]? {
        let applicationID = domainName == UserDefaults.globalDomain
            ? kCFPreferencesAnyApplication : domainName as CFString
        guard let value = CFPreferencesCopyValue(
            key as CFString, applicationID,
            kCFPreferencesCurrentUser, kCFPreferencesAnyHost
        ) else { return nil }
        return value as? [String] ?? []
    }

    static func choice(for storedLanguages: [String]?) -> LanguageChoice {
        guard let languages = storedLanguages else { return .system }
        return effectiveLanguage(for: languages) == "en" ? .english : .simplifiedChinese
    }

    static func write(_ choice: LanguageChoice, to defaults: UserDefaults) {
        if let code = choice.languageCode {
            defaults.set([code], forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }

    /// 比较最终会显示的语言，而非选项本身；改回当前实际语言时不再提示重新打开。
    static func requiresRestart(_ choice: LanguageChoice, runningLanguage: String, systemLanguages: [String]) -> Bool {
        let desired = choice.languageCode ?? effectiveLanguage(for: systemLanguages)
        return desired != effectiveLanguage(for: [runningLanguage])
    }

    static func effectiveLanguage(for languages: [String]) -> String {
        Bundle.preferredLocalizations(from: ["zh-Hans", "en"], forPreferences: languages).first ?? "zh-Hans"
    }

    /// 独立读取全局语言顺序，避免 App 自己的 AppleLanguages 覆盖「跟随系统」的目标语言。
    static func systemLanguages(from defaults: UserDefaults = .standard) -> [String] {
        storedLanguages(domainName: UserDefaults.globalDomain) ?? ["zh-Hans"]
    }
}

@MainActor
final class LanguageSettings: ObservableObject {
    @Published private var currentChoice: LanguageChoice

    var choice: LanguageChoice {
        get { currentChoice }
        set {
            guard newValue != currentChoice else { return }
            currentChoice = newValue
            storedLanguages = newValue.languageCode.map { [$0] }
            LanguagePreference.write(newValue, to: defaults)
            if reopenError != nil { reopenError = nil }
            refreshSystemLanguage()
        }
    }
    @Published private(set) var isReopening = false
    @Published private(set) var reopenError: String?
    @Published private(set) var restartRequired: Bool
    /// AppDelegate 在打开新实例前保存计时快照；不提前 shutdown，打开失败后原进程继续工作。
    var beforeReopen: () -> Void = {}

    private let defaults: UserDefaults
    private let domainName: String
    private let runningLanguage: String
    private let systemLanguages: () -> [String]
    private var storedLanguages: [String]?
    private var preferenceChanges: AnyCancellable?

    init(
        defaults: UserDefaults = .standard,
        domainName: String = LanguagePreference.appDomain,
        runningLanguage: String = Bundle.main.preferredLocalizations.first ?? "zh-Hans",
        systemLanguages: @escaping () -> [String] = { LanguagePreference.systemLanguages() },
        notificationCenter: NotificationCenter = .default
    ) {
        self.defaults = defaults
        self.domainName = domainName
        self.runningLanguage = runningLanguage
        self.systemLanguages = systemLanguages
        let stored = LanguagePreference.storedLanguages(domainName: domainName)
        storedLanguages = stored
        let initialChoice = LanguagePreference.choice(for: stored)
        currentChoice = initialChoice
        restartRequired = LanguagePreference.requiresRestart(
            initialChoice, runningLanguage: runningLanguage, systemLanguages: systemLanguages()
        )
        preferenceChanges = notificationCenter.publisher(for: UserDefaults.didChangeNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    let stored = LanguagePreference.storedLanguages(domainName: self.domainName)
                    guard stored != self.storedLanguages else { return }
                    self.storedLanguages = stored
                    let saved = LanguagePreference.choice(for: stored)
                    if self.choice != saved { self.choice = saved }
                }
            }
    }

    /// 设置窗口显示时重算系统语言提示；普通偏好写入不读取全局语言，也不触发视图刷新。
    func refreshSystemLanguage() {
        let required = LanguagePreference.requiresRestart(
            choice, runningLanguage: runningLanguage, systemLanguages: systemLanguages()
        )
        if restartRequired != required { restartRequired = required }
    }

    func reopen() {
        // 测试宿主绝不能启动另一份 App 或退出测试；Sparkle 的重启也不走这个入口。
        guard !EyeBreakConfig.isRunningTests, restartRequired, !isReopening else { return }
        isReopening = true
        reopenError = nil
        beforeReopen()
        // 交接进程前建立持久化屏障，确保新进程启动时就能读到语言和计时快照。
        guard RelaunchHandoff.synchronizePreferences(domainName: domainName) else {
            isReopening = false
            reopenError = String(localized: "无法重新打开 EyeBreak，请稍后重试")
            return
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        configuration.arguments = RelaunchHandoff.arguments(previousProcessID: ProcessInfo.processInfo.processIdentifier)
        Task { @MainActor in
            do {
                _ = try await NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration)
                // 新进程已经完成启动但尚未创建菜单，正常退出再由其接管，避免长期双图标。
                NSApp.terminate(nil)
            } catch {
                isReopening = false
                reopenError = String(localized: "无法重新打开 EyeBreak，请稍后重试")
            }
        }
    }
}

/// 只处理语言切换传入的握手参数；普通启动、测试宿主和 Sparkle 重启保持原来的流程。
enum RelaunchHandoff {
    private static let argumentPrefix = "--eyebreak-wait-for-process="

    @discardableResult
    static func synchronizePreferences(domainName: String = LanguagePreference.appDomain) -> Bool {
        // CFPreferences 明确保证写出待保存值并重新读取外部修改；只在实例交接边界调用。
        CFPreferencesAppSynchronize(domainName as CFString)
    }

    static func arguments(previousProcessID: Int32) -> [String] {
        ["\(argumentPrefix)\(previousProcessID)"]
    }

    static func previousProcessID(in arguments: [String], currentProcessID: Int32) -> Int32? {
        guard let argument = arguments.first(where: { $0.hasPrefix(argumentPrefix) }),
              let pid = Int32(argument.dropFirst(argumentPrefix.count)), pid > 0, pid != currentProcessID else { return nil }
        return pid
    }

    /// 异步等待让 didFinishLaunching 正常返回；旧进程的 openApplication 完成回调因此不会死锁。
    @MainActor
    static func waitForExit(
        processID: Int32,
        attempts: Int = 150,
        isRunning: (Int32) -> Bool,
        pause: () async -> Void = { try? await Task.sleep(for: .milliseconds(100)) }
    ) async -> Bool {
        for _ in 0..<attempts {
            if !isRunning(processID) { return true }
            await pause()
            if Task.isCancelled { return false }
        }
        return !isRunning(processID)
    }
}
