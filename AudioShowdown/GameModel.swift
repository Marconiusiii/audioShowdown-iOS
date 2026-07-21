import Foundation
import UIKit
import Combine

@MainActor
final class GameModel: ObservableObject {
    enum Phase { case waitingForServe, placedServe, live, paused, gameOver, training }
    typealias Server = GameRules.Server
    struct Disc { var x: Double; var y: Double; var vx: Double = 0; var vy: Double = 0 }

    static let width = GameRules.width
    static let height = GameRules.height
    static let center = GameRules.center
    static let goalHalfWidth = GameRules.goalHalfWidth
    static let puckSpeedCap = GameRules.puckSpeedCap
    let settings: GameSettings
    let audio: GameAudioEngine
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
    private var lastCenterSide = 0
    private var tapCount = 0
    private var lastTapTime: TimeInterval = 0
    private var pendingGameOverRestart: DispatchWorkItem?
    private var pendingGameOverAnnouncement: DispatchWorkItem?
    private var serveInputLockedUntil: TimeInterval = 0
    private var placingPuck = false
    private var playerAirHockeyServeCount = 1
    private var computerAirHockeyServeCount = 0
    private var lastPlayerStrikeTime: TimeInterval = 0
    private var lastOpponentStrikeTime: TimeInterval = 0
    private var lastRicochetTime: TimeInterval = 0
    private var recentSideWallHits: [TimeInterval] = []
    private var lastHitByPlayer: Bool?
    private var progressY = 600.0
    private var progressTime: TimeInterval = 0
    private var previousTrainingPoint: CGPoint?
    private var previousTrainingMoveTime: TimeInterval?
    private var phaseBeforePause: Phase?
    private let training: Bool

    var isPaused: Bool { phase == .paused }
    var isGameOver: Bool { phase == .gameOver }
    var scoreText: String { "You: \(playerScore), Computer: \(opponentScore)" }
    var puckRadius: Double { [26, 34, 42][settings.puckSize] }
    var snapshot: GameSnapshot {
        GameSnapshot(
            puck: puck.snapshotDisc,
            playerPaddle: playerMallet.snapshotDisc,
            opponentPaddle: opponentMallet.snapshotDisc,
            playerScore: playerScore,
            opponentScore: opponentScore,
            phase: phase.snapshotPhase,
            server: server.snapshotServer,
            serveNumber: serveNumber
        )
    }

    static func pointsPerGoal(airHockeyMode: Bool) -> Int {
        GameRules.pointsPerGoal(airHockeyMode: airHockeyMode)
    }

    static func isWinningScore(player: Int, opponent: Int, airHockeyMode: Bool) -> Bool {
        GameRules.isWinningScore(player: player, opponent: opponent, airHockeyMode: airHockeyMode)
    }

    static func nextShowdownServe(server: Server, serveNumber: Int) -> (Server, Int) {
        GameRules.nextShowdownServe(server: server, serveNumber: serveNumber)
    }

    static func playerProximity(forY y: Double) -> Double {
        GameRules.playerProximity(forY: y)
    }

    static func puckPulseInterval(speed: Int, speedsUpWhenApproaching: Bool, proximity: Double) -> TimeInterval {
        GameRules.puckPulseInterval(speed: speed, speedsUpWhenApproaching: speedsUpWhenApproaching, proximity: proximity)
    }

    static func shapedStrikeVelocity(vx: Double, vy: Double, byPlayer: Bool) -> (vx: Double, vy: Double) {
        GameRules.shapedStrikeVelocity(vx: vx, vy: vy, byPlayer: byPlayer)
    }

    static func recoveredPuckVelocity(vx: Double, vy: Double, byPlayer: Bool) -> (vx: Double, vy: Double) {
        GameRules.recoveredPuckVelocity(vx: vx, vy: vy, byPlayer: byPlayer)
    }

    static func cappedVelocity(vx: Double, vy: Double) -> (vx: Double, vy: Double) {
        GameRules.cappedVelocity(vx: vx, vy: vy)
    }

    static func gameTimeScale(speed: Double) -> Double {
        GameRules.gameTimeScale(speed: speed)
    }

    static func serveAnnouncement(server: Server, serveNumber: Int, playerScore: Int, computerScore: Int) -> String {
        GameRules.serveAnnouncement(server: server, serveNumber: serveNumber, playerScore: playerScore, computerScore: computerScore)
    }

    init(settings: GameSettings, training: Bool, audio: GameAudioEngine) {
        self.settings = settings
        self.training = training
        self.audio = audio
        phase = training ? .training : .waitingForServe
    }

    func announceInitialState() {
        if training {
            announce("Training mode. Drag the puck around the table and follow the sound. Double-tap the table to return home.")
        } else {
            announce(serveAnnouncement)
        }
    }

    func tick(_ date: Date) {
        audio.setVolume(settings.volume)
        audio.setReverb(settings.reverbStyle)
        audio.setPuckVolume(settings.puckVolume)
        let now = date.timeIntervalSinceReferenceDate
        guard let previousTime else { self.previousTime = now; return }
        self.previousTime = now
        guard phase == .live else {
            if phase == .training || phase == .placedServe { updatePuckAudio(now: now) }
            else { audio.stopSmoothPuck() }
            return
        }
        let realDt = min(now - previousTime, 0.033)
        let timeScale = Self.gameTimeScale(speed: settings.gameSpeed)
        moveOpponent(realDt: realDt, timeScale: timeScale)
        let substeps = max(3, Int(ceil(timeScale * 3)))
        let scaledStep = realDt * timeScale / Double(substeps)
        let realStep = realDt / Double(substeps)
        for _ in 0..<substeps {
            puck.x += puck.vx * scaledStep
            puck.y += puck.vy * scaledStep
            puck.vx *= exp(-GameRules.friction * realStep)
            puck.vy *= exp(-GameRules.friction * realStep)
            capPuckSpeed()
            collideWithWalls()
            collide(mallet: playerMallet, isPlayer: true)
            collide(mallet: opponentMallet, isPlayer: false)
            capPuckSpeed()
        }
        if !unpin(from: playerMallet) {
            _ = unpin(from: opponentMallet)
        }
        capPuckSpeed()
        recoverDeadPuck(now: now)
        detectCenterCrossing()
        detectGoal()
        updatePuckAudio(now: now)
    }

    func touchBegan(at point: CGPoint) {
        if phase == .training {
            let clamped = CGPoint(
                x: clamp(Double(point.x), puckRadius, Self.width - puckRadius),
                y: clamp(Double(point.y), puckRadius, Self.height - puckRadius)
            )
            puck.x = clamped.x
            puck.y = clamped.y
            puck.vx = 0
            puck.vy = 0
            previousTrainingPoint = clamped
            previousTrainingMoveTime = Date.timeIntervalSinceReferenceDate
            lastCenterSide = puck.y < Self.center ? -1 : 1
            return
        }
        guard phase == .waitingForServe || phase == .placedServe || phase == .live else { return }
        if phase == .waitingForServe || phase == .placedServe {
            guard Date.timeIntervalSinceReferenceDate >= serveInputLockedUntil else { return }
        }
        if (phase == .waitingForServe || phase == .placedServe), point.y < Self.center {
            return
        }
        if phase == .waitingForServe {
            if server == .player {
                puck = Disc(x: clamp(point.x, puckRadius, Self.width - puckRadius), y: clamp(point.y, Self.center + puckRadius, Self.height - puckRadius))
                placingPuck = true
                resetPuckRecoveryState()
                phase = .placedServe
                haptics.play(.serve, level: settings.haptics)
            } else {
                opponentServe()
            }
        }
        movePlayer(to: point, allowStrike: false)
        if phase == .live {
            resolvePlayerDirectContact()
        }
    }

    func touchMoved(to point: CGPoint) {
        if phase == .training {
            let previousY = puck.y
            let clamped = CGPoint(
                x: clamp(Double(point.x), puckRadius, Self.width - puckRadius),
                y: clamp(Double(point.y), puckRadius, Self.height - puckRadius)
            )
            let now = Date.timeIntervalSinceReferenceDate
            if let previousTrainingPoint, let previousTrainingMoveTime {
                let dt = max(0.008, now - previousTrainingMoveTime)
                puck.vx = (clamped.x - previousTrainingPoint.x) / dt
                puck.vy = (clamped.y - previousTrainingPoint.y) / dt
                let speed = hypot(puck.vx, puck.vy)
                if settings.smoothPuckSound == 3, speed > 260 {
                    audio.energizeSmoothPuck(amount: speed / 2_200)
                }
            }
            puck.x = clamped.x
            puck.y = clamped.y
            detectTrainingCenterCrossing(previousY: previousY)
            previousTrainingPoint = clamped
            previousTrainingMoveTime = now
            return
        }
        guard phase == .live || phase == .placedServe else { return }
        movePlayer(to: point)
    }

    func touchEnded(wasTap: Bool, at _: CGPoint) {
        audio.stopMalletSlide()
        placingPuck = false
        guard wasTap else { return }
        let now = Date.timeIntervalSinceReferenceDate
        let window = phase == .gameOver || phase == .training ? 0.65 : 0.4
        tapCount = now - lastTapTime < window ? tapCount + 1 : 1
        lastTapTime = now
        if (phase == .waitingForServe || phase == .placedServe || phase == .live), tapCount >= 2 {
            togglePause()
            tapCount = 0
        } else if phase == .gameOver {
            if tapCount >= 3 {
                pendingGameOverRestart?.cancel()
                pendingGameOverRestart = nil
                pendingGameOverAnnouncement?.cancel()
                pendingGameOverAnnouncement = nil
                tapCount = 0
                NotificationCenter.default.post(name: .gameOverReturnHome, object: nil)
            } else if tapCount == 2 {
                scheduleGameOverRestart()
            }
        } else if phase == .training, tapCount >= 2 { NotificationCenter.default.post(name: .trainingFinished, object: nil); tapCount = 0 }
    }

    func togglePause() {
        guard phase == .waitingForServe || phase == .placedServe || phase == .live || phase == .paused else { return }
        audio.stopMalletSlide()
        audio.stopSmoothPuck()
        if phase == .paused {
            phase = phaseBeforePause ?? .live
            phaseBeforePause = nil
        } else {
            phaseBeforePause = phase
            phase = .paused
        }
        previousTime = nil
        announce(phase == .paused ? "Game paused. Settings are available." : "Game resumed.")
    }

    func stopContinuousAudio() {
        audio.stopSmoothPuck()
        audio.stopMalletSlide()
    }

    func restart() {
        pendingGameOverRestart?.cancel()
        pendingGameOverRestart = nil
        pendingGameOverAnnouncement?.cancel()
        pendingGameOverAnnouncement = nil
        playerScore = 0; opponentScore = 0; server = .player; serveNumber = 1
        playerAirHockeyServeCount = 1; computerAirHockeyServeCount = 0
        phaseBeforePause = nil
        puck = Disc(x: 300, y: 600); phase = .waitingForServe; previousTime = nil
        recentSideWallHits = []
        resetPuckRecoveryState()
        announce(serveAnnouncement)
    }

    private func movePlayer(to point: CGPoint, allowStrike: Bool = true) {
        let next = Disc(x: clamp(Double(point.x), 44, Self.width - 44), y: clamp(Double(point.y), Self.center + 44, Self.height - 44))
        let previous = previousPlayerPosition
        let dx = next.x - previousPlayerPosition.x
        let dy = next.y - previousPlayerPosition.y
        playerMallet.vx = dx * 28; playerMallet.vy = dy * 28
        playerMallet.x = next.x; playerMallet.y = next.y
        previousPlayerPosition = next
        if allowStrike, phase == .placedServe || phase == .live, sweptPlayerStrike(from: previous, to: next) {
            placingPuck = false
            phase = .live
        } else if phase == .live {
            resolvePlayerDirectContact()
        }
        let movementSpeed = hypot(playerMallet.vx, playerMallet.vy)
        if movementSpeed > 60 {
            audio.updateMalletSlide(x: next.x / Self.width, speed: movementSpeed, volume: settings.malletSlideVolume)
        } else {
            audio.stopMalletSlide()
        }
    }

    private func moveOpponent(realDt: Double, timeScale: Double) {
        let t = (settings.opponentSkill - 1) / 9
        let maxSpeed = 380 + 670 * t
        let puckSpeed = hypot(puck.vx, puck.vy)
        let slowNearOpponentGoal = puck.y < 150 && puckSpeed < 420
        let targetX = phase == .live && puck.y < Self.center && !slowNearOpponentGoal ? puck.x : 300.0
        let targetY: Double
        if phase == .live && puck.y < Self.center {
            targetY = slowNearOpponentGoal ? 210.0 : max(90.0, puck.y - 80)
        } else {
            targetY = 180.0
        }
        let dx = targetX - opponentMallet.x, dy = targetY - opponentMallet.y
        let length = max(1, hypot(dx, dy)), distance = min(maxSpeed * realDt * timeScale, length)
        let previousX = opponentMallet.x
        let previousY = opponentMallet.y
        opponentMallet.x = clamp(opponentMallet.x + dx / length * distance, 44, Self.width - 44)
        opponentMallet.y = clamp(opponentMallet.y + dy / length * distance, 44, Self.center - 44)
        opponentMallet.vx = realDt > 0 ? (opponentMallet.x - previousX) / realDt : 0
        opponentMallet.vy = realDt > 0 ? (opponentMallet.y - previousY) / realDt : 0
    }

    private func collideWithWalls() {
        var hitWall = false
        var hitSideWall = false
        if puck.x < puckRadius { puck.x = puckRadius; puck.vx = abs(puck.vx) * GameRules.wallRestitution; hitWall = true; hitSideWall = true }
        if puck.x > Self.width - puckRadius { puck.x = Self.width - puckRadius; puck.vx = -abs(puck.vx) * GameRules.wallRestitution; hitWall = true; hitSideWall = true }
        if puck.y < puckRadius, abs(puck.x - 300) >= Self.goalHalfWidth { puck.y = puckRadius; puck.vy = abs(puck.vy) * GameRules.wallRestitution; hitWall = true }
        if puck.y > Self.height - puckRadius, abs(puck.x - 300) >= Self.goalHalfWidth { puck.y = Self.height - puckRadius; puck.vy = -abs(puck.vy) * GameRules.wallRestitution; hitWall = true }
        if hitWall {
            let now = Date.timeIntervalSinceReferenceDate
            if hitSideWall {
                softenSideWallRally(now: now)
            }
            guard now - lastRicochetTime >= 0.055 else { return }
            lastRicochetTime = now
            let impactSpeed = hypot(puck.vx, puck.vy)
            audio.energizeSmoothPuck(amount: impactSpeed / 2_800)
            audio.ricochet(x: puck.x / Self.width, speed: impactSpeed)
            haptics.play(.wall, level: settings.haptics, strength: impactSpeed / 1_400)
        }
    }

    private func collide(mallet: Disc, isPlayer: Bool) {
        let dx = puck.x - mallet.x, dy = puck.y - mallet.y, minimum = puckRadius + 44
        let distance = hypot(dx, dy)
        guard distance < minimum, distance > 0 else { return }
        let nx = dx / distance, ny = dy / distance
        let relativeVx = puck.vx - mallet.vx
        let relativeVy = puck.vy - mallet.vy
        let normalVelocity = relativeVx * nx + relativeVy * ny
        let overlap = minimum - distance
        puck.x += nx * overlap
        puck.y += ny * overlap
        guard normalVelocity < 0 else { return }
        let impulse = -1.85 * normalVelocity
        puck.vx += impulse * nx
        puck.vy += impulse * ny
        if -normalVelocity > 40 {
            shapeStrike(byPlayer: isPlayer)
        }
        if -normalVelocity > 100 {
            playStrikeIfReady(byPlayer: isPlayer, speed: hypot(puck.vx, puck.vy))
        }
    }

    private func resolvePlayerDirectContact() {
        let dx = puck.x - playerMallet.x
        let dy = puck.y - playerMallet.y
        let distance = hypot(dx, dy)
        let minimum = puckRadius + playerAssistRadius()
        guard distance < minimum else { return }
        let nx: Double
        let ny: Double
        if distance < 0.001 {
            nx = 0
            ny = -1
        } else {
            nx = dx / distance
            ny = dy / distance
        }
        puck.x = clamp(playerMallet.x + nx * (minimum + 1), puckRadius, Self.width - puckRadius)
        puck.y = clamp(playerMallet.y + ny * (minimum + 1), puckRadius, Self.height - puckRadius)
        puck.vx = playerMallet.vx * 0.75 + nx * 160
        puck.vy = playerMallet.vy * 0.75
        shapeStrike(byPlayer: true)
        capPuckSpeed()
        playStrikeIfReady(byPlayer: true, speed: hypot(puck.vx, puck.vy))
    }

    private func sweptPlayerStrike(from start: Disc, to end: Disc) -> Bool {
        let sx = end.x - start.x
        let sy = end.y - start.y
        let lengthSquared = sx * sx + sy * sy
        guard lengthSquared >= 1 else { return false }
        let along = clamp(((puck.x - start.x) * sx + (puck.y - start.y) * sy) / lengthSquared, 0, 1)
        let closestX = start.x + sx * along
        let closestY = start.y + sy * along
        var dx = puck.x - closestX
        var dy = puck.y - closestY
        var distance = hypot(dx, dy)
        let minimum = puckRadius + playerAssistRadius()
        guard distance < minimum else { return false }
        if distance < 0.001 {
            dx = 0
            dy = -1
            distance = 1
        }
        let nx = dx / distance
        let ny = dy / distance
        puck.x = clamp(closestX + nx * (minimum + 1), puckRadius, Self.width - puckRadius)
        puck.y = clamp(closestY + ny * (minimum + 1), puckRadius, Self.height - puckRadius)
        puck.vx += playerMallet.vx * 0.9
        puck.vy += playerMallet.vy * 0.9
        shapeStrike(byPlayer: true)
        capPuckSpeed()
        playStrikeIfReady(byPlayer: true, speed: hypot(puck.vx, puck.vy))
        return true
    }

    private func shapeStrike(byPlayer: Bool) {
        let shaped = Self.shapedStrikeVelocity(vx: puck.vx, vy: puck.vy, byPlayer: byPlayer)
        puck.vx = shaped.vx
        puck.vy = shaped.vy
        lastHitByPlayer = byPlayer
        progressY = puck.y
        progressTime = Date.timeIntervalSinceReferenceDate
    }

    private func playStrikeIfReady(byPlayer: Bool, speed: Double) {
        let now = Date.timeIntervalSinceReferenceDate
        if byPlayer {
            guard now - lastPlayerStrikeTime >= 0.075 else { return }
            lastPlayerStrikeTime = now
        } else {
            guard now - lastOpponentStrikeTime >= 0.075 else { return }
            lastOpponentStrikeTime = now
        }
        audio.strike(style: settings.strikeSound, x: puck.x / Self.width, byPlayer: byPlayer)
        audio.energizeSmoothPuck(amount: speed / 2_400)
        haptics.play(
            byPlayer ? .playerStrike : .computerStrike,
            level: settings.haptics,
            strength: speed / 1_600
        )
    }

    private func capPuckSpeed() {
        let capped = Self.cappedVelocity(vx: puck.vx, vy: puck.vy)
        puck.vx = capped.vx
        puck.vy = capped.vy
    }

    private func playerAssistRadius() -> Double {
        50
    }

    private func softenSideWallRally(now: TimeInterval) {
        recentSideWallHits.append(now)
        recentSideWallHits.removeAll { now - $0 > 1.15 }
        guard recentSideWallHits.count >= 4 else { return }
        let horizontal = abs(puck.vx)
        let vertical = abs(puck.vy)
        guard horizontal > 520, horizontal > vertical * 2.7 else { return }
        let direction: Double
        if abs(puck.vy) > 1 {
            direction = puck.vy > 0 ? 1 : -1
        } else if let lastHitByPlayer {
            direction = lastHitByPlayer ? -1 : 1
        } else {
            direction = puck.y >= Self.center ? -1 : 1
        }
        let speed = hypot(puck.vx, puck.vy)
        let targetVy = min(max(210, speed * 0.24), speed * 0.40)
        let reducedVx = puck.vx * 0.82
        puck.vx = reducedVx
        puck.vy = direction * max(vertical, targetVy)
        capPuckSpeed()
        recentSideWallHits.removeFirst(max(0, recentSideWallHits.count - 2))
    }

    private func unpin(from mallet: Disc) -> Bool {
        let dx = puck.x - mallet.x
        let dy = puck.y - mallet.y
        let distance = hypot(dx, dy)
        let minimum = puckRadius + 44
        guard distance < minimum else { return false }
        let isOpponent = mallet.y < Self.center
        var escapeX = Self.width / 2 - puck.x
        var escapeY = isOpponent && puck.y < 140 ? 1 : Self.center - puck.y
        var escapeLength = hypot(escapeX, escapeY)
        if escapeLength < 1 {
            escapeX = puck.x < Self.width / 2 ? 1 : -1
            escapeY = puck.y < Self.center ? 1 : -1
            escapeLength = hypot(escapeX, escapeY)
        }
        escapeX /= escapeLength
        escapeY /= escapeLength
        let distanceOrOne = max(distance, 1)
        escapeX = escapeX * 0.6 + dx / distanceOrOne * 0.4
        escapeY = escapeY * 0.6 + dy / distanceOrOne * 0.4
        escapeLength = max(1, hypot(escapeX, escapeY))
        escapeX /= escapeLength
        escapeY /= escapeLength
        puck.x = clamp(puck.x + escapeX * (minimum - distance + 6), puckRadius, Self.width - puckRadius)
        puck.y = clamp(puck.y + escapeY * (minimum - distance + 6), puckRadius, Self.height - puckRadius)
        let kick = max(hypot(puck.vx, puck.vy), 300)
        puck.vx = escapeX * kick
        puck.vy = escapeY * kick
        capPuckSpeed()
        return true
    }

    private func recoverDeadPuck(now: TimeInterval) {
        let speed = hypot(puck.vx, puck.vy)
        if progressTime == 0 {
            progressY = puck.y
            progressTime = now
            return
        }
        if abs(puck.y - progressY) >= 90 {
            progressY = puck.y
            progressTime = now
            return
        }
        let creeping = speed < 260 && abs(puck.vy) < 155
        let stalled = speed < GameRules.deadSpeed
        let tooLateral = abs(puck.vy) < GameRules.deadVerticalSpeed
        guard stalled || tooLateral || creeping else { return }
        let delay = creeping ? 0.85 : (stalled ? 0.95 : 1.35)
        guard now - progressTime >= delay else { return }
        let recoveryHitByPlayer = lastHitByPlayer ?? (puck.y >= Self.center)
        let recovered = Self.recoveredPuckVelocity(vx: puck.vx, vy: puck.vy, byPlayer: recoveryHitByPlayer)
        puck.vx = recovered.vx
        puck.vy = recovered.vy
        capPuckSpeed()
        progressY = puck.y
        progressTime = now
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

    private func detectTrainingCenterCrossing(previousY: Double) {
        guard settings.centerCrossingSound else { return }
        let crossed = (previousY < Self.center && puck.y >= Self.center) || (previousY > Self.center && puck.y <= Self.center)
        guard crossed else { return }
        audio.centerCrossing(volume: settings.centerCrossingVolume)
    }

    private func detectGoal() {
        if puck.y < -puckRadius, abs(puck.x - 300) < Self.goalHalfWidth { score(player: true) }
        else if puck.y > Self.height + puckRadius, abs(puck.x - 300) < Self.goalHalfWidth { score(player: false) }
    }

    private func score(player: Bool) {
        let points = Self.pointsPerGoal(airHockeyMode: settings.airHockeyMode)
        if player { playerScore += points } else { opponentScore += points }
        advanceServe(pointToPlayer: player)
        if hasWinner {
            phase = .gameOver
            audio.stopSmoothPuck()
            let playerWon = playerScore > opponentScore
            if playerWon { audio.matchWon() }
            else { audio.matchLost() }
            haptics.play(.gameOver, level: settings.haptics)
            scheduleGameOverAnnouncement(
                "\(playerWon ? "You win!" : "Computer wins.") Final score, \(scoreText). Double-tap the table to play again. Triple-tap to return home.",
                delay: playerWon ? 1.45 : 1.15
            )
        } else {
            audio.goal(playerScored: player)
            audio.stopSmoothPuck()
            haptics.play(.goal, level: settings.haptics)
            phase = .waitingForServe; puck = Disc(x: 300, y: 600)
            resetPuckRecoveryState()
            lockServeInput(for: 1.1)
            announce(serveAnnouncement)
        }
    }

    private func boardBall(againstPlayer: Bool) {
        if againstPlayer { opponentScore += 1 } else { playerScore += 1 }
        audio.boardBall(); haptics.play(.boardBall, level: settings.haptics)
        audio.stopSmoothPuck()
        advanceShowdownServe()
        puck = Disc(x: 300, y: 600)
        resetPuckRecoveryState()
        if hasWinner {
            phase = .gameOver
            haptics.play(.gameOver, level: settings.haptics)
            let playerWon = playerScore > opponentScore
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.32) { [weak self] in
                guard let self, self.phase == .gameOver else { return }
                if playerWon { self.audio.matchWon() }
                else { self.audio.matchLost() }
            }
            scheduleGameOverAnnouncement(
                "Board Ball. \(againstPlayer ? "Computer" : "You") wins. Final score, \(scoreText). Double-tap the table to play again. Triple-tap to return home.",
                delay: playerWon ? 1.75 : 1.45
            )
        } else {
            phase = .waitingForServe
            lockServeInput(for: 1.1)
            announce("Board Ball. \(againstPlayer ? "Computer" : "You") scores one point. \(serveAnnouncement)")
        }
    }

    private func advanceServe(pointToPlayer: Bool) {
        if settings.airHockeyMode {
            server = pointToPlayer ? .opponent : .player
            if server == .player { playerAirHockeyServeCount += 1 }
            else { computerAirHockeyServeCount += 1 }
        } else {
            advanceShowdownServe()
        }
    }

    private func advanceShowdownServe() {
        (server, serveNumber) = Self.nextShowdownServe(server: server, serveNumber: serveNumber)
    }

    private func opponentServe() {
        puck = Disc(x: opponentMallet.x, y: opponentMallet.y + 60, vx: Double.random(in: -180...180), vy: 650)
        lastHitByPlayer = false
        progressY = puck.y
        progressTime = Date.timeIntervalSinceReferenceDate
        phase = .live; haptics.play(.serve, level: settings.haptics)
    }

    private func resetPuckRecoveryState() {
        lastHitByPlayer = nil
        progressY = puck.y
        progressTime = Date.timeIntervalSinceReferenceDate
    }

    private func lockServeInput(for duration: TimeInterval) {
        serveInputLockedUntil = Date.timeIntervalSinceReferenceDate + duration
    }

    private func updatePuckAudio(now: TimeInterval) {
        let proximity = Self.playerProximity(forY: puck.y)
        if settings.puckTrackingStyle == .smooth {
            audio.updateSmoothPuck(
                style: settings.smoothPuckSound,
                x: puck.x / Self.width,
                proximity: proximity,
                speed: hypot(puck.vx, puck.vy),
                volume: settings.puckVolume,
                pitchBehavior: settings.pitchBehavior,
                pitchChangesWithDistance: settings.pitchChangesWithDistance,
                lowerWhenCloser: settings.lowerPitchWhenCloser,
                volumeChangesWithDistance: settings.volumeChangesWithDistance
            )
            return
        }
        audio.stopSmoothPuck()
        guard now >= nextPingTime else { return }
        let base = Self.puckPulseInterval(
            speed: settings.pingRate,
            speedsUpWhenApproaching: settings.speedsUpWhenApproaching,
            proximity: proximity
        )
        nextPingTime = now + max(0.085, base)
        audio.puckPing(
            x: puck.x / Self.width,
            distance: proximity,
            style: settings.puckSound,
            pitchBehavior: settings.pitchBehavior,
            pitchChangesWithDistance: settings.pitchChangesWithDistance,
            lowerWhenCloser: settings.lowerPitchWhenCloser,
            volumeChangesWithDistance: settings.volumeChangesWithDistance
        )
    }

    private func scheduleGameOverRestart() {
        pendingGameOverRestart?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self, self.phase == .gameOver, self.tapCount == 2 else { return }
            self.tapCount = 0
            self.restart()
        }
        pendingGameOverRestart = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: workItem)
    }

    private func scheduleGameOverAnnouncement(_ text: String, delay: TimeInterval) {
        pendingGameOverAnnouncement?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self, self.phase == .gameOver else { return }
            self.announce(text)
        }
        pendingGameOverAnnouncement = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private var hasWinner: Bool {
        Self.isWinningScore(player: playerScore, opponent: opponentScore, airHockeyMode: settings.airHockeyMode)
    }

    private var serveAnnouncement: String {
        let currentServeNumber: Int
        if settings.airHockeyMode {
            currentServeNumber = server == .player ? playerAirHockeyServeCount : computerAirHockeyServeCount
        } else {
            currentServeNumber = serveNumber
        }
        return Self.serveAnnouncement(
            server: server,
            serveNumber: currentServeNumber,
            playerScore: playerScore,
            computerScore: opponentScore
        )
    }

    private func announce(_ text: String) { UIAccessibility.post(notification: .announcement, argument: text) }
    private func clamp(_ value: Double, _ low: Double, _ high: Double) -> Double { min(max(value, low), high) }
}

extension Notification.Name {
    static let trainingFinished = Notification.Name("AudioShowdownTrainingFinished")
    static let gameOverReturnHome = Notification.Name("AudioShowdownGameOverReturnHome")
}

private extension GameModel.Disc {
    var snapshotDisc: GameSnapshot.Disc {
        GameSnapshot.Disc(x: x, y: y, vx: vx, vy: vy)
    }
}

private extension GameModel.Phase {
    var snapshotPhase: GameSnapshot.Phase {
        switch self {
        case .waitingForServe: .waitingForServe
        case .placedServe: .placedServe
        case .live: .live
        case .paused: .paused
        case .gameOver: .gameOver
        case .training: .training
        }
    }
}

private extension GameModel.Server {
    var snapshotServer: GameSnapshot.Server {
        switch self {
        case .player: .player
        case .opponent: .opponent
        }
    }
}
