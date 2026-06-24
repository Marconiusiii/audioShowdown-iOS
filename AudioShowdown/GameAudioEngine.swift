import AVFoundation

@MainActor
final class GameAudioEngine {
    private enum Wave { case sine, triangle, square, saw }
    private let engine = AVAudioEngine()
    private let puckPlayer = AVAudioPlayerNode()
    private let effectsPlayer = AVAudioPlayerNode()
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2)!
    private var started = false

    init() {
        engine.attach(puckPlayer)
        engine.attach(effectsPlayer)
        engine.connect(puckPlayer, to: engine.mainMixerNode, format: format)
        engine.connect(effectsPlayer, to: engine.mainMixerNode, format: format)
    }

    func prepare(volume: Double) {
        engine.mainMixerNode.outputVolume = Float(volume)
        guard !started else { return }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
            try engine.start()
            started = true
        } catch {}
    }

    func setVolume(_ volume: Double) { engine.mainMixerNode.outputVolume = Float(volume) }

    func puckPing(x: Double, distance: Double, style: Int, pitchBehavior: Int, lowerWhenCloser: Bool) {
        let closeness = 1 - max(0, min(1, distance))
        let pitchRange = [0.0, 0.6, 1.4][pitchBehavior]
        var pitch = pitchRange == 0 ? 1 : pow(2, (lowerWhenCloser ? 1 - closeness : closeness) * pitchRange - pitchRange / 2)
        if style == 10 || style == 11 { pitch = pentatonicPitch(closeness: closeness, range: pitchRange, lower: lowerWhenCloser) }
        puckPlayer.pan = Float(max(-1, min(1, x * 2 - 1)))
        puckPlayer.volume = Float(0.2 + closeness * 0.8)
        switch style {
        case 0: play(player: puckPlayer, frequency: 560 * pitch, endFrequency: 430 * pitch, duration: 0.07, noise: 0.2, wave: .triangle)
        case 1: play(player: puckPlayer, frequency: 700 * pitch, duration: 0.26, harmonics: [(2, 0.24)])
        case 2: play(player: puckPlayer, frequency: 3_500 * pitch, duration: 0.02, noise: 0.9)
        case 3: play(player: puckPlayer, frequency: 880 * pitch, duration: 0.09)
        case 4: play(player: puckPlayer, frequency: 620 * pitch, duration: 0.08, wave: .square)
        case 5: play(player: puckPlayer, frequency: 540 * pitch, endFrequency: 470 * pitch, duration: 0.13, wave: .triangle)
        case 6: play(player: puckPlayer, frequency: 540 * pitch, duration: 0.12, harmonics: [(800.0 / 540.0, 0.55)], wave: .square)
        case 7: play(player: puckPlayer, frequency: 2_000 * pitch, duration: 0.04, noise: 0.3)
        case 8: play(player: puckPlayer, frequency: 1_300 * pitch, endFrequency: 480 * pitch, duration: 0.16)
        case 9: play(player: puckPlayer, frequency: 990 * pitch, endFrequency: 1_080 * pitch, duration: 0.3)
        case 10: play(player: puckPlayer, frequency: 220 * pitch, duration: 0.2, harmonics: [(2, 0.5), (3, 0.22)], wave: .triangle)
        case 11: play(player: puckPlayer, frequency: 440 * pitch, duration: 0.4, harmonics: [(2.76, 0.5), (5.4, 0.3)])
        case 12: play(player: puckPlayer, frequency: 1_760 * pitch, duration: 0.18, harmonics: [(3, 0.4)])
        case 13: play(player: puckPlayer, frequency: 190 * pitch, endFrequency: 95 * pitch, duration: 0.18, noise: 0.18)
        default: play(player: puckPlayer, frequency: 1_400 * pitch, endFrequency: 320 * pitch, duration: 0.16, wave: .saw)
        }
    }

    func strike(style: Int, x: Double) {
        effectsPlayer.pan = Float(max(-1, min(1, x * 2 - 1)))
        let frequencies = [480.0, 1_700, 620, 420, 450, 700, 300, 1_700, 360, 320]
        let endFrequencies: [Double?] = [nil, nil, 320, nil, nil, 560, nil, 300, 720, nil]
        let noise = [0.5, 0.65, 0, 0.25, 0.65, 0, 0, 0, 0, 0.55]
        play(player: effectsPlayer, frequency: frequencies[style], endFrequency: endFrequencies[style], duration: style == 6 || style == 8 ? 0.12 : 0.07, noise: noise[style], wave: style == 7 ? .saw : .triangle)
    }

    func malletMovement(style: Int, x: Double) {
        effectsPlayer.pan = Float(max(-1, min(1, x * 2 - 1)))
        let frequencies = [0.0, 150, 1_500, 220, 300, 110, 4_000, 260, 600, 170]
        let durations = [0.0, 0.05, 0.02, 0.12, 0.04, 0.08, 0.025, 0.07, 0.1, 0.05]
        play(player: effectsPlayer, frequency: frequencies[style], duration: durations[style], noise: style == 2 || style == 6 ? 0.9 : 0, wave: style == 9 ? .square : (style == 4 || style == 7 ? .triangle : .sine))
    }

    func ricochet(x: Double, speed: Double) {
        effectsPlayer.pan = Float(max(-1, min(1, x * 2 - 1)))
        let strength = max(0.18, min(1, speed / 1_400))
        effectsPlayer.volume = Float(strength)
        play(player: effectsPlayer, frequency: 1_050, endFrequency: 760, duration: 0.055, noise: 0.32, harmonics: [(0.2, 0.25), (2.25, 0.2)], wave: .triangle)
    }

    func centerCrossing(volume: Double) {
        effectsPlayer.pan = 0
        effectsPlayer.volume = Float(volume)
        play(player: effectsPlayer, frequency: 500, endFrequency: 1_900, duration: 0.3, noise: 0.7)
    }

    func goal(playerScored: Bool) {
        effectsPlayer.pan = playerScored ? 0.45 : -0.45
        if playerScored {
            play(player: effectsPlayer, frequency: 523, endFrequency: 1_047, duration: 0.4, harmonics: [(1.26, 0.4), (1.5, 0.35)], wave: .triangle)
        } else {
            play(player: effectsPlayer, frequency: 160, endFrequency: 120, duration: 0.5, wave: .saw)
        }
    }

    func boardBall() {
        effectsPlayer.pan = 0
        play(player: effectsPlayer, frequency: 115, duration: 0.25, noise: 0.65)
    }

    private func pentatonicPitch(closeness: Double, range: Double, lower: Bool) -> Double {
        let notes = [146.83, 174.61, 196, 220, 261.63, 293.66, 349.23, 392, 440, 523.25, 587.33]
        let span = range == 0 ? 0 : (range < 1 ? 4 : notes.count - 1)
        let start = (notes.count - 1 - span) / 2
        let position = lower ? 1 - closeness : closeness
        return notes[start + Int((position * Double(span)).rounded())] / 220
    }

    private func play(player: AVAudioPlayerNode, frequency: Double, endFrequency: Double? = nil, duration: Double, noise: Double = 0, harmonics: [(Double, Double)] = [], wave: Wave = .sine) {
        let frames = AVAudioFrameCount(format.sampleRate * duration)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames), let channels = buffer.floatChannelData else { return }
        buffer.frameLength = frames
        for frame in 0..<Int(frames) {
            let t = Double(frame) / format.sampleRate
            let envelope = Float(pow(max(0, 1 - t / duration), 2.2))
            let progress = t / duration
            let currentFrequency = frequency + ((endFrequency ?? frequency) - frequency) * progress
            let phase = 2 * Double.pi * currentFrequency * t
            var tone = waveform(phase, wave: wave)
            for harmonic in harmonics { tone += Float(harmonic.1) * waveform(phase * harmonic.0, wave: .sine) }
            let random = Float.random(in: -1...1)
            let sample = (tone * Float(1 - noise) + random * Float(noise)) * envelope * 0.55
            channels[0][frame] = sample
            channels[1][frame] = sample
        }
        player.scheduleBuffer(buffer)
        if !player.isPlaying { player.play() }
    }

    private func waveform(_ phase: Double, wave: Wave) -> Float {
        switch wave {
        case .sine: return Float(sin(phase))
        case .triangle: return Float(2 / Double.pi * asin(sin(phase)))
        case .square: return sin(phase) >= 0 ? 1 : -1
        case .saw: return Float(2 * (phase / (2 * .pi) - floor(phase / (2 * .pi) + 0.5)))
        }
    }
}
