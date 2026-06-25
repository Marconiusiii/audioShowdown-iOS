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
    private var smoothPuckQueuedBuffers = 0
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
                let session = AVAudioSession.sharedInstance()
                try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
                try session.setPreferredSampleRate(sourceFormat.sampleRate)
                // A 5 ms buffer is too aggressive when debugging tethered from Xcode and can starve VoiceOver speech.
                // 12 ms keeps gameplay responsive while leaving enough audio scheduling room for assistive audio.
                try session.setPreferredIOBufferDuration(0.012)
                try session.setActive(true)
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

    func puckPing(x: Double, distance proximity: Double, style: Int, pitchBehavior: Int, lowerWhenCloser: Bool) {
        let near = clamp(proximity)
        let pitchAmount = [0.0, 0.6, 1.4][pitchBehavior]
        let pitchMultiplier = 1 + pitchAmount * (lowerWhenCloser ? 1 - near : near)
        let gain = min(1, 0.30 + 0.70 * near) * puckVolume
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

    func updateSmoothPuck(style: Int, x: Double, proximity: Double, speed: Double, volume: Double, distanceBehavior: PuckDistanceBehavior, closerIncreases: Bool) {
        guard volume > 0 else {
            stopSmoothPuck()
            return
        }
        if !engine.isRunning { try? engine.start() }
        smoothPuckRattleEnergy = max(0, smoothPuckRattleEnergy - 0.010)
        let near = clamp(proximity)
        let distanceFactor = closerIncreases ? near : 1 - near
        smoothPuckRenderSpeed = speed
        smoothPuckPitchMultiplier = distanceBehavior == .pitch ? 0.72 + 0.56 * distanceFactor : 1

        if style != smoothPuckStyle || !smoothPuckVoice.dryPlayer.isPlaying {
            smoothPuckGeneration += 1
            smoothPuckStyle = style
            smoothPuckQueuedBuffers = 0
            smoothPuckRenderState = SmoothPuckRenderState()
            smoothPuckVoice.dryPlayer.stop()
            smoothPuckVoice.wetPlayer.stop()
            primeSmoothPuckQueue(generation: smoothPuckGeneration)
            smoothPuckVoice.dryPlayer.play()
            if reverbStyle > 0 { smoothPuckVoice.wetPlayer.play() }
        } else if reverbStyle > 0, !smoothPuckVoice.wetPlayer.isPlaying {
            smoothPuckGeneration += 1
            smoothPuckQueuedBuffers = 0
            smoothPuckRenderState = SmoothPuckRenderState()
            smoothPuckVoice.dryPlayer.stop()
            smoothPuckVoice.wetPlayer.stop()
            primeSmoothPuckQueue(generation: smoothPuckGeneration)
            smoothPuckVoice.dryPlayer.play()
            smoothPuckVoice.wetPlayer.play()
        } else if reverbStyle == 0, smoothPuckVoice.wetPlayer.isPlaying {
            smoothPuckVoice.wetPlayer.stop()
        }
        primeSmoothPuckQueue(generation: smoothPuckGeneration)
        let baseGain = distanceBehavior == .volume ? 0.48 + 0.42 * distanceFactor : 0.68
        let speedGain = 0.72 + 0.28 * clamp(speed / 1_800)
        let gain = Float(baseGain * speedGain * clamp(volume))
        let position = spatialPosition(x: x, proximity: near)
        smoothPuckVoice.dryPlayer.position = position
        smoothPuckVoice.wetPlayer.position = position
        smoothPuckVoice.dryPlayer.volume = gain
        smoothPuckVoice.wetPlayer.volume = gain
    }

    func previewSmoothPuck(style: Int, x: Double, proximity: Double, speed: Double, volume: Double, distanceBehavior: PuckDistanceBehavior, closerIncreases: Bool) {
        stopSmoothPuck()
        guard volume > 0 else { return }
        if !engine.isRunning { try? engine.start() }
        let near = clamp(proximity)
        let distanceFactor = closerIncreases ? near : 1 - near
        let pitchMultiplier = distanceBehavior == .pitch ? 0.72 + 0.56 * distanceFactor : 1
        let previewRattleEnergy = style == 3 ? 0.85 : 0.12
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
        smoothPuckQueuedBuffers = 0
        smoothPuckRenderState = SmoothPuckRenderState()
    }

    func energizeSmoothPuck(amount: Double) {
        smoothPuckRattleEnergy = clamp(smoothPuckRattleEnergy + amount)
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

    func updateMalletSlide(style: Int, x: Double, speed: Double, volume: Double) {
        guard style > 0, speed > 0, volume > 0 else {
            stopMalletSlide()
            return
        }
        if !engine.isRunning { try? engine.start() }
        let gain = Float((0.025 + 0.30 * clamp(speed / 1_400)) * clamp(volume))
        let position = spatialPosition(x: x, proximity: 0.95)
        if style != malletSlideStyle || !malletSlideVoice.dryPlayer.isPlaying {
            malletSlideStyle = style
            let buffer = renderMalletSlideLoop(style: style)
            malletSlideVoice.dryPlayer.stop()
            malletSlideVoice.dryPlayer.scheduleBuffer(buffer, at: nil, options: .loops)
            malletSlideVoice.dryPlayer.play()
            malletSlideVoice.wetPlayer.stop()
            malletSlideVoice.wetPlayer.scheduleBuffer(buffer, at: nil, options: .loops)
            if reverbStyle > 0 { malletSlideVoice.wetPlayer.play() }
        } else if reverbStyle > 0, !malletSlideVoice.wetPlayer.isPlaying {
            let buffer = renderMalletSlideLoop(style: style)
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
        voice.dryPlayer.renderingAlgorithm = .HRTFHQ
        voice.dryPlayer.reverbBlend = 0
        voice.wetPlayer.renderingAlgorithm = .HRTFHQ
        voice.wetPlayer.reverbBlend = 100
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
        environment.distanceAttenuationParameters.rolloffFactor = 0.6
    }

    private func spatialPosition(x: Double, proximity: Double) -> AVAudio3DPoint {
        let horizontal = Float((clamp(x) - 0.5) * 4.8)
        let depth = Float(-(0.5 + (1 - clamp(proximity)) * 5.0))
        return AVAudio3DPoint(x: horizontal, y: 0, z: depth)
    }

    private func renderMalletSlideLoop(style: Int) -> AVAudioPCMBuffer {
        let duration = 2.0
        let frameCount = Int(duration * sourceFormat.sampleRate)
        let buffer = AVAudioPCMBuffer(pcmFormat: sourceFormat, frameCapacity: AVAudioFrameCount(frameCount))!
        buffer.frameLength = AVAudioFrameCount(frameCount)
        let samples = buffer.floatChannelData![0]
        let sampleRate = sourceFormat.sampleRate
        var lowState = 0.0
        var midState = 0.0
        var highState = 0.0
        var previousInput = 0.0

        func lowPass(_ value: Double, cutoff: Double, state: inout Double) -> Double {
            let alpha = 1 - exp(-2 * Double.pi * cutoff / sampleRate)
            state += alpha * (value - state)
            return state
        }

        func highPass(_ value: Double, cutoff: Double, state: inout Double) -> Double {
            let alpha = exp(-2 * Double.pi * cutoff / sampleRate)
            state = alpha * (state + value - previousInput)
            previousInput = value
            return state
        }

        for frame in 0..<frameCount {
            let t = Double(frame) / sampleRate
            let noise = Double.random(in: -1...1)
            let value: Double
            switch style {
            case 1: // Wood
                let grain = lowPass(noise, cutoff: 850, state: &lowState)
                let chatter = abs(sin(2 * Double.pi * 37 * t)) * 2 - 1
                value = grain * 0.28 + chatter * 0.045 + sin(2 * Double.pi * 118 * t) * 0.045 + sin(2 * Double.pi * 236 * t) * 0.018
            case 2: // Rubber
                let drag = lowPass(noise, cutoff: 260, state: &lowState)
                let grip = waveformSample(phase: 2 * Double.pi * 54 * t, waveform: .triangle)
                value = drag * 0.34 + grip * 0.07 + sin(2 * Double.pi * 112 * t) * 0.025
            case 3: // Iron
                let scrape = highPass(lowPass(noise, cutoff: 2_200, state: &lowState), cutoff: 320, state: &highState)
                value = scrape * 0.11 + sin(2 * Double.pi * 430 * t) * 0.052 + sin(2 * Double.pi * 860 * t) * 0.022
            case 4: // Gold
                let polish = highPass(lowPass(noise, cutoff: 2_800, state: &lowState), cutoff: 420, state: &highState)
                value = polish * 0.08 + sin(2 * Double.pi * 660 * t) * 0.05 + sin(2 * Double.pi * 1_320 * t) * 0.017
            case 5: // Stone
                let rough = lowPass(noise, cutoff: 620, state: &lowState)
                let grit = highPass(lowPass(Double.random(in: -1...1), cutoff: 1_400, state: &midState), cutoff: 180, state: &highState)
                value = rough * 0.25 + grit * 0.09 + waveformSample(phase: 2 * Double.pi * 83 * t, waveform: .triangle) * 0.04
            default: // Plastic
                let scrape = highPass(lowPass(noise, cutoff: 1_900, state: &lowState), cutoff: 260, state: &highState)
                value = scrape * 0.10 + sin(2 * Double.pi * 290 * t) * 0.035 + waveformSample(phase: 2 * Double.pi * 145 * t, waveform: .triangle) * 0.035
            }
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
        while smoothPuckQueuedBuffers < 4 {
            let buffer = renderSmoothPuckBuffer(
                style: smoothPuckStyle,
                speed: smoothPuckRenderSpeed,
                pitchMultiplier: smoothPuckPitchMultiplier,
                rattleEnergy: smoothPuckRattleEnergy,
                state: &smoothPuckRenderState,
                previewEnvelope: false
            )
            smoothPuckQueuedBuffers += 1
            smoothPuckVoice.dryPlayer.scheduleBuffer(buffer) { [weak self] in
                Task { @MainActor [weak self] in
                    guard let self, generation == self.smoothPuckGeneration else { return }
                    self.smoothPuckQueuedBuffers = max(0, self.smoothPuckQueuedBuffers - 1)
                    self.primeSmoothPuckQueue(generation: generation)
                }
            }
            if reverbStyle > 0 {
                smoothPuckVoice.wetPlayer.scheduleBuffer(buffer)
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

        for frame in 0..<frameCount {
            let noise = Double.random(in: -1...1)
            let value: Double
            switch style {
            case 0: // Low Synth
                let fundamental = oscillator((54 + 22 * speedFactor) * pitchMultiplier, phase: &state.primaryPhase)
                let octave = oscillator((108 + 44 * speedFactor) * pitchMultiplier, phase: &state.secondaryPhase, waveform: .triangle)
                let movement = oscillator(2.4 + 2.8 * speedFactor, phase: &state.tertiaryPhase)
                let sub = lowPass(noise, cutoff: 42 + 35 * speedFactor, state: &state.lowState)
                value = fundamental * 0.070 + octave * 0.026 + movement * 0.010 + sub * 0.035
            case 1: // Soft Hum
                let hum = oscillator((92 + 30 * speedFactor) * pitchMultiplier, phase: &state.primaryPhase)
                let warmth = oscillator((184 + 60 * speedFactor) * pitchMultiplier, phase: &state.secondaryPhase, waveform: .triangle)
                let drift = oscillator(3.0 + 2.0 * speedFactor, phase: &state.tertiaryPhase)
                let body = lowPass(noise, cutoff: 65 + 60 * speedFactor, state: &state.lowState)
                value = hum * 0.055 + warmth * 0.025 + drift * 0.014 + body * 0.030
            case 2: // Table Roll
                let roll = oscillator((74 + 42 * speedFactor) * pitchMultiplier, phase: &state.primaryPhase, waveform: .triangle)
                let wobble = oscillator((31 + 20 * speedFactor) * pitchMultiplier, phase: &state.secondaryPhase)
                let body = lowPass(noise, cutoff: 115 + 160 * speedFactor, state: &state.lowState)
                let contact = lowPass(Double.random(in: -1...1), cutoff: 260 + 220 * speedFactor, state: &state.midState)
                value = roll * 0.042 + wobble * 0.022 + body * 0.065 + contact * 0.020
            case 3: // Showdown Ball
                let rollBody = lowPass(noise, cutoff: 95 + 250 * speedFactor, state: &state.lowState)
                let tableTexture = lowPass(Double.random(in: -1...1), cutoff: 280 + 250 * speedFactor, state: &state.midState)
                let ballTone = oscillator((68 + 38 * speedFactor) * pitchMultiplier, phase: &state.primaryPhase, waveform: .triangle)
                let eventRate = 1.4 + 7.0 * speedFactor + 8.0 * rattleEnergy
                let burstChance = eventRate / sampleRate
                if Double.random(in: 0...1) < burstChance {
                    let eventStrength = Double.random(in: 0.018...0.075) * (0.22 + speedFactor * 0.42 + rattleEnergy * 0.45)
                    state.rattleEnvelope += eventStrength
                    state.rattleBodyEnvelope += eventStrength * Double.random(in: 0.22...0.50)
                }
                state.rattleEnvelope *= exp(-1 / (sampleRate * (0.014 + 0.018 * rattleEnergy)))
                state.rattleBodyEnvelope *= exp(-1 / (sampleRate * (0.055 + 0.080 * rattleEnergy)))
                let internalTone = oscillator((176 + 70 * speedFactor) * pitchMultiplier, phase: &state.rattleResonancePhase, waveform: .triangle)
                value = rollBody * 0.075
                    + tableTexture * 0.026
                    + ballTone * 0.030
                    + state.rattleBodyEnvelope * rollBody * 0.070
                    + state.rattleEnvelope * internalTone * 0.050
            case 4: // Bearing Roll
                let bearing = oscillator((150 + 110 * speedFactor) * pitchMultiplier, phase: &state.primaryPhase)
                let lower = oscillator((75 + 55 * speedFactor) * pitchMultiplier, phase: &state.secondaryPhase, waveform: .triangle)
                let rotation = oscillator(5.5 + 7.5 * speedFactor, phase: &state.tertiaryPhase)
                let body = lowPass(noise, cutoff: 90 + 110 * speedFactor, state: &state.lowState)
                value = bearing * 0.044 + lower * 0.034 + rotation * 0.010 + body * 0.026
            case 5: // Gentle Jingle
                let carrier = oscillator((210 + 90 * speedFactor) * pitchMultiplier, phase: &state.primaryPhase)
                let bell = oscillator((420 + 180 * speedFactor) * pitchMultiplier, phase: &state.secondaryPhase)
                let sway = oscillator(2.0 + 3.5 * speedFactor, phase: &state.tertiaryPhase)
                if Double.random(in: 0...1) < (1.5 + 5.0 * speedFactor) / sampleRate {
                    state.rattleEnvelope += Double.random(in: 0.025...0.09)
                }
                state.rattleEnvelope *= exp(-1 / (sampleRate * 0.045))
                value = carrier * 0.022 + bell * 0.018 + sway * 0.010 + state.rattleEnvelope * bell * 0.080
            default: // Warm Buzz
                let buzz = oscillator((118 + 40 * speedFactor) * pitchMultiplier, phase: &state.primaryPhase, waveform: .triangle)
                let warmth = oscillator((59 + 20 * speedFactor) * pitchMultiplier, phase: &state.secondaryPhase)
                let pulse = oscillator(3.6 + 3.2 * speedFactor, phase: &state.tertiaryPhase)
                let body = lowPass(noise, cutoff: 80 + 80 * speedFactor, state: &state.lowState)
                value = buzz * 0.055 + warmth * 0.035 + pulse * 0.012 + body * 0.026
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
