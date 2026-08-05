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
}
