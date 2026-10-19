import AppKit
import QuartzCore
import SwiftUI

/// 把阶段与本轮实际时长一同传入，避免把重来或阶段切换误认为正常倒计时。
struct RingAnimationState: Equatable {
    var remaining: Double
    var phase: EyeBreakModel.Phase
    var duration: TimeInterval
}

enum RingAnimationPolicy {
    /// 只平滑同阶段的小幅递减；允许偶尔漏过两次刷新，较大的时间校正直接定位。
    static func shouldAnimate(
        previous: RingAnimationState?, current: RingAnimationState, reduceMotion: Bool
    ) -> Bool {
        guard !reduceMotion, let previous,
              current.phase == previous.phase,
              current.phase == .working || current.phase == .resting,
              current.duration.isFinite, current.duration > 0,
              current.duration == previous.duration,
              previous.remaining.isFinite, current.remaining.isFinite else { return false }
        let decrease = previous.remaining - current.remaining
        return decrease > 0 && decrease <= 3 / current.duration + 1e-9
    }
}

private struct RingSnapshotRenderingKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// ImageRenderer 不包含 AppKit 图层；离屏导出显式启用静态 SwiftUI 进度弧。
    var ringSnapshotRendering: Bool {
        get { self[RingSnapshotRenderingKey.self] }
        set { self[RingSnapshotRenderingKey.self] = newValue }
    }
}

/// 底圈和中心内容保持静态，进度弧的逐帧插值由渲染服务完成。
struct RingView<Content: View>: View {
    var remaining: Double
    var color: Color
    var lineWidth: CGFloat = 12
    var phase: EyeBreakModel.Phase
    var duration: TimeInterval
    var isActive = true
    var animationResetID = 0
    @ViewBuilder var content: Content
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.ringSnapshotRendering) private var snapshotRendering

    var body: some View {
        ZStack {
            Circle().stroke(Theme.creamDeep, lineWidth: lineWidth)
            if snapshotRendering {
                Circle()
                    .trim(from: 0, to: min(1, max(0, remaining)))
                    .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            } else {
                RingProgressView(
                    state: RingAnimationState(remaining: remaining, phase: phase, duration: duration),
                    color: color, lineWidth: lineWidth, reduceMotion: reduceMotion,
                    isActive: isActive, animationResetID: animationResetID
                )
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
            content
        }
    }
}

private struct RingProgressView: NSViewRepresentable {
    var state: RingAnimationState
    var color: Color
    var lineWidth: CGFloat
    var reduceMotion: Bool
    var isActive: Bool
    var animationResetID: Int

    func makeNSView(context: Context) -> RingProgressNSView { RingProgressNSView() }

    func updateNSView(_ view: RingProgressNSView, context: Context) {
        view.update(
            state: state, color: NSColor(color), lineWidth: lineWidth,
            reduceMotion: reduceMotion, animationsAllowed: !context.transaction.disablesAnimations,
            isActive: isActive, animationResetID: animationResetID
        )
    }

    static func dismantleNSView(_ view: RingProgressNSView, coordinator: ()) {
        view.progressLayer.removeAllAnimations()
    }
}

@MainActor
final class RingProgressNSView: NSView {
    let progressLayer = CAShapeLayer()
    private var previousState: RingAnimationState?
    private var strokeColor = NSColor.clear
    private var pathBounds = CGRect.null
    private var isActive = true
    private var animationResetID = 0

    // 翻转坐标后，-π/2 位于正上方，正向完整圆弧按屏幕顺时针绘制。
    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        // macOS 13 默认裁切 NSView，显式保留与底圈一致的外半条描边。
        clipsToBounds = false
        wantsLayer = true
        layer?.masksToBounds = false
        progressLayer.fillColor = nil
        progressLayer.lineCap = .round
        progressLayer.strokeEnd = 0
        layer?.addSublayer(progressLayer)
    }

    convenience init() { self.init(frame: .zero) }
    required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        guard isActive else { return }
        updatePath()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        guard isActive else { return }
        updateBackingScale()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        guard isActive else { return }
        updateColor()
    }

    func update(
        state: RingAnimationState, color: NSColor, lineWidth: CGFloat,
        reduceMotion: Bool, animationsAllowed: Bool, isActive: Bool = true, animationResetID: Int = 0
    ) {
        guard isActive else {
            if self.isActive {
                self.isActive = false
                previousState = nil
                progressLayer.removeAllAnimations()
            }
            return
        }
        // 重开菜单的第一帧直接采用最新进度，即使只漏过一秒，也不补播隐藏期间的动画。
        if !self.isActive {
            self.isActive = true
            previousState = nil
        }
        // 宿主可能合并隐藏期间的 SwiftUI 更新；重新打开的代号仍保证首帧不补播。
        if self.animationResetID != animationResetID {
            self.animationResetID = animationResetID
            previousState = nil
        }
        updateBackingScale()
        strokeColor = color
        updateColor()
        withoutImplicitAnimations { progressLayer.lineWidth = lineWidth }
        updatePath()

        // 配色或其他环境刷新不能重启正在运行的一秒动画；暂停和减少动态效果立即停住。
        guard state != previousState || reduceMotion || !animationsAllowed else { return }
        let target = CGFloat(state.remaining.isFinite ? min(1, max(0, state.remaining)) : 0)
        let shouldAnimate = animationsAllowed && RingAnimationPolicy.shouldAnimate(
            previous: previousState, current: state, reduceMotion: reduceMotion
        )
        let displayed = progressLayer.presentation()?.strokeEnd ?? progressLayer.strokeEnd
        previousState = state
        withoutImplicitAnimations {
            progressLayer.removeAnimation(forKey: "countdown")
            progressLayer.strokeEnd = target
            if shouldAnimate {
                let animation = CABasicAnimation(keyPath: "strokeEnd")
                animation.fromValue = displayed
                animation.toValue = target
                animation.duration = 1
                animation.timingFunction = CAMediaTimingFunction(name: .linear)
                progressLayer.add(animation, forKey: "countdown")
            }
        }
    }

    private func updatePath() {
        guard bounds != pathBounds else { return }
        pathBounds = bounds
        let path = CGMutablePath()
        // 与 SwiftUI Circle.stroke 一样，路径位于布局边界，描边向两侧各延伸半条线宽。
        path.addArc(
            center: CGPoint(x: bounds.width / 2, y: bounds.height / 2),
            radius: max(0, min(bounds.width, bounds.height) / 2),
            startAngle: -.pi / 2, endAngle: .pi * 1.5, clockwise: false
        )
        withoutImplicitAnimations {
            progressLayer.frame = bounds
            progressLayer.path = path
        }
    }

    private func updateColor() {
        // 动态 NSColor 不能缓存 CGColor；阶段、窗口外观变化时都按有效外观重新解析。
        effectiveAppearance.performAsCurrentDrawingAppearance {
            withoutImplicitAnimations { progressLayer.strokeColor = strokeColor.cgColor }
        }
    }

    private func updateBackingScale() {
        let scale = window?.backingScaleFactor ?? 2
        guard progressLayer.contentsScale != scale else { return }
        withoutImplicitAnimations { progressLayer.contentsScale = scale }
    }

    private func withoutImplicitAnimations(_ changes: () -> Void) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        changes()
        CATransaction.commit()
    }
}
