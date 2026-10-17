import Foundation
import Testing
@testable import EyeBreak

struct DiagnosticsTests {
    private func snapshot(lastUpdateCheck: Date? = Date(timeIntervalSince1970: 0)) -> DiagnosticSnapshot {
        DiagnosticSnapshot(
            appVersion: "1.3.2", buildNumber: "2", macOSVersion: "macOS-fixture",
            chip: "Apple Silicon", isTranslated: true, interfaceLanguage: "en",
            phase: "fixture-phase", deferReason: "fixture-reason", isSnoozing: true,
            overridesSchedule: true, workSeconds: 1200, restSeconds: 20,
            enabledExercises: ["fixture-exercise"], reminderSound: "fixture-sound",
            schedule: WorkSchedule(isEnabled: true, startHour: 9, endHour: 19, weekdaysOnly: true),
            launchAtLogin: "fixture-login", automaticUpdates: true,
            lastUpdateCheck: lastUpdateCheck
        )
    }

    @Test("诊断白名单包含所有规定字段和运行值")
    func requiredFields() {
        let text = DiagnosticReport.text(from: snapshot())
        let labels = [
            String(localized: "App 版本"), String(localized: "构建号"),
            String(localized: "macOS 版本"), String(localized: "芯片"),
            String(localized: "Rosetta 转译"), String(localized: "界面语言"),
            String(localized: "当前阶段"), String(localized: "推迟原因"),
            String(localized: "稍后提醒中"), String(localized: "覆盖工作时段"),
            String(localized: "专注时长（秒）"), String(localized: "眺望时长（秒）"),
            String(localized: "启用的动作"), String(localized: "提示音"),
            String(localized: "工作时段已启用"), String(localized: "工作开始时间"),
            String(localized: "工作结束时间"), String(localized: "仅工作日"),
            String(localized: "开机自启"), String(localized: "自动检查更新"),
            String(localized: "上次检查更新时间"),
        ]
        let lines = text.split(separator: "\n")
        #expect(lines.count == labels.count)
        for label in labels {
            #expect(lines.contains { $0.hasPrefix(label + ": ") })
        }
        for value in ["1.3.2", "macOS-fixture", "Apple Silicon", "fixture-phase", "fixture-reason", "1200", "20", "fixture-exercise", "fixture-sound", "9:00", "19:00", "fixture-login", "1970-01-01T00:00:00Z"] {
            #expect(text.contains(value))
        }
    }

    @Test("从未检查更新时诊断写为未知")
    func missingLastCheck() {
        let text = DiagnosticReport.text(from: snapshot(lastUpdateCheck: nil))
        #expect(text.contains(String(localized: "上次检查更新时间") + ": " + String(localized: "未知")))
    }

    @Test("上次更新时间读取 Sparkle 的日期键，不接受其它偏好")
    func sparkleDate() throws {
        let suite = "DiagnosticsTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(DiagnosticReport.lastUpdateCheck(defaults: defaults) == nil)
        defaults.set("not-a-date", forKey: "SULastCheckTime")
        #expect(DiagnosticReport.lastUpdateCheck(defaults: defaults) == nil)
        let date = Date(timeIntervalSince1970: 1234)
        defaults.set(date, forKey: "SULastCheckTime")
        #expect(DiagnosticReport.lastUpdateCheck(defaults: defaults) == date)
    }

    @Test("收集诊断不会带出统计、成就和其它用户偏好")
    @MainActor
    func excludesPrivatePreferences() throws {
        let suite = "DiagnosticsTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("PRIVATE_STATS_RECORD", forKey: "tomatoCounts")
        defaults.set(["PRIVATE_ACHIEVEMENT"], forKey: "achievements")
        defaults.set("PRIVATE_PERSONAL_VALUE", forKey: "unrelatedSetting")
        let sounds = ReminderSounds(choice: .off)
        let model = EyeBreakModel(
            workInterval: 1200, restDuration: 20, reminder: sounds,
            idleTime: { 0 }, isInMeeting: { false }, isFullscreen: { false },
            usesSystemTimer: false
        )
        let captured = DiagnosticSnapshot.capture(
            model: model, sounds: sounds, launchAtLogin: LaunchAtLogin(),
            updates: AppUpdater(), schedule: WorkScheduleSettings(defaults: defaults), defaults: defaults
        )
        let text = DiagnosticReport.text(from: captured)
        #expect(!text.contains("PRIVATE_"))
        #expect(!text.contains("tomatoCounts"))
        #expect(!text.contains("achievements"))
        #expect(!text.contains("unrelatedSetting"))
        #expect(captured.enabledExercises.count == 4)
        #expect(captured.workSeconds == 1200)
        #expect(captured.restSeconds == 20)
    }
}
