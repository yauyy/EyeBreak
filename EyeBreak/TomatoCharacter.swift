import SwiftUI

/// 用 SwiftUI 绘制的番茄仔（与图标同款画风），眼睛和身体可以做动作。
/// 在 100×100 的坐标系里绘制，按实际尺寸缩放。
struct TomatoCharacter: View {
    enum Motion {
        case still
        /// 眼珠慢慢往远处飘、再回来
        case lookFar
        /// 有节奏地眨眼
        case blink
        /// 闭着眼，身体随呼吸轻轻起伏
        case closeEyes
        /// 眼珠画圈
        case rollEyes
    }

    var motion: Motion
    var size: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: nil, paused: reduceMotion || motion == .still)) { timeline in
            Canvas { context, canvasSize in
                // 减少动态效果时停在第 0 秒：保留表情，不做动作
                let t = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
                draw(in: context, scale: canvasSize.width / 100, t: t)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private static let ink = Color(red: 0.29, green: 0.20, blue: 0.16)
    private static let leaf = Color(red: 0.36, green: 0.80, blue: 0.43)
    private static let leafDeep = Color(red: 0.24, green: 0.62, blue: 0.32)

    private func draw(in context: GraphicsContext, scale: CGFloat, t: Double) {
        var ctx = context
        ctx.scaleBy(x: scale, y: scale)

        if motion == .closeEyes {
            // 以底部为支点，随 4 秒一次的呼吸轻轻伸缩
            let breathe = sin(t * 2 * .pi / 4)
            ctx.translateBy(x: 50, y: 93)
            ctx.scaleBy(x: 1 - 0.015 * breathe, y: 1 + 0.03 * breathe)
            ctx.translateBy(x: -50, y: -93)
        }

        drawBody(ctx)
        drawLeaves(ctx)
        drawFace(ctx, t: t)
    }

    private func drawBody(_ ctx: GraphicsContext) {
        let body = Path(ellipseIn: CGRect(x: 12, y: 27, width: 76, height: 66))
        // 先画两倍宽的描边、再填充，只留下外侧的一圈粗描边
        ctx.stroke(body, with: .color(Self.ink), lineWidth: 4.8)
        ctx.fill(body, with: .radialGradient(
            Gradient(colors: [Color(red: 1, green: 0.60, blue: 0.51), Color(red: 0.94, green: 0.27, blue: 0.23)]),
            center: CGPoint(x: 40, y: 46), startRadius: 2, endRadius: 46
        ))
        var highlight = ctx
        highlight.translateBy(x: 37, y: 45)
        highlight.rotate(by: .degrees(-32))
        highlight.fill(Path(ellipseIn: CGRect(x: -6.5, y: -3.2, width: 13, height: 6.4)), with: .color(.white.opacity(0.55)))
        ctx.fill(Path(ellipseIn: CGRect(x: 42, y: 39, width: 2.6, height: 2.6)), with: .color(.white.opacity(0.7)))
    }

    private func drawLeaves(_ ctx: GraphicsContext) {
        let stem = Path { p in
            p.move(to: CGPoint(x: 50, y: 30))
            p.addQuadCurve(to: CGPoint(x: 54, y: 15.5), control: CGPoint(x: 49.2, y: 21))
        }
        ctx.stroke(stem, with: .color(Self.ink), style: StrokeStyle(lineWidth: 6.4, lineCap: .round))

        let petals = Path { p in
            for angle in stride(from: -144.0, through: 144, by: 72) {
                let a = (angle - 90) * .pi / 180
                let center = CGPoint(x: 50 + cos(a) * 8.4, y: 31 + sin(a) * 8.4)
                let petal = Path(ellipseIn: CGRect(x: -9.6, y: -3.9, width: 19.2, height: 7.8))
                p.addPath(petal, transform: CGAffineTransform(translationX: center.x, y: center.y).rotated(by: a))
            }
        }
        ctx.stroke(petals, with: .color(Self.ink), style: StrokeStyle(lineWidth: 4.4, lineJoin: .round))
        ctx.fill(petals, with: .color(Self.leaf))
        ctx.stroke(stem, with: .color(Self.leafDeep), style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
    }

    private func drawFace(_ ctx: GraphicsContext, t: Double) {
        var look = CGSize.zero
        var openness = 1.0
        switch motion {
        case .still, .closeEyes:
            break
        case .lookFar:
            look = CGSize(width: 1.8 * sin(t * 0.8), height: -1.2)
        case .blink:
            // 每 2.4 秒眨一次眼，闭合与睁开各约 0.12 秒
            let phase = t.truncatingRemainder(dividingBy: 2.4)
            if phase < 0.12 { openness = 1 - phase / 0.12 } else if phase < 0.24 { openness = (phase - 0.12) / 0.12 }
        case .rollEyes:
            look = CGSize(width: 2 * cos(t * 1.6), height: 2 * sin(t * 1.6))
        }

        for x: Double in [37, 63] {
            if motion == .closeEyes || openness < 0.2 {
                closedEye(ctx, x: x, y: 60)
            } else {
                openEye(ctx, x: x + look.width, y: 60 + look.height, openness: openness)
            }
        }

        for x: Double in [28, 72] {
            ctx.fill(Path(ellipseIn: CGRect(x: x - 5.8, y: 66.5, width: 11.6, height: 6.4)), with: .color(Color(red: 1, green: 0.43, blue: 0.55).opacity(0.42)))
        }

        let mouth = Path { p in
            p.move(to: CGPoint(x: 46.6, y: 67.5))
            p.addQuadCurve(to: CGPoint(x: 50, y: 67.5), control: CGPoint(x: 48.3, y: 71))
            p.addQuadCurve(to: CGPoint(x: 53.4, y: 67.5), control: CGPoint(x: 51.7, y: 71))
        }
        ctx.stroke(mouth, with: .color(Self.ink), style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
    }

    private func openEye(_ context: GraphicsContext, x: Double, y: Double, openness: Double) {
        var ctx = context
        ctx.translateBy(x: x, y: y)
        ctx.scaleBy(x: 1, y: max(0.1, openness))
        let eye = Path(ellipseIn: CGRect(x: -5.6, y: -6.9, width: 11.2, height: 13.8))
        ctx.fill(eye, with: .color(Color(red: 0.23, green: 0.16, blue: 0.13)))
        var shine = ctx
        shine.clip(to: eye)
        shine.fill(Path(ellipseIn: CGRect(x: -5.3, y: 2.2, width: 10.6, height: 7)), with: .color(.white.opacity(0.2)))
        ctx.fill(Path(ellipseIn: CGRect(x: -4, y: -4.7, width: 4.6, height: 4.4)), with: .color(.white))
        ctx.fill(Path(ellipseIn: CGRect(x: 1.1, y: 1.3, width: 1.9, height: 1.9)), with: .color(.white))
    }

    private func closedEye(_ ctx: GraphicsContext, x: Double, y: Double) {
        let arc = Path { p in
            p.move(to: CGPoint(x: x - 5.4, y: y))
            p.addQuadCurve(to: CGPoint(x: x + 5.4, y: y), control: CGPoint(x: x, y: y + 5.6))
        }
        ctx.stroke(arc, with: .color(Self.ink), style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
    }
}

extension RestExercise {
    var motion: TomatoCharacter.Motion {
        switch self {
        case .lookFar: return .lookFar
        case .blink: return .blink
        case .closeEyes: return .closeEyes
        case .rollEyes: return .rollEyes
        }
    }
}
