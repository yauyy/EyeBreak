import Foundation
import Testing
@testable import EyeBreak

struct AppLinksTests {
    @Test("反馈链接指向 GitHub 新建 Issue，并带上版本和系统信息")
    func newIssueLink() throws {
        let url = AppLinks.newIssue(version: "1.3", build: "40", system: "Version 27.0 (Build 27A1)")
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        #expect(components.host == "github.com")
        #expect(components.path == "/yauyy/EyeBreak/issues/new")
        let body = try #require(components.queryItems?.first { $0.name == "body" }?.value)
        #expect(body.contains("EyeBreak：1.3 (40)"))
        #expect(body.contains("macOS：Version 27.0 (Build 27A1)"))
        #expect(body.contains("芯片："))
    }

    @Test("第三方许可声明随 App 一起分发，并包含 Sparkle 的许可")
    func noticesAreBundled() throws {
        let url = try #require(AppLinks.thirdPartyNotices)
        let text = try String(contentsOf: url, encoding: .utf8)
        #expect(text.contains("Sparkle"))
        #expect(text.contains("Andy Matuschak"))
    }
}
