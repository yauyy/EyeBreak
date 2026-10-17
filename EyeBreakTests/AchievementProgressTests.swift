import Foundation
import Testing
@testable import EyeBreak

struct AchievementProgressTests {
    /// 整套测试分别以中英文宿主运行，直接核对用户实际读到的文案。
    private var isEnglish: Bool {
        Bundle.main.preferredLocalizations.first?.hasPrefix("en") == true
    }

    @Test("单日、连续和累计成就各自使用对应的数据与文案")
    func metricAndText() {
        let cases: [(Achievement, Int, Int, Achievement.Progress.Metric, String, String)] = [
            (.firstTomato, 0, 1, .total, "累计 0/1", "Total 0/1"),
            (.dailyFive, 3, 5, .today, "今天 3/5", "Today 3/5"),
            (.dailyTen, 3, 10, .today, "今天 3/10", "Today 3/10"),
            (.streakThree, 2, 3, .streak, "连续 2/3 天", "Streak 2/3 days"),
            (.streakSeven, 2, 7, .streak, "连续 2/7 天", "Streak 2/7 days"),
            (.streakThirty, 2, 30, .streak, "连续 2/30 天", "Streak 2/30 days"),
            (.totalFifty, 37, 50, .total, "累计 37/50", "Total 37/50"),
            (.totalHundred, 37, 100, .total, "累计 37/100", "Total 37/100"),
        ]
        for (achievement, current, target, metric, chinese, english) in cases {
            let progress = achievement.progress(
                today: 3, streak: 2, total: achievement == .firstTomato ? 0 : 37, earned: false
            )
            #expect(progress.current == current)
            #expect(progress.target == target)
            #expect(progress.metric == metric)
            #expect(progress.text == (isEnglish ? english : chinese))
        }
    }

    @Test("各项成就的零值、阈值前、阈值和超出阈值进度保持在零到一")
    func boundaryProgress() {
        let targets: [(Achievement, Int)] = [
            (.firstTomato, 1), (.dailyFive, 5), (.dailyTen, 10),
            (.streakThree, 3), (.streakSeven, 7), (.streakThirty, 30),
            (.totalFifty, 50), (.totalHundred, 100),
        ]
        for (achievement, target) in targets {
            for count in [-1, 0, target - 1, target, target + 1, Int.max] {
                let earned = achievement.isMet(today: count, streak: count, total: count)
                let progress = achievement.progress(today: count, streak: count, total: count, earned: earned)
                #expect(progress.current == max(count, 0))
                #expect(progress.target == target)
                #expect(progress.fraction == min(Double(max(count, 0)) / Double(target), 1))
                #expect((0...1).contains(progress.fraction))
                #expect(progress.isUnlocked == (count >= target))
                let unlockedText = isEnglish ? "Unlocked" : "已解锁"
                if count >= target {
                    #expect(progress.text == unlockedText)
                } else {
                    #expect(progress.text != unlockedText)
                }
            }
        }
    }

    @MainActor
    @Test("实际休息达到单日和累计阈值后，卡片输入与持久化解锁状态一致")
    func recordedBreakUnlocksProgress() {
        let suite = "AchievementProgressTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(99, forKey: "tomatoTotal")
        let date = Date(timeIntervalSince1970: 1_791_799_200)
        let stats = TomatoStats(defaults: defaults, now: { date })
        let unlockedText = isEnglish ? "Unlocked" : "已解锁"

        func progress(_ achievement: Achievement) -> Achievement.Progress {
            achievement.progress(
                today: stats.today, streak: stats.streak, total: stats.total,
                earned: stats.unlocked.contains(achievement)
            )
        }

        #expect(progress(.totalHundred).text == (isEnglish ? "Total 99/100" : "累计 99/100"))
        stats.recordBreak()
        #expect(stats.unlocked.contains(.totalHundred))
        #expect(progress(.totalHundred).text == unlockedText)

        for _ in 0..<3 { stats.recordBreak() }
        #expect(progress(.dailyFive).text == (isEnglish ? "Today 4/5" : "今天 4/5"))
        stats.recordBreak()
        #expect(stats.unlocked.contains(.dailyFive))
        #expect(progress(.dailyFive).text == unlockedText)
        let saved = defaults.stringArray(forKey: "achievements") ?? []
        #expect(saved.contains(Achievement.dailyFive.rawValue))
        #expect(saved.contains(Achievement.totalHundred.rawValue))
    }

    @Test("已达成的成就显示已解锁，当前计数回落也不会重新锁定")
    func earnedTextSurvivesCounterReset() {
        for achievement in Achievement.allCases {
            for count in [0, 1, 100, Int.max] {
                let progress = achievement.progress(today: count, streak: count, total: count, earned: true)
                #expect(progress.isUnlocked)
                #expect(progress.text == (isEnglish ? "Unlocked" : "已解锁"))
            }
        }
    }

    @Test("未解锁卡片的辅助功能包含名称和对应进度")
    func lockedAccessibility() {
        let cases: [(Achievement, String, String)] = [
            (.dailyTen, "未解锁：单日 10 个，今天 3/10", "Locked: 10 in a day, Today 3/10"),
            (.streakSeven, "未解锁：连续 7 天，连续 2/7 天", "Locked: 7-day streak, Streak 2/7 days"),
            (.totalHundred, "未解锁：累计 100 个，累计 37/100", "Locked: 100 total, Total 37/100"),
        ]
        for (achievement, chinese, english) in cases {
            let progress = achievement.progress(today: 3, streak: 2, total: 37, earned: false)
            #expect(achievement.accessibilityText(progress: progress) == (isEnglish ? english : chinese))
        }
    }

    @Test("已解锁卡片的辅助功能包含状态和名称，不再朗读进行中的进度")
    func earnedAccessibility() {
        let progress = Achievement.dailyFive.progress(today: 0, streak: 0, total: 50, earned: true)
        #expect(Achievement.dailyFive.accessibilityText(progress: progress) == (
            isEnglish ? "Unlocked: 5 in a day" : "已解锁：单日 5 个"
        ))
    }
}
