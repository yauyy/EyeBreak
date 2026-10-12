import AppKit
import Combine
import os

/// 检查更新：读取 GitHub 上最新 Release 的版本号，比当前版本新就提示下载。
/// 只发送一次公开接口的 GET 请求，不上传任何数据；关闭「自动检查更新」后不会主动联网。
@MainActor
final class UpdateChecker: ObservableObject {
    struct Release: Equatable {
        /// 去掉前缀 v 的版本号，如 "1.2"
        var version: String
        /// Release 页面地址
        var url: URL
    }

    enum Status: Equatable {
        case idle
        case checking
        case upToDate
        case failed
    }

    /// 检测到的新版本；没有新版本时为 nil
    @Published private(set) var available: Release?
    @Published private(set) var status: Status = .idle
    @Published var automaticChecks: Bool {
        didSet {
            defaults.set(automaticChecks, forKey: Self.automaticKey)
            if automaticChecks { checkIfDue() }
        }
    }

    let currentVersion: String

    static let releasesPage = URL(string: "https://github.com/yauyy/EyeBreak/releases/latest")!
    private static let latestAPI = URL(string: "https://api.github.com/repos/yauyy/EyeBreak/releases/latest")!
    private static let automaticKey = "automaticUpdateChecks"
    private static let lastCheckKey = "lastUpdateCheck"
    private static let checkInterval: TimeInterval = 24 * 3600

    private let defaults: UserDefaults
    private let now: () -> Date
    private let fetchLatest: () async throws -> Release
    private let logger = Logger(subsystem: "EyeBreak", category: "update")
    private var timer: Timer?

    init(
        currentVersion: String = UpdateChecker.bundleVersion,
        defaults: UserDefaults = .standard,
        now: @escaping () -> Date = Date.init,
        fetchLatest: (() async throws -> Release)? = nil
    ) {
        self.currentVersion = currentVersion
        self.defaults = defaults
        self.now = now
        self.fetchLatest = fetchLatest ?? { try await UpdateChecker.fetchFromGitHub(currentVersion: currentVersion) }
        automaticChecks = defaults.object(forKey: Self.automaticKey) as? Bool ?? true
    }

    nonisolated static var bundleVersion: String {
        #if DEBUG
        // 仅 Debug：-EyeBreakTestCurrentVersion 0.9 假装是旧版本，用来测试新版本提示
        if let fake = UserDefaults.standard.string(forKey: "EyeBreakTestCurrentVersion") { return fake }
        #endif
        return Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    /// 启动后开始自动检查：距离上次检查超过一天才会真正联网，之后每小时看一次是否到期
    func startAutomaticChecks() {
        checkIfDue()
        let timer = Timer(timeInterval: 3600, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkIfDue() }
        }
        timer.tolerance = 300
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func checkIfDue() {
        guard automaticChecks else { return }
        let last = defaults.object(forKey: Self.lastCheckKey) as? Date ?? .distantPast
        guard now().timeIntervalSince(last) >= Self.checkInterval else { return }
        Task { await check() }
    }

    /// 立即检查（菜单里的「检查更新」）
    func check() async {
        guard status != .checking else { return }
        status = .checking
        defaults.set(now(), forKey: Self.lastCheckKey)
        do {
            let latest = try await fetchLatest()
            if Self.isVersion(latest.version, newerThan: currentVersion) {
                logger.notice("Update available: \(latest.version, privacy: .public)")
                available = latest
            } else {
                available = nil
            }
            status = .upToDate
        } catch {
            logger.error("Update check failed: \(error.localizedDescription, privacy: .public)")
            status = .failed
        }
    }

    func openDownloadPage() {
        NSWorkspace.shared.open(available?.url ?? Self.releasesPage)
    }

    // MARK: - 版本比较与解析

    /// 按数字逐段比较：1.10 比 1.9 新，1.1 与 1.1.0 相同
    static func isVersion(_ candidate: String, newerThan current: String) -> Bool {
        let a = numbers(candidate), b = numbers(current)
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0
            let y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    private static func numbers(_ version: String) -> [Int] {
        version
            .trimmingCharacters(in: CharacterSet(charactersIn: "vV "))
            .split(separator: ".")
            .map { Int($0.prefix { $0.isNumber }) ?? 0 }
    }

    /// 解析 GitHub「最新 Release」接口的返回
    static func parseRelease(_ data: Data) throws -> Release {
        struct Payload: Decodable {
            let tag_name: String
            let html_url: URL
            let draft: Bool?
            let prerelease: Bool?
        }
        let payload = try JSONDecoder().decode(Payload.self, from: data)
        let version = payload.tag_name.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
        return Release(version: version, url: payload.html_url)
    }

    private static func fetchFromGitHub(currentVersion: String) async throws -> Release {
        var request = URLRequest(url: latestAPI, timeoutInterval: 15)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("EyeBreak/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        return try parseRelease(data)
    }
}
