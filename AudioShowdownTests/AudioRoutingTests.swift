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

    // MARK: - Stereo width

    /// Angle of a source off the centre line, in degrees. 0 is dead centre,
    /// 90 is fully to one side. This is what the player actually perceives,
    /// so it is what the width assertions are written against.
    private func offCentreDegrees(_ point: AVAudio3DPoint) -> Double {
        Double(atan2(abs(point.x), abs(point.z))) * 180 / .pi
    }

    private func headphonePosition(x: Double, proximity: Double) -> AVAudio3DPoint {
        GameAudioEngine.spatialPosition(x: x, proximity: proximity, profile: .personalAudio)
    }

    /// The core regression. A puck against a side wall must be hard against
    /// that ear at every distance. A 1.0.x build scaled the spread down by
    /// `1.6 * near²`, which pulled the near walls — the most extreme cue in
    /// the game — back toward centre and flattened the field on headphones.
    func testSideWallsStayHardLeftAndRightAtEveryDistance() {
        for proximity in stride(from: 0.0, through: 1.0, by: 0.05) {
            let left = headphonePosition(x: 0, proximity: proximity)
            let right = headphonePosition(x: 1, proximity: proximity)

            XCTAssertGreaterThan(
                offCentreDegrees(left), 60,
                "left wall collapsed toward centre at proximity \(proximity)"
            )
            XCTAssertGreaterThan(
                offCentreDegrees(right), 60,
                "right wall collapsed toward centre at proximity \(proximity)"
            )
            XCTAssertLessThan(left.x, 0, "left wall must sit in the left ear")
            XCTAssertGreaterThan(right.x, 0, "right wall must sit in the right ear")
        }
    }

    /// The horizontal placement of a side wall must never shrink as the puck
    /// approaches. This is the precise failure in the compression commit: the
    /// spread was scaled down by `1.6 * near²`, so the near walls were placed
    /// least far out. Note this asserts the raw horizontal value, not the
    /// perceived angle — the broken maths still *widened* in angle, because its
    /// depth term shrank faster than its width term, which is exactly why the
    /// bug was easy to miss.
    func testHorizontalPlacementNeverShrinksAsThePuckApproaches() {
        var previous = abs(headphonePosition(x: 0, proximity: 0).x)
        for proximity in stride(from: 0.05, through: 1.0, by: 0.05) {
            let current = abs(headphonePosition(x: 0, proximity: proximity).x)
            XCTAssertGreaterThanOrEqual(
                current, previous,
                "horizontal spread shrank as the puck approached, at proximity \(proximity)"
            )
            previous = current
        }
    }

    /// Horizontal placement must depend only on x, so the same wall reads at
    /// the same width whether the puck is near or far.
    func testHorizontalPlacementIsIndependentOfDistance() {
        for x in [0.0, 0.25, 0.5, 0.75, 1.0] {
            let near = headphonePosition(x: x, proximity: 1)
            let far = headphonePosition(x: x, proximity: 0)
            XCTAssertEqual(
                near.x, far.x, accuracy: 0.0001,
                "x=\(x) shifted horizontally with distance"
            )
        }
    }

    /// Only a puck actually at the centre line belongs in the centre. Anything
    /// off-centre must be audibly off-centre.
    func testOnlyTheCentreLineRendersCentred() {
        XCTAssertEqual(headphonePosition(x: 0.5, proximity: 0.5).x, 0, accuracy: 0.0001)

        for x in [0.35, 0.4, 0.45, 0.55, 0.6, 0.65] {
            let point = headphonePosition(x: x, proximity: 0.5)
            XCTAssertGreaterThan(
                abs(point.x), 0.5,
                "x=\(x) rendered too close to centre"
            )
        }
    }

    /// Placement must be symmetric: mirrored positions land at mirrored
    /// angles, so neither ear is favoured.
    func testPlacementIsSymmetricAboutTheCentreLine() {
        for offset in stride(from: 0.05, through: 0.5, by: 0.05) {
            let left = headphonePosition(x: 0.5 - offset, proximity: 0.5)
            let right = headphonePosition(x: 0.5 + offset, proximity: 0.5)
            XCTAssertEqual(left.x, -right.x, accuracy: 0.0001)
            XCTAssertEqual(left.z, right.z, accuracy: 0.0001)
        }
    }

    /// The speaker has no usable stereo field, so it keeps its own narrow
    /// equal-power placement. Guarded so the headphone fix is not "helpfully"
    /// applied to speaker playback later.
    func testSpeakerProfileKeepsItsOwnNarrowPlacement() {
        XCTAssertEqual(
            GameAudioEngine.spatialPosition(x: 0, proximity: 1, profile: .builtInSpeaker).x,
            -1, accuracy: 0.0001
        )
        XCTAssertEqual(
            GameAudioEngine.spatialPosition(x: 1, proximity: 1, profile: .builtInSpeaker).x,
            1, accuracy: 0.0001
        )
    }

    /// Before the session activates the engine has not classified the route
    /// yet. That must take the wide path — narrowing an unknown route would
    /// squash the field on headphones for the first cues of a match.
    func testUnclassifiedRouteUsesTheWideField() {
        let unknown = GameAudioEngine.spatialPosition(x: 0, proximity: 1, profile: nil)
        let headphones = headphonePosition(x: 0, proximity: 1)
        XCTAssertEqual(unknown.x, headphones.x, accuracy: 0.0001)
        XCTAssertEqual(unknown.z, headphones.z, accuracy: 0.0001)
    }

    /// Out-of-range input must clamp to the walls rather than flying past them.
    func testOutOfRangeInputClampsToTheWalls() {
        XCTAssertEqual(headphonePosition(x: -3, proximity: 0.5).x,
                       headphonePosition(x: 0, proximity: 0.5).x, accuracy: 0.0001)
        XCTAssertEqual(headphonePosition(x: 4, proximity: 0.5).x,
                       headphonePosition(x: 1, proximity: 0.5).x, accuracy: 0.0001)
    }
}
