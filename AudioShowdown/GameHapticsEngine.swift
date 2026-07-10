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

        let levelScale = level == .subtle ? 1.0 : 1.45
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
            var result = [
                transient(intensity: 0.48 * scale, sharpness: 0.25, time: 0),
                transient(intensity: 0.30 * scale, sharpness: 0.42, time: 0.075)
            ]
            if intense {
                result.append(transient(intensity: 0.42 * scale, sharpness: 0.55, time: 0.15))
            }
            return result
        case .playerStrike:
            var result = [
                transient(intensity: 1.0 * scale, sharpness: 0.82, time: 0),
                transient(intensity: 0.48 * scale, sharpness: 0.58, time: 0.035)
            ]
            if intense {
                result.append(continuous(intensity: 0.56 * scale, sharpness: 0.42, time: 0.018, duration: 0.055))
                result.append(transient(intensity: 0.44 * scale, sharpness: 0.35, time: 0.085))
            }
            return result
        case .computerStrike:
            var result = [
                transient(intensity: 0.58 * scale, sharpness: 0.50, time: 0),
                transient(intensity: 0.24 * scale, sharpness: 0.35, time: 0.045)
            ]
            if intense {
                result.append(transient(intensity: 0.36 * scale, sharpness: 0.45, time: 0.095))
            }
            return result
        case .wall:
            var result = [
                transient(intensity: 0.82 * scale, sharpness: 0.92, time: 0),
                transient(intensity: 0.34 * scale, sharpness: 0.72, time: 0.028)
            ]
            if intense {
                result.append(continuous(intensity: 0.44 * scale, sharpness: 0.70, time: 0.012, duration: 0.045))
                result.append(transient(intensity: 0.34 * scale, sharpness: 0.55, time: 0.07))
            }
            return result
        case .goal:
            var result = [
                transient(intensity: 0.58 * scale, sharpness: 0.35, time: 0),
                transient(intensity: 0.78 * scale, sharpness: 0.48, time: 0.09),
                transient(intensity: 1.0 * scale, sharpness: 0.68, time: 0.18)
            ]
            if intense {
                result.append(continuous(intensity: 0.72 * scale, sharpness: 0.36, time: 0.02, duration: 0.24))
                result.append(transient(intensity: 0.85 * scale, sharpness: 0.62, time: 0.29))
            }
            return result
        case .boardBall:
            var result = [
                continuous(intensity: 0.82 * scale, sharpness: 0.22, time: 0, duration: 0.13),
                transient(intensity: 1.0 * scale, sharpness: 0.92, time: 0.04),
                transient(intensity: 0.58 * scale, sharpness: 0.52, time: 0.16)
            ]
            if intense {
                result.append(continuous(intensity: 0.72 * scale, sharpness: 0.42, time: 0.11, duration: 0.14))
                result.append(transient(intensity: 0.70 * scale, sharpness: 0.78, time: 0.25))
            }
            return result
        case .gameOver:
            var result = [
                continuous(intensity: 0.50 * scale, sharpness: 0.18, time: 0, duration: 0.18),
                continuous(intensity: 0.72 * scale, sharpness: 0.28, time: 0.20, duration: 0.24),
                transient(intensity: 0.85 * scale, sharpness: 0.42, time: 0.46)
            ]
            if intense {
                result.append(continuous(intensity: 0.92 * scale, sharpness: 0.35, time: 0.50, duration: 0.22))
                result.append(transient(intensity: 1.0 * scale, sharpness: 0.60, time: 0.76))
            }
            return result
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
