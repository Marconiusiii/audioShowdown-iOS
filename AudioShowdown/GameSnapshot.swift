import Foundation

struct GameSnapshot: Codable, Equatable {
    enum Phase: String, Codable {
        case waitingForServe
        case placedServe
        case live
        case paused
        case gameOver
        case training
    }

    enum Server: String, Codable {
        case player
        case opponent
    }

    struct Disc: Codable, Equatable {
        var x: Double
        var y: Double
        var vx: Double
        var vy: Double
    }

    var puck: Disc
    var playerPaddle: Disc
    var opponentPaddle: Disc
    var playerScore: Int
    var opponentScore: Int
    var phase: Phase
    var server: Server
    var serveNumber: Int
}
