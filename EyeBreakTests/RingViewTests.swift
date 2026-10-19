import AppKit
import QuartzCore
import SwiftUI
import Testing
@testable import EyeBreak

@MainActor
struct RingViewTests {
    @Test("首次显示直接定位，不从空圈开始播放")
    func firstAppearanceDoesNotAnimate() {
        #expect(!RingAnimationPolicy.shouldAnimate(previous: nil, current: state(0.5), reduceMotion: false))
    }

    @Test("专注和休息的正常一秒倒计时都平滑插值")
    func oneSecondStepAnimates() {
        for phase in [EyeBreakModel.Phase.working, .resting] {
            #expect(RingAnimationPolicy.shouldAnimate(
                previous: state(0.5, phase: phase), current: state(0.45, phase: phase), reduceMotion: false
            ))
        }
    }

    @Test("时间大跳变、同阶段重来和时长改变都直接定位")
    func resetsAndLargeCorrectionsDoNotAnimate() {
        let previous = state(0.5)
        for current in [state(0.2), state(1), state(0.45, duration: 60)] {
            #expect(!RingAnimationPolicy.shouldAnimate(previous: previous, current: current, reduceMotion: false))
        }
    }

    @Test("漏过三秒仍可连续插值，超过三秒直接定位")
    func normalStepBoundary() {
        let previous = state(0.5)
        #expect(RingAnimationPolicy.shouldAnimate(previous: previous, current: state(0.35), reduceMotion: false))
        #expect(!RingAnimationPolicy.shouldAnimate(previous: previous, current: state(0.349), reduceMotion: false))
    }

    @Test("阶段切换、暂停和静止刷新都不启动动画")
    func phaseChangesAndPausedStatesDoNotAnimate() {
        let previous = state(0.5)
        #expect(!RingAnimationPolicy.shouldAnimate(previous: previous, current: state(0.45, phase: .resting), reduceMotion: false))
        #expect(!RingAnimationPolicy.shouldAnimate(previous: previous, current: state(0.45, phase: .paused), reduceMotion: false))
        #expect(!RingAnimationPolicy.shouldAnimate(previous: state(0.5, phase: .paused), current: state(0.45, phase: .paused), reduceMotion: false))
        #expect(!RingAnimationPolicy.shouldAnimate(previous: previous, current: previous, reduceMotion: false))
    }

    @Test("减少动态效果覆盖正常一秒步长")
    func reducedMotionDoesNotAnimate() {
        #expect(!RingAnimationPolicy.shouldAnimate(previous: state(0.5), current: state(0.45), reduceMotion: true))
    }

    @Test("无效时长和非有限进度不能启动动画")
    func invalidValuesDoNotAnimate() {
        for duration in [0.0, -1, .infinity, .nan] {
            #expect(!RingAnimationPolicy.shouldAnimate(
                previous: state(0.5, duration: duration), current: state(0.45, duration: duration), reduceMotion: false
            ))
        }
        #expect(!RingAnimationPolicy.shouldAnimate(previous: state(.nan), current: state(0.45), reduceMotion: false))
        #expect(!RingAnimationPolicy.shouldAnimate(previous: state(0.5), current: state(.infinity), reduceMotion: false))
    }

    @Test("原生进度弧保持十二点起点、顺时针、圆头和指定线宽")
    func nativePathMatchesRingGeometry() throws {
        let view = nativeView()
        view.update(state: state(0.25), color: .red, lineWidth: 10, reduceMotion: false, animationsAllowed: true)
        let path = try #require(view.progressLayer.path)
        var start: CGPoint?
        var firstCurveControl: CGPoint?
        path.applyWithBlock { pointer in
            let element = pointer.pointee
            if element.type == .moveToPoint && start == nil { start = element.points[0] }
            if element.type == .addCurveToPoint && firstCurveControl == nil { firstCurveControl = element.points[0] }
        }
        let origin = try #require(start)
        let control = try #require(firstCurveControl)
        #expect(abs(origin.x - 50) < 0.001)
        #expect(abs(origin.y - (view.isFlipped ? 0 : 100)) < 0.001)
        // 从顶部先向右延伸，才是屏幕坐标中的顺时针。
        #expect(control.x > origin.x)
        #expect(view.progressLayer.lineCap == .round)
        #expect(!view.clipsToBounds)
        #expect(view.layer?.masksToBounds == false)
        #expect(view.progressLayer.lineWidth == 10)
        #expect(view.progressLayer.strokeEnd == 0.25)
        #expect(view.progressLayer.animationKeys()?.isEmpty ?? true)
    }

    @Test("一秒步长由 Core Animation 线性插值，环境刷新不重启动画")
    func nativeAnimationProperties() throws {
        let view = nativeView()
        view.update(state: state(0.5), color: .red, lineWidth: 10, reduceMotion: false, animationsAllowed: true)
        view.update(state: state(0.45), color: .red, lineWidth: 10, reduceMotion: false, animationsAllowed: true)
        // 同一帧的外观或颜色刷新不能把起点改成已写入模型层的终点。
        view.update(state: state(0.45), color: .blue, lineWidth: 10, reduceMotion: false, animationsAllowed: true)
        let key = try #require(view.progressLayer.animationKeys()?.first)
        let animation = try #require(view.progressLayer.animation(forKey: key) as? CABasicAnimation)
        #expect(animation.keyPath == "strokeEnd")
        #expect(animation.duration == 1)
        #expect(abs(try #require(animation.fromValue as? Double) - 0.5) < 0.0001)
        #expect(abs(try #require(animation.toValue as? Double) - 0.45) < 0.0001)
        #expect(abs(view.progressLayer.strokeEnd - 0.45) < 0.0001)
        let timing = try #require(animation.timingFunction)
        var firstControl = [Float](repeating: 0, count: 2)
        var secondControl = [Float](repeating: 0, count: 2)
        timing.getControlPoint(at: 1, values: &firstControl)
        timing.getControlPoint(at: 2, values: &secondControl)
        #expect(firstControl[0] == firstControl[1])
        #expect(secondControl[0] == secondControl[1])
    }

    @Test("暂停、减少动态效果和禁止动画事务立即移除旧动画", arguments: ["paused", "reducedMotion", "transaction"])
    func interruptedAnimationsStop(reason: String) {
        let view = nativeView()
        view.update(state: state(0.5), color: .red, lineWidth: 10, reduceMotion: false, animationsAllowed: true)
        view.update(state: state(0.45), color: .red, lineWidth: 10, reduceMotion: false, animationsAllowed: true)
        view.update(
            state: state(0.45, phase: reason == "paused" ? .paused : .working), color: .red, lineWidth: 10,
            reduceMotion: reason == "reducedMotion", animationsAllowed: reason != "transaction"
        )
        #expect(view.progressLayer.animationKeys()?.isEmpty ?? true)
        #expect(abs(view.progressLayer.strokeEnd - 0.45) < 0.0001)
    }

    @Test("动态描边颜色在外观回调时按当前 effectiveAppearance 重新解析")
    func nativeColorTracksAppearance() throws {
        let view = nativeView()
        let light = try #require(NSAppearance(named: .aqua))
        let dark = try #require(NSAppearance(named: .darkAqua))
        view.appearance = light
        view.update(state: state(0.5), color: NSColor(Theme.ink), lineWidth: 10, reduceMotion: false, animationsAllowed: true)
        let lightColor = try #require(view.progressLayer.strokeColor)
        view.appearance = dark
        view.viewDidChangeEffectiveAppearance()
        let darkColor = try #require(view.progressLayer.strokeColor)
        #expect(lightColor != darkColor)
        var expectedDark: CGColor?
        dark.performAsCurrentDrawingAppearance { expectedDark = NSColor(Theme.ink).cgColor }
        #expect(darkColor == expectedDark)
    }

    @Test("隐藏圆环停止动画且完全冻结图层，重开首帧直接定位后恢复平滑")
    func hiddenRingDoesNotUpdateLayersAndResumesWithoutAnimation() throws {
        let view = nativeView()
        view.update(state: state(0.5), color: .red, lineWidth: 10, reduceMotion: false, animationsAllowed: true)
        view.update(state: state(0.45), color: .red, lineWidth: 10, reduceMotion: false, animationsAllowed: true)
        #expect(!(view.progressLayer.animationKeys()?.isEmpty ?? true))

        view.update(
            state: state(0.45), color: .red, lineWidth: 10,
            reduceMotion: false, animationsAllowed: true, isActive: false
        )
        #expect(view.progressLayer.animationKeys()?.isEmpty ?? true)
        let color = try #require(view.progressLayer.strokeColor)
        let pathBounds = try #require(view.progressLayer.path).boundingBox
        let layerFrame = view.progressLayer.frame
        let scale = view.progressLayer.contentsScale
        view.update(
            state: state(0.4), color: .blue, lineWidth: 20,
            reduceMotion: false, animationsAllowed: true, isActive: false
        )
        view.frame.size = NSSize(width: 120, height: 120)
        view.layout()
        view.viewDidChangeEffectiveAppearance()
        view.viewDidChangeBackingProperties()
        #expect(view.progressLayer.strokeEnd == 0.45)
        #expect(view.progressLayer.strokeColor == color)
        #expect(view.progressLayer.lineWidth == 10)
        #expect(view.progressLayer.path?.boundingBox == pathBounds)
        #expect(view.progressLayer.frame == layerFrame)
        #expect(view.progressLayer.contentsScale == scale)
        #expect(view.progressLayer.animationKeys()?.isEmpty ?? true)

        // 只漏过一秒也不能补播；下一次正常 tick 才恢复插值。
        view.update(state: state(0.4), color: .blue, lineWidth: 10, reduceMotion: false, animationsAllowed: true)
        #expect(view.progressLayer.strokeEnd == 0.4)
        #expect(view.progressLayer.animationKeys()?.isEmpty ?? true)
        view.update(state: state(0.35), color: .blue, lineWidth: 10, reduceMotion: false, animationsAllowed: true)
        #expect(!(view.progressLayer.animationKeys()?.isEmpty ?? true))
    }

    @Test("宿主合并隐藏帧时，重新显示的代号仍禁止补播一秒动画")
    func resumeGenerationResetsAnimationWithoutHiddenRender() {
        let view = nativeView()
        view.update(state: state(0.5), color: .red, lineWidth: 10, reduceMotion: false, animationsAllowed: true)
        view.update(state: state(0.45), color: .red, lineWidth: 10, reduceMotion: false, animationsAllowed: true)
        #expect(!(view.progressLayer.animationKeys()?.isEmpty ?? true))
        // 不调用 isActive=false，模拟 SwiftUI 没有绘制隐藏帧便重新打开菜单。
        view.update(
            state: state(0.4), color: .red, lineWidth: 10,
            reduceMotion: false, animationsAllowed: true, animationResetID: 1
        )
        #expect(view.progressLayer.strokeEnd == 0.4)
        #expect(view.progressLayer.animationKeys()?.isEmpty ?? true)
        view.update(
            state: state(0.35), color: .red, lineWidth: 10,
            reduceMotion: false, animationsAllowed: true, animationResetID: 1
        )
        #expect(!(view.progressLayer.animationKeys()?.isEmpty ?? true))
    }

    @Test("ImageRenderer 的静态回退包含当前四分之一进度弧")
    func imageRendererIncludesCurrentProgress() throws {
        let renderer = ImageRenderer(content: ring(snapshot: true))
        renderer.scale = 1
        let image = try #require(renderer.cgImage)
        try expectQuarterArc(in: NSBitmapImageRep(cgImage: image))
    }

    @Test("NSHostingView 的 cacheDisplay 原生图层和快照回退都包含当前进度弧", arguments: [false, true])
    func cacheDisplaySnapshotIncludesCurrentProgress(snapshot: Bool) async throws {
        let host = NSHostingView(rootView: ring(snapshot: snapshot))
        host.frame = NSRect(x: 0, y: 0, width: 100, height: 100)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.close() }
        host.layoutSubtreeIfNeeded()
        await Task.yield()
        host.layoutSubtreeIfNeeded()
        host.displayIfNeeded()
        let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        try expectQuarterArc(in: bitmap)
    }

    private func state(
        _ remaining: Double, phase: EyeBreakModel.Phase = .working, duration: TimeInterval = 20
    ) -> RingAnimationState {
        RingAnimationState(remaining: remaining, phase: phase, duration: duration)
    }

    private func nativeView() -> RingProgressNSView {
        RingProgressNSView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
    }

    private func ring(snapshot: Bool) -> some View {
        RingView(remaining: 0.25, color: Color(red: 1, green: 0, blue: 0), lineWidth: 10, phase: .resting, duration: 20) {
            Color.clear
        }
        .frame(width: 100, height: 100)
        .background(Color.white)
        .environment(\.ringSnapshotRendering, snapshot)
        .transaction { $0.disablesAnimations = true }
    }

    /// 真正检查输出像素，避免只验证图层模型值却漏掉离屏导出中的空白进度弧。
    private func expectQuarterArc(in bitmap: NSBitmapImageRep) throws {
        var leftRedPixels = 0
        var rightRedPixels = 0
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
                let color = try #require(bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB))
                // 测试宿主的位图带色彩管理，纯红会读成约 (0.86, 0.39, 0.19)；只要求明显偏红，且区别于白底和奶油色底圈。
                if color.redComponent > 0.7 && color.redComponent - color.blueComponent > 0.4 && color.redComponent - color.greenComponent > 0.3 {
                    if x < bitmap.pixelsWide / 2 { leftRedPixels += 1 } else { rightRedPixels += 1 }
                }
            }
        }
        #expect(rightRedPixels > bitmap.pixelsWide)
        #expect(rightRedPixels > leftRedPixels * 5)
    }
}
