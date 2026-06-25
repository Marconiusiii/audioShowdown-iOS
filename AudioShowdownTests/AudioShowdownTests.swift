//
//  AudioShowdownTests.swift
//  AudioShowdownTests
//
//  Created by Marco Salsiccia on 6/24/26.
//

import Testing
import Foundation
@testable import AudioShowdown

@MainActor
struct AudioShowdownTests {
    @Test func reverbDefaultsToOffAndPersists() {
        let suiteName = "AudioShowdownTests.Reverb.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let initialSettings = GameSettings(defaults: defaults)
        #expect(initialSettings.reverbStyle == 0)
        initialSettings.reverbStyle = 3

        let restoredSettings = GameSettings(defaults: defaults)
        #expect(restoredSettings.reverbStyle == 3)
    }

    @Test func puckTrackingDefaultsToPulseWithVolumeDistanceAvailable() {
        let suiteName = "AudioShowdownTests.PuckTracking.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = GameSettings(defaults: defaults)
        #expect(settings.puckTrackingStyle == .pulse)
        #expect(settings.smoothPuckSound == 3)
        #expect(settings.puckDistanceBehavior == .volume)
        #expect(settings.closerIncreasesPuckFeedback)

        settings.puckTrackingStyle = .smooth
        settings.smoothPuckSound = 5
        settings.puckDistanceBehavior = .pitch
        settings.closerIncreasesPuckFeedback = false

        let restoredSettings = GameSettings(defaults: defaults)
        #expect(restoredSettings.puckTrackingStyle == .smooth)
        #expect(restoredSettings.smoothPuckSound == 5)
        #expect(restoredSettings.puckDistanceBehavior == .pitch)
        #expect(!restoredSettings.closerIncreasesPuckFeedback)
    }


    @Test func scoringAndWinningRules() {
        #expect(GameModel.pointsPerGoal(airHockeyMode: false) == 2)
        #expect(GameModel.pointsPerGoal(airHockeyMode: true) == 1)
        #expect(!GameModel.isWinningScore(player: 11, opponent: 10, airHockeyMode: false))
        #expect(GameModel.isWinningScore(player: 12, opponent: 10, airHockeyMode: false))
        #expect(!GameModel.isWinningScore(player: 6, opponent: 4, airHockeyMode: true))
        #expect(GameModel.isWinningScore(player: 7, opponent: 6, airHockeyMode: true))
    }

    @Test func showdownServiceChangesAfterFiveServes() {
        let sameServer = GameModel.nextShowdownServe(server: .player, serveNumber: 4)
        #expect(sameServer.0 == .player)
        #expect(sameServer.1 == 5)
        let changedServer = GameModel.nextShowdownServe(server: .player, serveNumber: 5)
        #expect(changedServer.0 == .opponent)
        #expect(changedServer.1 == 1)
    }

    @Test func playerProximityIncreasesTowardBottomOfTable() {
        #expect(GameModel.playerProximity(forY: 0) == 0)
        #expect(GameModel.playerProximity(forY: GameModel.center) == 0.5)
        #expect(GameModel.playerProximity(forY: GameModel.height) == 1)
    }

    @Test func puckPingsAccelerateTowardPlayer() {
        let topInterval = GameModel.puckPulseInterval(speed: 2, speedsUpWhenApproaching: true, proximity: 0)
        let centerInterval = GameModel.puckPulseInterval(speed: 2, speedsUpWhenApproaching: true, proximity: 0.5)
        let bottomInterval = GameModel.puckPulseInterval(speed: 2, speedsUpWhenApproaching: true, proximity: 1)
        #expect(topInterval > centerInterval)
        #expect(centerInterval > bottomInterval)
        #expect(abs(topInterval - 0.25) < 0.0001)
        #expect(abs(bottomInterval - 0.058) < 0.0001)
    }

    @Test func pulseSpeedRemainsConstantWhenApproachSpeedupIsOff() {
        let topInterval = GameModel.puckPulseInterval(speed: 1, speedsUpWhenApproaching: false, proximity: 0)
        let bottomInterval = GameModel.puckPulseInterval(speed: 1, speedsUpWhenApproaching: false, proximity: 1)
        #expect(topInterval == 0.16)
        #expect(bottomInterval == 0.16)
    }

    @Test func shapedPlayerStrikeKeepsMostlyUpwardMomentum() {
        let shaped = GameModel.shapedStrikeVelocity(vx: 520, vy: -40, byPlayer: true)

        #expect(shaped.vy <= -180)
        #expect(abs(shaped.vx) < 520)
    }

    @Test func shapedComputerStrikeKeepsMostlyDownwardMomentum() {
        let shaped = GameModel.shapedStrikeVelocity(vx: -520, vy: 40, byPlayer: false)

        #expect(shaped.vy >= 180)
        #expect(abs(shaped.vx) < 520)
    }

    @Test func gameSpeedUsesWebTimeScale() {
        #expect(abs(GameModel.gameTimeScale(speed: 1) - 0.45) < 0.0001)
        #expect(abs(GameModel.gameTimeScale(speed: 10) - 2.6) < 0.0001)
        #expect(GameModel.gameTimeScale(speed: 2) < 0.6)
    }

    @Test func puckVelocityCapsAtWebMaximum() {
        let capped = GameModel.cappedVelocity(vx: 3_000, vy: 4_000)
        #expect(abs(hypot(capped.vx, capped.vy) - GameModel.puckSpeedCap) < 0.0001)
    }

    @Test func deadPuckRecoveryNudgesTowardOpponentAfterPlayerHit() {
        let recovered = GameModel.recoveredPuckVelocity(vx: 80, vy: 12, byPlayer: true)

        #expect(recovered.vy <= -240)
        #expect(abs(recovered.vx) <= 80)
    }

    @Test func deadPuckRecoveryNudgesTowardPlayerAfterComputerHit() {
        let recovered = GameModel.recoveredPuckVelocity(vx: -80, vy: -12, byPlayer: false)

        #expect(recovered.vy >= 240)
        #expect(abs(recovered.vx) <= 80)
    }

    @Test func playerServeCanBePlacedWithoutImmediatelyGoingLive() {
        let suiteName = "AudioShowdownTests.PlacedServe.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let model = GameModel(settings: GameSettings(defaults: defaults), training: false, audio: GameAudioEngine())

        model.touchBegan(at: CGPoint(x: 300, y: 900))
        model.touchEnded(wasTap: true)

        #expect(model.phase == .placedServe)
        #expect(model.puck.vx == 0)
        #expect(model.puck.vy == 0)
    }

    @Test func oldApproachPulseSettingMigratesToMediumWithSpeedup() {
        let suiteName = "AudioShowdownTests.PulseMigration.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(0, forKey: "pingRate")

        let settings = GameSettings(defaults: defaults)
        #expect(settings.pingRate == 1)
        #expect(settings.speedsUpWhenApproaching)
        #expect(settings.puckVolume == 0.8)

        let restoredSettings = GameSettings(defaults: defaults)
        #expect(restoredSettings.pingRate == 1)
        #expect(restoredSettings.speedsUpWhenApproaching)
    }

    @Test func serveAnnouncementsPutServerAndServerScoreFirst() {
        #expect(
            GameModel.serveAnnouncement(
                server: .player,
                serveNumber: 3,
                playerScore: 6,
                computerScore: 4
            ) == "Your third serve, 6 serving 4"
        )
        #expect(
            GameModel.serveAnnouncement(
                server: .opponent,
                serveNumber: 2,
                playerScore: 6,
                computerScore: 8
            ) == "Computer's second serve, 8 serving 6"
        )
    }
}
