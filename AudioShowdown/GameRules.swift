import Foundation

enum GameRules {
    enum Server { case player, opponent }

    static let width = 600.0
    static let height = 1200.0
    static let center = 600.0
    static let goalHalfWidth = 150.0
    static let puckSpeedCap = 2_150.0
    static let friction = 0.06
    static let wallRestitution = 0.97
    static let deadVerticalSpeed = 105.0
    static let deadSpeed = 190.0

    static func pointsPerGoal(airHockeyMode: Bool) -> Int {
        airHockeyMode ? 1 : 2
    }

    static func isWinningScore(player: Int, opponent: Int, airHockeyMode: Bool) -> Bool {
        if airHockeyMode { return max(player, opponent) >= 7 }
        return max(player, opponent) >= 11 && abs(player - opponent) >= 2
    }

    static func nextShowdownServe(server: Server, serveNumber: Int) -> (Server, Int) {
        serveNumber >= 5 ? (server == .player ? .opponent : .player, 1) : (server, serveNumber + 1)
    }

    static func playerProximity(forY y: Double) -> Double {
        min(max(y / height, 0), 1)
    }

    static func puckPulseInterval(speed: Int, speedsUpWhenApproaching: Bool, proximity: Double) -> TimeInterval {
        let clampedProximity = min(max(proximity, 0), 1)
        let speed = min(max(speed, 0), 2)
        let nearIntervals = [0.30, 0.16, 0.092]
        let selectedInterval = nearIntervals[speed]
        guard speedsUpWhenApproaching else { return selectedInterval }
        let farAdditions = [0.22, 0.22, 0.192]
        return selectedInterval + farAdditions[speed] * pow(1 - clampedProximity, 0.8)
    }

    static func shapedStrikeVelocity(vx: Double, vy: Double, byPlayer: Bool) -> (vx: Double, vy: Double) {
        let direction = byPlayer ? -1.0 : 1.0
        let speed = max(360, hypot(vx, vy))
        let minimumVerticalSpeed = min(speed * 0.65, max(180, speed * 0.25))
        guard vy * direction < minimumVerticalSpeed else { return (vx, vy) }
        let shapedVy = direction * minimumVerticalSpeed
        let maximumVx = sqrt(max(0, speed * speed - minimumVerticalSpeed * minimumVerticalSpeed))
        return (min(max(vx, -maximumVx), maximumVx), shapedVy)
    }

    static func recoveredPuckVelocity(vx: Double, vy: Double, byPlayer: Bool) -> (vx: Double, vy: Double) {
        let direction = byPlayer ? -1.0 : 1.0
        let speed = hypot(vx, vy)
        let targetSpeed = max(420, speed)
        let targetVy = max(240, targetSpeed * 0.35)
        let maximumVx = sqrt(max(0, targetSpeed * targetSpeed - targetVy * targetVy))
        return (min(max(vx, -maximumVx), maximumVx), direction * targetVy)
    }

    static func cappedVelocity(vx: Double, vy: Double) -> (vx: Double, vy: Double) {
        let speed = hypot(vx, vy)
        guard speed > puckSpeedCap else { return (vx, vy) }
        let scale = puckSpeedCap / speed
        return (vx * scale, vy * scale)
    }

    static func gameTimeScale(speed: Double) -> Double {
        0.45 * pow(2.6 / 0.45, (speed - 1) / 9)
    }

    static func serveAnnouncement(server: Server, serveNumber: Int, playerScore: Int, computerScore: Int) -> String {
        let ordinal = ordinalWord(serveNumber)
        if server == .player {
            return "Your \(ordinal) serve, \(playerScore) serving \(computerScore)"
        }
        return "Computer's \(ordinal) serve, \(computerScore) serving \(playerScore)"
    }

    private static func ordinalWord(_ number: Int) -> String {
        let words = ["first", "second", "third", "fourth", "fifth", "sixth", "seventh", "eighth", "ninth", "tenth"]
        return words.indices.contains(number - 1) ? words[number - 1] : "\(number)th"
    }
}
