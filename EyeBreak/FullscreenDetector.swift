import AppKit
import CoreGraphics

/// 判断当前正在使用的 App 是否全屏（看视频、演示、全屏写代码等）。
/// 只读取窗口的位置和大小，不读取窗口内容和标题，因此不需要屏幕录制权限。
enum FullscreenDetector {
    @MainActor
    static func isFrontmostAppFullscreen() -> Bool {
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return false }
        let screens = NSScreen.screens.map(\.frame)
        guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return false
        }
        return windows.contains { window in
            guard (window[kCGWindowOwnerPID as String] as? pid_t) == app.processIdentifier,
                  (window[kCGWindowLayer as String] as? Int) == 0,
                  let bounds = window[kCGWindowBounds as String] as? [String: CGFloat],
                  let width = bounds["Width"], let height = bounds["Height"] else { return false }
            return screens.contains { abs($0.width - width) < 1 && abs($0.height - height) < 1 }
        }
    }
}
