import Foundation

/// 限制一个较重的系统检测的调用频率：间隔内重复调用直接返回上次的结果
@MainActor
final class ThrottledCheck {
    private let interval: TimeInterval
    private let check: @MainActor () -> Bool
    private var lastValue = false
    private var lastCheckedAt = Date.distantPast

    init(every interval: TimeInterval, _ check: @escaping @MainActor () -> Bool) {
        self.interval = interval
        self.check = check
    }

    func value() -> Bool {
        let now = Date()
        if now.timeIntervalSince(lastCheckedAt) >= interval {
            lastValue = check()
            lastCheckedAt = now
        }
        return lastValue
    }
}
