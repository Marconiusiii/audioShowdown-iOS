import Foundation
import UIKit
import Combine

@MainActor
final class GameModel: ObservableObject {
    enum Phase { case waitingForServe, live, paused, gameOver, training }
    enum Server { case player, opponent }
    struct Disc { var x: Double; var y: Double; var vx: Double = 0; var vy: Double = 0 }

    static let width = 600.0
    static let height = 1200.0
    static let center = 600.0
    static let goalHalfWidth = 150.0
    let settings: GameSettings
    let audio = GameAudioEngine()
    let haptics = GameHapticsEngine()

    @Published var puck = Disc(x: 300, y: 600)
    @Published var playerMallet = Disc(x: 300, y: 1020)
    @Published var opponentMallet = Disc(x: 300, y: 180)
    @Published var playerScore = 0
    @Published var opponentScore = 0
    @Published var phase: Phase
    @Published var server: Server = .player
    @Published var serveNumber = 1

    private var previousTime: TimeInterval?
    private var previousPlayerPosition = Disc(x: 300, y: 1020)
    private var nextPingTime: TimeInterval = 0
    private var lastMovementSound: TimeInterval = 0
    private var lastCenterSide = 0
    private var tapCount = 0
    private var lastTapTime: TimeInterval = 0
    private var placingPuck = false
    private let training: Bool

    var isPaused: Bool { phase == .paused }
    var isGameOver: Bool { phase == .gameOver }
    var scoreText: String { "You \(playerScore), Opponent \(opponentScore)" }
    var modeName: String { settings.airHockeyMode ? "Air Hockey" : "Showdown" }
    var puckRadius: Double { [26, 34, 42][settings.puckSize] }

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

    init(settings: GameSettings, training: Bool) {
        self.settings = settings
        self.training = training
        phase = training ? .training : .waitingForServe
        audio.prepare(volume: settings.volume)
    }

    func announceInitialState() {
        if training {
            announce("Training mode. Drag the puck around the table and follow the sound. Double-tap the table to return home.")
        } else {
            announce("Starting \(modeName). \(serveAnnouncement)")
        }
    }

    func tick(_ date: Date) {
        audio.setVolume(settings.volume)
        let now = date.timeIntervalSinceReferenceDate
        guard let previousTime else { self.previousTime = now; return }
        self.previousTime = now
        guard phase == .live else {
            if phase == .training { updatePuckAudio(now: now) }
            return
        }
        let timeScale = 0.45 * pow(2.6 / 0.45, (settings.gameSpeed - 1) / 9)
        let dt = min(now - previousTime, 0.033) * timeScale
        moveOpponent(dt: dt)
        puck.x += puck.vx * dt
        puck.y += puck.vy * dt
        puck.vx *= pow(0.94, dt)
        puck.vy *= pow(0.94, dt)
        collideWithWalls()
        collide(mallet: playerMallet, isPlayer: true)
        collide(mallet: opponentMallet, isPlayer: false)
        detectCenterCrossing()
        detectGoal()
        updatePuckAudio(now: now)
    }

    func touchBegan(at point: CGPoint) {
        if phase == .training {
            puck.x = point.x; puck.y = point.y
            return
        }
        guard phase == .waitingForServe || phase == .live else { return }
        if phase == .waitingForServe {
            if server == .player {
                puck = Disc(x: clamp(point.x, puckRadius, Self.width - puckRadius), y: clamp(point.y, Self.center + puckRadius, Self.height - puckRadius))
                placingPuck = true
                phase = .live
                haptics.play(.serve, level: settings.haptics)
            } else {
                opponentServe()
            }
        }
        movePlayer(to: point)
    }

    func touchMoved(to point: CGPoint) {
        if phase == .training {
            puck.x = clamp(point.x, puckRadius, Self.width - puckRadius)
            puck.y = clamp(point.y, puckRadius, Self.height - puckRadius)
            return
        }
        guard phase == .live, !placingPuck else { return }
        movePlayer(to: point)
    }

    func touchEnded(wasTap: Bool) {
        placingPuck = false
        guard wasTap else { return }
        let now = Date.timeIntervalSinceReferenceDate
        let window = phase == .gameOver || phase == .training ? 0.65 : 0.4
        tapCount = now - lastTapTime < window ? tapCount + 1 : 1
        lastTapTime = now
        if phase == .gameOver, tapCount >= 2 { restart(); tapCount = 0 }
        else if phase == .training, tapCount >= 2 { NotificationCenter.default.post(name: .trainingFinished, object: nil); tapCount = 0 }
        else if phase == .live, tapCount >= 3 { togglePause(); tapCount = 0 }
    }

    func togglePause() {
        guard phase == .live || phase == .paused else { return }
        phase = phase == .paused ? .live : .paused
        previousTime = nil
        announce(phase == .paused ? "Game paused. Settings are available." : "Game resumed.")
    }

    func restart() {
        playerScore = 0; opponentScore = 0; server = .player; serveNumber = 1
        puck = Disc(x: 300, y: 600); phase = .waitingForServe; previousTime = nil
        announce("New \(modeName) game. \(serveAnnouncement)")
    }

    private func movePlayer(to point: CGPoint) {
        let next = Disc(x: clamp(Double(point.x), 44, Self.width - 44), y: clamp(Double(point.y), Self.center + 44, Self.height - 44))
        let dx = next.x - previousPlayerPosition.x
        let dy = next.y - previousPlayerPosition.y
        playerMallet.vx = dx * 28; playerMallet.vy = dy * 28
        playerMallet.x = next.x; playerMallet.y = next.y
        previousPlayerPosition = next
        let now = Date.timeIntervalSinceReferenceDate
        if settings.movementSound > 0, now - lastMovementSound > 0.065, hypot(dx, dy) > 2 {
            audio.malletMovement(style: settings.movementSound, x: next.x / Self.width)
            lastMovementSound = now
        }
    }

    private func moveOpponent(dt: Double) {
        let t = (settings.opponentSkill - 1) / 9
        let maxSpeed = 380 + 670 * t
        let targetX = phase == .live && puck.y < Self.center ? puck.x : 300
        let targetY = phase == .live && puck.y < Self.center ? max(90, puck.y - 80) : 180
        let dx = targetX - opponentMallet.x, dy = targetY - opponentMallet.y
        let length = max(1, hypot(dx, dy)), distance = min(maxSpeed * dt, length)
        opponentMallet.vx = dx / length * maxSpeed; opponentMallet.vy = dy / length * maxSpeed
        opponentMallet.x += dx / length * distance
        opponentMallet.y += dy / length * distance
    }

    private func collideWithWalls() {
        var hitWall = false
        if puck.x < puckRadius { puck.x = puckRadius; puck.vx = abs(puck.vx) * 0.97; hitWall = true }
        if puck.x > Self.width - puckRadius { puck.x = Self.width - puckRadius; puck.vx = -abs(puck.vx) * 0.97; hitWall = true }
        if puck.y < puckRadius, abs(puck.x - 300) >= Self.goalHalfWidth { puck.y = puckRadius; puck.vy = abs(puck.vy) * 0.97; hitWall = true }
        if puck.y > Self.height - puckRadius, abs(puck.x - 300) >= Self.goalHalfWidth { puck.y = Self.height - puckRadius; puck.vy = -abs(puck.vy) * 0.97; hitWall = true }
        if hitWall {
            audio.ricochet(x: puck.x / Self.width, speed: hypot(puck.vx, puck.vy))
            haptics.play(.wall, level: settings.haptics)
        }
    }

    private func collide(mallet: Disc, isPlayer: Bool) {
        let dx = puck.x - mallet.x, dy = puck.y - mallet.y, minimum = puckRadius + 44
        let distance = hypot(dx, dy)
        guard distance < minimum, distance > 0 else { return }
        let nx = dx / distance, ny = dy / distance
        puck.x = mallet.x + nx * minimum; puck.y = mallet.y + ny * minimum
        let impulse = max(520, hypot(mallet.vx, mallet.vy) * 1.25)
        puck.vx = nx * impulse + mallet.vx * 0.65
        puck.vy = ny * impulse + mallet.vy * 0.65
        audio.strike(style: settings.strikeSound, x: puck.x / Self.width)
        haptics.play(.strike, level: settings.haptics)
    }

    private func detectCenterCrossing() {
        let side = puck.y < Self.center ? -1 : 1
        guard lastCenterSide != 0, side != lastCenterSide else { lastCenterSide = side; return }
        lastCenterSide = side
        if settings.centerCrossingSound { audio.centerCrossing(volume: settings.centerCrossingVolume) }
        if !settings.airHockeyMode, hypot(puck.vx, puck.vy) > 1_900, Double.random(in: 0...1) < 0.08 {
            boardBall(againstPlayer: side < 0)
        }
    }

    private func detectGoal() {
        if puck.y < -puckRadius, abs(puck.x - 300) < Self.goalHalfWidth { score(player: true) }
        else if puck.y > Self.height + puckRadius, abs(puck.x - 300) < Self.goalHalfWidth { score(player: false) }
    }

    private func score(player: Bool) {
        let points = Self.pointsPerGoal(airHockeyMode: settings.airHockeyMode)
        if player { playerScore += points } else { opponentScore += points }
        audio.goal(playerScored: player)
        haptics.play(.goal, level: settings.haptics)
        advanceServe(pointToPlayer: player)
        if hasWinner {
            phase = .gameOver
            haptics.play(.gameOver, level: settings.haptics)
            announce("\(playerScore > opponentScore ? "You win!" : "Opponent wins.") Final score, \(scoreText). Double-tap the table to play again.")
        } else {
            phase = .waitingForServe; puck = Disc(x: 300, y: 600)
            announce("\(player ? "Goal!" : "Opponent scores.") \(serveAnnouncement)")
        }
    }

    private func boardBall(againstPlayer: Bool) {
        if againstPlayer { opponentScore += 1 } else { playerScore += 1 }
        audio.boardBall(); haptics.play(.boardBall, level: settings.haptics)
        advanceShowdownServe(); phase = .waitingForServe; puck = Disc(x: 300, y: 600)
        announce("Board Ball. \(againstPlayer ? "Opponent" : "You") scores one point. \(serveAnnouncement)")
    }

    private func advanceServe(pointToPlayer: Bool) {
        if settings.airHockeyMode { server = pointToPlayer ? .opponent : .player }
        else { advanceShowdownServe() }
    }

    private func advanceShowdownServe() {
        (server, serveNumber) = Self.nextShowdownServe(server: server, serveNumber: serveNumber)
    }

    private func opponentServe() {
        puck = Disc(x: opponentMallet.x, y: opponentMallet.y + 60, vx: Double.random(in: -180...180), vy: 650)
        phase = .live; haptics.play(.serve, level: settings.haptics)
    }

    private func updatePuckAudio(now: TimeInterval) {
        guard now >= nextPingTime else { return }
        let distance = max(0, min(1, puck.y / Self.height))
        let approaching = puck.vy > 0
        let base: TimeInterval = [0.24 - 0.17 * (1 - distance), 0.16, 0.28, 0.07][settings.pingRate]
        nextPingTime = now + max(0.055, base)
        audio.puckPing(x: puck.x / Self.width, distance: distance, style: settings.puckSound, pitchBehavior: settings.pitchBehavior, lowerWhenCloser: settings.lowerPitchWhenCloser && approaching)
    }

    private var hasWinner: Bool {
        Self.isWinningScore(player: playerScore, opponent: opponentScore, airHockeyMode: settings.airHockeyMode)
    }

    private var serveAnnouncement: String {
        if settings.airHockeyMode { return "\(server == .player ? "Your" : "Opponent’s") serve. \(scoreText)." }
        let ordinal = ["first", "second", "third", "fourth", "fifth"][serveNumber - 1]
        return "\(server == .player ? "Your" : "Opponent’s") \(ordinal) serve. \(scoreText)."
    }

    private func announce(_ text: String) { UIAccessibility.post(notification: .announcement, argument: text) }
    private func clamp(_ value: Double, _ low: Double, _ high: Double) -> Double { min(max(value, low), high) }
}

extension Notification.Name {
    static let trainingFinished = Notification.Name("AudioShowdownTrainingFinished")
}
