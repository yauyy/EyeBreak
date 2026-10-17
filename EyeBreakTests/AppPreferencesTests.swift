import AppKit
import Foundation
import Testing
@testable import EyeBreak

private struct PreferenceFixture {
    let domainName = "EyeBreak.AppPreferencesTests.\(UUID().uuidString)"
    let defaults: UserDefaults

    init() throws {
        defaults = try #require(UserDefaults(suiteName: domainName))
    }

    func cleanUp() { defaults.removePersistentDomain(forName: domainName) }
}

struct AppearancePreferenceTests {
    @Test("外观默认跟随系统，未知偏好安全回退")
    func defaultAndUnknownValues() throws {
        let fixture = try PreferenceFixture()
        defer { fixture.cleanUp() }
        #expect(AppearancePreference.read(from: fixture.defaults) == .system)
        fixture.defaults.set("future-appearance", forKey: AppearancePreference.key)
        #expect(AppearancePreference.read(from: fixture.defaults) == .system)
    }

    @Test("三种外观均可独立读写", arguments: AppearanceMode.allCases)
    func roundTrip(mode: AppearanceMode) throws {
        let fixture = try PreferenceFixture()
        defer { fixture.cleanUp() }
        AppearancePreference.write(mode, to: fixture.defaults)
        #expect(AppearancePreference.read(from: fixture.defaults) == mode)
        #expect(fixture.defaults.string(forKey: AppearancePreference.key) == mode.rawValue)
    }

    @Test("外观映射为系统继承、浅色与深色")
    func appKitAppearanceMapping() {
        #expect(AppearanceMode.system.appearanceName == nil)
        #expect(AppearanceMode.light.appearanceName == .aqua)
        #expect(AppearanceMode.dark.appearanceName == .darkAqua)
    }

    @MainActor
    @Test("设置对象变更写入注入域，测试无需更改 App 全局外观")
    func observableSettingsWritePreference() throws {
        let fixture = try PreferenceFixture()
        defer { fixture.cleanUp() }
        let settings = AppearanceSettings(defaults: fixture.defaults, appliesToApplication: false)
        settings.mode = .dark
        #expect(AppearancePreference.read(from: fixture.defaults) == .dark)
        settings.mode = .system
        #expect(AppearancePreference.read(from: fixture.defaults) == .system)
    }
}

struct LanguagePreferenceTests {
    @Test("语言只读取 App 持久域，注册默认值不会伪装成单独语言")
    func readsOnlyAppDomain() throws {
        let fixture = try PreferenceFixture()
        defer { fixture.cleanUp() }
        fixture.defaults.register(defaults: [LanguagePreference.key: ["en"]])
        #expect(LanguagePreference.read(from: fixture.defaults, domainName: fixture.domainName) == .system)
        fixture.defaults.set(["zh-Hans"], forKey: LanguagePreference.key)
        #expect(LanguagePreference.read(from: fixture.defaults, domainName: fixture.domainName) == .simplifiedChinese)
        fixture.defaults.set(["en-US"], forKey: LanguagePreference.key)
        #expect(LanguagePreference.read(from: fixture.defaults, domainName: fixture.domainName) == .english)
    }

    @Test("中英文写入 AppleLanguages 的标准语言标记", arguments: [LanguageChoice.simplifiedChinese, .english])
    func writesAppLanguage(choice: LanguageChoice) throws {
        let fixture = try PreferenceFixture()
        defer { fixture.cleanUp() }
        LanguagePreference.write(choice, to: fixture.defaults)
        let code = try #require(choice.languageCode)
        #expect(fixture.defaults.persistentDomain(forName: fixture.domainName)?[LanguagePreference.key] as? [String] == [code])
        #expect(LanguagePreference.read(from: fixture.defaults, domainName: fixture.domainName) == choice)
    }

    @Test("跟随系统移除 App 的 AppleLanguages，保留其他偏好")
    func systemRemovesAppOverride() throws {
        let fixture = try PreferenceFixture()
        defer { fixture.cleanUp() }
        fixture.defaults.set(42, forKey: "unrelated")
        LanguagePreference.write(.english, to: fixture.defaults)
        LanguagePreference.write(.system, to: fixture.defaults)
        #expect(fixture.defaults.persistentDomain(forName: fixture.domainName)?[LanguagePreference.key] == nil)
        #expect(fixture.defaults.integer(forKey: "unrelated") == 42)
        #expect(LanguagePreference.read(from: fixture.defaults, domainName: fixture.domainName) == .system)
    }

    @Test("两种语言选项始终显示原名")
    func nativeNames() {
        #expect(LanguageChoice.simplifiedChinese.title == "简体中文")
        #expect(LanguageChoice.english.title == "English")
    }

    @Test("显式语言按当前实际语言判断待生效", arguments: ["zh-Hans", "en-US"])
    func explicitRestartRequirement(runningLanguage: String) {
        let isEnglish = runningLanguage.hasPrefix("en")
        #expect(LanguagePreference.requiresRestart(.english, runningLanguage: runningLanguage, systemLanguages: ["zh-Hans"]) == !isEnglish)
        #expect(LanguagePreference.requiresRestart(.simplifiedChinese, runningLanguage: runningLanguage, systemLanguages: ["en"]) == isEnglish)
    }

    @Test("跟随系统比较全局语言而非已写入的 App 覆盖")
    func systemRestartRequirement() {
        #expect(!LanguagePreference.requiresRestart(.system, runningLanguage: "zh-Hans", systemLanguages: ["zh-CN", "en"]))
        #expect(LanguagePreference.requiresRestart(.system, runningLanguage: "zh-Hans", systemLanguages: ["en-US", "zh-Hans"]))
        #expect(!LanguagePreference.requiresRestart(.system, runningLanguage: "en", systemLanguages: ["en-GB", "zh-Hans"]))
        #expect(LanguagePreference.requiresRestart(.system, runningLanguage: "en", systemLanguages: ["zh-Hans", "en"]))
    }

    @MainActor
    @Test("选择变更后提示出现，改回当前语言或同语言系统选项时消失")
    func pendingHintFollowsEffectiveLanguage() throws {
        let fixture = try PreferenceFixture()
        defer { fixture.cleanUp() }
        let settings = LanguageSettings(
            defaults: fixture.defaults, domainName: fixture.domainName,
            runningLanguage: "zh-Hans", systemLanguages: { ["zh-Hans"] }
        )
        #expect(!settings.restartRequired)
        settings.choice = .english
        #expect(settings.restartRequired)
        settings.choice = .simplifiedChinese
        #expect(!settings.restartRequired)
        settings.choice = .system
        #expect(!settings.restartRequired)
        #expect(fixture.defaults.persistentDomain(forName: fixture.domainName)?[LanguagePreference.key] == nil)
    }

    @MainActor
    @Test("单元测试宿主禁止重新打开或保存实际计时快照")
    func reopeningDoesNotAffectTestHost() throws {
        let fixture = try PreferenceFixture()
        defer { fixture.cleanUp() }
        let settings = LanguageSettings(
            defaults: fixture.defaults, domainName: fixture.domainName,
            runningLanguage: "zh-Hans", systemLanguages: { ["zh-Hans"] }
        )
        settings.choice = .english
        var saved = false
        settings.beforeReopen = { saved = true }
        settings.reopen()
        #expect(!saved)
        #expect(!settings.isReopening)
        #expect(settings.reopenError == nil)
    }
}

@MainActor
struct RelaunchHandoffTests {
    @Test("交接后重新读取统计和成就，旧实例最后一次休息不会丢失或被覆盖")
    func reloadsFinalStatsFromPreviousInstance() throws {
        let fixture = try PreferenceFixture()
        defer { fixture.cleanUp() }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let now = Date(timeIntervalSince1970: 1_791_799_200)
        let previous = TomatoStats(defaults: fixture.defaults, now: { now }, calendar: calendar)
        let replacement = TomatoStats(defaults: fixture.defaults, now: { now }, calendar: calendar)
        previous.recordBreak()
        #expect(replacement.total == 0)
        replacement.reloadFromDefaults()
        #expect(replacement.today == 1)
        #expect(replacement.total == 1)
        #expect(replacement.streak == 1)
        #expect(replacement.unlocked.contains(.firstTomato))
        #expect(replacement.justUnlocked.isEmpty)
        replacement.recordBreak()
        #expect(replacement.total == 2)
        #expect(TomatoStats(defaults: fixture.defaults, now: { now }, calendar: calendar).today == 2)
    }

    @Test("交接只在恢复快照前同步动作索引，运行后不再覆盖当前动作")
    func reloadsExerciseIndexOnlyBeforeRestoring() {
        let model = EyeBreakModel(
            workInterval: 1200, restDuration: 20, reminder: ReminderSounds(choice: .off),
            idleTime: { 0 }, isInMeeting: { false }, isFullscreen: { false },
            exerciseIndex: 0, usesSystemTimer: false
        )
        defer { model.shutdown() }
        model.refreshExerciseIndexBeforeRestoring(RestExercise.drinkWater.rawValue)
        #expect(model.exercise == .drinkWater)
        model.restore(EyeBreakModel.Snapshot(phase: .awaitingBreak, remaining: 0, savedAt: Date()))
        #expect(model.phase == .awaitingBreak)
        #expect(model.exercise == .drinkWater)
        model.refreshExerciseIndexBeforeRestoring(RestExercise.lookFar.rawValue)
        #expect(model.exercise == .drinkWater)
    }

    @Test("只有自己的合法握手参数触发等待，普通启动和 Sparkle 参数不触发")
    func parsesOnlyValidatedProcessIDs() {
        let arguments = RelaunchHandoff.arguments(previousProcessID: 123)
        #expect(RelaunchHandoff.previousProcessID(in: arguments, currentProcessID: 456) == 123)
        #expect(RelaunchHandoff.previousProcessID(in: [], currentProcessID: 456) == nil)
        #expect(RelaunchHandoff.previousProcessID(in: ["-NSDocumentRevisionsDebugMode", "YES"], currentProcessID: 456) == nil)
        for pid in ["0", "-1", "invalid", "99999999999999999999", "456"] {
            #expect(RelaunchHandoff.previousProcessID(in: ["--eyebreak-wait-for-process=\(pid)"], currentProcessID: 456) == nil)
        }
    }

    @Test("等待旧进程退出后才允许新实例接管")
    func waitsUntilPreviousInstanceExits() async {
        var checks = 0
        var pauses = 0
        let exited = await RelaunchHandoff.waitForExit(
            processID: 123, attempts: 5,
            isRunning: { pid in
                #expect(pid == 123)
                checks += 1
                return checks <= 2
            },
            pause: { pauses += 1 }
        )
        #expect(exited)
        #expect(checks == 3)
        #expect(pauses == 2)
    }

    @Test("旧进程没有退出时超时撤销接管，不插入第二个图标")
    func timesOutWithoutTakingOver() async {
        var pauses = 0
        let exited = await RelaunchHandoff.waitForExit(
            processID: 123, attempts: 3, isRunning: { _ in true }, pause: { pauses += 1 }
        )
        #expect(!exited)
        #expect(pauses == 3)
    }

    @Test("旧进程已经退出时立即接管")
    func takesOverImmediatelyAfterExit() async {
        var paused = false
        let exited = await RelaunchHandoff.waitForExit(
            processID: 123, isRunning: { _ in false }, pause: { paused = true }
        )
        #expect(exited)
        #expect(!paused)
    }
}
