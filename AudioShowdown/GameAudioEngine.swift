import AVFoundation

@MainActor
final class GameAudioEngine {
    private enum Waveform { case sine, triangle, square, sawtooth }

    private struct Tone {
        let waveform: Waveform
        let startFrequency: Double
        let endFrequency: Double?
        let duration: TimeInterval
        let peak: Double
        var startTime: TimeInterval = 0
        var attack: TimeInterval = 0.004
    }

    private struct Noise {
        let duration: TimeInterval
        let peak: Double
        var highPass: Double? = nil
        var lowPass: Double? = nil
        var startTime: TimeInterval = 0
    }

    private final class SpatialVoice {
        let player = AVAudioPlayerNode()
    }

    private let engine = AVAudioEngine()
    private let environment = AVAudioEnvironmentNode()
    private let sourceFormat = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1)!
    private var puckVoices: [SpatialVoice] = []
    private var effectVoices: [SpatialVoice] = []
    private var nextPuckVoice = 0
    private var nextEffectVoice = 0
    private var started = false
    private var reverbStyle = -1
    private var reverbBlend: Float = 0

    init() {
        engine.attach(environment)
        engine.connect(environment, to: engine.mainMixerNode, format: nil)
        environment.listenerPosition = AVAudio3DPoint(x: 0, y: 0, z: 0)
        environment.listenerAngularOrientation = AVAudio3DAngularOrientation(yaw: 0, pitch: 0, roll: 0)
        environment.distanceAttenuationParameters.distanceAttenuationModel = .inverse
        environment.distanceAttenuationParameters.referenceDistance = 0.8
        environment.distanceAttenuationParameters.maximumDistance = 30
        environment.distanceAttenuationParameters.rolloffFactor = 0.6
        environment.reverbParameters.enable = false
        puckVoices = makeVoices(count: 10)
        effectVoices = makeVoices(count: 16)
    }

    func prepare(volume: Double) {
        engine.mainMixerNode.outputVolume = Float(volume)
        do {
            if !started {
                let session = AVAudioSession.sharedInstance()
                try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
                try session.setPreferredSampleRate(sourceFormat.sampleRate)
                try session.setPreferredIOBufferDuration(0.005)
                try session.setActive(true)
                engine.prepare()
            }
            if !engine.isRunning { try engine.start() }
            started = true
        } catch {
            started = false
        }
    }

    func setVolume(_ volume: Double) {
        engine.mainMixerNode.outputVolume = Float(volume)
    }

    func setReverb(_ style: Int) {
        let style = min(max(style, 0), 3)
        guard style != reverbStyle else { return }
        reverbStyle = style
        switch style {
        case 1:
            environment.reverbParameters.loadFactoryReverbPreset(.smallRoom)
            environment.reverbParameters.level = -26
            reverbBlend = 2.5
            environment.reverbParameters.enable = true
        case 2:
            environment.reverbParameters.loadFactoryReverbPreset(.largeRoom)
            environment.reverbParameters.level = -25
            reverbBlend = 4
            environment.reverbParameters.enable = true
        case 3:
            environment.reverbParameters.loadFactoryReverbPreset(.largeHall)
            environment.reverbParameters.level = -24
            reverbBlend = 6.5
            environment.reverbParameters.enable = true
        default:
            reverbBlend = 0
            environment.reverbParameters.enable = false
        }
        for voice in puckVoices + effectVoices {
            voice.player.reverbBlend = reverbBlend
        }
    }

    func puckPing(x: Double, distance proximity: Double, style: Int, pitchBehavior: Int, lowerWhenCloser: Bool) {
        let near = clamp(proximity)
        let pitchAmount = [0.0, 0.6, 1.4][pitchBehavior]
        let pitchMultiplier = 1 + pitchAmount * (lowerWhenCloser ? 1 - near : near)
        let gain = min(1, 0.30 + 0.70 * near)
        let tones: [Tone]
        let noises: [Noise]

        switch style {
        case 0:
            tones = [Tone(waveform: .triangle, startFrequency: 560 * pitchMultiplier, endFrequency: 430 * pitchMultiplier, duration: 0.07, peak: 0.5)]
            noises = [Noise(duration: 0.03, peak: 0.25, highPass: 2_200 * pitchMultiplier)]
        case 1:
            tones = [
                Tone(waveform: .sine, startFrequency: 700 * pitchMultiplier, endFrequency: nil, duration: 0.26, peak: 0.5),
                Tone(waveform: .sine, startFrequency: 1_400 * pitchMultiplier, endFrequency: nil, duration: 0.14, peak: 0.12)
            ]
            noises = []
        case 2:
            tones = []
            noises = [Noise(duration: 0.02, peak: 0.6, highPass: 3_500 * pitchMultiplier)]
        case 3:
            tones = [Tone(waveform: .sine, startFrequency: 880 * pitchMultiplier, endFrequency: nil, duration: 0.09, peak: 0.5)]
            noises = []
        case 4:
            tones = [Tone(waveform: .square, startFrequency: 620 * pitchMultiplier, endFrequency: nil, duration: 0.08, peak: 0.32)]
            noises = []
        case 5:
            tones = [Tone(waveform: .triangle, startFrequency: 540 * pitchMultiplier, endFrequency: 470 * pitchMultiplier, duration: 0.13, peak: 0.5)]
            noises = []
        case 6:
            tones = [
                Tone(waveform: .square, startFrequency: 540 * pitchMultiplier, endFrequency: nil, duration: 0.12, peak: 0.18),
                Tone(waveform: .square, startFrequency: 800 * pitchMultiplier, endFrequency: nil, duration: 0.12, peak: 0.168)
            ]
            noises = []
        case 7:
            tones = [Tone(waveform: .sine, startFrequency: 2_000 * pitchMultiplier, endFrequency: nil, duration: 0.04, peak: 0.5)]
            noises = [Noise(duration: 0.015, peak: 0.4, highPass: 4_000 * pitchMultiplier)]
        case 8:
            tones = [Tone(waveform: .sine, startFrequency: 1_300 * pitchMultiplier, endFrequency: 480 * pitchMultiplier, duration: 0.16, peak: 0.5)]
            noises = []
        case 9:
            tones = [Tone(waveform: .sine, startFrequency: 990 * pitchMultiplier, endFrequency: 1_080 * pitchMultiplier, duration: 0.3, peak: 0.45)]
            noises = []
        case 10:
            let frequency = pentatonicFrequency(near: near, pitchBehavior: pitchBehavior, lowerWhenCloser: lowerWhenCloser)
            tones = [
                Tone(waveform: .triangle, startFrequency: frequency, endFrequency: nil, duration: 0.20, peak: 0.5),
                Tone(waveform: .sine, startFrequency: frequency * 2, endFrequency: nil, duration: 0.12, peak: 0.20),
                Tone(waveform: .sine, startFrequency: frequency * 3, endFrequency: nil, duration: 0.07, peak: 0.066)
            ]
            noises = []
        case 11:
            let frequency = pentatonicFrequency(near: near, pitchBehavior: pitchBehavior, lowerWhenCloser: lowerWhenCloser) * 2
            tones = [
                Tone(waveform: .sine, startFrequency: frequency, endFrequency: nil, duration: 0.4, peak: 0.5),
                Tone(waveform: .sine, startFrequency: frequency * 2.76, endFrequency: nil, duration: 0.3, peak: 0.175),
                Tone(waveform: .sine, startFrequency: frequency * 5.4, endFrequency: nil, duration: 0.18, peak: 0.075)
            ]
            noises = []
        case 12:
            tones = [
                Tone(waveform: .sine, startFrequency: 1_760 * pitchMultiplier, endFrequency: nil, duration: 0.18, peak: 0.45),
                Tone(waveform: .sine, startFrequency: 5_280 * pitchMultiplier, endFrequency: nil, duration: 0.1, peak: 0.12)
            ]
            noises = []
        case 13:
            tones = [Tone(waveform: .sine, startFrequency: 190 * pitchMultiplier, endFrequency: 95 * pitchMultiplier, duration: 0.18, peak: 0.55)]
            noises = [Noise(duration: 0.04, peak: 0.12, lowPass: 500)]
        default:
            tones = [Tone(waveform: .sawtooth, startFrequency: 1_400 * pitchMultiplier, endFrequency: 320 * pitchMultiplier, duration: 0.16, peak: 0.4)]
            noises = []
        }

        let cutoff = 2_000 + 16_000 * near
        let buffer = render(tones: tones, noises: noises, gain: gain, lowPass: cutoff)
        playPuck(buffer, x: x, proximity: near)
    }

    func strike(style: Int, x: Double, byPlayer: Bool = true) {
        let baseGain = 0.75
        let tones: [Tone]
        let noises: [Noise]
        switch style {
        case 0:
            tones = [Tone(waveform: .triangle, startFrequency: byPlayer ? 480 : 180, endFrequency: nil, duration: 0.1, peak: 0.4)]
            noises = [Noise(duration: 0.09, peak: 0.5, highPass: byPlayer ? 800 : 280, lowPass: byPlayer ? 7_000 : 2_600)]
        case 1:
            tones = [Tone(waveform: .triangle, startFrequency: byPlayer ? 1_700 : 1_000, endFrequency: nil, duration: 0.03, peak: 0.35)]
            noises = [Noise(duration: 0.02, peak: 0.6, highPass: byPlayer ? 3_200 : 2_000)]
        case 2:
            tones = [Tone(waveform: .sine, startFrequency: byPlayer ? 620 : 340, endFrequency: byPlayer ? 320 : 180, duration: 0.07, peak: 0.5)]
            noises = []
        case 3:
            tones = [Tone(waveform: .triangle, startFrequency: byPlayer ? 420 : 220, endFrequency: nil, duration: 0.05, peak: 0.45)]
            noises = [Noise(duration: 0.02, peak: 0.15, highPass: 1_500)]
        case 4:
            tones = [Tone(waveform: .triangle, startFrequency: byPlayer ? 450 : 250, endFrequency: nil, duration: 0.05, peak: 0.18)]
            noises = [Noise(duration: 0.08, peak: 0.5, highPass: 1_200)]
        case 5:
            tones = [Tone(waveform: .triangle, startFrequency: byPlayer ? 700 : 380, endFrequency: byPlayer ? 560 : 300, duration: 0.05, peak: 0.45)]
            noises = []
        case 6:
            tones = [Tone(waveform: .sine, startFrequency: byPlayer ? 300 : 150, endFrequency: nil, duration: 0.12, peak: 0.55)]
            noises = []
        case 7:
            tones = [Tone(waveform: .sawtooth, startFrequency: byPlayer ? 1_700 : 1_000, endFrequency: 300, duration: 0.08, peak: 0.4)]
            noises = []
        case 8:
            tones = [Tone(waveform: .sine, startFrequency: byPlayer ? 360 : 200, endFrequency: byPlayer ? 720 : 420, duration: 0.12, peak: 0.5)]
            noises = []
        default:
            tones = [Tone(waveform: .sine, startFrequency: byPlayer ? 320 : 180, endFrequency: nil, duration: 0.06, peak: 0.21)]
            noises = [Noise(duration: 0.06, peak: 0.5, lowPass: 1_200)]
        }
        playEffect(render(tones: tones, noises: noises, gain: baseGain), x: x, proximity: byPlayer ? 0.9 : 0.15)
    }

    func malletMovement(style: Int, x: Double) {
        guard style > 0 else { return }
        let tone: Tone?
        let noise: Noise?
        switch style {
        case 1: tone = Tone(waveform: .sine, startFrequency: 150, endFrequency: nil, duration: 0.05, peak: 0.22); noise = nil
        case 2: tone = nil; noise = Noise(duration: 0.02, peak: 0.3, highPass: 1_500)
        case 3: tone = Tone(waveform: .sine, startFrequency: 220, endFrequency: nil, duration: 0.12, peak: 0.18); noise = nil
        case 4: tone = Tone(waveform: .triangle, startFrequency: 300, endFrequency: 240, duration: 0.04, peak: 0.25); noise = nil
        case 5: tone = Tone(waveform: .sine, startFrequency: 110, endFrequency: nil, duration: 0.08, peak: 0.3); noise = nil
        case 6: tone = nil; noise = Noise(duration: 0.025, peak: 0.25, highPass: 4_000)
        case 7: tone = Tone(waveform: .triangle, startFrequency: 260, endFrequency: nil, duration: 0.07, peak: 0.25); noise = nil
        case 8: tone = Tone(waveform: .sine, startFrequency: 600, endFrequency: nil, duration: 0.1, peak: 0.2); noise = nil
        default: tone = Tone(waveform: .square, startFrequency: 170, endFrequency: nil, duration: 0.05, peak: 0.18); noise = nil
        }
        playEffect(render(tones: tone.map { [$0] } ?? [], noises: noise.map { [$0] } ?? [], gain: 0.35), x: x, proximity: 0.95)
    }

    func ricochet(x: Double, speed: Double) {
        guard speed >= 80 else { return }
        let velocity = min(1, speed / 1_400)
        let gain = 0.22 + 0.72 * velocity
        let centerFrequency = 1_050.0
        let tones = [
            Tone(waveform: .triangle, startFrequency: centerFrequency, endFrequency: centerFrequency * 0.72, duration: 0.04 + 0.02 * velocity, peak: 0.4),
            Tone(waveform: .sine, startFrequency: 200, endFrequency: nil, duration: 0.05, peak: 0.11),
            Tone(waveform: .sine, startFrequency: 2_300, endFrequency: nil, duration: 0.025, peak: 0.07)
        ]
        let noises = [Noise(duration: 0.012, peak: 0.6, highPass: 3_000 + 2_600 * velocity)]
        playEffect(render(tones: tones, noises: noises, gain: gain), x: x, proximity: 0.5)
    }

    func centerCrossing(volume: Double) {
        let tones = [Tone(waveform: .sine, startFrequency: 500, endFrequency: 1_900, duration: 0.30, peak: 0.12)]
        let noises = [Noise(duration: 0.33, peak: 0.42, highPass: 400, lowPass: 2_100)]
        playEffect(render(tones: tones, noises: noises, gain: volume), x: 0.5, proximity: 0.5)
    }

    func goal(playerScored: Bool) {
        if playerScored {
            let tones = [523.0, 659, 784, 1_047].enumerated().map { index, frequency in
                Tone(waveform: .triangle, startFrequency: frequency, endFrequency: nil, duration: 0.18, peak: 0.5, startTime: Double(index) * 0.07)
            }
            playEffect(render(tones: tones, noises: [], gain: 0.6), x: 0.5, proximity: 0.7)
        } else {
            let tones = [
                Tone(waveform: .sawtooth, startFrequency: 160, endFrequency: nil, duration: 0.5, peak: 0.5),
                Tone(waveform: .sawtooth, startFrequency: 120, endFrequency: nil, duration: 0.5, peak: 0.45, startTime: 0.12)
            ]
            playEffect(render(tones: tones, noises: [], gain: 0.6), x: 0.5, proximity: 0.4)
        }
    }

    func boardBall() {
        let tones = [
            Tone(waveform: .triangle, startFrequency: 118, endFrequency: 72, duration: 0.32, peak: 0.63),
            Tone(waveform: .sine, startFrequency: 310, endFrequency: 205, duration: 0.22, peak: 0.275),
            Tone(waveform: .triangle, startFrequency: 185, endFrequency: 125, duration: 0.18, peak: 0.225, startTime: 0.055)
        ]
        let noises = [Noise(duration: 0.24, peak: 0.8075, lowPass: 850)]
        playEffect(render(tones: tones, noises: noises, gain: 0.95), x: 0.5, proximity: 0.5)
    }

    private func makeVoices(count: Int) -> [SpatialVoice] {
        (0..<count).map { _ in
            let voice = SpatialVoice()
            engine.attach(voice.player)
            engine.connect(voice.player, to: environment, format: sourceFormat)
            voice.player.renderingAlgorithm = .HRTFHQ
            return voice
        }
    }

    private func playPuck(_ buffer: AVAudioPCMBuffer, x: Double, proximity: Double) {
        let voice = puckVoices[nextPuckVoice]
        nextPuckVoice = (nextPuckVoice + 1) % puckVoices.count
        play(buffer, on: voice, x: x, proximity: proximity)
    }

    private func playEffect(_ buffer: AVAudioPCMBuffer, x: Double, proximity: Double) {
        let voice = effectVoices[nextEffectVoice]
        nextEffectVoice = (nextEffectVoice + 1) % effectVoices.count
        play(buffer, on: voice, x: x, proximity: proximity)
    }

    private func play(_ buffer: AVAudioPCMBuffer, on voice: SpatialVoice, x: Double, proximity: Double) {
        if !engine.isRunning { try? engine.start() }
        if voice.player.isPlaying { voice.player.stop() }
        voice.player.position = spatialPosition(x: x, proximity: proximity)
        voice.player.reverbBlend = reverbBlend
        voice.player.volume = 1
        voice.player.scheduleBuffer(buffer)
        voice.player.play()
    }

    private func spatialPosition(x: Double, proximity: Double) -> AVAudio3DPoint {
        let horizontal = Float((clamp(x) - 0.5) * 4.8)
        let depth = Float(-(0.5 + (1 - clamp(proximity)) * 5.0))
        return AVAudio3DPoint(x: horizontal, y: 0, z: depth)
    }

    private func render(tones: [Tone], noises: [Noise], gain: Double, lowPass: Double? = nil) -> AVAudioPCMBuffer {
        let duration = max(
            tones.map { $0.startTime + $0.duration }.max() ?? 0,
            noises.map { $0.startTime + $0.duration }.max() ?? 0
        )
        let frameCount = max(1, Int(ceil(duration * sourceFormat.sampleRate)))
        let buffer = AVAudioPCMBuffer(pcmFormat: sourceFormat, frameCapacity: AVAudioFrameCount(frameCount))!
        buffer.frameLength = AVAudioFrameCount(frameCount)
        let samples = buffer.floatChannelData![0]

        for tone in tones { add(tone: tone, gain: gain, to: samples, frameCount: frameCount) }
        for noise in noises { add(noise: noise, gain: gain, to: samples, frameCount: frameCount) }
        if let lowPass { applyLowPass(cutoff: lowPass, samples: samples, frameCount: frameCount) }
        for frame in 0..<frameCount { samples[frame] = tanh(samples[frame]) }
        return buffer
    }

    private func add(tone: Tone, gain: Double, to samples: UnsafeMutablePointer<Float>, frameCount: Int) {
        let sampleRate = sourceFormat.sampleRate
        let startFrame = Int(tone.startTime * sampleRate)
        let toneFrames = min(Int(tone.duration * sampleRate), frameCount - startFrame)
        guard toneFrames > 0 else { return }
        var phase = 0.0
        for frame in 0..<toneFrames {
            let time = Double(frame) / sampleRate
            let progress = min(1, time / tone.duration)
            let frequency: Double
            if let end = tone.endFrequency, tone.startFrequency > 0, end > 0 {
                frequency = tone.startFrequency * pow(end / tone.startFrequency, progress)
            } else {
                frequency = tone.startFrequency
            }
            phase += 2 * Double.pi * frequency / sampleRate
            let envelope = amplitudeEnvelope(time: time, duration: tone.duration, attack: tone.attack, peak: tone.peak)
            samples[startFrame + frame] += Float(waveformSample(phase: phase, waveform: tone.waveform) * envelope * gain)
        }
    }

    private func add(noise: Noise, gain: Double, to samples: UnsafeMutablePointer<Float>, frameCount: Int) {
        let sampleRate = sourceFormat.sampleRate
        let startFrame = Int(noise.startTime * sampleRate)
        let noiseFrames = min(Int(noise.duration * sampleRate), frameCount - startFrame)
        guard noiseFrames > 0 else { return }
        var lowPassState = 0.0
        var previousInput = 0.0
        var highPassState = 0.0
        let lowAlpha = noise.lowPass.map { 1 - exp(-2 * Double.pi * $0 / sampleRate) }
        let highAlpha = noise.highPass.map { exp(-2 * Double.pi * $0 / sampleRate) }

        for frame in 0..<noiseFrames {
            let time = Double(frame) / sampleRate
            var value = Double.random(in: -1...1)
            if let alpha = lowAlpha {
                lowPassState += alpha * (value - lowPassState)
                value = lowPassState
            }
            if let alpha = highAlpha {
                highPassState = alpha * (highPassState + value - previousInput)
                previousInput = value
                value = highPassState
            }
            let envelope = amplitudeEnvelope(time: time, duration: noise.duration, attack: 0, peak: noise.peak)
            samples[startFrame + frame] += Float(value * envelope * gain)
        }
    }

    private func applyLowPass(cutoff: Double, samples: UnsafeMutablePointer<Float>, frameCount: Int) {
        let alpha = 1 - exp(-2 * Double.pi * cutoff / sourceFormat.sampleRate)
        var state = 0.0
        for frame in 0..<frameCount {
            state += alpha * (Double(samples[frame]) - state)
            samples[frame] = Float(state)
        }
    }

    private func amplitudeEnvelope(time: TimeInterval, duration: TimeInterval, attack: TimeInterval, peak: Double) -> Double {
        if attack > 0, time < attack { return peak * max(0.0001, time / attack) }
        let decayDuration = max(0.001, duration - attack)
        let decayProgress = min(1, max(0, (time - attack) / decayDuration))
        return peak * pow(0.0001 / max(peak, 0.0001), decayProgress)
    }

    private func waveformSample(phase: Double, waveform: Waveform) -> Double {
        switch waveform {
        case .sine: return sin(phase)
        case .triangle: return 2 / Double.pi * asin(sin(phase))
        case .square: return sin(phase) >= 0 ? 1 : -1
        case .sawtooth: return 2 * (phase / (2 * Double.pi) - floor(phase / (2 * Double.pi) + 0.5))
        }
    }

    private func pentatonicFrequency(near: Double, pitchBehavior: Int, lowerWhenCloser: Bool) -> Double {
        let notes = [146.83, 174.61, 196, 220, 261.63, 293.66, 349.23, 392, 440, 523.25, 587.33]
        let span = pitchBehavior == 0 ? 0 : (pitchBehavior == 1 ? 4 : notes.count - 1)
        let start = (notes.count - 1 - span) / 2
        let position = lowerWhenCloser ? 1 - near : near
        return notes[start + Int((clamp(position) * Double(span)).rounded())]
    }

    private func clamp(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }
}
