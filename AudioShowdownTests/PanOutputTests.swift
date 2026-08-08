import AVFoundation
import XCTest
@testable import AudioShowdown

/// Measures what the REAL game graph renders per channel.
///
/// Every earlier suite asserted on values handed *into* the audio graph and so
/// passed while the audible field stayed narrow. These render the actual
/// engine offline and look at the samples.
@MainActor
final class PanOutputTests: XCTestCase {

    /// Plays a puck ping at table position `x` through the real engine and
    /// returns peak amplitude of (left, right).
    private func renderPuck(x: Double) throws -> (Float, Float) {
        let game = GameAudioEngine()
        let engine = game.engineForTesting
        let stereo = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2)!

        try engine.enableManualRenderingMode(.offline, format: stereo,
                                             maximumFrameCount: 1_024)
        try engine.start()

        game.setVolume(1)
        game.setPuckVolume(1)
        game.forceOutputProfileForTesting(.personalAudio)
        game.puckPing(x: x, distance: 0.5, style: 1, pitchBehavior: 0,
                      pitchChangesWithDistance: false, lowerWhenCloser: false,
                      volumeChangesWithDistance: false)

        let out = AVAudioPCMBuffer(pcmFormat: engine.manualRenderingFormat,
                                   frameCapacity: 1_024)!
        var left: Float = 0
        var right: Float = 0
        for _ in 0..<48 {
            let status = try engine.renderOffline(1_024, to: out)
            guard status == .success else { break 
    /// The mix format must carry the BINAURAL channel layout tag.
    ///
    /// This is what tells AirPods not to spatialise the game. A plain stereo
    /// tag gets re-rendered through a head model, which collapses the field
    /// toward the centre — the route reports `spatialON` and no amount of
    /// panning reaches the ear.
    func testMixFormatIsTaggedBinaural() {
        let game = GameAudioEngine()
        let format = game.engineForTesting.mainMixerNode.outputFormat(forBus: 0)
        XCTAssertEqual(format.channelCount, 2)
        let tag = game.mixFormatForTesting.channelLayout?.layoutTag
        XCTAssertEqual(tag, kAudioChannelLayoutTag_Binaural,
                       "mix format lost its binaural tag; AirPods will spatialise the game")
    }
}
            for i in 0..<Int(out.frameLength) {
                left = max(left, abs(out.floatChannelData![0][i]))
                right = max(right, abs(out.floatChannelData![1][i]))
            }
        }
        engine.stop()
        return (left, right)
    }

    /// A puck at the left wall must be in the LEFT channel and essentially
    /// absent from the right. This is the requirement, stated plainly.
    func testLeftWallIsLeftChannelOnly() throws {
        let (l, r) = try renderPuck(x: 0)
        XCTAssertGreaterThan(l, 0.05, "left wall produced no left channel")
        XCTAssertLessThan(r / max(l, 0.0001), 0.1,
                          "left wall bled into the right channel: L=\(l) R=\(r)")
    }

    func testRightWallIsRightChannelOnly() throws {
        let (l, r) = try renderPuck(x: 1)
        XCTAssertGreaterThan(r, 0.05, "right wall produced no right channel")
        XCTAssertLessThan(l / max(r, 0.0001), 0.1,
                          "right wall bled into the left channel: L=\(l) R=\(r)")
    }

    /// The sweep must be linear across the field.
    ///
    /// The law is a linear crossfade: the near channel holds at unity and the
    /// far channel falls linearly to zero at the wall. So at every step the
    /// *difference* between the channels moves by the same amount. That
    /// difference is the position cue, and it is what this asserts on.
    ///
    /// Do not assert on a balance ratio like (R-L)/(L+R): it compresses
    /// mid-sweep and reads as uneven even when the gains are perfectly linear.
    func testSweepIsLinearAcrossTheTable() throws {
        var levels: [(Float, Float)] = []
        for x in stride(from: 0.0, through: 1.0, by: 0.125) {
            levels.append(try renderPuck(x: x))
        }
        let peak = levels.map { max($0.0, $0.1) }.max() ?? 1
        for index in 1..<levels.count {
            let previous = (levels[index - 1].1 - levels[index - 1].0) / peak
            let current = (levels[index].1 - levels[index].0) / peak
            XCTAssertEqual(current - previous, 0.25, accuracy: 0.03,
                           "uneven step at index \(index): moved \(current - previous)")
        }
    }

    func testCentreIsBalanced() throws {
        let (l, r) = try renderPuck(x: 0.5)
        XCTAssertEqual(l, r, accuracy: 0.02, "centre is not balanced: L=\(l) R=\(r)")
    }

    // MARK: - Continuous puck (the sound tracked during a rally)

    /// Renders the STREAMING smooth-puck voice, which is a different code path
    /// from `puckPing` and is the sound actually followed during play.
    private func renderSmoothPuck(x: Double) throws -> (Float, Float) {
        let game = GameAudioEngine()
        let engine = game.engineForTesting
        let stereo = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2)!
        try engine.enableManualRenderingMode(.offline, format: stereo, maximumFrameCount: 1_024)
        try engine.start()

        game.setVolume(1)
        game.setPuckVolume(1)
        game.forceOutputProfileForTesting(.personalAudio)
        game.updateSmoothPuck(style: 0, x: x, proximity: 0.5, speed: 500, volume: 1,
                              pitchBehavior: 0, pitchChangesWithDistance: false,
                              lowerWhenCloser: false, volumeChangesWithDistance: false)

        let out = AVAudioPCMBuffer(pcmFormat: engine.manualRenderingFormat, frameCapacity: 1_024)!
        var left: Float = 0
        var right: Float = 0
        for _ in 0..<48 {
            guard (try engine.renderOffline(1_024, to: out)) == .success else { break }
            for i in 0..<Int(out.frameLength) {
                left = max(left, abs(out.floatChannelData![0][i]))
                right = max(right, abs(out.floatChannelData![1][i]))
            }
        }
        engine.stop()
        return (left, right)
    }

    func testSmoothPuckLeftWallIsLeftChannelOnly() throws {
        let (l, r) = try renderSmoothPuck(x: 0)
        XCTAssertGreaterThan(l, 0.01, "smooth puck produced no left channel")
        XCTAssertLessThan(r / max(l, 0.0001), 0.1,
                          "smooth puck left wall bled into right: L=\(l) R=\(r)")
    }

    func testSmoothPuckRightWallIsRightChannelOnly() throws {
        let (l, r) = try renderSmoothPuck(x: 1)
        XCTAssertGreaterThan(r, 0.01, "smooth puck produced no right channel")
        XCTAssertLessThan(l / max(r, 0.0001), 0.1,
                          "smooth puck right wall bled into left: L=\(l) R=\(r)")
    }
}
