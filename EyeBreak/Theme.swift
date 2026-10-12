import SwiftUI

/// 与番茄仔图标一致的 Q 版配色：奶油底、番茄红、叶子绿、深棕描边色
enum Theme {
    static let tomato = Color(red: 0.94, green: 0.33, blue: 0.27)
    static let tomatoDeep = Color(red: 0.80, green: 0.22, blue: 0.18)
    static let leaf = Color(red: 0.30, green: 0.73, blue: 0.40)
    static let cream = Color(red: 1.00, green: 0.97, blue: 0.94)
    static let creamDeep = Color(red: 1.00, green: 0.91, blue: 0.85)
    static let ink = Color(red: 0.29, green: 0.20, blue: 0.16)
    static let inkSoft = Color(red: 0.29, green: 0.20, blue: 0.16).opacity(0.55)
    /// 未开始 / 暂停时的圆环：淡番茄色，比灰色更柔和
    static let tomatoSoft = Color(red: 0.94, green: 0.33, blue: 0.27).opacity(0.35)

    static func font(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
}

/// 胶囊按钮：底下垫一层深色，按下时下沉，像软软的果冻按钮
struct PillButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary, plain }
    var kind: Kind = .primary

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        return configuration.label
            .font(Theme.font(14, .semibold))
            .lineLimit(1)
            .padding(.horizontal, kind == .plain ? 6 : 16)
            .padding(.vertical, kind == .plain ? 4 : 9)
            .frame(maxWidth: kind == .plain ? nil : .infinity)
            .foregroundStyle(foreground)
            .background {
                if kind != .plain {
                    ZStack {
                        Capsule().fill(base).offset(y: pressed ? 1 : 3)
                        Capsule().fill(fill).offset(y: pressed ? 1 : 0)
                    }
                }
            }
            .scaleEffect(pressed ? 0.97 : 1)
            .animation(.spring(response: 0.22, dampingFraction: 0.6), value: pressed)
            .contentShape(Capsule())
    }

    private var foreground: Color {
        switch kind {
        case .primary: return .white
        case .secondary: return Theme.ink
        case .plain: return Theme.inkSoft
        }
    }

    private var fill: Color { kind == .primary ? Theme.tomato : .white }
    private var base: Color { kind == .primary ? Theme.tomatoDeep : Theme.creamDeep }
}

/// 圆环倒计时：剩余比例从满环逐渐变短
struct RingView<Content: View>: View {
    var remaining: Double
    var color: Color
    var lineWidth: CGFloat = 12
    @ViewBuilder var content: Content

    var body: some View {
        ZStack {
            Circle()
                .stroke(Theme.creamDeep, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: remaining)
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 1), value: remaining)
            content
        }
    }
}

/// 圆形加减步进器
struct CuteStepper: View {
    let title: String
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
            Text("\(value) \(unit)")
                .font(Theme.font(14, .semibold))
                .monospacedDigit()
                .foregroundStyle(Theme.ink)
                .frame(minWidth: 52)
            roundButton("plus", enabled: value < range.upperBound) {
                value = min(range.upperBound, value + step)
            }
        }
    }

    private func roundButton(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .heavy))
                .foregroundStyle(enabled ? Theme.tomato : Theme.inkSoft)
                .frame(width: 24, height: 24)
                .background(Circle().fill(.white))
                .overlay(Circle().strokeBorder(Theme.creamDeep, lineWidth: 1.5))
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
                        .frame(width: 40, height: 24)
                    Circle()
                        .fill(.white)
                        .shadow(color: Theme.ink.opacity(0.15), radius: 1, y: 1)
                        .frame(width: 20, height: 20)
                        .padding(2)
                }
                .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isOn)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
