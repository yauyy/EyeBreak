import Foundation
import Testing
@testable import EyeBreak

@MainActor
struct UpdateCheckerTests {
    private let suiteName = "UpdateCheckerTests-\(UUID().uuidString)"
    private let defaults: UserDefaults
    private let page = URL(string: "https://github.com/yauyy/EyeBreak/releases/tag/v1.2")!

    init() {
        defaults = UserDefaults(suiteName: suiteName)!
    }

    // MARK: - 版本比较

    @Test("按数字逐段比较版本号", arguments: [
        ("1.1", "1.0", true),
        ("1.10", "1.9", true),
        ("2.0", "1.99", true),
        ("1.0.1", "1.0", true),
        ("1.0", "1.0", false),
        ("1.0.0", "1.0", false),
        ("1.0", "1.1", false),
        ("v1.2", "1.1", true),
    ])
    func versionComparison(candidate: String, current: String, newer: Bool) {
        #expect(UpdateChecker.isVersion(candidate, newerThan: current) == newer)
    }

    // MARK: - 接口解析

    @Test("解析 GitHub 最新 Release 接口，去掉标签里的 v")
    func parsesRelease() throws {
        let json = #"{"tag_name":"v1.2","html_url":"https://github.com/yauyy/EyeBreak/releases/tag/v1.2","draft":false,"prerelease":false,"assets":[]}"#
        let release = try UpdateChecker.parseRelease(Data(json.utf8))
        #expect(release.version == "1.2")
        #expect(release.url == page)
    }

    @Test("返回内容不对时解析失败")
    func rejectsBadPayload() {
        #expect(throws: (any Error).self) {
            try UpdateChecker.parseRelease(Data(#"{"message":"Not Found"}"#.utf8))
        }
    }

    // MARK: - 检查结果

    @Test("远端版本更新时提示新版本")
    func findsNewerVersion() async {
        let release = UpdateChecker.Release(version: "1.2", url: page)
        let checker = UpdateChecker(currentVersion: "1.1", defaults: defaults, fetchLatest: { release })
        await checker.check()
        #expect(checker.available == release)
        #expect(checker.status == .upToDate)
        defaults.removePersistentDomain(forName: suiteName)
    }

    @Test("远端版本相同或更旧时不提示")
    func upToDate() async {
        let release = UpdateChecker.Release(version: "1.1", url: page)
        let checker = UpdateChecker(currentVersion: "1.1", defaults: defaults, fetchLatest: { release })
        await checker.check()
        #expect(checker.available == nil)
        #expect(checker.status == .upToDate)
        defaults.removePersistentDomain(forName: suiteName)
    }

    @Test("网络失败时显示失败状态，不崩溃")
    func reportsFailure() async {
        let checker = UpdateChecker(currentVersion: "1.1", defaults: defaults, fetchLatest: { throw URLError(.notConnectedToInternet) })
        await checker.check()
        #expect(checker.status == .failed)
        #expect(checker.available == nil)
        defaults.removePersistentDomain(forName: suiteName)
    }

    // MARK: - 自动检查

    @Test("默认开启自动检查，开关状态会保存")
    func automaticChecksSetting() {
        let checker = UpdateChecker(currentVersion: "1.1", defaults: defaults, fetchLatest: { throw URLError(.cancelled) })
        #expect(checker.automaticChecks)
        checker.automaticChecks = false
        let reopened = UpdateChecker(currentVersion: "1.1", defaults: defaults, fetchLatest: { throw URLError(.cancelled) })
        #expect(!reopened.automaticChecks)
        defaults.removePersistentDomain(forName: suiteName)
    }

    @Test("一天内检查过就不再自动联网；关闭自动检查后完全不联网")
    func automaticCheckThrottling() async {
        var fetches = 0
        var now = Date(timeIntervalSince1970: 1_000_000)
        let release = UpdateChecker.Release(version: "1.1", url: page)
        let checker = UpdateChecker(currentVersion: "1.1", defaults: defaults, now: { now }, fetchLatest: {
            fetches += 1
            return release
        })

        await checker.check()
        #expect(fetches == 1)

        now += 3600
        checker.checkIfDue()
        await Task.yield()
        #expect(fetches == 1)

        checker.automaticChecks = false
        now += 2 * 86400
        checker.checkIfDue()
        await Task.yield()
        #expect(fetches == 1)
        defaults.removePersistentDomain(forName: suiteName)
    }
}
