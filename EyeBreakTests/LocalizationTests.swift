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
        ("喝口水", "Sip some water"),
        ("起身喝几口水", "Get up and sip some water"),
        ("走一走", "Take a walk"),
        ("起身走一走", "Get up and walk around"),
        ("下一轮生效", "Takes effect next round"),
        ("下次休息生效", "Takes effect next break"),
        ("EyeBreak 设置", "EyeBreak Settings"),
        ("外观", "Appearance"),
        ("语言", "Language"),
        ("语言设置", "Language setting"),
        ("跟随系统", "System"),
        ("浅色", "Light"),
        ("深色", "Dark"),
        ("重新打开 EyeBreak 后生效", "Takes effect after reopening EyeBreak"),
        ("立即重新打开", "Reopen now"),
        ("成就", "Achievements"),
        ("已解锁", "Unlocked"),
        ("收集第一个番茄", "Collect your first tomato"),
        ("一天内收集 5 个番茄", "Collect 5 tomatoes in one day"),
        ("一天内收集 10 个番茄", "Collect 10 tomatoes in one day"),
        ("连续 3 天都有番茄", "Collect tomatoes for 3 days in a row"),
        ("连续 7 天都有番茄", "Collect tomatoes for 7 days in a row"),
        ("连续 30 天都有番茄", "Collect tomatoes for 30 days in a row"),
        ("累计收集 50 个番茄", "Collect 50 tomatoes in total"),
        ("累计收集 100 个番茄", "Collect 100 tomatoes in total"),
        ("设置…", "Settings…"),
        ("现在休息", "Rest now"),
        ("启用的动作", "Enabled exercises"),
        ("至少保留一个动作", "Keep at least one exercise enabled"),
        ("复制诊断信息", "Copy diagnostics"),
        ("诊断信息预览", "Diagnostics preview"),
        ("上次检查更新时间", "Last update check"),
        ("欢迎来到 EyeBreak", "Welcome to EyeBreak"),
        ("知道了", "Got it"),
        ("起来活动一下吧", "Time to get up and move"),
        ("长休息", "Long break"),
        ("长休息中", "Long break"),
        ("该活动啦", "Time to move"),
        ("眼睛动作", "Eye exercises"),
        ("起身活动", "Get-up activities"),
        ("自动继续", "Resume"),
        ("1 小时后", "in 1 h"),
        ("2 小时后", "in 2 h"),
        ("明天", "tomorrow"),
        ("明天继续", "Resumes tomorrow"),
    ])
    func englishStrings(key: String, english: String) throws {
        #expect(try englishBundle().localizedString(forKey: key, value: nil, table: nil) == english)
    }

    @Test("带参数的文案在英文下格式正确")
    func englishFormat() throws {
        let format = try englishBundle().localizedString(forKey: "%@，放松 %lld 秒", value: nil, table: nil)
        #expect(String(format: format, "Blink slowly", 20) == "Blink slowly for 20 seconds")
        let drinkWater = try englishBundle().localizedString(forKey: "起身喝几口水", value: nil, table: nil)
        #expect(String(format: format, drinkWater, 20) == "Get up and sip some water for 20 seconds")
        let walk = try englishBundle().localizedString(forKey: "起身走一走", value: nil, table: nil)
        #expect(String(format: format, walk, 20) == "Get up and walk around for 20 seconds")
        let minutes = try englishBundle().localizedString(forKey: "%@，放松 %lld 分钟", value: nil, table: nil)
        #expect(String(format: minutes, walk, 3) == "Get up and walk around for 3 minutes")
        let remaining = try englishBundle().localizedString(forKey: "还剩 %lld 分 %lld 秒", value: nil, table: nil)
        #expect(String(format: remaining, 2, 30) == "2 min 30 sec left")
        let resume = try englishBundle().localizedString(forKey: "%@ 继续", value: nil, table: nil)
        #expect(String(format: resume, "14:30") == "Resumes at 14:30")
    }

    @Test("圆环完整读法有英文版")
    func englishRingAccessibility() throws {
        let format = try englishBundle().localizedString(forKey: "%@，剩余 %lld 分 %lld 秒", value: nil, table: nil)
        #expect(String(format: format, "Focusing", 18, 30) == "Focusing, 18 minutes and 30 seconds remaining")
    }

    @Test("成就进度、汇总和无障碍读法有完整英文版")
    func englishAchievementFormats() throws {
        let bundle = try englishBundle()
        let today = bundle.localizedString(forKey: "今天 %lld/%lld", value: nil, table: nil)
        #expect(String(format: today, 3, 5) == "Today 3/5")
        let streak = bundle.localizedString(forKey: "连续 %lld/%lld 天", value: nil, table: nil)
        #expect(String(format: streak, 2, 7) == "Streak 2/7 days")
        let total = bundle.localizedString(forKey: "累计 %lld/%lld", value: nil, table: nil)
        #expect(String(format: total, 37, 100) == "Total 37/100")
        let summary = bundle.localizedString(forKey: "已解锁 %lld / %lld", value: nil, table: nil)
        #expect(String(format: summary, 4, 8) == "Unlocked 4 / 8")
        let locked = bundle.localizedString(forKey: "未解锁：%@，%@", value: nil, table: nil)
        #expect(String(format: locked, "5 in a day", "Today 3/5") == "Locked: 5 in a day, Today 3/5")
    }

    @Test("快捷指令短语有英文版")
    func shortcutPhrases() throws {
        let phrase = try englishBundle().localizedString(forKey: "用${applicationName}开始专注", value: nil, table: "AppShortcuts")
        #expect(phrase == "Start focusing with ${applicationName}")
    }
}
