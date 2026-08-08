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

    /// Sweeping the paddle across the table must not re-schedule the loop.
    func testSweepingDoesNotRestartTheLoop() throws {
        let game = try startedEngine()
        game.updateMalletSlide(x: 0, speed: 800, volume: 1)
        let schedulesAfterStart = game.malletSlideScheduleCountForTesting
        XCTAssertEqual(schedulesAfterStart, 1, "slide should schedule its loop once")

        for x in stride(from: 0.0, through: 1.0, by: 0.05) {
            game.updateMalletSlide(x: x, speed: 800, volume: 1)
        }

        XCTAssertEqual(
            game.malletSlideScheduleCountForTesting, schedulesAfterStart,
            "loop was re-scheduled during the sweep; the slide will grate instead of glide"
        )
        XCTAssertTrue(game.malletSlideIsPlayingForTesting, "slide stopped mid-sweep")
    }

    /// The balance must still actually follow the paddle.
    func testBalanceFollowsThePaddle() throws {
        let game = try startedEngine()
        game.updateMalletSlide(x: 0, speed: 800, volume: 1)
        let (leftAtLeftWall, rightAtLeftWall) = game.malletSlideVolumesForTesting
        XCTAssertGreaterThan(leftAtLeftWall, rightAtLeftWall)
        XCTAssertEqual(rightAtLeftWall, 0, accuracy: 0.0001,
                       "left wall must put nothing in the right channel")

        game.updateMalletSlide(x: 1, speed: 800, volume: 1)
        let (leftAtRightWall, rightAtRightWall) = game.malletSlideVolumesForTesting
        XCTAssertGreaterThan(rightAtRightWall, leftAtRightWall)
        XCTAssertEqual(leftAtRightWall, 0, accuracy: 0.0001,
                       "right wall must put nothing in the left channel")

        game.updateMalletSlide(x: 0.5, speed: 800, volume: 1)
        let (leftAtCentre, rightAtCentre) = game.malletSlideVolumesForTesting
        XCTAssertEqual(leftAtCentre, rightAtCentre, accuracy: 0.0001)
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
}