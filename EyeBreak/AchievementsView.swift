import AppKit
import SwiftUI

/// 实际生成灰阶像素，兼容不会执行 SwiftUI 颜色滤镜的离屏截图。
@MainActor
enum LockedAchievementAvatar {
    static let image: NSImage? = {
        guard let original = NSImage(named: "Tomato") else { return nil }
        // 请求 2 倍表示，保留素材的 Retina 清晰度；输出仍沿用原图的逻辑尺寸。
        var proposedRect = NSRect(
            origin: .zero,
            size: NSSize(width: original.size.width * 2, height: original.size.height * 2)
        )
        guard let source = original.cgImage(forProposedRect: &proposedRect, context: nil, hints: nil),
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        let width = source.width
        let height = source.height
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
            .union(.byteOrder32Big)
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: colorSpace, bitmapInfo: bitmapInfo.rawValue
            ) else { return false }
            context.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }
        // 在 CPU 上一次生成实际灰阶像素，不依赖 GPU 滤镜或截图时的颜色效果。
        // 先还原预乘 alpha 和 sRGB，再提亮线性亮度，保留暗轮廓与透明边缘。
        for offset in stride(from: 0, to: pixels.count, by: 4) {
            let alpha = Double(pixels[offset + 3])
            guard alpha > 0 else { continue }
            let luminance = 0.2126 * linear(Double(pixels[offset]) / alpha)
                + 0.7152 * linear(Double(pixels[offset + 1]) / alpha)
                + 0.0722 * linear(Double(pixels[offset + 2]) / alpha)
            let brightened = min(1, luminance + 0.28)
            let gray = 1.055 * pow(brightened, 1 / 2.4) - 0.055
            let component = UInt8(min(alpha, max(0, (gray * alpha).rounded())))
            pixels[offset] = component
            pixels[offset + 1] = component
            pixels[offset + 2] = component
        }
        guard let provider = CGDataProvider(data: Data(pixels) as CFData),
              let rendered = CGImage(
                width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                bytesPerRow: width * 4, space: colorSpace, bitmapInfo: bitmapInfo,
                provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent
              ) else { return nil }
        return NSImage(cgImage: rendered, size: original.size)
    }()

    private static func linear(_ component: Double) -> Double {
        component <= 0.04045 ? component / 12.92 : pow((component + 0.055) / 1.055, 2.4)
    }
}

/// 成就内容由设置窗口的 ScrollView 承载，窗口保持固定尺寸。
struct AchievementsView: View {
    @ObservedObject var stats: TomatoStats

    private let columns = [
        GridItem(.flexible(minimum: 0), spacing: 10),
        GridItem(.flexible(minimum: 0), spacing: 10)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("已解锁 \(stats.unlocked.count) / \(Achievement.allCases.count)")
                .font(Theme.font(14, .semibold))
                .foregroundStyle(Theme.ink)

            LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
                ForEach(Achievement.allCases) { achievement in
                    AchievementCard(
                        achievement: achievement,
                        progress: achievement.progress(
                            today: stats.today, streak: stats.streak, total: stats.total,
                            earned: stats.unlocked.contains(achievement)
                        )
                    )
                }
            }
        }
    }
}

private struct AchievementCard: View {
    let achievement: Achievement
    let progress: Achievement.Progress

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                avatar
                Text(verbatim: achievement.title)
                    .font(Theme.font(13, .semibold))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
            }

            Text(verbatim: achievement.detail)
                .font(Theme.font(11))
                .foregroundStyle(Theme.inkSoft)
                // 两行高度让不同语言的同一行卡片保持对齐。
                .lineLimit(2, reservesSpace: true)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 5) {
                if progress.isUnlocked {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Theme.leafFill)
                }
                Text(verbatim: progress.text)
                    .foregroundStyle(progress.isUnlocked ? Theme.leafFill : Theme.inkSoft)
            }
            .font(Theme.font(11, .semibold))
            .monospacedDigit()

            // 解锁后的占位保持卡片高度稳定，不再显示进行中的进度条。
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.ink.opacity(0.1))
                    Capsule().fill(Theme.tomatoFill)
                        .frame(width: geometry.size.width * progress.fraction)
                }
            }
            .frame(height: 3)
            .opacity(progress.isUnlocked ? 0 : 1)
        }
        // 单卡约 106 点高，固定窗口内能完整看到前三排成就。
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .fill(Theme.creamDeep.opacity(0.6))
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: achievement.accessibilityText(progress: progress)))
    }

    @ViewBuilder
    private var avatar: some View {
        if progress.isUnlocked {
            TomatoAvatar(size: 30)
        } else {
            Group {
                if let image = LockedAchievementAvatar.image {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.high)
                } else {
                    // 素材不可用时仍显示灰色轮廓，不回退成已解锁的红色头像。
                    Image("Tomato")
                        .renderingMode(.template)
                        .resizable()
                        .interpolation(.high)
                        .foregroundStyle(Color(white: 0.7))
                }
            }
            .scaledToFit()
            .frame(width: 30, height: 30)
            .accessibilityHidden(true)
        }
    }
}
