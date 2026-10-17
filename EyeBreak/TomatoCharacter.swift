import SwiftUI

/// 与图标同款画风的番茄仔，在 100×100 坐标系里演示护眼动作。
struct TomatoCharacter: View {
    enum Motion: CaseIterable, Equatable, Sendable {
        case still
        /// 抬手遮阳，望向右上方远处
        case lookFar
        /// 有节奏地眨眼，偶尔连眨两下
        case blink
        /// 双手轻捂眼睛外侧，露出闭眼弧线，随呼吸轻轻起伏
        case closeEyes
        /// 眼珠跟着带手臂的小手顺时针画圈
        case rollEyes
    }

    var motion: Motion
    var size: CGFloat
    /// 指定秒数可固定帧，便于与离线预览页逐帧对照；默认跟随时间播放。
    var time: TimeInterval? = nil
    /// nil 保持无限播放；有限播放在完整周期的末帧静止，避免切换代表帧时跳动。
    var loops: Int? = nil
    var replayID: Int = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var startedAt = Date()
    @State private var hasFinished = true
    @State private var suppressed = false
    @State private var stopTask: Task<Void, Never>?

    var body: some View {
        // 渲染闭包只捕获可发送的动作值和时间值，不捕获 View 或环境包装器。
        let currentMotion = motion
        let representative = TomatoRenderer.representativeTime(for: currentMotion)
        let frozenTime = reduceMotion ? representative : (time ?? (suppressed ? representative : nil))
        return TimelineView(.animation(paused: hasFinished || frozenTime != nil || currentMotion == .still)) { timeline in
            let elapsed = hasFinished ? TomatoPlayback.duration(for: currentMotion, loops: loops) : timeline.date.timeIntervalSince(startedAt)
            let seconds = frozenTime ?? TomatoPlayback.frame(motion: currentMotion, elapsed: elapsed, loops: loops).time
            Canvas { context, canvasSize in
                TomatoRenderer.draw(in: context, scale: canvasSize.width / 100, motion: currentMotion, t: seconds)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
        .onAppear(perform: replay)
        .onChange(of: motion) { _ in replay() }
        .onChange(of: replayID) { _ in replay() }
        .onChange(of: reduceMotion) { reduced in
            guard reduced else { return }
            // 关闭系统设置后仍保持本次静止，等待出现、换动作或悬停进入再重播。
            suppressed = true
            stop()
        }
        .onDisappear(perform: stop)
    }

    private func replay() {
        stop()
        startedAt = Date()
        suppressed = reduceMotion
        guard time == nil, !reduceMotion, motion != .still else { return }
        let initial = TomatoPlayback.frame(motion: motion, elapsed: 0, loops: loops)
        hasFinished = initial.isFinished
        guard !hasFinished, loops != nil else { return }
        let duration = TomatoPlayback.duration(for: motion, loops: loops)
        // 每次播放只有一次结束唤醒；倒计时及其他模型刷新不会重新创建任务。
        stopTask = Task { @MainActor in
            do { try await Task.sleep(for: .seconds(duration)) }
            catch { return }
            guard !Task.isCancelled else { return }
            hasFinished = true
            stopTask = nil
        }
    }

    private func stop() {
        stopTask?.cancel()
        stopTask = nil
        hasFinished = true
    }
}

/// 相对播放时间到绘制时间的纯计算；有限播放钳制在周期边界，减少动态优先取代表帧。
enum TomatoPlayback {
    struct Frame: Equatable, Sendable {
        let time: TimeInterval
        let isFinished: Bool
    }

    nonisolated static func cycleDuration(for motion: TomatoCharacter.Motion) -> TimeInterval {
        switch motion {
        case .still: return 0
        case .lookFar, .closeEyes: return 4
        case .blink: return 6.4
        case .rollEyes: return 3
        }
    }

    nonisolated static func duration(for motion: TomatoCharacter.Motion, loops: Int?) -> TimeInterval {
        cycleDuration(for: motion) * Double(max(0, loops ?? 0))
    }

    nonisolated static func frame(motion: TomatoCharacter.Motion, elapsed: TimeInterval, loops: Int?, reduceMotion: Bool = false) -> Frame {
        if reduceMotion { return Frame(time: TomatoRenderer.representativeTime(for: motion), isFinished: true) }
        if motion == .still { return Frame(time: 0, isFinished: true) }
        let elapsed = max(0, elapsed)
        guard loops != nil else { return Frame(time: elapsed, isFinished: false) }
        let end = duration(for: motion, loops: loops)
        return Frame(time: min(elapsed, end), isFinished: elapsed >= end)
    }
}

/// 无状态的绘制函数，与 Design/motion/tomato-motion.js 保持相同公式和图层顺序。
private enum TomatoRenderer {
    nonisolated private static let ink = Color(red: 74 / 255, green: 52 / 255, blue: 40 / 255)
    nonisolated private static let leaf = Color(red: 91 / 255, green: 203 / 255, blue: 110 / 255)
    nonisolated private static let leafDeep = Color(red: 62 / 255, green: 158 / 255, blue: 82 / 255)

    private struct Frame: Sendable {
        var lookX = 0.0
        var lookY = 0.0
        var closure = 0.0
        var gaze = 0.0
        var breath = 0.0
        var angle = 0.0
    }

    nonisolated static func representativeTime(for motion: TomatoCharacter.Motion) -> Double {
        switch motion {
        case .still, .closeEyes: return 0
        case .lookFar: return 1.8
        case .blink: return 0.78
        case .rollEyes: return 1.5
        }
    }

    nonisolated private static func phase(_ t: Double, duration: Double) -> Double {
        let remainder = t.truncatingRemainder(dividingBy: duration)
        return (remainder + duration).truncatingRemainder(dividingBy: duration)
    }

    nonisolated private static func ease(_ value: Double) -> Double {
        (1 - cos(.pi * max(0, min(1, value)))) / 2
    }

    nonisolated private static func circleAngle(_ t: Double) -> Double {
        let duration = TomatoPlayback.cycleDuration(for: .rollEyes)
        return -.pi / 2 + 2 * .pi * ease(phase(t, duration: duration) / duration)
    }

    nonisolated private static func frame(motion: TomatoCharacter.Motion, t: Double) -> Frame {
        var state = Frame()
        switch motion {
        case .still:
            break
        case .lookFar:
            let p = phase(t, duration: TomatoPlayback.cycleDuration(for: .lookFar))
            if p < 1.2 {
                state.gaze = ease(p / 1.2)
            } else if p < 2.3 {
                state.gaze = 1
            } else if p < 3.5 {
                state.gaze = 1 - ease((p - 2.3) / 1.2)
            }
            state.lookX = 3 * state.gaze
            state.lookY = -3 * state.gaze
        case .blink:
            // 每约两秒一次；6.4 秒循环内的最后一次补眨一下。
            let p = phase(t, duration: TomatoPlayback.cycleDuration(for: .blink))
            for start in [0.65, 2.65, 4.65, 5.03] {
                let d = p - start
                let closure: Double
                if d < 0 || d >= 0.28 {
                    closure = 0
                } else if d < 0.13 {
                    closure = ease(d / 0.13)
                } else {
                    closure = 1 - ease((d - 0.13) / 0.15)
                }
                state.closure = max(state.closure, closure)
            }
        case .closeEyes:
            let duration = TomatoPlayback.cycleDuration(for: .closeEyes)
            state.breath = (1 - cos(2 * .pi * phase(t, duration: duration) / duration)) / 2
        case .rollEyes:
            state.angle = circleAngle(t)
            state.lookX = 3 * cos(state.angle)
            state.lookY = 3 * sin(state.angle)
        }
        return state
    }

    nonisolated static func draw(in context: GraphicsContext, scale: CGFloat, motion: TomatoCharacter.Motion, t: Double) {
        let state = frame(motion: motion, t: t)
        var ctx = context
        ctx.scaleBy(x: scale, y: scale)
        if motion == .closeEyes {
            // 以身体底部为支点，4 秒完成一次吸气和呼气；手随身体一起伸缩。
            ctx.translateBy(x: 50, y: 93)
            ctx.scaleBy(x: 1 - 0.012 * state.breath, y: 1 + 0.025 * state.breath)
            ctx.translateBy(x: -50, y: -93)
        }
        if motion == .lookFar {
            // 屏幕坐标中正角度使上半身向右倾；脸、手臂和手掌一起倾斜。
            ctx.translateBy(x: 50, y: 93)
            ctx.rotate(by: .degrees(3.5 * state.gaze))
            ctx.translateBy(x: -50, y: -93)
        }
        drawBody(ctx)
        drawLeaves(ctx)
        drawFace(ctx, motion: motion, state: state)
        // 下半身根部的圆端与身体重叠；实心手臂盖在脸上，手掌最后绘制。
        switch motion {
        case .still, .blink:
            break
        case .lookFar:
            drawArm(ctx, rootX: 85, rootY: 74, bendX: 98, bendY: 58,
                    x: 68 + 2.8 * state.gaze, y: 43 - 3.7 * state.gaze)
        case .closeEyes:
            drawArm(ctx, rootX: 15, rootY: 74, bendX: 4, bendY: 64,
                    x: 26.5, y: 58 - 0.7 * state.breath)
            drawArm(ctx, rootX: 85, rootY: 74, bendX: 96, bendY: 64,
                    x: 73.5, y: 58 - 0.7 * state.breath)
        case .rollEyes:
            drawArm(ctx, rootX: 85, rootY: 74, bendX: 98, bendY: 58,
                    x: 83 + 7 * cos(state.angle), y: 48 + 8 * sin(state.angle))
        }
        if motion == .rollEyes { drawTrail(ctx, t: t) }
        switch motion {
        case .still, .blink:
            break
        case .lookFar:
            // 手下沿与移动后的眼睛顶部始终相隔约 2～3。
            drawHand(ctx, x: 68 + 2.8 * state.gaze, y: 43 - 3.7 * state.gaze, rotation: 8)
        case .closeEyes:
            let y = 58 - 0.7 * state.breath
            let rotation = atan2(y - 64, 22.5) * 180 / .pi
            drawHand(ctx, x: 26.5, y: y, rotation: rotation)
            drawHand(ctx, x: 73.5, y: y, rotation: -rotation)
        case .rollEyes:
            let x = 83 + 7 * cos(state.angle)
            let y = 48 + 8 * sin(state.angle)
            drawHand(ctx, x: x, y: y, rotation: atan2(y - 58, x - 98) * 180 / .pi)
        }
    }

    nonisolated private static func drawBody(_ ctx: GraphicsContext) {
        let body = Path(ellipseIn: CGRect(x: 12, y: 27, width: 76, height: 66))
        // 先描边再填充，只保留外侧的一圈粗描边。
        ctx.stroke(body, with: .color(ink), lineWidth: 4.8)
        fillTomato(ctx, path: body)
        fillEllipse(ctx, x: 37, y: 45, rx: 6.5, ry: 3.2, color: .white.opacity(0.55), rotation: -32)
        fillEllipse(ctx, x: 43.3, y: 40.3, rx: 1.3, ry: 1.3, color: .white.opacity(0.7))
    }

    nonisolated private static func fillTomato(_ ctx: GraphicsContext, path: Path) {
        ctx.fill(path, with: .radialGradient(
            Gradient(colors: [Color(red: 1, green: 154 / 255, blue: 130 / 255), Color(red: 240 / 255, green: 69 / 255, blue: 58 / 255)]),
            center: CGPoint(x: 40, y: 46), startRadius: 2, endRadius: 46
        ))
    }

    nonisolated private static func drawLeaves(_ ctx: GraphicsContext) {
        let petals = Path { p in
            for angle in [-144.0, -72, 0, 72, 144] {
                let a = (angle - 90) * .pi / 180
                let center = CGPoint(x: 50 + cos(a) * 8.4, y: 31 + sin(a) * 8.4)
                let petal = Path(ellipseIn: CGRect(x: -9.6, y: -3.9, width: 19.2, height: 7.8))
                p.addPath(petal, transform: CGAffineTransform(translationX: center.x, y: center.y).rotated(by: a))
            }
        }
        ctx.stroke(petals, with: .color(ink), style: StrokeStyle(lineWidth: 4.4, lineJoin: .round))
        ctx.fill(petals, with: .color(leaf))
        let stem = Path { p in
            p.move(to: CGPoint(x: 50, y: 30))
            p.addQuadCurve(to: CGPoint(x: 54, y: 15.5), control: CGPoint(x: 49.2, y: 21))
        }
        ctx.stroke(stem, with: .color(ink), style: StrokeStyle(lineWidth: 6.4, lineCap: .round))
        ctx.stroke(stem, with: .color(leafDeep), style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
    }

    nonisolated private static func drawFace(_ ctx: GraphicsContext, motion: TomatoCharacter.Motion, state: Frame) {
        for x: Double in [37, 63] {
            if motion == .closeEyes {
                closedEye(ctx, x: x, y: 60)
            } else {
                openEye(ctx, x: x + state.lookX, y: 60 + state.lookY, closure: state.closure)
            }
        }
        for x: Double in [28, 72] {
            fillEllipse(ctx, x: x, y: 69.7, rx: 5.8, ry: 3.2, color: Color(red: 1, green: 110 / 255, blue: 140 / 255).opacity(0.42))
        }
        let mouth = Path { p in
            p.move(to: CGPoint(x: 46.6, y: 67.5))
            p.addQuadCurve(to: CGPoint(x: 50, y: 67.5), control: CGPoint(x: 48.3, y: 71))
            p.addQuadCurve(to: CGPoint(x: 53.4, y: 67.5), control: CGPoint(x: 51.7, y: 71))
        }
        ctx.stroke(mouth, with: .color(ink), style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
    }

    nonisolated private static func openEye(_ context: GraphicsContext, x: Double, y: Double, closure: Double) {
        var ctx = context
        // 保持眼珠和高光原尺寸，用上下眼皮围成的开口裁切，避免把眼珠压扁。
        let top = y - 6.9 * (1 - closure)
        let bottom = y + 6.9 * (1 - closure)
        let opening = Path { p in
            p.move(to: CGPoint(x: x - 5.9, y: top))
            p.addQuadCurve(to: CGPoint(x: x + 5.9, y: top), control: CGPoint(x: x, y: top + 3 * closure))
            p.addLine(to: CGPoint(x: x + 5.9, y: bottom))
            p.addQuadCurve(to: CGPoint(x: x - 5.9, y: bottom), control: CGPoint(x: x, y: bottom + 3 * closure))
            p.closeSubpath()
        }
        ctx.clip(to: opening)
        let eye = Path(ellipseIn: CGRect(x: x - 5.6, y: y - 6.9, width: 11.2, height: 13.8))
        ctx.fill(eye, with: .color(Color(red: 59 / 255, green: 42 / 255, blue: 34 / 255)))
        var shine = ctx
        shine.clip(to: eye)
        fillEllipse(shine, x: x, y: y + 5.865, rx: 5.32, ry: 3.45, color: .white.opacity(0.2))
        fillEllipse(ctx, x: x - 1.568, y: y - 2.484, rx: 2.24, ry: 2.208, color: .white)
        fillEllipse(ctx, x: x + 2.016, y: y + 2.208, rx: 0.952, ry: 0.952, color: .white)
        if closure > 0 {
            let lid = Path { p in
                p.move(to: CGPoint(x: x - 5.4, y: top))
                p.addQuadCurve(to: CGPoint(x: x + 5.4, y: top), control: CGPoint(x: x, y: top + 3 * closure))
            }
            context.stroke(lid, with: .color(ink.opacity(closure)), style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
        }
    }

    nonisolated private static func closedEye(_ ctx: GraphicsContext, x: Double, y: Double) {
        let arc = Path { p in
            p.move(to: CGPoint(x: x - 5.4, y: y))
            p.addQuadCurve(to: CGPoint(x: x + 5.4, y: y), control: CGPoint(x: x, y: y + 5.6))
        }
        ctx.stroke(arc, with: .color(ink), style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
    }

    nonisolated private static func drawArm(_ ctx: GraphicsContext, rootX: Double, rootY: Double, bendX: Double, bendY: Double, x: Double, y: Double) {
        let arm = Path { p in
            p.move(to: CGPoint(x: rootX, y: rootY))
            p.addQuadCurve(to: CGPoint(x: x, y: y), control: CGPoint(x: bendX, y: bendY))
        }
        // 同一条二次曲线叠画成红色实心圆头管子，外沿保留深棕描边。
        ctx.stroke(arm, with: .color(ink), style: StrokeStyle(lineWidth: 11, lineCap: .round, lineJoin: .round))
        ctx.stroke(arm, with: .color(Color(red: 240 / 255, green: 69 / 255, blue: 58 / 255)),
                   style: StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round))
    }

    nonisolated private static func drawHand(_ context: GraphicsContext, x: Double, y: Double, rotation: Double) {
        var ctx = context
        ctx.translateBy(x: x, y: y)
        ctx.rotate(by: .degrees(rotation))
        // 横向椭圆手掌，宽高比 1.15；高光和底部暖色随手掌一起旋转。
        let hand = Path(ellipseIn: CGRect(x: -8.05, y: -7, width: 16.1, height: 14))
        ctx.fill(hand, with: .color(Color(red: 1, green: 253 / 255, blue: 248 / 255)))
        var clipped = ctx
        clipped.clip(to: hand)
        fillEllipse(clipped, x: 0, y: 4.1, rx: 7, ry: 2.6, color: Color(red: 244 / 255, green: 235 / 255, blue: 221 / 255))
        fillEllipse(clipped, x: -2.6, y: -3, rx: 2.8, ry: 1.6, color: .white, rotation: -32)
        ctx.stroke(hand, with: .color(ink), style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
    }

    nonisolated private static func drawTrail(_ ctx: GraphicsContext, t: Double) {
        // 按历史时间取样，与手使用同一缓动轨道；越远的点越小、越淡。
        for i in stride(from: 6, through: 1, by: -1) {
            let index = Double(i)
            let angle = circleAngle(t - index * 0.18)
            let radius = 2.2 - index * 0.16
            var dot = ctx
            dot.opacity = 0.9 - index * 0.08
            let point = Path(ellipseIn: CGRect(x: 83 + 7 * cos(angle) - radius, y: 48 + 8 * sin(angle) - radius,
                                             width: radius * 2, height: radius * 2))
            dot.fill(point, with: .color(Color(red: 1, green: 253 / 255, blue: 248 / 255)))
            dot.stroke(point, with: .color(ink), lineWidth: 0.65)
        }
    }

    nonisolated private static func fillEllipse(_ context: GraphicsContext, x: Double, y: Double, rx: Double, ry: Double, color: Color, rotation: Double = 0) {
        var ctx = context
        ctx.translateBy(x: x, y: y)
        ctx.rotate(by: .degrees(rotation))
        ctx.fill(Path(ellipseIn: CGRect(x: -rx, y: -ry, width: rx * 2, height: ry * 2)), with: .color(color))
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
