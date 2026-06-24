//
//  AudioShowdownTests.swift
//  AudioShowdownTests
//
//  Created by Marco Salsiccia on 6/24/26.
//

import Testing
@testable import AudioShowdown

@MainActor
struct AudioShowdownTests {

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
}
