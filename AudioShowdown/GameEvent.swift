import Foundation

struct GameEvent: Codable, Equatable {
    enum Kind: String, Codable {
        case playerStrike
        case opponentStrike
        case wallBounce
        case centerCrossing
        case goal
        case boardBall
        case serve
        case pause
        case resume
        case gameOver
    }

    enum Side: String, Codable {
        case player
        case opponent
    }

    var kind: Kind
    var side: Side?
    var x: Double?
    var y: Double?
    var speed: Double?
    var playerScore: Int?
    var opponentScore: Int?
    var message: String?
}
