import AppKit

@MainActor
enum MenuBarIcon {
    private static let iconSize: CGFloat = 18
    private static let gap: CGFloat = 4
    private static let font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .medium)
    private static let textAttributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.black]
    private static var icons: [String: NSImage] = [:]
    private static var lastComposition: (assetName: String, text: String, image: NSImage)?

    /// 把番茄仔和倒计时画成一张模板图：系统按菜单栏的深浅自动着色，与其他菜单栏图标保持一致。
    /// 画成一张图而不是「图标 + 文字」两个视图，是因为菜单栏标签里的组合视图在不同系统版本上显示不稳定。
    static func compose(assetName: String, text: String?) -> NSImage {
        let icon = cachedIcon(named: assetName)
        guard let text else { return icon }
        if let cached = lastComposition, cached.assetName == assetName, cached.text == text { return cached.image }

        let textSize = (text as NSString).size(withAttributes: textAttributes)
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
        (text as NSString).draw(at: NSPoint(x: iconSize + gap, y: (iconSize - textSize.height) / 2), withAttributes: textAttributes)
        NSGraphicsContext.restoreGraphicsState()

        let image = NSImage(size: size)
        image.addRepresentation(bitmap)
        image.isTemplate = true
        // 只保留最近一张合成图，避免长期计时累积成千上万张不同秒数的位图。
        lastComposition = (assetName, text, image)
        return image
    }

    private static func cachedIcon(named assetName: String) -> NSImage {
        if let icon = icons[assetName] { return icon }
        let icon = (NSImage(named: assetName)?.copy() as? NSImage) ?? NSImage()
        icon.isTemplate = true
        icon.size = NSSize(width: iconSize, height: iconSize)
        icons[assetName] = icon
        return icon
    }
}
