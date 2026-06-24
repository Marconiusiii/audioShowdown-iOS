import CoreHaptics

@MainActor
final class GameHapticsEngine {
    enum Cue { case serve, strike, wall, goal, boardBall, gameOver }
    private var engine: CHHapticEngine?

    init() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        do {
            engine = try CHHapticEngine()
            engine?.isAutoShutdownEnabled = true
            engine?.resetHandler = { [weak self] in try? self?.engine?.start() }
            try engine?.start()
        } catch {
            engine = nil
        }
    }

    func play(_ cue: Cue, level: HapticsLevel) {
        guard level != .off, let engine else { return }
        let scale: Float = level == .subtle ? 0.42 : 0.9
        let values: (Float, Float, TimeInterval)
        switch cue {
        case .serve: values = (0.45, 0.35, 0)
        case .strike: values = (0.78, 0.72, 0)
        case .wall: values = (0.32, 0.8, 0)
        case .goal: values = (1, 0.35, 0.16)
        case .boardBall: values = (0.9, 0.95, 0.22)
        case .gameOver: values = (0.8, 0.25, 0.4)
        }
        let parameters = [
            CHHapticEventParameter(parameterID: .hapticIntensity, value: values.0 * scale),
            CHHapticEventParameter(parameterID: .hapticSharpness, value: values.1)
        ]
        let event: CHHapticEvent
        if values.2 > 0 {
            event = CHHapticEvent(eventType: .hapticContinuous, parameters: parameters, relativeTime: 0, duration: values.2)
        } else {
            event = CHHapticEvent(eventType: .hapticTransient, parameters: parameters, relativeTime: 0)
        }
        do {
            try engine.start()
            let pattern = try CHHapticPattern(events: [event], parameters: [])
            try engine.makePlayer(with: pattern).start(atTime: CHHapticTimeImmediate)
        } catch {}
    }
}
