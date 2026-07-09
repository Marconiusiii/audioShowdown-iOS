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
        let dryPlayer = AVAudioPlayerNode()
        let wetPlayer = AVAudioPlayerNode()
    }

    private struct SmoothPuckRenderState {
        var lowState = 0.0
        var midState = 0.0
        var highState = 0.0
        var previousInput = 0.0
        var subPreviousInput = 0.0
        var primaryPhase = 0.0
        var secondaryPhase = 0.0
        var tertiaryPhase = 0.0
        var rattleEnvelope = 0.0
        var rattleBodyEnvelope = 0.0
        var rattleResonancePhase = 0.0
        var clicker1Countdown = 0.02
        var clicker2Countdown = 0.08
        var clicker3Countdown = 0.14
        var clicker4Countdown = 0.21
        var clicker5Countdown = 0.29
        var clicker6Countdown = 0.36
        var clicker7Countdown = 0.47
        var clicker8Countdown = 0.55
        var clicker1Envelope = 0.0
        var clicker2Envelope = 0.0
        var clicker3Envelope = 0.0
        var clicker4Envelope = 0.0
        var clicker5Envelope = 0.0
        var clicker6Envelope = 0.0
        var clicker7Envelope = 0.0
        var clicker8Envelope = 0.0
        var transientState1 = 0.0
        var transientState2 = 0.0
        var transientState3 = 0.0
        var transientState4 = 0.0
        var transientState5 = 0.0
        var transientState6 = 0.0
        var transientPrevious1 = 0.0
        var transientPrevious2 = 0.0
        var transientPrevious3 = 0.0
        var transientPrevious4 = 0.0
    }

    private let engine = AVAudioEngine()
    private let dryEnvironment = AVAudioEnvironmentNode()
    private let wetEnvironment = AVAudioEnvironmentNode()
    private let wetMixer = AVAudioMixerNode()
    private let sourceFormat = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1)!
    private let malletSlideVoice = SpatialVoice()
    private let smoothPuckVoice = SpatialVoice()
    private var puckVoices: [SpatialVoice] = []
    private var effectVoices: [SpatialVoice] = []
    private var nextPuckVoice = 0
    private var nextEffectVoice = 0
    private var started = false
    private var reverbStyle = -1
    private var puckVolume = 0.8
    private var warmedUp = false
    private var malletSlideStyle = -1
    private var smoothPuckStyle = -1
    private var smoothPuckGeneration = 0
    private var smoothPuckDryQueuedBuffers = 0
    private var smoothPuckWetQueuedBuffers = 0
    private var smoothPuckRenderState = SmoothPuckRenderState()
    private var smoothPuckRenderSpeed = 0.0
    private var smoothPuckPitchMultiplier = 1.0
    private var smoothPuckRattleEnergy = 0.0
    private var lastWinMotifIndex = -1
    private var lastLossMotifIndex = -1

    init() {
        engine.attach(dryEnvironment)
        engine.attach(wetEnvironment)
        engine.attach(wetMixer)
        engine.connect(dryEnvironment, to: engine.mainMixerNode, format: nil)
        engine.connect(wetEnvironment, to: wetMixer, format: nil)
        engine.connect(wetMixer, to: engine.mainMixerNode, format: nil)
        configureSpatialEnvironment(dryEnvironment)
        configureSpatialEnvironment(wetEnvironment)
        dryEnvironment.reverbParameters.enable = false
        wetEnvironment.reverbParameters.enable = true
        wetMixer.outputVolume = 0
        configure(voice: malletSlideVoice)
        configure(voice: smoothPuckVoice)
        puckVoices = makeVoices(count: 10)
        effectVoices = makeVoices(count: 16)
    }

    func prepare(volume: Double) {
        engine.mainMixerNode.outputVolume = Float(volume)
        do {
            if !started {
                try configureAudioSession()
                engine.prepare()
            }
            if !engine.isRunning { try engine.start() }
            started = true
        } catch {
            started = false
        }
    }

    func warmUp(volume: Double, reverbStyle: Int, puckVolume: Double) {
        prepare(volume: volume)
        setReverb(reverbStyle)
        setPuckVolume(puckVolume)
        guard !warmedUp else { return }
        warmedUp = true
        let silence = render(tones: [], noises: [], gain: 0)
        playEffect(silence, x: 0.5, proximity: 0.5)
    }

    func setVolume(_ volume: Double) {
        engine.mainMixerNode.outputVolume = Float(volume)
    }

    func setPuckVolume(_ volume: Double) {
        puckVolume = clamp(volume)
    }

    func setReverb(_ style: Int) {
        let style = min(max(style, 0), 3)
        guard style != reverbStyle else { return }
        reverbStyle = style
        switch style {
        case 1:
            wetEnvironment.reverbParameters.loadFactoryReverbPreset(.smallRoom)
            wetEnvironment.reverbParameters.level = 0
            wetMixer.outputVolume = 0.025
        case 2:
            wetEnvironment.reverbParameters.loadFactoryReverbPreset(.largeRoom)
            wetEnvironment.reverbParameters.level = 0
            wetMixer.outputVolume = 0.04
        case 3:
            wetEnvironment.reverbParameters.loadFactoryReverbPreset(.largeHall)
            wetEnvironment.reverbParameters.level = 0
            wetMixer.outputVolume = 0.065
        default:
            wetMixer.outputVolume = 0
        }
    }

    func puckPing(x: Double, distance proximity: Double, style: Int, pitchBehavior: Int, pitchChangesWithDistance: Bool, lowerWhenCloser: Bool, volumeChangesWithDistance: Bool) {
        let near = clamp(proximity)
        let pitchAmount = pitchChangesWithDistance ? [0.0, 0.6, 1.4][pitchBehavior] : 0
        let pitchMultiplier = 1 + pitchAmount * (lowerWhenCloser ? 1 - near : near)
        let gain = min(1, volumeChangesWithDistance ? 0.74 + 0.30 * near : 0.92) * puckVolume
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
            tones = [
                Tone(waveform: .sine, startFrequency: 880 * pitchMultiplier, endFrequency: nil, duration: 0.10, peak: 0.52),
                Tone(waveform: .triangle, startFrequency: 440 * pitchMultiplier, endFrequency: nil, duration: 0.08, peak: 0.16)
            ]
            noises = []
        case 4:
            tones = [
                Tone(waveform: .square, startFrequency: 620 * pitchMultiplier, endFrequency: nil, duration: 0.09, peak: 0.34),
                Tone(waveform: .triangle, startFrequency: 310 * pitchMultiplier, endFrequency: nil, duration: 0.08, peak: 0.12)
            ]
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
            tones = [
                Tone(waveform: .sine, startFrequency: 760 * pitchMultiplier, endFrequency: 890 * pitchMultiplier, duration: 0.30, peak: 0.56),
                Tone(waveform: .triangle, startFrequency: 190 * pitchMultiplier, endFrequency: 220 * pitchMultiplier, duration: 0.30, peak: 0.20),
                Tone(waveform: .sine, startFrequency: 1_520 * pitchMultiplier, endFrequency: 1_780 * pitchMultiplier, duration: 0.16, peak: 0.12)
            ]
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
            tones = [
                Tone(waveform: .sawtooth, startFrequency: 1_050 * pitchMultiplier, endFrequency: 520 * pitchMultiplier, duration: 0.18, peak: 0.54),
                Tone(waveform: .sine, startFrequency: 520 * pitchMultiplier, endFrequency: 360 * pitchMultiplier, duration: 0.16, peak: 0.24)
            ]
            noises = []
        }

        let cutoff = 2_000 + 16_000 * near
        let buffer = render(tones: tones, noises: noises, gain: gain, lowPass: cutoff)
        playPuck(buffer, x: x, proximity: near)
    }

    func updateSmoothPuck(style: Int, x: Double, proximity: Double, speed: Double, volume: Double, pitchBehavior: Int, pitchChangesWithDistance: Bool, lowerWhenCloser: Bool, volumeChangesWithDistance: Bool) {
        guard volume > 0 else {
            stopSmoothPuck()
            return
        }
        guard ensureEngineRunning() else {
            stopSmoothPuck()
            return
        }
        smoothPuckRattleEnergy = max(0, smoothPuckRattleEnergy - 0.010)
        let near = clamp(proximity)
        smoothPuckRenderSpeed = speed
        let pitchAmount = pitchChangesWithDistance && style != 3 ? [0.0, 0.25, 0.5][pitchBehavior] : 0
        smoothPuckPitchMultiplier = 1 + pitchAmount * (lowerWhenCloser ? 1 - near : near)

        if style != smoothPuckStyle || !smoothPuckVoice.dryPlayer.isPlaying {
            smoothPuckGeneration += 1
            smoothPuckStyle = style
            smoothPuckDryQueuedBuffers = 0
            smoothPuckWetQueuedBuffers = 0
            smoothPuckRenderState = SmoothPuckRenderState()
            smoothPuckVoice.dryPlayer.stop()
            smoothPuckVoice.wetPlayer.stop()
            primeSmoothPuckQueue(generation: smoothPuckGeneration)
            if smoothPuckDryQueuedBuffers > 0 {
                smoothPuckVoice.dryPlayer.play()
            }
            if reverbStyle > 0, smoothPuckWetQueuedBuffers > 0 {
                smoothPuckVoice.wetPlayer.play()
            }
        } else if reverbStyle > 0, !smoothPuckVoice.wetPlayer.isPlaying {
            smoothPuckGeneration += 1
            smoothPuckDryQueuedBuffers = 0
            smoothPuckWetQueuedBuffers = 0
            smoothPuckRenderState = SmoothPuckRenderState()
            smoothPuckVoice.dryPlayer.stop()
            smoothPuckVoice.wetPlayer.stop()
            primeSmoothPuckQueue(generation: smoothPuckGeneration)
            if smoothPuckDryQueuedBuffers > 0 {
                smoothPuckVoice.dryPlayer.play()
            }
            if smoothPuckWetQueuedBuffers > 0 {
                smoothPuckVoice.wetPlayer.play()
            }
        } else if reverbStyle == 0, smoothPuckVoice.wetPlayer.isPlaying {
            smoothPuckVoice.wetPlayer.stop()
            smoothPuckWetQueuedBuffers = 0
        }
        primeSmoothPuckQueue(generation: smoothPuckGeneration)
        let baseGain = volumeChangesWithDistance ? 0.86 + 0.14 * near : 0.94
        let gain = Float(baseGain * clamp(volume))
        let position = smoothTrackingPosition(x: x, proximity: near)
        let pan = puckTrackingPan(x: x)
        smoothPuckVoice.dryPlayer.position = position
        smoothPuckVoice.wetPlayer.position = position
        smoothPuckVoice.dryPlayer.pan = pan
        smoothPuckVoice.wetPlayer.pan = pan
        smoothPuckVoice.dryPlayer.volume = gain
        smoothPuckVoice.wetPlayer.volume = gain
    }

    func previewSmoothPuck(style: Int, x: Double, proximity: Double, speed: Double, volume: Double, pitchBehavior: Int, pitchChangesWithDistance: Bool, lowerWhenCloser: Bool, volumeChangesWithDistance: Bool) {
        stopSmoothPuck()
        guard volume > 0 else { return }
        guard ensureEngineRunning() else { return }
        let near = clamp(proximity)
        let pitchAmount = pitchChangesWithDistance && style != 3 ? [0.0, 0.25, 0.5][pitchBehavior] : 0
        let pitchMultiplier = 1 + pitchAmount * (lowerWhenCloser ? 1 - near : near)
        let previewRattleEnergy = style == 3 ? 1.0 : 0.12
        var previewState = SmoothPuckRenderState()
        let buffer = renderSmoothPuckBuffer(
            style: style,
            speed: speed,
            pitchMultiplier: pitchMultiplier,
            rattleEnergy: previewRattleEnergy,
            state: &previewState,
            previewEnvelope: true
        )
        playPuck(buffer, x: x, proximity: near)
    }

    func stopSmoothPuck() {
        smoothPuckVoice.dryPlayer.volume = 0
        smoothPuckVoice.wetPlayer.volume = 0
        if smoothPuckVoice.dryPlayer.isPlaying { smoothPuckVoice.dryPlayer.stop() }
        if smoothPuckVoice.wetPlayer.isPlaying { smoothPuckVoice.wetPlayer.stop() }
        smoothPuckStyle = -1
        smoothPuckGeneration += 1
        smoothPuckDryQueuedBuffers = 0
        smoothPuckWetQueuedBuffers = 0
        smoothPuckRenderState = SmoothPuckRenderState()
    }

    func energizeSmoothPuck(amount: Double) {
        smoothPuckRattleEnergy = clamp(smoothPuckRattleEnergy + amount)
    }

    func reverbAudition() {
        let tones = [
            Tone(waveform: .triangle, startFrequency: 520, endFrequency: 280, duration: 0.08, peak: 0.46),
            Tone(waveform: .sine, startFrequency: 1_040, endFrequency: 620, duration: 0.06, peak: 0.20)
        ]
        let noises = [Noise(duration: 0.035, peak: 0.32, highPass: 1_800)]
        playEffect(render(tones: tones, noises: noises, gain: 0.68), x: 0.5, proximity: 0.62)
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

    func updateMalletSlide(x: Double, speed: Double, volume: Double) {
        guard speed > 0, volume > 0 else {
            stopMalletSlide()
            return
        }
        guard ensureEngineRunning() else {
            stopMalletSlide()
            return
        }
        let gain = Float((0.025 + 0.30 * clamp(speed / 1_400)) * clamp(volume))
        let position = spatialPosition(x: x, proximity: 0.95)
        if malletSlideStyle != 1 || !malletSlideVoice.dryPlayer.isPlaying {
            malletSlideStyle = 1
            let buffer = renderMalletSlideLoop()
            malletSlideVoice.dryPlayer.stop()
            malletSlideVoice.dryPlayer.scheduleBuffer(buffer, at: nil, options: .loops)
            malletSlideVoice.dryPlayer.play()
            malletSlideVoice.wetPlayer.stop()
            malletSlideVoice.wetPlayer.scheduleBuffer(buffer, at: nil, options: .loops)
            if reverbStyle > 0 { malletSlideVoice.wetPlayer.play() }
        } else if reverbStyle > 0, !malletSlideVoice.wetPlayer.isPlaying {
            let buffer = renderMalletSlideLoop()
            malletSlideVoice.wetPlayer.scheduleBuffer(buffer, at: nil, options: .loops)
            malletSlideVoice.wetPlayer.play()
        } else if reverbStyle == 0, malletSlideVoice.wetPlayer.isPlaying {
            malletSlideVoice.wetPlayer.stop()
        }
        malletSlideVoice.dryPlayer.position = position
        malletSlideVoice.wetPlayer.position = position
        malletSlideVoice.dryPlayer.volume = gain
        malletSlideVoice.wetPlayer.volume = gain
    }

    func stopMalletSlide() {
        malletSlideVoice.dryPlayer.volume = 0
        malletSlideVoice.wetPlayer.volume = 0
        if malletSlideVoice.dryPlayer.isPlaying { malletSlideVoice.dryPlayer.stop() }
        if malletSlideVoice.wetPlayer.isPlaying { malletSlideVoice.wetPlayer.stop() }
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

    func matchWon() {
        let motifs = [
            [261.63, 329.63, 392.00, 523.25],
            [293.66, 392.00, 440.00, 587.33],
            [349.23, 440.00, 523.25, 698.46]
        ]
        let motifIndex = nonRepeatingIndex(count: motifs.count, excluding: lastWinMotifIndex)
        lastWinMotifIndex = motifIndex
        let motif = motifs[motifIndex]
        let beat = Double.random(in: 0.105...0.125)
        var tones: [Tone] = []
        for (index, frequency) in motif.enumerated() {
            let start = Double(index) * beat
            tones.append(Tone(waveform: .triangle, startFrequency: frequency, endFrequency: nil, duration: 0.24, peak: 0.46, startTime: start))
            tones.append(Tone(waveform: .sine, startFrequency: frequency * 2, endFrequency: nil, duration: 0.17, peak: 0.16, startTime: start))
        }
        playEffect(render(tones: tones, noises: [], gain: 0.72), x: 0.5, proximity: 0.72)

        let sparkleNotes = [1_046.50, 1_174.66, 1_318.51, 1_396.91, 1_568.0, 1_760.0, 2_093.0]
        for index in 0..<7 {
            let frequency = sparkleNotes.randomElement()!
            let delay = 0.18 + Double(index) * Double.random(in: 0.045...0.075)
            let sparkle = [
                Tone(waveform: .sine, startFrequency: frequency, endFrequency: frequency * 1.04, duration: 0.18, peak: 0.30, startTime: delay),
                Tone(waveform: .sine, startFrequency: frequency * 2.02, endFrequency: nil, duration: 0.10, peak: 0.10, startTime: delay)
            ]
            playEffect(
                render(tones: sparkle, noises: [], gain: Double.random(in: 0.42...0.58)),
                x: Double.random(in: 0.08...0.92),
                proximity: Double.random(in: 0.5...0.9)
            )
        }
    }

    func matchLost() {
        let motifs: [[(Double, Double)]] = [
            [(233.08, 196.00), (196.00, 164.81), (174.61, 130.81)],
            [(261.63, 220.00), (220.00, 174.61), (196.00, 146.83)],
            [(220.00, 185.00), (185.00, 155.56), (164.81, 123.47)]
        ]
        let motifIndex = nonRepeatingIndex(count: motifs.count, excluding: lastLossMotifIndex)
        lastLossMotifIndex = motifIndex
        let motif = motifs[motifIndex]
        let beat = Double.random(in: 0.24...0.29)
        var tones: [Tone] = []
        for (index, note) in motif.enumerated() {
            let start = Double(index) * beat
            tones.append(Tone(waveform: .sawtooth, startFrequency: note.0, endFrequency: note.1, duration: beat * 1.16, peak: 0.28, startTime: start, attack: 0.025))
            tones.append(Tone(waveform: .triangle, startFrequency: note.0 * 0.5, endFrequency: note.1 * 0.5, duration: beat * 1.2, peak: 0.18, startTime: start, attack: 0.03))
        }
        playEffect(render(tones: tones, noises: [], gain: Double.random(in: 0.68...0.78), lowPass: 1_600), x: 0.5, proximity: 0.6)
    }

    private func makeVoices(count: Int) -> [SpatialVoice] {
        (0..<count).map { _ in
            let voice = SpatialVoice()
            configure(voice: voice)
            return voice
        }
    }

    private func configure(voice: SpatialVoice) {
        engine.attach(voice.dryPlayer)
        engine.attach(voice.wetPlayer)
        engine.connect(voice.dryPlayer, to: dryEnvironment, format: sourceFormat)
        engine.connect(voice.wetPlayer, to: wetEnvironment, format: sourceFormat)
        voice.dryPlayer.sourceMode = .spatializeIfMono
        voice.dryPlayer.renderingAlgorithm = .HRTFHQ
        voice.dryPlayer.reverbBlend = 0
        voice.wetPlayer.sourceMode = .spatializeIfMono
        voice.wetPlayer.renderingAlgorithm = .HRTFHQ
        voice.wetPlayer.reverbBlend = 100
    }

    private func ensureEngineRunning() -> Bool {
        if engine.isRunning { return true }
        do {
            if !started {
                try configureAudioSession()
                engine.prepare()
            }
            try engine.start()
            started = true
            return true
        } catch {
            started = false
            return false
        }
    }

    private func configureAudioSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try session.setPreferredSampleRate(sourceFormat.sampleRate)
        // A 5 ms buffer is too aggressive when debugging tethered from Xcode and can starve VoiceOver speech.
        // 12 ms keeps gameplay responsive while leaving enough audio scheduling room for assistive audio.
        try session.setPreferredIOBufferDuration(0.012)
        try session.setActive(true)
    }

    private func playPuck(_ buffer: AVAudioPCMBuffer, x: Double, proximity: Double) {
        guard ensureEngineRunning() else { return }
        let voice = puckVoices[nextPuckVoice]
        nextPuckVoice = (nextPuckVoice + 1) % puckVoices.count
        let position = puckTrackingPosition(x: x, proximity: proximity)
        let pan = puckTrackingPan(x: x)
        if voice.dryPlayer.isPlaying { voice.dryPlayer.stop() }
        voice.dryPlayer.position = position
        voice.dryPlayer.pan = pan
        voice.dryPlayer.volume = 1
        voice.dryPlayer.scheduleBuffer(buffer)
        voice.dryPlayer.play()

        if reverbStyle > 0 {
            if voice.wetPlayer.isPlaying { voice.wetPlayer.stop() }
            voice.wetPlayer.position = position
            voice.wetPlayer.pan = pan
            voice.wetPlayer.volume = 1
            voice.wetPlayer.scheduleBuffer(buffer)
            voice.wetPlayer.play()
        }
    }

    private func playEffect(_ buffer: AVAudioPCMBuffer, x: Double, proximity: Double) {
        let voice = effectVoices[nextEffectVoice]
        nextEffectVoice = (nextEffectVoice + 1) % effectVoices.count
        play(buffer, on: voice, x: x, proximity: proximity)
    }

    private func play(_ buffer: AVAudioPCMBuffer, on voice: SpatialVoice, x: Double, proximity: Double) {
        guard ensureEngineRunning() else { return }
        let position = spatialPosition(x: x, proximity: proximity)
        if voice.dryPlayer.isPlaying { voice.dryPlayer.stop() }
        voice.dryPlayer.position = position
        voice.dryPlayer.volume = 1
        voice.dryPlayer.scheduleBuffer(buffer)
        voice.dryPlayer.play()

        if reverbStyle > 0 {
            if voice.wetPlayer.isPlaying { voice.wetPlayer.stop() }
            voice.wetPlayer.position = position
            voice.wetPlayer.volume = 1
            voice.wetPlayer.scheduleBuffer(buffer)
            voice.wetPlayer.play()
        }
    }

    private func configureSpatialEnvironment(_ environment: AVAudioEnvironmentNode) {
        environment.listenerPosition = AVAudio3DPoint(x: 0, y: 0, z: 0)
        environment.listenerAngularOrientation = AVAudio3DAngularOrientation(yaw: 0, pitch: 0, roll: 0)
        environment.distanceAttenuationParameters.distanceAttenuationModel = .inverse
        environment.distanceAttenuationParameters.referenceDistance = 0.8
        environment.distanceAttenuationParameters.maximumDistance = 30
        environment.distanceAttenuationParameters.rolloffFactor = 0.35
    }

    private func spatialPosition(x: Double, proximity: Double) -> AVAudio3DPoint {
        let horizontal = Float((clamp(x) - 0.5) * 4.8)
        let depth = Float(-(0.5 + (1 - clamp(proximity)) * 5.0))
        return AVAudio3DPoint(x: horizontal, y: 0, z: depth)
    }

    private func puckTrackingPosition(x: Double, proximity: Double) -> AVAudio3DPoint {
        let horizontal = Float((clamp(x) - 0.5) * 56.0)
        let depth = Float(-(0.30 + (1 - clamp(proximity)) * 3.20))
        return AVAudio3DPoint(x: horizontal, y: 0, z: depth)
    }

    private func smoothTrackingPosition(x: Double, proximity: Double) -> AVAudio3DPoint {
        let horizontal = Float((clamp(x) - 0.5) * 56.0)
        let depth = Float(-(0.30 + (1 - clamp(proximity)) * 3.20))
        return AVAudio3DPoint(x: horizontal, y: 0, z: depth)
    }

    private func puckTrackingPan(x: Double) -> Float {
        Float(min(max((clamp(x) - 0.5) * 12.0, -1), 1))
    }

    private func renderMalletSlideLoop() -> AVAudioPCMBuffer {
        let duration = 2.0
        let frameCount = Int(duration * sourceFormat.sampleRate)
        let buffer = AVAudioPCMBuffer(pcmFormat: sourceFormat, frameCapacity: AVAudioFrameCount(frameCount))!
        buffer.frameLength = AVAudioFrameCount(frameCount)
        let samples = buffer.floatChannelData![0]
        let sampleRate = sourceFormat.sampleRate
        var lowState = 0.0

        func lowPass(_ value: Double, cutoff: Double, state: inout Double) -> Double {
            let alpha = 1 - exp(-2 * Double.pi * cutoff / sampleRate)
            state += alpha * (value - state)
            return state
        }

        for frame in 0..<frameCount {
            let t = Double(frame) / sampleRate
            let noise = Double.random(in: -1...1)
            let grain = lowPass(noise, cutoff: 850, state: &lowState)
            let chatter = abs(sin(2 * Double.pi * 37 * t)) * 2 - 1
            let value = grain * 0.28 + chatter * 0.045 + sin(2 * Double.pi * 118 * t) * 0.045 + sin(2 * Double.pi * 236 * t) * 0.018
            let edgeFrames = Int(0.025 * sampleRate)
            let edgeGain: Double
            if frame < edgeFrames {
                edgeGain = Double(frame) / Double(edgeFrames)
            } else if frame > frameCount - edgeFrames {
                edgeGain = Double(frameCount - frame) / Double(edgeFrames)
            } else {
                edgeGain = 1
            }
            samples[frame] = Float(tanh(value * edgeGain))
        }
        return buffer
    }

    private func primeSmoothPuckQueue(generation: Int) {
        guard generation == smoothPuckGeneration, smoothPuckStyle >= 0 else { return }
        while smoothPuckDryQueuedBuffers < 4 {
            let buffer = renderSmoothPuckBuffer(
                style: smoothPuckStyle,
                speed: smoothPuckRenderSpeed,
                pitchMultiplier: smoothPuckPitchMultiplier,
                rattleEnergy: smoothPuckRattleEnergy,
                state: &smoothPuckRenderState,
                previewEnvelope: false
            )
            smoothPuckDryQueuedBuffers += 1
            smoothPuckVoice.dryPlayer.scheduleBuffer(buffer) { [weak self] in
                Task { @MainActor [weak self] in
                    guard let self, generation == self.smoothPuckGeneration else { return }
                    self.smoothPuckDryQueuedBuffers = max(0, self.smoothPuckDryQueuedBuffers - 1)
                    self.primeSmoothPuckQueue(generation: generation)
                }
            }
            if reverbStyle > 0 {
                smoothPuckWetQueuedBuffers += 1
                smoothPuckVoice.wetPlayer.scheduleBuffer(buffer) { [weak self] in
                    Task { @MainActor [weak self] in
                        guard let self, generation == self.smoothPuckGeneration else { return }
                        self.smoothPuckWetQueuedBuffers = max(0, self.smoothPuckWetQueuedBuffers - 1)
                    }
                }
            }
        }
    }

    private func renderSmoothPuckBuffer(style: Int, speed: Double, pitchMultiplier: Double, rattleEnergy: Double, state: inout SmoothPuckRenderState, previewEnvelope: Bool) -> AVAudioPCMBuffer {
        let duration = previewEnvelope ? 0.65 : 0.28
        let frameCount = Int(duration * sourceFormat.sampleRate)
        let buffer = AVAudioPCMBuffer(pcmFormat: sourceFormat, frameCapacity: AVAudioFrameCount(frameCount))!
        buffer.frameLength = AVAudioFrameCount(frameCount)
        let samples = buffer.floatChannelData![0]
        let sampleRate = sourceFormat.sampleRate
        let speedFactor = clamp(speed / 1_800)

        func lowPass(_ value: Double, cutoff: Double, state: inout Double) -> Double {
            let alpha = 1 - exp(-2 * Double.pi * cutoff / sampleRate)
            state += alpha * (value - state)
            return state
        }

        func highPass(_ value: Double, cutoff: Double, state: inout Double, previousInput: inout Double) -> Double {
            let alpha = exp(-2 * Double.pi * cutoff / sampleRate)
            state = alpha * (state + value - previousInput)
            previousInput = value
            return state
        }

        func oscillator(_ frequency: Double, phase: inout Double, waveform: Waveform = .sine) -> Double {
            phase += 2 * Double.pi * frequency / sampleRate
            if phase > 2 * Double.pi { phase.formTruncatingRemainder(dividingBy: 2 * Double.pi) }
            return waveformSample(phase: phase, waveform: waveform)
        }

        func triggerClicker(_ countdown: inout Double, _ envelope: inout Double, baseRange: ClosedRange<Double>, chaos: Double) {
            countdown -= 1 / sampleRate
            guard countdown <= 0 else { return }
            let chaosCompression = 1 - 0.62 * chaos
            let interval = Double.random(in: baseRange) * max(0.36, chaosCompression)
            countdown = interval * Double.random(in: 0.72...1.42)
            envelope += Double.random(in: 1.0...1.55)
        }

        for frame in 0..<frameCount {
            let noise = Double.random(in: -1...1)
            let value: Double
            switch style {
            case 0: // Warm Tone
                let body = oscillator((150 + 28 * speedFactor) * pitchMultiplier, phase: &state.primaryPhase)
                let roundness = oscillator((75 + 14 * speedFactor) * pitchMultiplier, phase: &state.secondaryPhase, waveform: .triangle)
                let presence = oscillator((300 + 56 * speedFactor) * pitchMultiplier, phase: &state.tertiaryPhase)
                value = body * 0.120 + roundness * 0.050 + presence * 0.026
            case 1: // Bell Tone
                let bell = oscillator((330 + 70 * speedFactor) * pitchMultiplier, phase: &state.primaryPhase)
                let chime = oscillator((660 + 140 * speedFactor) * pitchMultiplier, phase: &state.secondaryPhase)
                let shimmer = oscillator(5.2 + 2.2 * speedFactor, phase: &state.tertiaryPhase)
                value = bell * 0.095 + chime * 0.052 + shimmer * chime * 0.022
            case 2: // Tick Tone
                let tick = oscillator((500 + 95 * speedFactor) * pitchMultiplier, phase: &state.primaryPhase, waveform: .square)
                let body = oscillator((250 + 48 * speedFactor) * pitchMultiplier, phase: &state.secondaryPhase)
                let softener = lowPass(noise, cutoff: 1_200 + 400 * speedFactor, state: &state.lowState)
                value = tick * 0.052 + body * 0.070 + softener * 0.012
            case 3: // Showdown Ball
                let chaos = clamp(rattleEnergy)
                let movement = 0.35 + 0.65 * speedFactor
                let shellBody = lowPass(noise, cutoff: 70 + 120 * speedFactor, state: &state.lowState)
                let shellTone = oscillator(56 + 22 * speedFactor, phase: &state.primaryPhase, waveform: .triangle)
                let rotation = oscillator(2.5 + 5.0 * speedFactor, phase: &state.secondaryPhase)

                triggerClicker(&state.clicker1Countdown, &state.clicker1Envelope, baseRange: 0.16...0.38, chaos: chaos)
                triggerClicker(&state.clicker2Countdown, &state.clicker2Envelope, baseRange: 0.20...0.48, chaos: chaos)
                triggerClicker(&state.clicker3Countdown, &state.clicker3Envelope, baseRange: 0.25...0.60, chaos: chaos)
                triggerClicker(&state.clicker4Countdown, &state.clicker4Envelope, baseRange: 0.31...0.74, chaos: chaos)
                triggerClicker(&state.clicker5Countdown, &state.clicker5Envelope, baseRange: 0.38...0.88, chaos: chaos)
                triggerClicker(&state.clicker6Countdown, &state.clicker6Envelope, baseRange: 0.46...1.05, chaos: chaos)
                triggerClicker(&state.clicker7Countdown, &state.clicker7Envelope, baseRange: 0.56...1.26, chaos: chaos)
                triggerClicker(&state.clicker8Countdown, &state.clicker8Envelope, baseRange: 0.68...1.52, chaos: chaos)

                if Double.random(in: 0...1) < (0.50 + chaos * 9.0 + speedFactor * 2.4) / sampleRate {
                    let burst = Double.random(in: 0.45...0.85)
                    switch Int.random(in: 0...7) {
                    case 0: state.clicker1Envelope += burst
                    case 1: state.clicker2Envelope += burst
                    case 2: state.clicker3Envelope += burst
                    case 3: state.clicker4Envelope += burst
                    case 4: state.clicker5Envelope += burst
                    case 5: state.clicker6Envelope += burst
                    case 6: state.clicker7Envelope += burst
                    default: state.clicker8Envelope += burst
                    }
                }

                state.clicker1Envelope *= exp(-1 / (sampleRate * 0.0026))
                state.clicker2Envelope *= exp(-1 / (sampleRate * 0.0029))
                state.clicker3Envelope *= exp(-1 / (sampleRate * 0.0032))
                state.clicker4Envelope *= exp(-1 / (sampleRate * 0.0035))
                state.clicker5Envelope *= exp(-1 / (sampleRate * 0.0038))
                state.clicker6Envelope *= exp(-1 / (sampleRate * 0.0041))
                state.clicker7Envelope *= exp(-1 / (sampleRate * 0.0044))
                state.clicker8Envelope *= exp(-1 / (sampleRate * 0.0047))

                let bearingA = highPass(
                    lowPass(Double.random(in: -1...1), cutoff: 4_200, state: &state.transientState1),
                    cutoff: 1_450,
                    state: &state.transientState2,
                    previousInput: &state.transientPrevious1
                )
                let bearingB = highPass(
                    Double.random(in: -1...1),
                    cutoff: 2_050,
                    state: &state.transientState3,
                    previousInput: &state.transientPrevious2
                )
                let bearingC = highPass(
                    lowPass(Double.random(in: -1...1), cutoff: 5_400, state: &state.midState),
                    cutoff: 2_400,
                    state: &state.highState,
                    previousInput: &state.previousInput
                )
                let bearingD = highPass(
                    Double.random(in: -1...1),
                    cutoff: 4_800,
                    state: &state.transientState4,
                    previousInput: &state.transientPrevious3
                )
                let bearingE = highPass(
                    lowPass(Double.random(in: -1...1), cutoff: 6_200, state: &state.transientState5),
                    cutoff: 2_850,
                    state: &state.transientState6,
                    previousInput: &state.transientPrevious4
                )
                let bearingF = highPass(
                    Double.random(in: -1...1),
                    cutoff: 3_600,
                    state: &state.rattleBodyEnvelope,
                    previousInput: &state.subPreviousInput
                )
                let bearingG = bearingC * 0.82 + bearingA * 0.18
                let bearingH = bearingD * 0.86 + bearingB * 0.14

                let clicks = state.clicker1Envelope * bearingA * 0.060
                    + state.clicker2Envelope * bearingB * 0.056
                    + state.clicker3Envelope * bearingC * 0.064
                    + state.clicker4Envelope * bearingD * 0.062
                    + state.clicker5Envelope * bearingE * 0.050
                    + state.clicker6Envelope * bearingF * 0.048
                    + state.clicker7Envelope * bearingG * 0.054
                    + state.clicker8Envelope * bearingH * 0.052
                value = shellBody * 0.020 * movement
                    + shellTone * 0.010
                    + rotation * 0.004
                    + clicks * 1.35
            case 4: // Sine Tone
                let tone = oscillator((430 + 90 * speedFactor) * pitchMultiplier, phase: &state.primaryPhase)
                let anchor = oscillator((215 + 45 * speedFactor) * pitchMultiplier, phase: &state.secondaryPhase)
                let presence = oscillator((860 + 180 * speedFactor) * pitchMultiplier, phase: &state.tertiaryPhase)
                value = tone * 0.145 + anchor * 0.046 + presence * 0.020
            case 5: // Square Tone
                let square = oscillator((240 + 70 * speedFactor) * pitchMultiplier, phase: &state.primaryPhase, waveform: .square)
                let rounded = oscillator((120 + 35 * speedFactor) * pitchMultiplier, phase: &state.secondaryPhase)
                let edge = oscillator((480 + 140 * speedFactor) * pitchMultiplier, phase: &state.tertiaryPhase, waveform: .triangle)
                value = square * 0.070 + rounded * 0.074 + edge * 0.022
            case 6: // Pluck Tone
                let pluck = oscillator((285 + 65 * speedFactor) * pitchMultiplier, phase: &state.primaryPhase, waveform: .triangle)
                let overtone = oscillator((570 + 130 * speedFactor) * pitchMultiplier, phase: &state.secondaryPhase)
                let motion = oscillator(4.0 + 4.0 * speedFactor, phase: &state.tertiaryPhase)
                value = pluck * 0.095 + overtone * 0.038 + motion * overtone * 0.018
            case 7: // Cowbell Tone
                let metalA = oscillator((540 + 95 * speedFactor) * pitchMultiplier, phase: &state.primaryPhase, waveform: .square)
                let metalB = oscillator((810 + 135 * speedFactor) * pitchMultiplier, phase: &state.secondaryPhase, waveform: .square)
                value = metalA * 0.050 + metalB * 0.040 + oscillator((270 + 48 * speedFactor) * pitchMultiplier, phase: &state.tertiaryPhase) * 0.035
            case 8: // Clave Tone
                let clave = oscillator((720 + 110 * speedFactor) * pitchMultiplier, phase: &state.primaryPhase)
                let hollow = oscillator((360 + 55 * speedFactor) * pitchMultiplier, phase: &state.secondaryPhase, waveform: .triangle)
                value = clave * 0.075 + hollow * 0.056
            case 9: // Water Tone
                let water = oscillator((300 + 80 * speedFactor) * pitchMultiplier, phase: &state.primaryPhase)
                let ripple = oscillator((450 + 160 * speedFactor) * pitchMultiplier, phase: &state.secondaryPhase)
                let sway = oscillator(3.5 + 2.5 * speedFactor, phase: &state.tertiaryPhase)
                value = water * 0.080 + ripple * 0.050 + sway * water * 0.022
            case 10: // Sonar Tone
                let ping = oscillator((620 + 120 * speedFactor) * pitchMultiplier, phase: &state.primaryPhase)
                let depth = oscillator((155 + 30 * speedFactor) * pitchMultiplier, phase: &state.secondaryPhase)
                let harmonic = oscillator((1_240 + 240 * speedFactor) * pitchMultiplier, phase: &state.tertiaryPhase)
                value = ping * 0.128 + depth * 0.055 + harmonic * 0.026
            case 11: // Piano Tone
                let fundamental = oscillator((262 + 70 * speedFactor) * pitchMultiplier, phase: &state.primaryPhase)
                let fifth = oscillator((393 + 105 * speedFactor) * pitchMultiplier, phase: &state.secondaryPhase)
                let octave = oscillator((524 + 140 * speedFactor) * pitchMultiplier, phase: &state.tertiaryPhase)
                value = fundamental * 0.080 + fifth * 0.044 + octave * 0.030
            case 12: // Chime Tone
                let chime = oscillator((660 + 120 * speedFactor) * pitchMultiplier, phase: &state.primaryPhase)
                let sparkle = oscillator((990 + 180 * speedFactor) * pitchMultiplier, phase: &state.secondaryPhase)
                let body = oscillator((330 + 60 * speedFactor) * pitchMultiplier, phase: &state.tertiaryPhase)
                value = chime * 0.092 + sparkle * 0.054 + body * 0.028
            case 13: // Glass Tone
                let glass = oscillator((780 + 160 * speedFactor) * pitchMultiplier, phase: &state.primaryPhase)
                let shine = oscillator((1_170 + 240 * speedFactor) * pitchMultiplier, phase: &state.secondaryPhase)
                let body = oscillator((390 + 80 * speedFactor) * pitchMultiplier, phase: &state.tertiaryPhase)
                value = glass * 0.062 + shine * 0.036 + body * 0.036
            default: // Laser Tone
                let laser = oscillator((520 + 190 * speedFactor) * pitchMultiplier, phase: &state.primaryPhase, waveform: .sawtooth)
                let beam = oscillator((260 + 95 * speedFactor) * pitchMultiplier, phase: &state.secondaryPhase)
                let core = oscillator((780 + 285 * speedFactor) * pitchMultiplier, phase: &state.tertiaryPhase)
                value = laser * 0.078 + beam * 0.092 + core * 0.030
            }
            let rendered: Double
            if previewEnvelope {
                let edgeFrames = Int(0.018 * sampleRate)
                let edgeGain: Double
                if frame < edgeFrames {
                    edgeGain = Double(frame) / Double(edgeFrames)
                } else if frame > frameCount - edgeFrames {
                    edgeGain = Double(frameCount - frame) / Double(edgeFrames)
                } else {
                    edgeGain = 1
                }
                rendered = value * edgeGain
            } else {
                rendered = value
            }
            samples[frame] = Float(tanh(rendered))
        }
        return buffer
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
        let notes = [
            73.42, 87.31, 98.00, 110.00, 130.81,
            146.83, 174.61, 196.00, 220.00, 261.63,
            293.66, 349.23, 392.00, 440.00, 523.25,
            587.33, 698.46, 783.99, 880.00, 1_046.50
        ]
        let span = pitchBehavior == 0 ? 0 : (pitchBehavior == 1 ? 9 : notes.count - 1)
        let start = (notes.count - 1 - span) / 2
        let position = lowerWhenCloser ? 1 - near : near
        return notes[start + Int((clamp(position) * Double(span)).rounded())]
    }

    private func clamp(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }

    private func nonRepeatingIndex(count: Int, excluding previous: Int) -> Int {
        let choices = (0..<count).filter { $0 != previous }
        return choices.randomElement() ?? 0
    }
}
