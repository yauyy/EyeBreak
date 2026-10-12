import SwiftUI

/// 撒花动画：左右两侧各一门"礼花炮"向上斜射彩纸，受重力下落并翻转，约 2.6 秒后淡出。
struct ConfettiView: View {
    private struct Piece {
        let fromLeft: Bool
        let speed: Double
        let angle: Double
        let size: CGSize
        let color: Color
        let spin: Double
        let flip: Double
        let isCircle: Bool
        let delay: Double

        static func random() -> Piece {
            let fromLeft = Bool.random()
            return Piece(
                fromLeft: fromLeft,
                speed: .random(in: 380...680),
                angle: .random(in: 55...82) * .pi / 180,
                size: CGSize(width: .random(in: 6...10), height: .random(in: 3...6)),
                color: palette.randomElement()!,
                spin: .random(in: -9...9),
                flip: .random(in: 4...12),
                isCircle: Int.random(in: 0..<5) == 0,
                delay: .random(in: 0...0.25)
            )
        }

        static let palette: [Color] = [
            Color(red: 1.00, green: 0.42, blue: 0.42),
            Color(red: 1.00, green: 0.78, blue: 0.25),
            Color(red: 0.36, green: 0.80, blue: 0.43),
            Color(red: 0.36, green: 0.67, blue: 1.00),
            Color(red: 0.75, green: 0.52, blue: 1.00),
            Color(red: 1.00, green: 0.55, blue: 0.75),
        ]
    }

    private static let gravity = 620.0
    private static let duration = 2.6

    @State private var start = Date()
    @State private var pieces = (0..<110).map { _ in Piece.random() }

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let elapsed = timeline.date.timeIntervalSince(start)
                let fade = elapsed > Self.duration - 0.8 ? max(0, (Self.duration - elapsed) / 0.8) : 1
                guard fade > 0 else { return }

                for piece in pieces {
                    let t = elapsed - piece.delay
                    guard t > 0 else { continue }
                    let vx = cos(piece.angle) * piece.speed * (piece.fromLeft ? 1 : -1)
                    let vy = -sin(piece.angle) * piece.speed
                    let x = (piece.fromLeft ? 0 : size.width) + vx * t
                    let y = size.height + vy * t + 0.5 * Self.gravity * t * t

                    var ctx = context
                    ctx.opacity = fade
                    ctx.translateBy(x: x, y: y)
                    ctx.rotate(by: .radians(piece.spin * t))
                    // 绕水平轴翻转的错觉：宽度随时间周期性缩放
                    ctx.scaleBy(x: cos(piece.flip * t), y: 1)
                    let rect = CGRect(x: -piece.size.width / 2, y: -piece.size.height / 2, width: piece.size.width, height: piece.size.height)
                    let path = piece.isCircle ? Path(ellipseIn: rect.insetBy(dx: 0, dy: -1)) : Path(rect)
                    ctx.fill(path, with: .color(piece.color))
                }
            }
        }
    }
}
