import AVFoundation

@MainActor
final class GameAudioEngine: @unchecked Sendable {
    private enum Waveform { case sine, triangle, square, sawtooth }

    private struct Tone {
        let waveform: Waveform
        let startFrequency: Double
        let endFrequency: Double?
        let duration: TimeInterval
        let peak: Double
        var startTime: TimeInterval = 0
        var attack: TimeInterval = 0.004
        var tremoloRate: Double = 0
        var tremoloDepth: Double = 0
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

    enum OutputProfile: Sendable {
        case personalAudio
        case builtInSpeaker
    }

    private let engine = AVAudioEngine()
    private let dryMixer = AVAudioMixerNode()
    private let wetInputMixer = AVAudioMixerNode()
    private let reverb = AVAudioUnitReverb()
    private let wetMixer = AVAudioMixerNode()
    private let sourceFormat = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1)!
    /// Explicit stereo format for every connection downstream of the voices,
    /// tagged as **binaural**.
    ///
    /// The graph is built in `init()`, before `configureAudioSession()` has
    /// activated the session, so `format: nil` would leave the engine to infer
    /// a format from whatever the hardware reports at that moment. Panning
    /// requires two channels downstream, so the format is stated rather than
    /// inferred. The environment nodes used to impose a stereo format here as a
    /// side effect; nothing does now.
    ///
    /// The binaural tag is a hint, not a guarantee.
    ///
    /// Apple documents spatialisation as applying to plain *stereo* content and
    /// not to binaural content — a binaural signal is already the finished
    /// left/right ear signal, so re-rendering it through a head model would be
    /// wrong, which is exactly our case. On device it did NOT prevent AirPods
    /// from spatialising: the route still reported `spatialON` and the field
    /// stayed narrow until Spatial Audio was set to Off manually in Control
    /// Center. That documented exemption appears to be honoured for
    /// AVPlayerItem playback, not for AVAudioEngine output.
    ///
    /// It is kept because it correctly describes what these buffers are and
    /// costs nothing, but it must not be mistaken for a fix.
    private let mixFormat: AVAudioFormat = {
        var layout = AudioChannelLayout()
        layout.mChannelLayoutTag = kAudioChannelLayoutTag_Binaural
        let channelLayout = AVAudioChannelLayout(layout: &layout)
        return AVAudioFormat(standardFormatWithSampleRate: 48_000, channelLayout: channelLayout)
    }()
    /// The mallet slide has its own pair of players rather than a SpatialVoice.
    ///
    /// It is the only continuously looping sound whose pan must track a moving
    /// object. Baking the pan into the buffer restarts the loop on every
    /// change, and node `pan` is constant-power and leaves ~-12 dB in the far
    /// channel. Two permanently-looping players, each hard wired to one side
    /// with the crossfade applied through `volume`, avoid both problems.
    private let malletSlideLeft = AVAudioPlayerNode()
    private let malletSlideRight = AVAudioPlayerNode()
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
    private var smoothPuckWetRenderState = SmoothPuckRenderState()
    private var smoothPuckRenderX = 0.5
    private var smoothPuckRenderSpeed = 0.0
    private var smoothPuckPitchMultiplier = 1.0
    private var smoothPuckRattleEnergy = 0.0
    private var lastWinMotifIndex = -1
    private var lastLossMotifIndex = -1
    private var outputProfile: OutputProfile?
    /// Test-only pin; when set, route detection cannot overwrite the profile.
    private var forcedOutputProfile: OutputProfile?
    private var routeChangeObserver: NSObjectProtocol?
    private var interruptionObserver: NSObjectProtocol?
    private var mediaServicesResetObserver: NSObjectProtocol?
    private var isInterrupted = false

    init() {
        engine.attach(dryMixer)
        engine.attach(wetInputMixer)
        engine.attach(reverb)
        engine.attach(wetMixer)
        engine.connect(dryMixer, to: engine.mainMixerNode, format: mixFormat)
        engine.connect(wetInputMixer, to: reverb, format: mixFormat)
        engine.connect(reverb, to: wetMixer, format: mixFormat)
        engine.connect(wetMixer, to: engine.mainMixerNode, format: mixFormat)
        // The reverb send is fully wet; its level in the mix is the wet mixer's
        // output volume, set by `setReverb`.
        reverb.wetDryMix = 100
        wetMixer.outputVolume = 0
        configureMalletSlide()
        configure(voice: smoothPuckVoice)
        puckVoices = makeTrackingVoices(count: 10)
        effectVoices = makeVoices(count: 16)
        refreshOutputProfile(force: true)
        routeChangeObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshOutputProfile(force: true)
            }
        }
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let rawType = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            Task { @MainActor [weak self] in
                self?.handleAudioSessionInterruption(rawType: rawType)
            }
        }
        mediaServicesResetObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.mediaServicesWereResetNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleMediaServicesReset()
            }
        }
    }

    deinit {
        if let routeChangeObserver {
            NotificationCenter.default.removeObserver(routeChangeObserver)
        }
        if let interruptionObserver {
            NotificationCenter.default.removeObserver(interruptionObserver)
        }
        if let mediaServicesResetObserver {
            NotificationCenter.default.removeObserver(mediaServicesResetObserver)
        }
    }

    func prepare(volume: Double) {
        guard !isInterrupted else { return }
        engine.mainMixerNode.outputVolume = Float(volume)
        do {
            if !started {
                try configureAudioSession()
                refreshOutputProfile(force: true)
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

    /// Reports what the audio stack is actually doing on the current device and
    /// route. The simulator cannot produce an AirPods route, so this is the only
    /// way to see the real values rather than guessing at them.
    ///
    /// `pan` is what the engine would apply to a puck at the left wall: -1 means
    /// full left. If that reads -1 while the sound is still centred, the
    /// narrowing is happening after the engine, not inside it.
    func routeDiagnostics() -> String {
        // Start the engine first. Nothing configures the session until a sound
        // actually plays, so reading the route cold reports iOS's default
        // SoloAmbient session rather than the game's — which is what made the
        // first diagnostic misleading.
        _ = ensureEngineRunning()
        let session = AVAudioSession.sharedInstance()
        let route = session.currentRoute
        let outputs = route.outputs
        let ports = outputs.map { "\($0.portType.rawValue)(\($0.portName))" }.joined(separator: ", ")
        let spatial = outputs.map { output -> String in
            if #available(iOS 15.0, *) {
                return output.isSpatialAudioEnabled ? "spatialON" : "spatialOFF"
            }
            return "spatialUnknown"
        }.joined(separator: ", ")
        // The verdict first: HFP is a mono transport, so on that route iOS sums
        // the channels and no pan can reach one ear. A2DP is true stereo.
        let isHFP = outputs.contains { $0.portType == .bluetoothHFP }
        let channels = session.outputNumberOfChannels
        let verdict: String
        if isHFP {
            verdict = "PROBLEM: HFP route — mono transport, stereo cannot work"
        } else if channels < 2 {
            verdict = "PROBLEM: route reports \(channels) channel(s), not stereo"
        } else {
            verdict = "OK: stereo route"
        }
        let leftWallPan = Self.stereoPan(for: 0, profile: outputProfile)
        let profileName: String
        switch outputProfile {
        case .some(.personalAudio): profileName = "personalAudio"
        case .some(.builtInSpeaker): profileName = "builtInSpeaker"
        case nil: profileName = "unclassified"
        }
        return """
        \(verdict)
        route: \(ports.isEmpty ? "none" : ports)
        spatial: \(spatial.isEmpty ? "n/a" : spatial)
        profile: \(profileName)
        leftWallPan: \(leftWallPan)
        outputChannels: \(session.outputNumberOfChannels) (max \(session.maximumOutputNumberOfChannels))
        category: \(session.category.rawValue) mode: \(session.mode.rawValue)
        options: \(session.categoryOptions.rawValue)
        engineRunning: \(engine.isRunning)
        mainMixerFormat: \(engine.mainMixerNode.outputFormat(forBus: 0))
        outputNodeFormat: \(engine.outputNode.outputFormat(forBus: 0))
        """
    }

    /// Whether the underlying engine is actually running. Exposed so tests can
    /// start the real graph and catch a wiring fault that pure-function tests
    /// cannot see.
    var isRunningForTesting: Bool { engine.isRunning }

    /// The live engine, so tests can render the real graph offline and measure
    /// what each channel actually receives. Asserting on the pan value we hand
    /// the players is what let a narrow field ship repeatedly.
    var engineForTesting: AVAudioEngine { engine }

    /// The binaural-tagged mix format, so tests can assert the tag survives.
    var mixFormatForTesting: AVAudioFormat { mixFormat }

    /// Mallet slide playback state, so tests can prove the loop keeps running
    /// while its balance follows the paddle.
    /// Counts how many times the slide loop has been (re)scheduled. A sweep
    /// across the table must not increase it: re-scheduling restarts the loop
    /// from frame zero, which is what made the slide grate.
    private(set) var malletSlideScheduleCountForTesting = 0
    var malletSlideIsPlayingForTesting: Bool { malletSlideLeft.isPlaying && malletSlideRight.isPlaying }
    var malletSlideVolumesForTesting: (Float, Float) { (malletSlideLeft.volume, malletSlideRight.volume) }

    /// The rendered slide loop, so tests can inspect its seams directly.
    func malletSlideLoopForTesting() -> AVAudioPCMBuffer { renderMalletSlideLoop() }

    /// Pins the output profile so tests can measure a specific route's pan.
    /// The simulator reports the built-in speaker, which would otherwise make
    /// every measurement the speaker path.
    func forceOutputProfileForTesting(_ profile: OutputProfile) {
        forcedOutputProfile = profile
        outputProfile = profile
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
            reverb.loadFactoryPreset(.smallRoom)
            wetMixer.outputVolume = 0.025
        case 2:
            reverb.loadFactoryPreset(.largeRoom)
            wetMixer.outputVolume = 0.04
        case 3:
            reverb.loadFactoryPreset(.largeHall)
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
        let pulseClarity = near > 0.78 ? 0.78 : 1.0
        let buffer = render(
            tones: tones.map { shortened(tone: $0, scale: pulseClarity) },
            noises: noises.map { shortened(noise: $0, scale: pulseClarity) },
            gain: gain,
            lowPass: cutoff
        )
        playPuck(buffer, x: x, proximity: near)
    }

    private func shortened(tone: Tone, scale: Double) -> Tone {
        guard scale < 1 else { return tone }
        return Tone(
            waveform: tone.waveform,
            startFrequency: tone.startFrequency,
            endFrequency: tone.endFrequency,
            duration: tone.duration * scale,
            peak: tone.peak,
            startTime: tone.startTime,
            attack: tone.attack,
            tremoloRate: tone.tremoloRate,
            tremoloDepth: tone.tremoloDepth
        )
    }

    private func shortened(noise: Noise, scale: Double) -> Noise {
        guard scale < 1 else { return noise }
        return Noise(
            duration: noise.duration * scale,
            peak: noise.peak,
            highPass: noise.highPass,
            lowPass: noise.lowPass,
            startTime: noise.startTime
        )
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
        smoothPuckRenderX = clamp(x)
        smoothPuckRenderSpeed = speed
        let pitchAmount = pitchChangesWithDistance && style != 3 ? [0.0, 0.25, 0.5][pitchBehavior] : 0
        smoothPuckPitchMultiplier = 1 + pitchAmount * (lowerWhenCloser ? 1 - near : near)

        if style != smoothPuckStyle || !smoothPuckVoice.dryPlayer.isPlaying {
            smoothPuckGeneration += 1
            smoothPuckStyle = style
            smoothPuckDryQueuedBuffers = 0
            smoothPuckWetQueuedBuffers = 0
            smoothPuckRenderState = SmoothPuckRenderState()
            smoothPuckWetRenderState = SmoothPuckRenderState()
            smoothPuckVoice.dryPlayer.stop()
            smoothPuckVoice.wetPlayer.stop()
            primeSmoothPuckQueue(generation: smoothPuckGeneration)
            if smoothPuckDryQueuedBuffers > 0 {
                smoothPuckVoice.dryPlayer.play()
            }
            if reverbStyle > 0, smoothPuckWetQueuedBuffers > 0 {
                smoothPuckVoice.wetPlayer.play()
            }
        } else if reverbStyle == 0, smoothPuckVoice.wetPlayer.isPlaying {
            smoothPuckVoice.wetPlayer.stop()
            smoothPuckWetQueuedBuffers = 0
            smoothPuckWetRenderState = SmoothPuckRenderState()
        } else if reverbStyle > 0, !smoothPuckVoice.wetPlayer.isPlaying {
            smoothPuckWetQueuedBuffers = 0
            smoothPuckWetRenderState = SmoothPuckRenderState()
            primeSmoothPuckQueue(generation: smoothPuckGeneration)
            if smoothPuckWetQueuedBuffers > 0 {
                smoothPuckVoice.wetPlayer.play()
            }
        }
        primeSmoothPuckQueue(generation: smoothPuckGeneration)
        let baseGain = volumeChangesWithDistance ? 0.86 + 0.14 * near : 0.94
        let gain = Float(baseGain * clamp(volume))
        // The pan is applied per rendered buffer in `primeSmoothPuckQueue`,
        // using `smoothPuckRenderX`, which was updated above. It cannot be set
        // on the player, because a constant-power `pan` leaves ~-12 dB in the
        // far channel and that is precisely the leak being fixed.
        smoothPuckVoice.dryPlayer.volume = gain
        smoothPuckVoice.wetPlayer.volume = reverbStyle > 0 ? gain : 0
    }

    func previewSmoothPuck(style: Int, x: Double, proximity: Double, speed: Double, volume: Double, pitchBehavior: Int, pitchChangesWithDistance: Bool, lowerWhenCloser: Bool, volumeChangesWithDistance: Bool) {
        stopSmoothPuck()
        stopPuckPreviewVoices()
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
        smoothPuckWetRenderState = SmoothPuckRenderState()
    }

    private func stopPuckPreviewVoices() {
        for voice in puckVoices {
            voice.dryPlayer.volume = 0
            voice.wetPlayer.volume = 0
            if voice.dryPlayer.isPlaying { voice.dryPlayer.stop() }
            if voice.wetPlayer.isPlaying { voice.wetPlayer.stop() }
        }
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
        let compensatedGain = Float((0.025 + 0.30 * clamp(speed / 1_400)) * clamp(volume))
        let pan = Self.stereoPan(for: x, profile: outputProfile)

        // The slide is a continuous loop, so its pan must NEVER be baked into
        // the buffer. Doing that meant every pan change re-scheduled the loop,
        // restarting it from frame zero — dragging the paddle restarted it
        // constantly, which is the grating, repeating rattle this replaced.
        //
        // Instead each channel has its own permanently-looping player, hard
        // wired to one side, and the crossfade is applied through `volume`.
        // Changing a volume does not interrupt playback, so the loop runs
        // unbroken while the mallet moves.
        if malletSlideStyle != 1 || !malletSlideLeft.isPlaying || !malletSlideRight.isPlaying {
            malletSlideStyle = 1
            let loop = renderMalletSlideLoop()
            malletSlideScheduleCountForTesting += 1
            for (player, side) in [(malletSlideLeft, 0), (malletSlideRight, 1)] {
                player.stop()
                player.scheduleBuffer(singleChannel(loop, side: side), at: nil, options: .loops)
                player.play()
            }
        }

        // Same linear crossfade law as `panned(_:pan:)`: the near side holds at
        // unity and the far side falls linearly to zero at the wall.
        let leftGain = pan <= 0 ? 1 : 1 - pan
        let rightGain = pan >= 0 ? 1 : 1 + pan
        malletSlideLeft.volume = compensatedGain * leftGain
        malletSlideRight.volume = compensatedGain * rightGain
    }

    func stopMalletSlide() {
        for player in [malletSlideLeft, malletSlideRight] {
            player.volume = 0
            if player.isPlaying { player.stop() }
        }
        malletSlideStyle = -1
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
            playEffect(render(tones: tones, noises: [], gain: 0.42), x: 0.5, proximity: 0.4)
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
        let motifIndex = nonRepeatingIndex(count: 4, excluding: lastWinMotifIndex)
        lastWinMotifIndex = motifIndex
        var tones: [Tone] = []

        func addFanfareNote(_ frequency: Double, start: TimeInterval, duration: TimeInterval, peak: Double = 0.38, tremolo: Bool = false) {
            tones.append(Tone(
                waveform: .sine,
                startFrequency: frequency,
                endFrequency: nil,
                duration: duration,
                peak: peak,
                startTime: start,
                attack: 0.006,
                tremoloRate: tremolo ? 14.5 : 0,
                tremoloDepth: tremolo ? 0.28 : 0
            ))
            tones.append(Tone(
                waveform: .sine,
                startFrequency: frequency * 2,
                endFrequency: nil,
                duration: duration * 0.72,
                peak: peak * 0.12,
                startTime: start,
                attack: 0.008,
                tremoloRate: tremolo ? 14.5 : 0,
                tremoloDepth: tremolo ? 0.12 : 0
            ))
        }

        func addTensionPad(_ frequencies: [Double], start: TimeInterval = 0, duration: TimeInterval = 0.68) {
            for (index, frequency) in frequencies.enumerated() {
                tones.append(Tone(
                    waveform: .sine,
                    startFrequency: frequency,
                    endFrequency: nil,
                    duration: duration,
                    peak: index == 0 ? 0.046 : 0.036,
                    startTime: start,
                    attack: duration * (0.72 + Double(index) * 0.06),
                    tremoloRate: 4.2,
                    tremoloDepth: 0.03
                ))
            }
        }

        func addResolvingPad(_ frequency: Double, start: TimeInterval, duration: TimeInterval = 0.88) {
            tones.append(Tone(
                waveform: .sine,
                startFrequency: frequency,
                endFrequency: nil,
                duration: duration,
                peak: 0.034,
                startTime: start,
                attack: 0.14
            ))
        }

        func addBassLine(_ notes: [(Double, TimeInterval, TimeInterval, Double)]) {
            for note in notes {
                tones.append(Tone(
                    waveform: .sine,
                    startFrequency: note.0,
                    endFrequency: nil,
                    duration: note.2,
                    peak: note.3,
                    startTime: note.1,
                    attack: 0.008
                ))
            }
        }

        addTensionPad([261.63, 293.66, 329.63])
        switch motifIndex {
        case 0:
            addBassLine([
                (261.63, 0.00, 0.16, 0.36),
                (220.00, 0.11, 0.16, 0.34),
                (196.00, 0.22, 0.16, 0.34),
                (174.61, 0.33, 0.16, 0.32),
                (130.81, 0.44, 0.34, 0.30)
            ])
            addFanfareNote(523.25, start: 0.00, duration: 0.16)
            addFanfareNote(659.25, start: 0.11, duration: 0.16)
            addFanfareNote(783.99, start: 0.22, duration: 0.16)
            addFanfareNote(698.46, start: 0.33, duration: 0.16, peak: 0.34)
            addResolvingPad(1_046.50, start: 0.44)
            addFanfareNote(1_046.50, start: 0.44, duration: 0.36, peak: 0.34)
        case 1:
            addBassLine([
                (261.63, 0.00, 0.15, 0.36),
                (246.94, 0.10, 0.15, 0.34),
                (220.00, 0.20, 0.15, 0.34),
                (196.00, 0.31, 0.16, 0.32),
                (130.81, 0.42, 0.34, 0.30)
            ])
            addFanfareNote(523.25, start: 0.00, duration: 0.15)
            addFanfareNote(587.33, start: 0.10, duration: 0.15)
            addFanfareNote(554.37, start: 0.20, duration: 0.15)
            addFanfareNote(783.99, start: 0.31, duration: 0.16, peak: 0.38)
            addResolvingPad(1_046.50, start: 0.42)
            addFanfareNote(1_046.50, start: 0.42, duration: 0.36, peak: 0.34)
        case 2:
            addBassLine([
                (261.63, 0.00, 0.15, 0.36),
                (196.00, 0.10, 0.15, 0.34),
                (220.00, 0.20, 0.15, 0.34),
                (174.61, 0.31, 0.16, 0.32),
                (130.81, 0.42, 0.34, 0.30)
            ])
            addFanfareNote(523.25, start: 0.00, duration: 0.15)
            addFanfareNote(659.25, start: 0.10, duration: 0.15)
            addFanfareNote(587.33, start: 0.20, duration: 0.15)
            addFanfareNote(880.00, start: 0.31, duration: 0.16, peak: 0.36)
            addResolvingPad(1_046.50, start: 0.42)
            addFanfareNote(1_046.50, start: 0.42, duration: 0.36, peak: 0.34)
        default:
            addBassLine([
                (261.63, 0.00, 0.15, 0.36),
                (246.94, 0.10, 0.15, 0.34),
                (196.00, 0.20, 0.15, 0.34),
                (220.00, 0.31, 0.16, 0.32),
                (130.81, 0.42, 0.34, 0.30)
            ])
            addFanfareNote(523.25, start: 0.00, duration: 0.15)
            addFanfareNote(587.33, start: 0.10, duration: 0.15)
            addFanfareNote(659.25, start: 0.20, duration: 0.15)
            addFanfareNote(783.99, start: 0.31, duration: 0.16, peak: 0.38)
            addResolvingPad(1_046.50, start: 0.42)
            addFanfareNote(1_046.50, start: 0.42, duration: 0.36, peak: 0.34)
        }

        playEffect(render(tones: tones, noises: [], gain: 0.82), x: 0.5, proximity: 0.72)
    }

    func matchLost() {
        let motifIndex = nonRepeatingIndex(count: 4, excluding: lastLossMotifIndex)
        lastLossMotifIndex = motifIndex
        var tones: [Tone] = []
        var noises: [Noise] = []

        func addDirgeNote(_ frequency: Double, start: TimeInterval, duration: TimeInterval, peak: Double = 0.30) {
            tones.append(Tone(waveform: .triangle, startFrequency: frequency, endFrequency: nil, duration: duration, peak: peak, startTime: start, attack: 0.026))
            tones.append(Tone(waveform: .sine, startFrequency: frequency * 0.5, endFrequency: nil, duration: duration * 1.03, peak: peak * 0.18, startTime: start, attack: 0.035))
        }

        func addSplat(start: TimeInterval) {
            tones.append(Tone(waveform: .triangle, startFrequency: 146.83, endFrequency: 82.41, duration: 0.18, peak: 0.16, startTime: start, attack: 0.003))
            noises.append(Noise(duration: 0.16, peak: 0.34, lowPass: 900, startTime: start + 0.01))
        }

        switch motifIndex {
        case 0:
            tones.append(Tone(waveform: .sawtooth, startFrequency: 196.00, endFrequency: 174.61, duration: 0.38, peak: 0.22, startTime: 0.00, attack: 0.05))
            tones.append(Tone(waveform: .sawtooth, startFrequency: 174.61, endFrequency: 146.83, duration: 0.44, peak: 0.24, startTime: 0.42, attack: 0.05))
            tones.append(Tone(waveform: .triangle, startFrequency: 98.00, endFrequency: 82.41, duration: 0.44, peak: 0.11, startTime: 0.42, attack: 0.06))
            addDirgeNote(130.81, start: 0.92, duration: 0.34, peak: 0.26)
            addSplat(start: 1.36)
        case 1:
            addDirgeNote(329.63, start: 0.00, duration: 0.18, peak: 0.29)
            addDirgeNote(311.13, start: 0.20, duration: 0.16, peak: 0.28)
            addDirgeNote(293.66, start: 0.38, duration: 0.16, peak: 0.28)
            addDirgeNote(261.63, start: 0.58, duration: 0.30, peak: 0.30)
            addDirgeNote(220.00, start: 0.94, duration: 0.34, peak: 0.28)
            addSplat(start: 1.38)
        case 2:
            tones.append(Tone(waveform: .sawtooth, startFrequency: 220.00, endFrequency: 196.00, duration: 0.34, peak: 0.21, startTime: 0.00, attack: 0.05))
            tones.append(Tone(waveform: .sawtooth, startFrequency: 196.00, endFrequency: 164.81, duration: 0.42, peak: 0.23, startTime: 0.38, attack: 0.05))
            tones.append(Tone(waveform: .triangle, startFrequency: 110.00, endFrequency: 92.50, duration: 0.42, peak: 0.10, startTime: 0.38, attack: 0.06))
            addDirgeNote(146.83, start: 0.86, duration: 0.34, peak: 0.25)
            addSplat(start: 1.30)
        default:
            addDirgeNote(349.23, start: 0.00, duration: 0.18, peak: 0.28)
            addDirgeNote(329.63, start: 0.20, duration: 0.16, peak: 0.27)
            addDirgeNote(311.13, start: 0.38, duration: 0.16, peak: 0.27)
            addDirgeNote(293.66, start: 0.58, duration: 0.26, peak: 0.29)
            addDirgeNote(246.94, start: 0.90, duration: 0.34, peak: 0.27)
            addSplat(start: 1.34)
        }

        playEffect(render(tones: tones, noises: noises, gain: 0.72, lowPass: 1_800), x: 0.5, proximity: 0.6)
    }

    private func makeVoices(count: Int) -> [SpatialVoice] {
        (0..<count).map { _ in
            let voice = SpatialVoice()
            configure(voice: voice)
            return voice
        }
    }

    private func makeTrackingVoices(count: Int) -> [SpatialVoice] {
        (0..<count).map { _ in
            let voice = SpatialVoice()
            configure(voice: voice)
            return voice
        }
    }

    /// Wires a voice as a stereo source.
    ///
    /// The players are fed *stereo* buffers with the left/right split already
    /// applied to the samples (see `panned(_:pan:)`), and their `pan` property
    /// is left at 0.
    ///
    /// This is deliberate and must not be "simplified" back to a mono buffer
    /// plus `player.pan`. `AVAudioPlayerNode.pan` on a mono source is a
    /// *constant-power* pan: at full deflection it still leaves roughly -12 dB
    /// in the opposite channel, because constant-power law is built to hold
    /// perceived loudness steady across the sweep, not to reach silence.

    /// Measured on the real graph, a puck at a wall came out L=0.450 R=0.108 —
    /// about a quarter of the signal in the wrong ear. That is the narrowness
    /// that survived every previous attempt at this, because the pan value we
    /// set was correct and only the rendered samples showed the problem.
    /// Wires the mallet slide's two players straight into the dry mixer.
    ///
    /// Each player is fed a buffer that is already silent in the opposite
    /// channel (see `singleChannel(_:side:)`), so no node pan is involved and
    /// the far channel is exactly zero — the same guarantee the puck gets.
    private func configureMalletSlide() {
        for player in [malletSlideLeft, malletSlideRight] {
            engine.attach(player)
            engine.connect(player, to: dryMixer, format: mixFormat)
        }
    }

    /// Copies a mono buffer into one channel of a stereo buffer, leaving the
    /// other channel silent. Used for the mallet slide, whose loop must play
    /// unbroken while its left/right balance changes: the balance is then just
    /// the two players' volumes, which can change without restarting playback.
    private func singleChannel(_ mono: AVAudioPCMBuffer, side: Int) -> AVAudioPCMBuffer {
        let frames = mono.frameLength
        let stereo = AVAudioPCMBuffer(pcmFormat: mixFormat, frameCapacity: frames)!
        stereo.frameLength = frames
        let source = mono.floatChannelData![0]
        let target = stereo.floatChannelData![side]
        let silent = stereo.floatChannelData![1 - side]
        for frame in 0..<Int(frames) {
            target[frame] = source[frame]
            silent[frame] = 0
        }
        return stereo
    }

    private func configure(voice: SpatialVoice) {
        engine.attach(voice.dryPlayer)
        engine.attach(voice.wetPlayer)
        engine.connect(voice.dryPlayer, to: dryMixer, format: mixFormat)
        engine.connect(voice.wetPlayer, to: wetInputMixer, format: mixFormat)
    }

    /// Splits a mono buffer into a stereo buffer with a **linear** pan.
    ///
    /// `pan` is -1 (hard left) to +1 (hard right).
    ///
    /// The law is a **linear crossfade**: one channel holds at full while the
    /// other falls linearly from full at the centre to zero at the wall. So a
    /// wall puts exactly zero in the opposite channel, the centre sits equal in
    /// both, and every step across the table moves the mix by the same amount.
    ///
    /// Do not write this as `1 - pan` / `1 + pan` clamped to 0...1. That looks
    /// equivalent but is not: it saturates. Over the whole left half the left
    /// channel is pinned at 1 and only the right channel moves, so each channel
    /// is flat across half the table. Measured, the per-channel steps came out
    /// 0.25, 0.25, 0, 0 — half the sweep dead in each channel.
    private func panned(_ mono: AVAudioPCMBuffer, pan: Float) -> AVAudioPCMBuffer {
        let frames = mono.frameLength
        let stereo = AVAudioPCMBuffer(pcmFormat: mixFormat, frameCapacity: frames)!
        stereo.frameLength = frames
        let source = mono.floatChannelData![0]
        let left = stereo.floatChannelData![0]
        let right = stereo.floatChannelData![1]
        // The near channel holds at unity across the whole sweep and the far
        // channel falls linearly to zero at the wall. Peak level is therefore
        // constant (never above 1, so nothing clips) while the *difference*
        // between the channels moves linearly with table position.
        let clamped = min(max(pan, -1), 1)
        let leftGain = clamped <= 0 ? 1 : 1 - clamped
        let rightGain = clamped >= 0 ? 1 : 1 + clamped
        for frame in 0..<Int(frames) {
            let sample = source[frame]
            left[frame] = sample * leftGain
            right[frame] = sample * rightGain
        }
        return stereo
    }

    private func ensureEngineRunning() -> Bool {
        guard !isInterrupted else { return false }
        refreshOutputProfile()
        if engine.isRunning { return true }
        do {
            if !started {
                try configureAudioSession()
                refreshOutputProfile(force: true)
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
        // `.playback` with NO options, deliberately.
        //
        // This used to pass `.mixWithOthers`, which had been there since the
        // app's first commit and was never a considered choice. That flag makes
        // the game secondary, mixable audio, so instead of asserting its own
        // route it attaches to whatever route another session already
        // negotiated. On AirPods that can be HFP — the hands-free profile — and
        // **HFP is mono**. On a mono transport iOS sums the two channels and
        // sends the same signal to both ears, so no amount of correct panning
        // can reach one ear. That is the narrow, always-partly-centred field:
        // it is the Bluetooth route, not the mix.
        //
        // Anything holding the microphone pulls AirPods onto HFP, and "Hey
        // Siri" on the AirPods themselves is enough. Dropping the flag lets the
        // game own a `.playback` route, which negotiates A2DP — true stereo.
        try session.setCategory(.playback, mode: audioSessionMode(for: currentOutputProfile()), options: [])
        try session.setPreferredSampleRate(sourceFormat.sampleRate)
        // A 5 ms buffer is too aggressive when debugging tethered from Xcode and can starve VoiceOver speech.
        // 12 ms keeps gameplay responsive while leaving enough audio scheduling room for assistive audio.
        try session.setPreferredIOBufferDuration(0.012)
        try session.setActive(true)
        // Preferred-format requests only take effect on an ACTIVE session, so
        // this must follow `setActive`. It previously ran before activation and
        // was silently dropped, leaving the channel count to whatever the route
        // happened to offer.
        if session.maximumOutputNumberOfChannels >= 2 {
            try? session.setPreferredOutputNumberOfChannels(2)
        }
        routeAwayFromReceiverIfNeeded()
    }

    /// Forces playback off the built-in receiver (earpiece).
    ///
    /// The `.playback` category should never select the receiver on its own,
    /// but a session can land there after another app, a call, or a mode change
    /// leaves the route in that state. When it happens the game is almost
    /// inaudible, so this moves output back to the speaker. It deliberately
    /// does nothing when headphones or any other external route is attached.
    private func routeAwayFromReceiverIfNeeded() {
        let session = AVAudioSession.sharedInstance()
        let outputs = session.currentRoute.outputs
        guard outputs.contains(where: { $0.portType == .builtInReceiver }) else { return }
        try? session.overrideOutputAudioPort(.speaker)
    }

    private func handleAudioSessionInterruption(rawType: UInt?) {
        guard let rawType, let type = AVAudioSession.InterruptionType(rawValue: rawType) else {
            beginAudioInterruption()
            return
        }
        switch type {
        case .began:
            beginAudioInterruption()
        case .ended:
            endAudioInterruption()
        @unknown default:
            beginAudioInterruption()
        }
    }

    private func beginAudioInterruption() {
        isInterrupted = true
        stopContinuousAudioForInterruption()
        engine.pause()
        started = false
    }

    private func endAudioInterruption() {
        isInterrupted = false
        outputProfile = nil
        do {
            try configureAudioSession()
            refreshOutputProfile(force: true)
        } catch {
            started = false
        }
    }

    private func handleMediaServicesReset() {
        isInterrupted = false
        stopContinuousAudioForInterruption()
        engine.stop()
        started = false
        warmedUp = false
        outputProfile = nil
    }

    private func stopContinuousAudioForInterruption() {
        stopSmoothPuck()
        stopMalletSlide()
        stopPuckPreviewVoices()
    }

    private func playPuck(_ buffer: AVAudioPCMBuffer, x: Double, proximity: Double) {
        guard ensureEngineRunning() else { return }
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
        guard ensureEngineRunning() else { return }
        // Proximity is carried by the buffer itself — pitch, timing, and the
        // gain baked in by the caller. It must not affect the pan.
        _ = proximity
        let pan = Self.stereoPan(for: x, profile: outputProfile)
        let split = panned(buffer, pan: pan)
        if voice.dryPlayer.isPlaying { voice.dryPlayer.stop() }
        voice.dryPlayer.volume = 1
        voice.dryPlayer.scheduleBuffer(split)
        voice.dryPlayer.play()

        if reverbStyle > 0 {
            if voice.wetPlayer.isPlaying { voice.wetPlayer.stop() }
            voice.wetPlayer.volume = 1
            voice.wetPlayer.scheduleBuffer(split)
            voice.wetPlayer.play()
        }
    }

    private func refreshOutputProfile(force: Bool = false) {
        if let forcedOutputProfile {
            outputProfile = forcedOutputProfile
            routeAwayFromReceiverIfNeeded()
            return
        }
        let profile = currentOutputProfile()
        guard force || profile != outputProfile else { return }
        outputProfile = profile
        // Reassert the route whenever it changes. Unplugging headphones can
        // leave playback on the receiver, which is why removing AirPods
        // mid-match used to drop the game to a near-silent earpiece while
        // VoiceOver still played through the speaker.
        routeAwayFromReceiverIfNeeded()
        // Nothing else is route-dependent any more. Panning is identical on
        // every output, so there is no per-route rendering to reconfigure.
    }

    private func currentOutputProfile() -> OutputProfile {
        Self.outputProfile(forPortTypes: AVAudioSession.sharedInstance()
            .currentRoute.outputs.map(\.portType))
    }

    /// Classifies a route as personal audio or loudspeaker. Separated from the
    /// live session so it can be tested directly — this decision drove a 1.0.5
    /// regression that sent all game audio to the earpiece.
    ///
    /// This no longer affects how audio is rendered: the pan is the same on
    /// every output. It survives because the receiver override depends on
    /// knowing when nothing external is attached.
    nonisolated static func outputProfile(forPortTypes portTypes: [AVAudioSession.Port]) -> OutputProfile {
        // An empty route means the session isn't active yet; assume the speaker.
        guard !portTypes.isEmpty else { return .builtInSpeaker }
        let personalAudioPorts: Set<AVAudioSession.Port> = [
            .headphones,
            .bluetoothA2DP,
            .bluetoothHFP,
            .bluetoothLE,
            .airPlay,
            .usbAudio,
            .carAudio
        ]
        if portTypes.contains(where: { personalAudioPorts.contains($0) }) {
            return .personalAudio
        }
        // Everything else — built-in speaker, receiver, or an unfamiliar port —
        // is treated as loudspeaker playback.
        return .builtInSpeaker
    }

    /// The session mode is deliberately `.default` for every route.
    ///
    /// `.measurement` was previously used for headphone playback because it
    /// disables system signal processing and keeps the spatial cues clean. But
    /// iOS treats measurement as a call-like mode: with the `.playback`
    /// category it routes to the built-in *receiver* (the earpiece) rather than
    /// the speaker. On a phone with no headphones attached that made game audio
    /// nearly silent, while VoiceOver — which uses its own session — still came
    /// out of the speaker.
    ///
    /// `.default` keeps speaker output correct and costs nothing audible: the
    /// left/right placement is a plain stereo pan on each player node, not
    /// anything the session mode influences.
    nonisolated static func audioSessionMode(for profile: OutputProfile) -> AVAudioSession.Mode {
        _ = profile
        return .default
    }

    private func audioSessionMode(for profile: OutputProfile) -> AVAudioSession.Mode {
        Self.audioSessionMode(for: profile)
    }

    /// Maps table position straight onto the stereo field.
    ///
    /// `x` is 0 at the left wall and 1 at the right wall; the result is the
    /// player node's pan, -1 (hard left) to +1 (hard right). The mapping is
    /// deliberately the plain linear one, so equal steps across the table are
    /// equal steps across the stereo field the whole way out.
    ///
    /// This game does not want spatial audio. Left/right is the gameplay
    /// signal, and everything else — how far the puck is, how fast it is
    /// closing — is already carried by pulse timing, pitch, and volume. Do not
    /// reintroduce `AVAudioEnvironmentNode`, HRTF, or any 3D placement here.
    /// HRTF renders a generic head, and a head deliberately bleeds sound into
    /// the far ear, which caps the usable width no matter how far out a source
    /// is placed. That is what made the field read as narrow on AirPods, which
    /// reproduce the head model faithfully, while bone-conduction sets that
    /// destroy those cues sounded acceptable. A pan has no head model, so a
    /// puck at a wall is simply in that ear.
    ///
    /// Distance must never touch the pan: it is not directional information.
    ///
    /// `profile` scales how far the pan is allowed to travel, and *only* that.
    /// Personal audio gets the full sweep to the hard edges. The built-in
    /// speaker must not: the phone's speakers sit at opposite ends of the
    /// device, so a hard-panned sound leaves one of them entirely, and the hand
    /// holding the phone covers it. Limiting the speaker's travel keeps signal
    /// in both speakers at every table position while preserving the direction
    /// cue. It stays linear either way, so the sweep is still even.
    nonisolated static func stereoPan(for x: Double, profile: OutputProfile?) -> Float {
        let normalized = min(max(x, 0), 1) * 2 - 1
        return Float(normalized * maximumPan(for: profile))
    }

    /// How far toward a hard edge the pan may travel, per route.
    ///
    /// A nil profile means the session has not been classified yet, which takes
    /// the personal-audio value so the opening cues of a match are not narrow.
    nonisolated static func maximumPan(for profile: OutputProfile?) -> Double {
        profile == .builtInSpeaker ? 0.7 : 1.0
    }

    /// Renders the paddle-slide loop: a continuous, seamless friction texture.
    ///
    /// Three things matter here, all of them audible now that the sound is no
    /// longer smeared by the spatialiser.
    ///
    /// **It must loop seamlessly.** The previous version faded to silence at
    /// both ends of the buffer, which with `.loops` meant a dip to nothing
    /// every two seconds — heard as a stutter in a sound that should be
    /// unbroken. Instead the tail is crossfaded back over the head, so the
    /// join is continuous and no fade is needed.
    ///
    /// **The noise must be shaped, not raw.** A single one-pole low-pass over
    /// white noise is essentially hiss. Two cascaded poles plus a gentle
    /// high-pass give a band-limited rumble that reads as a surface rather
    /// than static.
    ///
    /// **The grain must not be periodic.** Any fixed-frequency component
    /// repeats at an audible rate and turns into a buzz, so the texture comes
    /// from slow random modulation of the noise level instead of oscillators.
    private func renderMalletSlideLoop() -> AVAudioPCMBuffer {
        let sampleRate = sourceFormat.sampleRate
        let duration = 2.0
        // Rendered long, then the tail is folded back over the head, so the
        // usable loop is shorter than what is synthesised.
        let crossfade = 0.25
        let crossfadeFrames = Int(crossfade * sampleRate)
        let loopFrames = Int(duration * sampleRate)
        let renderFrames = loopFrames + crossfadeFrames

        var scratch = [Double](repeating: 0, count: renderFrames)
        var low1 = 0.0
        var low2 = 0.0
        var highState = 0.0
        var envelope = 0.5
        var envelopeTarget = 0.5

        func lowPass(_ value: Double, cutoff: Double, state: inout Double) -> Double {
            let alpha = 1 - exp(-2 * Double.pi * cutoff / sampleRate)
            state += alpha * (value - state)
            return state
        }

        for frame in 0..<renderFrames {
            // Slow, irregular level drift: this is what makes it read as a
            // paddle dragging over a surface rather than flat noise.
            if frame % Int(sampleRate * 0.03) == 0 {
                envelopeTarget = Double.random(in: 0.55...1.0)
            }
            envelope += (envelopeTarget - envelope) * 0.0025

            let noise = Double.random(in: -1...1)
            // Two cascaded poles: a steeper skirt than one, so the result is a
            // rounded rumble instead of hiss.
            let body = lowPass(lowPass(noise, cutoff: 1_150, state: &low1), cutoff: 780, state: &low2)
            // Remove the sub-rumble that would otherwise sound like handling
            // noise rather than friction.
            highState += (body - highState) * (1 - exp(-2 * Double.pi * 90 / sampleRate))
            let friction = body - highState
            scratch[frame] = friction * envelope
        }

        // Fold the tail back over the head so the loop point is seamless.
        for frame in 0..<crossfadeFrames {
            let fade = Double(frame) / Double(crossfadeFrames)
            scratch[frame] = scratch[frame] * fade + scratch[loopFrames + frame] * (1 - fade)
        }

        let buffer = AVAudioPCMBuffer(pcmFormat: sourceFormat, frameCapacity: AVAudioFrameCount(loopFrames))!
        buffer.frameLength = AVAudioFrameCount(loopFrames)
        let samples = buffer.floatChannelData![0]
        // Normalise so the caller's gain is the only thing setting the level.
        let peak = scratch[0..<loopFrames].reduce(0.0) { max($0, abs($1)) }
        let scale = peak > 0 ? 0.92 / peak : 0
        for frame in 0..<loopFrames {
            samples[frame] = Float(scratch[frame] * scale)
        }
        return buffer
    }

    private func primeSmoothPuckQueue(generation: Int) {
        guard generation == smoothPuckGeneration, smoothPuckStyle >= 0 else { return }
        while smoothPuckDryQueuedBuffers < 2 {
            let monoBuffer = renderSmoothPuckBuffer(
                style: smoothPuckStyle,
                speed: smoothPuckRenderSpeed,
                pitchMultiplier: smoothPuckPitchMultiplier,
                rattleEnergy: smoothPuckRattleEnergy,
                state: &smoothPuckRenderState,
                previewEnvelope: false
            )
            smoothPuckDryQueuedBuffers += 1
            let split = panned(monoBuffer, pan: Self.stereoPan(for: smoothPuckRenderX, profile: outputProfile))
            smoothPuckVoice.dryPlayer.scheduleBuffer(split) { [weak self] in
                Task { @MainActor [weak self] in
                    guard let self, generation == self.smoothPuckGeneration else { return }
                    self.smoothPuckDryQueuedBuffers = max(0, self.smoothPuckDryQueuedBuffers - 1)
                    self.primeSmoothPuckQueue(generation: generation)
                }
            }
        }
        while reverbStyle > 0, smoothPuckWetQueuedBuffers < 2 {
            let monoBuffer = renderSmoothPuckBuffer(
                style: smoothPuckStyle,
                speed: smoothPuckRenderSpeed,
                pitchMultiplier: smoothPuckPitchMultiplier,
                rattleEnergy: smoothPuckRattleEnergy,
                state: &smoothPuckWetRenderState,
                previewEnvelope: false
            )
            smoothPuckWetQueuedBuffers += 1
            let split = panned(monoBuffer, pan: Self.stereoPan(for: smoothPuckRenderX, profile: outputProfile))
            smoothPuckVoice.wetPlayer.scheduleBuffer(split) { [weak self] in
                Task { @MainActor [weak self] in
                    guard let self, generation == self.smoothPuckGeneration else { return }
                    self.smoothPuckWetQueuedBuffers = max(0, self.smoothPuckWetQueuedBuffers - 1)
                    self.primeSmoothPuckQueue(generation: generation)
                }
            }
        }
    }

    private func renderSmoothPuckBuffer(style: Int, speed: Double, pitchMultiplier: Double, rattleEnergy: Double, state: inout SmoothPuckRenderState, previewEnvelope: Bool) -> AVAudioPCMBuffer {
        let duration = previewEnvelope ? 0.65 : 0.08
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
            var envelope = amplitudeEnvelope(time: time, duration: tone.duration, attack: tone.attack, peak: tone.peak)
            if tone.tremoloRate > 0, tone.tremoloDepth > 0 {
                let tremolo = 1 - tone.tremoloDepth * (0.5 + 0.5 * sin(2 * Double.pi * tone.tremoloRate * time))
                envelope *= tremolo
            }
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
