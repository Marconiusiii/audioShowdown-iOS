import AVFoundation
import XCTest
@testable import AudioShowdown

/// Live-graph cover. The unit suite asserts on pure functions and would pass
/// with a graph that cannot start at all, which is exactly how a speaker-route
/// regression reached a build. These start the real engine.
@MainActor
final class GraphSmokeTests: XCTestCase {

    func testEngineStartsAndPlaysOnSpeakerRoute() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try session.overrideOutputAudioPort(.speaker)
        try session.setActive(true)

        let engine = GameAudioEngine()
        engine.warmUp(volume: 1, reverbStyle: 0, puckVolume: 0.8)
        engine.puckPing(x: 0, distance: 0.5, style: 0, pitchBehavior: 0,
                        pitchChangesWithDistance: false, lowerWhenCloser: false,
                        volumeChangesWithDistance: false)
        XCTAssertTrue(engine.isRunningForTesting, "engine did not start on the speaker route")
    }

    func testEngineStartsWithReverbEnabled() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try session.overrideOutputAudioPort(.speaker)
        try session.setActive(true)

        let engine = GameAudioEngine()
        engine.warmUp(volume: 1, reverbStyle: 3, puckVolume: 0.8)
        engine.updateSmoothPuck(style: 0, x: 0.5, proximity: 0.5, speed: 400, volume: 0.8,
                                pitchBehavior: 0, pitchChangesWithDistance: false,
                                lowerWhenCloser: false, volumeChangesWithDistance: false)
        XCTAssertTrue(engine.isRunningForTesting, "wet path prevented the engine from running")
    }
}
