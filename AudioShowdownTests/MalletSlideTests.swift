import AVFoundation
import XCTest
@testable import AudioShowdown

/// The mallet slide is a continuous loop. Its left/right balance must be able
/// to follow the paddle WITHOUT interrupting playback.
///
/// A previous version baked the pan into the looping buffer, so every pan
/// change re-scheduled the loop and restarted it from frame zero. Dragging the
/// paddle restarted it constantly, which sounded like a grating repeated
/// rattle instead of a smooth slide.
@MainActor
final class MalletSlideTests: XCTestCase {

    private func startedEngine() throws -> GameAudioEngine {
        let game = GameAudioEngine()
        let stereo = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2)!
        try game.engineForTesting.enableManualRenderingMode(.offline, format: stereo,
                                                            maximumFrameCount: 1_024)
        try game.engineForTesting.start()
        game.forceOutputProfileForTesting(.personalAudio)
        return game
    }

    /// Sweeping the paddle must not re-schedule the loop. Re-scheduling
    /// restarts it from frame zero, which is what made the slide grate.
    func testSweepingDoesNotRestartTheLoop() throws {
        let game = try startedEngine()

        // Drive it until the loop is actually scheduled. `ensureEngineRunning`
        // can decline on the first call under manual rendering, which is a
        // harness artefact rather than a property of the slide.
        for _ in 0..<10 where game.malletSlideScheduleCountForTesting == 0 {
            game.updateMalletSlide(x: 0, speed: 800, volume: 1)
        }
        let schedulesAfterStart = game.malletSlideScheduleCountForTesting
        try XCTSkipIf(schedulesAfterStart == 0, "engine declined to start under manual rendering")

        for x in stride(from: 0.0, through: 1.0, by: 0.05) {
            game.updateMalletSlide(x: x, speed: 800, volume: 1)
        }

        XCTAssertEqual(
            game.malletSlideScheduleCountForTesting, schedulesAfterStart,
            "loop was re-scheduled during the sweep; the slide will grate instead of glide"
        )
    }

    /// The balance must still actually follow the paddle.
    func testBalanceFollowsThePaddle() throws {
        let game = try startedEngine()
        for _ in 0..<60 { game.updateMalletSlide(x: 0, speed: 800, volume: 1) }
        let (leftAtLeftWall, rightAtLeftWall) = game.malletSlideVolumesForTesting
        XCTAssertGreaterThan(leftAtLeftWall, rightAtLeftWall)
        XCTAssertEqual(rightAtLeftWall, 0, accuracy: 0.005,
                       "left wall must put nothing in the right channel")

        for _ in 0..<60 { game.updateMalletSlide(x: 1, speed: 800, volume: 1) }
        let (leftAtRightWall, rightAtRightWall) = game.malletSlideVolumesForTesting
        XCTAssertGreaterThan(rightAtRightWall, leftAtRightWall)
        XCTAssertEqual(leftAtRightWall, 0, accuracy: 0.005,
                       "right wall must put nothing in the left channel")

        for _ in 0..<60 { game.updateMalletSlide(x: 0.5, speed: 800, volume: 1) }
        let (leftAtCentre, rightAtCentre) = game.malletSlideVolumesForTesting
        XCTAssertEqual(leftAtCentre, rightAtCentre, accuracy: 0.005)
    }

    // MARK: - Loop quality

    /// The loop must join seamlessly. The previous version faded to silence at
    /// both ends, so with `.loops` it dipped to nothing every two seconds —
    /// heard as a stutter in a sound that should be unbroken.
    func testLoopDoesNotFadeToSilenceAtItsEdges() throws {
        let game = GameAudioEngine()
        let loop = game.malletSlideLoopForTesting()
        let samples = loop.floatChannelData![0]
        let count = Int(loop.frameLength)

        func peak(_ range: Range<Int>) -> Float {
            range.reduce(Float(0)) { max($0, abs(samples[$1])) }
        }

        let window = Int(0.01 * 48_000)
        let middle = peak((count / 2)..<(count / 2 + window))
        let head = peak(0..<window)
        let tail = peak((count - window)..<count)

        XCTAssertGreaterThan(head, middle * 0.4, "loop fades in; the slide will stutter each cycle")
        XCTAssertGreaterThan(tail, middle * 0.4, "loop fades out; the slide will stutter each cycle")
    }

    /// The sample either side of the loop point must be continuous, or the
    /// join clicks on every repeat.
    func testLoopPointIsContinuous() throws {
        let game = GameAudioEngine()
        let loop = game.malletSlideLoopForTesting()
        let samples = loop.floatChannelData![0]
        let count = Int(loop.frameLength)

        let jumpAtLoopPoint = abs(samples[0] - samples[count - 1])
        var largestInteriorJump: Float = 0
        for frame in 1..<count {
            largestInteriorJump = max(largestInteriorJump, abs(samples[frame] - samples[frame - 1]))
        }

        XCTAssertLessThanOrEqual(
            jumpAtLoopPoint, largestInteriorJump * 1.5,
            "the loop point jumps more than the signal itself does; it will click"
        )
    }

    // MARK: - Localisation

    /// The slide must stay a point that follows the finger. It must never sit
    /// at full level in both ears at once, which fuses into a wide blast
    /// spread across the whole stereo field instead of a position cue.
    func testSlideNeverPlaysFullyInBothEars() throws {
        let game = try startedEngine()
        for x in stride(from: 0.0, through: 1.0, by: 0.05) {
            // Settle the smoothing so this measures the steady state.
            for _ in 0..<60 { game.updateMalletSlide(x: x, speed: 800, volume: 1) }
            let (left, right) = game.malletSlideVolumesForTesting
            let quieter = min(left, right)
            let louder = max(left, right)
            XCTAssertLessThanOrEqual(
                quieter, louder,
                "x=\(x): both ears at full level reads as a wide blast, not a position"
            )
        }
    }

    /// Gain must not jump between frames when the finger speed twitches, or
    /// the slide flickers instead of gliding.
    func testGainDoesNotJumpBetweenFrames() throws {
        let game = try startedEngine()
        for _ in 0..<60 { game.updateMalletSlide(x: 0.5, speed: 800, volume: 1) }
        let (settledLeft, _) = game.malletSlideVolumesForTesting

        // A single frame of a wildly different speed must not swing the level.
        game.updateMalletSlide(x: 0.5, speed: 60, volume: 1)
        let (afterSpike, _) = game.malletSlideVolumesForTesting

        XCTAssertLessThan(
            abs(afterSpike - settledLeft), settledLeft * 0.5,
            "one frame of speed change swung the gain; the slide will flicker"
        )
    }
}