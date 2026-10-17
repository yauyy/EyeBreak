import AppKit
import SwiftUI

/// 与番茄仔图标一致的 Q 版配色：奶油底、番茄红、叶子绿、深棕描边色。
/// 跟随 App 的有效外观：深色模式下是「夜间番茄」，深可可底、奶油白文字，番茄红和叶子绿稍微提亮。
enum Theme {
    static let tomato = dynamic(light: (0.94, 0.33, 0.27), dark: (1.00, 0.42, 0.34))
    static let tomatoDeep = dynamic(light: (0.56, 0.16, 0.13), dark: (0.52, 0.18, 0.14))
    static let leaf = dynamic(light: (0.30, 0.73, 0.40), dark: (0.38, 0.80, 0.47))
    /// 白字专用填充色：保留番茄红、叶子绿的色相，深浅外观下的对比度都至少为 4.5:1。
    static let tomatoFill = dynamic(light: (0.79, 0.28, 0.23), dark: (0.75, 0.31, 0.25))
    static let leafFill = dynamic(light: (0.21, 0.51, 0.28), dark: (0.24, 0.51, 0.30))
    /// 页面底色
    static let cream = dynamic(light: (1.00, 0.97, 0.94), dark: (0.16, 0.13, 0.11))
    /// 卡片底色
    static let creamDeep = dynamic(light: (1.00, 0.91, 0.85), dark: (0.24, 0.19, 0.16))
    /// 按钮、加减号等小控件的表面色
    static let surface = dynamic(light: (1.00, 1.00, 1.00), dark: (0.31, 0.25, 0.21))
    static let ink = dynamic(light: (0.29, 0.20, 0.16), dark: (0.97, 0.91, 0.86))
    static let inkSoft = ink.opacity(0.55)
    /// 提醒面板上的波点
    static let dot = Color(nsColor: NSColor(name: nil) { appearance in
        isDark(appearance) ? NSColor.white.withAlphaComponent(0.05) : NSColor.white.withAlphaComponent(0.9)
    })

    private static func dynamic(light: (CGFloat, CGFloat, CGFloat), dark: (CGFloat, CGFloat, CGFloat)) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let c = isDark(appearance) ? dark : light
            return NSColor(srgbRed: c.0, green: c.1, blue: c.2, alpha: 1)
        })
    }

    private static func isDark(_ appearance: NSAppearance) -> Bool {
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }
    /// 未开始 / 暂停时的圆环：淡番茄色，比灰色更柔和
    static let tomatoSoft = tomato.opacity(0.35)

    static func font(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }

    /// 圆角规范：数值对齐 macOS 原生界面，统一使用 continuous（超椭圆）曲线。
    /// 控件贴着容器边角时保持同心：外层圆角 = 内层圆角 + 两者之间的间距。
    enum Radius {
        /// 按钮：macOS 大号按钮的圆角
        static let control: CGFloat = 8
        /// 小控件（加减按钮、分段控件里的选项）
        static let small: CGFloat = 6
        /// 分段控件外框：选项圆角 6 + 内边距 2
        static let segmented: CGFloat = small + Spacing.segmented
        /// 设置卡片：对齐「系统设置」里的分组卡片
        static let card: CGFloat = 12
        /// 休息提醒面板：底部按钮圆角 8 + 面板边距 12，接近 macOS 通知横幅
        static let panel: CGFloat = control + Spacing.panel
    }

    enum Spacing {
        /// 卡片内边距
        static let card: CGFloat = 12
        /// 休息提醒面板的左右和底部边距
        static let panel: CGFloat = 12
        /// 分段控件外框与选项之间的间距
        static let segmented: CGFloat = 2
    }

    /// 按钮的统一高度（macOS 大号控件）
    static let controlHeight: CGFloat = 32
    /// 小控件的统一尺寸
    static let smallControlSize: CGFloat = 24
}

/// 圆角按钮：底下垫一层深色，按下时下沉，保留一点 Q 版的立体感
struct PillButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary, plain }
    var kind: Kind = .primary
    /// 小号文字：用于菜单底部这类空间紧张的地方
    var small = false

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        return configuration.label
            .font(Theme.font(small ? 12 : 14, .semibold))
            .lineLimit(1)
            .fixedSize(horizontal: kind == .plain, vertical: false)
            .padding(.horizontal, kind == .plain ? (small ? 3 : 6) : 16)
            .padding(.vertical, kind == .plain ? 4 : 0)
            .frame(maxWidth: kind == .plain ? nil : .infinity)
            .frame(height: kind == .plain ? nil : Theme.controlHeight)
            .foregroundStyle(foreground)
            .background {
                if kind != .plain {
                    ZStack {
                        Self.shape.fill(base).offset(y: pressed ? 1 : 2)
                        Self.shape.fill(fill).offset(y: pressed ? 1 : 0)
                    }
                }
            }
            .scaleEffect(pressed ? 0.97 : 1)
            .animation(.spring(response: 0.22, dampingFraction: 0.6), value: pressed)
            .contentShape(Self.shape)
    }

    private var foreground: Color {
        switch kind {
        case .primary: return .white
        case .secondary: return Theme.ink
        case .plain: return Theme.inkSoft
        }
    }

    private static let shape = RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)

    private var fill: Color { kind == .primary ? Theme.tomatoFill : Theme.surface }
    private var base: Color { kind == .primary ? Theme.tomatoDeep : Theme.creamDeep }
}

/// 加减步进器
struct CuteStepper: View {
    let title: LocalizedStringKey
    let unit: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    let step: Int

    var body: some View {
        HStack(spacing: 10) {
            Text(title)
                .font(Theme.font(14, .medium))
                .foregroundStyle(Theme.ink)
            Spacer()
            roundButton("minus", enabled: value > range.lowerBound) {
                value = max(range.lowerBound, value - step)
            }
            Text(verbatim: "\(value) \(unit)")
                .font(Theme.font(14, .semibold))
                .monospacedDigit()
                .foregroundStyle(Theme.ink)
                .frame(minWidth: 52)
            roundButton("plus", enabled: value < range.upperBound) {
                value = min(range.upperBound, value + step)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(title))
        .accessibilityValue(Text(verbatim: "\(value) \(unit)"))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: value = min(range.upperBound, value + step)
            case .decrement: value = max(range.lowerBound, value - step)
            @unknown default: break
            }
        }
    }

    private func roundButton(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .heavy))
                .foregroundStyle(enabled ? Theme.tomato : Theme.inkSoft)
                .frame(width: Theme.smallControlSize, height: Theme.smallControlSize)
                .background(RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous).fill(Theme.surface))
                .overlay(RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous).strokeBorder(Theme.creamDeep, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.5)
    }
}

/// 番茄仔头像：不带图标底板的角色图（Assets 中的 Tomato，由 Design/icons-canvas 导出）
struct TomatoAvatar: View {
    var size: CGFloat

    var body: some View {
        Image("Tomato")
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// 胶囊开关：开启时番茄红，关闭时奶油色
struct CuteToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            HStack {
                configuration.label
                Spacer()
                ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                    Capsule()
                        .fill(configuration.isOn ? Theme.tomato : Theme.ink.opacity(0.15))
                        .frame(width: 40, height: Theme.smallControlSize)
                    // 开关保持 macOS 原生的胶囊形；圆点与外框同心：外框半径 12 = 圆点半径 10 + 间距 2
                    Circle()
                        .fill(.white)
                        .shadow(color: Theme.ink.opacity(0.15), radius: 1, y: 1)
                        .frame(width: Theme.smallControlSize - 4, height: Theme.smallControlSize - 4)
                        .padding(2)
                }
                .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isOn)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // 自绘外观保留原生开关的角色、标签、开关状态与辅助操作。
        .accessibilityRepresentation {
            Toggle(isOn: Binding(get: { configuration.isOn }, set: { configuration.isOn = $0 })) {
                configuration.label
            }
            .toggleStyle(.switch)
        }
    }
}
