//
//  AudioRoutingTests.swift
//  AudioShowdownTests
//
//  Regression cover for the 1.0.5 bug that sent all game audio to the iPhone
//  earpiece. Two causes: the session used `.measurement` mode, which iOS routes
//  to the built-in receiver under the `.playback` category; and an empty or
//  unrecognised route was classified as headphones.
//

import AVFoundation
import XCTest
@testable import AudioShowdown

final class AudioRoutingTests: XCTestCase {

    // MARK: - Session mode

    /// `.measurement` routes `.playback` audio to the earpiece. No route may
    /// ever select it, or the game becomes nearly silent on a bare phone.
    func testSessionModeIsNeverMeasurement() {
        XCTAssertEqual(GameAudioEngine.audioSessionMode(for: .builtInSpeaker), .default)
        XCTAssertEqual(GameAudioEngine.audioSessionMode(for: .personalAudio), .default)
    }

    // MARK: - Route classification

    func testNoRouteAssumesSpeaker() {
        // Before the session activates the route is empty. Assuming headphones
        // there applies HRTF to speaker playback.
        XCTAssertEqual(GameAudioEngine.outputProfile(forPortTypes: []), .builtInSpeaker)
    }

    func testBuiltInSpeakerIsSpeakerProfile() {
        XCTAssertEqual(
            GameAudioEngine.outputProfile(forPortTypes: [.builtInSpeaker]),
            .builtInSpeaker
        )
    }

    /// The earpiece is loudspeaker-like playback, not personal audio. Treating
    /// it as headphones was part of what kept audio stuck there.
    func testBuiltInReceiverIsSpeakerProfile() {
        XCTAssertEqual(
            GameAudioEngine.outputProfile(forPortTypes: [.builtInReceiver]),
            .builtInSpeaker
        )
    }

    func testUnknownPortFallsBackToSpeaker() {
        XCTAssertEqual(
            GameAudioEngine.outputProfile(forPortTypes: [.HDMI]),
            .builtInSpeaker
        )
    }

    func testWiredHeadphonesArePersonalAudio() {
        XCTAssertEqual(
            GameAudioEngine.outputProfile(forPortTypes: [.headphones]),
            .personalAudio
        )
    }

    func testBluetoothOutputsArePersonalAudio() {
        for port in [AVAudioSession.Port.bluetoothA2DP, .bluetoothHFP, .bluetoothLE] {
            XCTAssertEqual(
                GameAudioEngine.outputProfile(forPortTypes: [port]),
                .personalAudio,
                "\(port.rawValue) should render as personal audio"
            )
        }
    }

    func testAirPlayAndUSBAndCarAudioArePersonalAudio() {
        for port in [AVAudioSession.Port.airPlay, .usbAudio, .carAudio] {
            XCTAssertEqual(
                GameAudioEngine.outputProfile(forPortTypes: [port]),
                .personalAudio,
                "\(port.rawValue) should render as personal audio"
            )
        }
    }

    /// AirPods connected mid-match: the route briefly lists both ports, and the
    /// headphones must win so spatial audio follows the player's ears.
    func testHeadphonesWinWhenRouteListsSpeakerToo() {
        XCTAssertEqual(
            GameAudioEngine.outputProfile(forPortTypes: [.builtInSpeaker, .bluetoothA2DP]),
            .personalAudio
        )
    }

    /// Headphones unplugged mid-match: the route falls back to the phone and
    /// playback must return to speaker rendering rather than staying on HRTF.
    func testRemovingHeadphonesReturnsToSpeakerProfile() {
        XCTAssertEqual(
            GameAudioEngine.outputProfile(forPortTypes: [.headphones]),
            .personalAudio
        )
        XCTAssertEqual(
            GameAudioEngine.outputProfile(forPortTypes: [.builtInSpeaker]),
            .builtInSpeaker
        )
    }

    // MARK: - Stereo pan

    // Left/right is the gameplay signal in this game, and it is carried by a
    // plain stereo pan — not by spatial audio. Everything else about the puck
    // (how far, how fast) is already in the pulse timing, pitch, and volume.
    //
    // These assertions are written directly against the pan value the player
    // node receives, which is the whole of what the player hears. An earlier
    // suite asserted on 3D coordinates handed to an AVAudioEnvironmentNode and
    // so passed while the audible field was narrow: HRTF renders a generic
    // head, and a head bleeds sound into the far ear by design, which caps the
    // width regardless of how far out a source is placed. That is why the field
    // read as too narrow on AirPods — which reproduce the head model faithfully
    // — while bone-conduction sets that destroy those cues sounded fine.

    private func pan(_ x: Double) -> Double {
        Double(GameAudioEngine.stereoPan(for: x))
    }

    /// The walls must be hard left and hard right. Anything less is the
    /// narrowness this replaced the spatialiser to fix.
    func testSideWallsAreHardLeftAndHardRight() {
        XCTAssertEqual(pan(0), -1, accuracy: 0.0001, "left wall must be hard left")
        XCTAssertEqual(pan(1), 1, accuracy: 0.0001, "right wall must be hard right")
    }

    /// The centre line, and only the centre line, is centred.
    func testCentreLineIsCentred() {
        XCTAssertEqual(pan(0.5), 0, accuracy: 0.0001)
        XCTAssertNotEqual(pan(0.45), 0, accuracy: 0.01)
        XCTAssertNotEqual(pan(0.55), 0, accuracy: 0.01)
    }

    /// Equal steps across the table must be equal steps across the stereo
    /// field, the whole way out — a smooth sweep with no compression near the
    /// walls and no lurch at the centre.
    func testPanIsLinearAcrossTheTable() {
        let step = 0.05
        var previous = pan(0)

        for x in stride(from: step, through: 1.0, by: step) {
            let current = pan(x)
            XCTAssertEqual(
                current - previous, 2 * step, accuracy: 0.0001,
                "pan is uneven near x=\(x); every step must move the same amount"
            )
            previous = current
        }
    }

    /// The left half belongs in the left channel and the right half in the
    /// right, with no region that sits on the wrong side of centre.
    func testEachHalfOfTheTableStaysOnItsOwnSide() {
        for x in stride(from: 0.0, to: 0.5, by: 0.05) {
            XCTAssertLessThan(pan(x), 0, "x=\(x) is on the left but did not pan left")
        }
        for x in stride(from: 0.55, through: 1.0, by: 0.05) {
            XCTAssertGreaterThan(pan(x), 0, "x=\(x) is on the right but did not pan right")
        }
    }

    /// Mirrored positions must pan to mirrored places, so neither ear is
    /// favoured.
    func testPanIsSymmetricAboutTheCentreLine() {
        for offset in stride(from: 0.05, through: 0.5, by: 0.05) {
            XCTAssertEqual(
                pan(0.5 - offset), -pan(0.5 + offset), accuracy: 0.0001,
                "offset \(offset) is not mirrored about the centre"
            )
        }
    }

    /// Out-of-range input must clamp to the walls rather than flying past them.
    func testOutOfRangeInputClampsToTheWalls() {
        XCTAssertEqual(pan(-3), pan(0), accuracy: 0.0001)
        XCTAssertEqual(pan(4), pan(1), accuracy: 0.0001)
    }
}
