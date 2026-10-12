import CoreGraphics
import Foundation

enum SystemIdle {
    /// 距离上次键盘、鼠标、触控板操作过去的秒数；系统接口，无需辅助功能等权限
    static func seconds() -> TimeInterval {
        guard let anyInput = CGEventType(rawValue: UInt32.max) else { return 0 }
        return CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyInput)
    }
}
