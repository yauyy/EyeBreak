import Foundation
import Testing

struct LocalizationTests {
    private func englishBundle() throws -> Bundle {
        let path = try #require(Bundle.main.path(forResource: "en", ofType: "lproj"))
        return try #require(Bundle(path: path))
    }

    @Test("英文翻译随 App 一起打包", arguments: [
        ("休息一下眼睛吧", "Time to rest your eyes"),
        ("开始休息", "Start break"),
        ("看看 6 米外", "Look 20 feet away"),
        ("下一轮生效", "Takes effect next round"),
        ("下次休息生效", "Takes effect next break"),
    ])
    func englishStrings(key: String, english: String) throws {
        #expect(try englishBundle().localizedString(forKey: key, value: nil, table: nil) == english)
    }

    @Test("带参数的文案在英文下格式正确")
    func englishFormat() throws {
        let format = try englishBundle().localizedString(forKey: "%@，放松 %lld 秒", value: nil, table: nil)
        #expect(String(format: format, "Blink slowly", 20) == "Blink slowly for 20 seconds")
    }

    @Test("快捷指令短语有英文版")
    func shortcutPhrases() throws {
        let phrase = try englishBundle().localizedString(forKey: "用${applicationName}开始专注", value: nil, table: "AppShortcuts")
        #expect(phrase == "Start focusing with ${applicationName}")
    }
}
