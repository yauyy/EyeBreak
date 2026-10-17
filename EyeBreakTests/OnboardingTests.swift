import Foundation
import Testing
@testable import EyeBreak

struct OnboardingTests {
    @Test("空的持久偏好应显示首次引导")
    func emptyPreferencesPresent() {
        #expect(OnboardingPolicy.shouldPresent(persistentDomain: [:]))
    }

    @Test("任何历史业务键均视为老用户", arguments: OnboardingPolicy.legacyBusinessKeys.sorted())
    func anyHistoricalKeySuppressesOnboarding(key: String) {
        // 只判断键是否存在，值为 false、0 或旧格式也意味着曾使用过。
        #expect(!OnboardingPolicy.shouldPresent(persistentDomain: [key: false]))
    }

    @Test("已有已看标记时不显示引导")
    func seenMarkerSuppressesOnboarding() {
        #expect(!OnboardingPolicy.shouldPresent(persistentDomain: [OnboardingPolicy.seenKey: true]))
    }

    @Test("无关的系统偏好不会阻止首次引导")
    func unrelatedPreferenceStillPresents() {
        #expect(OnboardingPolicy.shouldPresent(persistentDomain: ["AppleLanguages": ["en"]]))
    }
}
