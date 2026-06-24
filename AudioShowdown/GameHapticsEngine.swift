import CoreHaptics
import Foundation

@MainActor
final class GameHapticsEngine {
    enum Cue: Hashable {
        case serve
        case playerStrike
        case computerStrike
        case wall
        case goal
        case boardBall
        case gameOver
    }

    private var engine: CHHapticEngine?
    private var lastPlayed: [Cue: TimeInterval] = [:]

    init() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        do {
            let engine = try CHHapticEngine()
            engine.isAutoShutdownEnabled = false
            engine.resetHandler = { [weak self] in
                try? self?.engine?.start()
            }
            engine.stoppedHandler = { [weak self] _ in
                try? self?.engine?.start()
            }
            try engine.start()
            self.engine = engine
        } catch {
            engine = nil
        }
    }

    func play(_ cue: Cue, level: HapticsLevel, strength: Double = 1) {
        guard level != .off, let engine else { return }
        let now = ProcessInfo.processInfo.systemUptime
        guard now - (lastPlayed[cue] ?? 0) >= cooldown(for: cue) else { return }
        lastPlayed[cue] = now

        let levelScale = level == .subtle ? 0.52 : 1.0
        let strengthScale = min(max(strength, 0.25), 1)
        let scale = Float(levelScale * strengthScale)
        let events = events(for: cue, scale: scale, intense: level == .intense)

        do {
            try engine.start()
            let pattern = try CHHapticPattern(events: events, parameters: [])
            let player = try engine.makePlayer(with: pattern)
            try player.start(atTime: CHHapticTimeImmediate)
        } catch {}
    }

    private func events(for cue: Cue, scale: Float, intense: Bool) -> [CHHapticEvent] {
        switch cue {
        case .serve:
            return [
                transient(intensity: 0.48 * scale, sharpness: 0.25, time: 0),
                transient(intensity: 0.30 * scale, sharpness: 0.42, time: 0.075)
            ]
        case .playerStrike:
            var result = [
                transient(intensity: 1.0 * scale, sharpness: 0.82, time: 0),
                transient(intensity: 0.48 * scale, sharpness: 0.58, time: 0.035)
            ]
            if intense { result.append(transient(intensity: 0.26 * scale, sharpness: 0.35, time: 0.075)) }
            return result
        case .computerStrike:
            return [
                transient(intensity: 0.58 * scale, sharpness: 0.50, time: 0),
                transient(intensity: 0.24 * scale, sharpness: 0.35, time: 0.045)
            ]
        case .wall:
            var result = [
                transient(intensity: 0.82 * scale, sharpness: 0.92, time: 0),
                transient(intensity: 0.34 * scale, sharpness: 0.72, time: 0.028)
            ]
            if intense { result.append(transient(intensity: 0.18 * scale, sharpness: 0.55, time: 0.06)) }
            return result
        case .goal:
            return [
                transient(intensity: 0.58 * scale, sharpness: 0.35, time: 0),
                transient(intensity: 0.78 * scale, sharpness: 0.48, time: 0.09),
                transient(intensity: 1.0 * scale, sharpness: 0.68, time: 0.18)
            ]
        case .boardBall:
            return [
                continuous(intensity: 0.82 * scale, sharpness: 0.22, time: 0, duration: 0.13),
                transient(intensity: 1.0 * scale, sharpness: 0.92, time: 0.04),
                transient(intensity: 0.58 * scale, sharpness: 0.52, time: 0.16)
            ]
        case .gameOver:
            return [
                continuous(intensity: 0.50 * scale, sharpness: 0.18, time: 0, duration: 0.18),
                continuous(intensity: 0.72 * scale, sharpness: 0.28, time: 0.20, duration: 0.24),
                transient(intensity: 0.85 * scale, sharpness: 0.42, time: 0.46)
            ]
        }
    }

    private func transient(intensity: Float, sharpness: Float, time: TimeInterval) -> CHHapticEvent {
        CHHapticEvent(
            eventType: .hapticTransient,
            parameters: parameters(intensity: intensity, sharpness: sharpness),
            relativeTime: time
        )
    }

    private func continuous(intensity: Float, sharpness: Float, time: TimeInterval, duration: TimeInterval) -> CHHapticEvent {
        CHHapticEvent(
            eventType: .hapticContinuous,
            parameters: parameters(intensity: intensity, sharpness: sharpness),
            relativeTime: time,
            duration: duration
        )
    }

    private func parameters(intensity: Float, sharpness: Float) -> [CHHapticEventParameter] {
        [
            CHHapticEventParameter(parameterID: .hapticIntensity, value: min(max(intensity, 0), 1)),
            CHHapticEventParameter(parameterID: .hapticSharpness, value: min(max(sharpness, 0), 1))
        ]
    }

    private func cooldown(for cue: Cue) -> TimeInterval {
        switch cue {
        case .serve: 0.18
        case .playerStrike: 0.055
        case .computerStrike: 0.07
        case .wall: 0.075
        case .goal, .boardBall: 0.30
        case .gameOver: 0.50
        }
    }
}
