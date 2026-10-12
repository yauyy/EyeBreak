import AppKit

@MainActor
enum MenuBarIcon {
    private static let iconSize: CGFloat = 18
    private static let gap: CGFloat = 4
    private static let font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .medium)

    /// 把番茄仔和倒计时画成一张模板图：系统按菜单栏的深浅自动着色，与其他菜单栏图标保持一致。
    /// 画成一张图而不是「图标 + 文字」两个视图，是因为菜单栏标签里的组合视图在不同系统版本上显示不稳定。
    static func compose(icon: NSImage, text: String?) -> NSImage {
        guard let text else {
            icon.isTemplate = true
            icon.size = NSSize(width: iconSize, height: iconSize)
            return icon
        }

        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.black]
        let textSize = (text as NSString).size(withAttributes: attributes)
        let size = NSSize(width: iconSize + gap + ceil(textSize.width), height: iconSize)

        // 按 2 倍像素绘制，在 Retina 屏上保持清晰
        let scale: CGFloat = 2
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ) else { return icon }
        bitmap.size = size

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        icon.draw(in: NSRect(x: 0, y: 0, width: iconSize, height: iconSize))
        (text as NSString).draw(at: NSPoint(x: iconSize + gap, y: (iconSize - textSize.height) / 2), withAttributes: attributes)
        NSGraphicsContext.restoreGraphicsState()

        let image = NSImage(size: size)
        image.addRepresentation(bitmap)
        image.isTemplate = true
        return image
    }
}
