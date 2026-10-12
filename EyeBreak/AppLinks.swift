import Foundation

/// 项目相关的链接：反馈问题、开源许可
enum AppLinks {
    static let repository = URL(string: "https://github.com/yauyy/EyeBreak")!

    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    }

    static var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
    }

    /// GitHub 新建 Issue 的链接，预先填好问题模板和环境信息。
    /// 只是在浏览器里打开，用户确认提交前不会发送任何内容。
    static func newIssue(
        version: String = version,
        build: String = build,
        system: String = ProcessInfo.processInfo.operatingSystemVersionString
    ) -> URL {
        let body = """
        **\(String(localized: "遇到了什么问题"))**


        **\(String(localized: "怎么复现"))**
        1.

        ---
        - EyeBreak：\(version) (\(build))
        - macOS：\(system)
        - \(String(localized: "芯片"))：\(architecture)
        """
        var components = URLComponents(url: repository.appendingPathComponent("issues/new"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "body", value: body)]
        return components.url!
    }

    /// 随 App 分发的第三方许可声明
    static var thirdPartyNotices: URL? {
        Bundle.main.url(forResource: "ThirdPartyNotices", withExtension: "txt")
    }

    private static var architecture: String {
        #if arch(arm64)
        return String(localized: "Apple 芯片")
        #else
        return "Intel"
        #endif
    }
}
