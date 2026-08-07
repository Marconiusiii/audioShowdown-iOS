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

    /// Signed angle off the centre line: negative is left, positive is right.
    /// Direction matters here, so these assertions use the signed value.
    private func signedAngle(_ point: AVAudio3DPoint) -> Double {
        Double(atan2(Double(point.x), abs(Double(point.z)))) * 180 / .pi
    }

    private func headphonePosition(x: Double, proximity: Double) -> AVAudio3DPoint {
        GameAudioEngine.spatialPosition(x: x, proximity: proximity, profile: .personalAudio)
    }

    /// A puck against a side wall must reach the full pan angle at every
    /// distance. A 1.0.x build scaled the spread down by `1.6 * near²`, which
    /// pulled the near walls — the most extreme cue in the game — back toward
    /// centre and flattened the field on headphones.
    func testSideWallsReachFullPanAtEveryDistance() {
        let full = GameAudioEngine.maximumPanAngleDegrees
        for proximity in stride(from: 0.0, through: 1.0, by: 0.05) {
            let left = headphonePosition(x: 0, proximity: proximity)
            let right = headphonePosition(x: 1, proximity: proximity)

            XCTAssertEqual(
                offCentreDegrees(left), full, accuracy: 0.01,
                "left wall fell short of full pan at proximity \(proximity)"
            )
            XCTAssertEqual(
                offCentreDegrees(right), full, accuracy: 0.01,
                "right wall fell short of full pan at proximity \(proximity)"
            )
            XCTAssertLessThan(left.x, 0, "left wall must sit in the left ear")
            XCTAssertGreaterThan(right.x, 0, "right wall must sit in the right ear")
        }
    }

    /// The pan must be *linear* across the table: equal steps in table position
    /// produce equal steps in perceived angle. This is the property that makes
    /// slowly dragging the puck read as a smooth sweep.
    ///
    /// A wide, shallow rectangular placement fails this badly — the angle is
    /// the arctangent of x over z, so it saturates near the walls and crams the
    /// whole audible sweep around the centre line.
    func testPanIsLinearAcrossTheTable() {
        let step = 0.05
        var previousAngle = signedAngle(headphonePosition(x: 0, proximity: 0.9))
        var deltas: [Double] = []

        for x in stride(from: step, through: 1.0, by: step) {
            let angle = signedAngle(headphonePosition(x: x, proximity: 0.9))
            deltas.append(angle - previousAngle)
            previousAngle = angle
        }

        let expected = 2 * GameAudioEngine.maximumPanAngleDegrees * step
        for delta in deltas {
            XCTAssertEqual(
                delta, expected, accuracy: 0.01,
                "pan is uneven across the table; every step must sweep the same angle"
            )
        }
    }

    /// No stretch of the table may be a dead zone where the puck barely moves
    /// in the mix, and no stretch may swing wildly. Both are the same fault
    /// seen from opposite ends, and both were present before the arc placement.
    func testNoDeadZonesOrViolentSwings() {
        let step = 0.05
        let expected = 2 * GameAudioEngine.maximumPanAngleDegrees * step
        var previousAngle = signedAngle(headphonePosition(x: 0, proximity: 0.9))

        for x in stride(from: step, through: 1.0, by: step) {
            let angle = signedAngle(headphonePosition(x: x, proximity: 0.9))
            let delta = abs(angle - previousAngle)
            XCTAssertGreaterThan(
                delta, expected * 0.5,
                "dead zone near x=\(x): the puck barely moves in the mix here"
            )
            XCTAssertLessThan(
                delta, expected * 2,
                "violent swing near x=\(x): the puck lurches between ears here"
            )
            previousAngle = angle
        }
    }

    /// Crossing the centre line must be as gentle as any other step. The old
    /// rectangular placement flipped through roughly 100 degrees inside a tenth
    /// of the table width right at the middle.
    func testCrossingTheCentreLineIsGentle() {
        let justLeft = signedAngle(headphonePosition(x: 0.45, proximity: 0.9))
        let justRight = signedAngle(headphonePosition(x: 0.55, proximity: 0.9))
        XCTAssertLessThan(
            abs(justRight - justLeft), 30,
            "the mix lurches from ear to ear when the puck crosses the centre"
        )
    }

    /// Distance may change how far away the puck sounds, but never which
    /// direction it comes from.
    func testDistanceDoesNotChangeDirection() {
        for x in [0.0, 0.25, 0.5, 0.75, 1.0] {
            let near = signedAngle(headphonePosition(x: x, proximity: 1))
            let far = signedAngle(headphonePosition(x: x, proximity: 0))
            XCTAssertEqual(
                near, far, accuracy: 0.01,
                "x=\(x) changed direction with distance"
            )
        }
    }

    /// A near puck must sit closer to the listener than a far one, so distance
    /// still reads even though it no longer bends the angle.
    func testNearPucksAreCloserThanFarPucks() {
        for x in [0.0, 0.5, 1.0] {
            let near = headphonePosition(x: x, proximity: 1)
            let far = headphonePosition(x: x, proximity: 0)
            let nearRadius = hypot(Double(near.x), Double(near.z))
            let farRadius = hypot(Double(far.x), Double(far.z))
            XCTAssertLessThan(
                nearRadius, farRadius,
                "a near puck at x=\(x) must sound closer than a far one"
            )
        }
    }

    /// Only a puck actually at the centre line belongs in the centre, and the
    /// centre must be a line rather than a wide band — a puck a tenth of the
    /// table off-centre should already be audibly off-centre.
    func testOnlyTheCentreLineRendersCentred() {
        XCTAssertEqual(headphonePosition(x: 0.5, proximity: 0.5).x, 0, accuracy: 0.0001)

        for x in [0.35, 0.4, 0.45, 0.55, 0.6, 0.65] {
            let offset = abs(x - 0.5)
            let expected = 2 * offset * GameAudioEngine.maximumPanAngleDegrees
            XCTAssertEqual(
                offCentreDegrees(headphonePosition(x: x, proximity: 0.5)),
                expected, accuracy: 0.01,
                "x=\(x) did not pan proportionally to its distance from centre"
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
    /// yet. That must take the personal-audio arc — using the speaker's narrow
    /// placement would squash the opening cues of a match on headphones.
    func testUnclassifiedRouteUsesThePersonalAudioArc() {
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
