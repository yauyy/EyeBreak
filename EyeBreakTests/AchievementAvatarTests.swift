import AppKit
import Testing
@testable import EyeBreak

@MainActor
struct AchievementAvatarTests {
    @Test("未解锁头像缓存同一张位图，并保留原素材逻辑尺寸与 Retina 分辨率")
    func cachedImageKeepsResolution() throws {
        let original = try #require(NSImage(named: "Tomato"))
        let first = try #require(LockedAchievementAvatar.image)
        let second = try #require(LockedAchievementAvatar.image)
        #expect(first === second)
        #expect(first.size == original.size)
        let bitmap = try bitmap(of: first)
        #expect(bitmap.pixelsWide >= Int(original.size.width * 2))
        #expect(bitmap.pixelsHigh >= Int(original.size.height * 2))
    }

    @Test("真实番茄素材的红色主体转换为不透明中性浅灰，保留深色轮廓与透明背景")
    func cachedPixelsAreNeutralLightGray() throws {
        let original = try #require(NSImage(named: "Tomato"))
        let source = try bitmap(of: original)
        let rendered = try bitmap(of: #require(LockedAchievementAvatar.image))
        #expect(rendered.pixelsWide == source.pixelsWide)
        #expect(rendered.pixelsHigh == source.pixelsHigh)
        var bodySamples = 0
        var outlineSamples = 0
        var transparentSamples = 0
        var bodyBrightness = 0.0
        var outlineBrightness = 0.0
        for y in stride(from: 0, to: source.pixelsHigh, by: 8) {
            for x in stride(from: 0, to: source.pixelsWide, by: 8) {
                let before = try #require(source.colorAt(x: x, y: y)?.usingColorSpace(.sRGB))
                let after = try #require(rendered.colorAt(x: x, y: y)?.usingColorSpace(.sRGB))
                #expect(abs(before.alphaComponent - after.alphaComponent) <= 1.0 / 255)
                if before.alphaComponent < 0.01 {
                    transparentSamples += 1
                    continue
                }
                // 检查原图的实色区域，避免透明边缘的预乘 alpha 影响颜色判断。
                guard before.alphaComponent > 0.99 else { continue }
                #expect(abs(after.redComponent - after.greenComponent) <= 1.0 / 255)
                #expect(abs(after.greenComponent - after.blueComponent) <= 1.0 / 255)
                if before.redComponent > 0.65 && before.greenComponent < 0.55 && before.blueComponent < 0.55 {
                    bodySamples += 1
                    bodyBrightness += after.redComponent
                    #expect((0.60...0.98).contains(after.redComponent))
                    #expect(after.alphaComponent > 0.99)
                }
                let luminance = 0.2126 * before.redComponent
                    + 0.7152 * before.greenComponent + 0.0722 * before.blueComponent
                if luminance < 0.25 {
                    outlineSamples += 1
                    outlineBrightness += after.redComponent
                }
            }
        }
        #expect(bodySamples > 100)
        #expect(outlineSamples > 10)
        #expect(transparentSamples > 100)
        // 轮廓应明显深于主体，不能把整个头像处理成一块等色剪影。
        #expect(bodyBrightness / Double(max(1, bodySamples))
            > outlineBrightness / Double(max(1, outlineSamples)) + 0.08)
    }

    private func bitmap(of image: NSImage) throws -> NSBitmapImageRep {
        var proposedRect = NSRect(
            origin: .zero,
            size: NSSize(width: image.size.width * 2, height: image.size.height * 2)
        )
        let cgImage = try #require(image.cgImage(forProposedRect: &proposedRect, context: nil, hints: nil))
        return NSBitmapImageRep(cgImage: cgImage)
    }
}
