import AppKit
import SwiftUI
import Testing
@testable import EyeBreak

@MainActor
struct ThemeTests {
    @Test("白字填充色在浅色和深色外观下都满足 WCAG 普通文字对比度", arguments: [false, true])
    func fillColorsContrastWithWhite(dark: Bool) throws {
        let appearance = try #require(NSAppearance(named: dark ? .darkAqua : .aqua))
        for fill in [Theme.tomatoFill, Theme.leafFill] {
            var resolved: NSColor?
            // 在指定外观下解析实际的动态颜色，避免只验证一份独立的色值常量。
            appearance.performAsCurrentDrawingAppearance {
                resolved = NSColor(fill).usingColorSpace(.sRGB)
            }
            let color = try #require(resolved)
            let luminance = 0.2126 * linear(color.redComponent)
                + 0.7152 * linear(color.greenComponent)
                + 0.0722 * linear(color.blueComponent)
            let contrast = 1.05 / (luminance + 0.05)
            #expect(color.alphaComponent == 1)
            #expect(contrast >= 4.5)
        }
    }

    /// WCAG 相对亮度先将 sRGB 分量还原成线性光强。
    private func linear(_ component: CGFloat) -> Double {
        let value = Double(component)
        return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
    }
}
