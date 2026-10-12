import Testing
@testable import EyeBreak

@MainActor
struct ReminderSoundsTests {
    @Test("默认提示音是清脆，对应系统声音 Glass")
    func defaultChoice() {
        let sounds = ReminderSounds()
        #expect(sounds.choice == .glass)
        #expect(sounds.choice.systemName == "Glass")
    }

    @Test("切换提示音会通知保存")
    func choiceChangeIsReported() {
        let sounds = ReminderSounds()
        var saved: ReminderSound?
        sounds.onChoiceChanged = { saved = $0 }
        sounds.choice = .purr
        #expect(saved == .purr)
    }

    @Test("关闭选项没有对应的系统声音")
    func offHasNoSound() {
        #expect(ReminderSound.off.systemName == nil)
        #expect(ReminderSound.allCases.filter { $0 != .off }.allSatisfy { $0.systemName != nil })
    }
}
