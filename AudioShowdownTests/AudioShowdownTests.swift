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
