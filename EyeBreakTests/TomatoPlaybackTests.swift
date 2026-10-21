import Testing
@testable import EyeBreak

struct TomatoPlaybackTests {
    @Test("每个动作的完整周期与绘制公式一致", arguments: [
        (TomatoCharacter.Motion.still, 0.0), (.lookFar, 4), (.blink, 6.4), (.closeEyes, 4), (.rollEyes, 3), (.drinkWater, 4), (.walk, 3.6)
    ])
    func completeCycles(motion: TomatoCharacter.Motion, expected: Double) {
        #expect(TomatoPlayback.cycleDuration(for: motion) == expected)
    }

    @Test("每次从零开始，第一轮中间保持相对时间", arguments: TomatoCharacter.Motion.allCases.filter { $0 != .still })
    func relativePlayback(motion: TomatoCharacter.Motion) {
        #expect(TomatoPlayback.frame(motion: motion, elapsed: 0, loops: 2) == .init(time: 0, isFinished: false))
        let middle = TomatoPlayback.cycleDuration(for: motion) / 2
        #expect(TomatoPlayback.frame(motion: motion, elapsed: middle, loops: 2) == .init(time: middle, isFinished: false))
    }

    @Test("刚好两轮和超时均在周期末帧结束，不切换代表帧", arguments: TomatoCharacter.Motion.allCases.filter { $0 != .still })
    func finiteBoundary(motion: TomatoCharacter.Motion) {
        let end = TomatoPlayback.cycleDuration(for: motion) * 2
        #expect(TomatoPlayback.frame(motion: motion, elapsed: end - 0.001, loops: 2) == .init(time: end - 0.001, isFinished: false))
        #expect(TomatoPlayback.frame(motion: motion, elapsed: end, loops: 2) == .init(time: end, isFinished: true))
        #expect(TomatoPlayback.frame(motion: motion, elapsed: end + 100, loops: 2) == .init(time: end, isFinished: true))
    }

    @Test("减少动态效果从第零秒起固定代表帧且结束", arguments: [
        (TomatoCharacter.Motion.still, 0.0), (.lookFar, 1.8), (.blink, 0.78), (.closeEyes, 0), (.rollEyes, 1.5), (.drinkWater, 1.4), (.walk, 0.45)
    ])
    func reducedMotion(motion: TomatoCharacter.Motion, representative: Double) {
        for elapsed in [0.0, 1, 100] {
            #expect(TomatoPlayback.frame(motion: motion, elapsed: elapsed, loops: 2, reduceMotion: true) == .init(time: representative, isFinished: true))
            #expect(TomatoPlayback.frame(motion: motion, elapsed: elapsed, loops: nil, reduceMotion: true).isFinished)
        }
    }

    @Test("无限播放保持时间，静止和零轮不启动动画")
    func infiniteAndEmptyPlayback() {
        #expect(TomatoPlayback.frame(motion: .blink, elapsed: 100, loops: nil) == .init(time: 100, isFinished: false))
        #expect(TomatoPlayback.frame(motion: .still, elapsed: 100, loops: nil) == .init(time: 0, isFinished: true))
        #expect(TomatoPlayback.frame(motion: .lookFar, elapsed: 0, loops: 0) == .init(time: 0, isFinished: true))
        #expect(TomatoPlayback.frame(motion: .lookFar, elapsed: 0, loops: -1).isFinished)
        #expect(TomatoPlayback.frame(motion: .lookFar, elapsed: -1, loops: 2).time == 0)
    }

    @Test("走一走两轮在 7.2 秒站姿结束，且动作映射一致")
    func walkEndsAtStandingPose() {
        #expect(RestExercise.walk.motion == .walk)
        #expect(TomatoPlayback.duration(for: .walk, loops: 2) == 7.2)
        #expect(TomatoPlayback.frame(motion: .walk, elapsed: 7.199, loops: 2) == .init(time: 7.199, isFinished: false))
        #expect(TomatoPlayback.frame(motion: .walk, elapsed: 7.2, loops: 2) == .init(time: 7.2, isFinished: true))
        #expect(TomatoPlayback.frame(motion: .walk, elapsed: 20, loops: 2) == .init(time: 7.2, isFinished: true))
    }
}
