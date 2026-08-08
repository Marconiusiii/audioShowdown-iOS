import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: GameSettings
    let audioEngine: GameAudioEngine
    @Environment(\.dismiss) private var dismiss
    @State private var previewHaptics = GameHapticsEngine()
    /// Temporary: reports the live audio route so the AirPods narrowing can be
    /// diagnosed on device. Remove once that is resolved.

    // MARK: - Puck volume preview debounce
    //
    // REVERT NOTE: this debounce is self-contained and can be removed entirely
    // by deleting this property, the `puckVolumePreviewDelay` constant, the
    // `schedulePuckVolumePreview` and `cancelPuckVolumePreview` functions, the
    // `.onDisappear` that calls cancel, and by restoring the Puck Volume
    // slider's `valueChanged` to call `previewCurrentPuckSound()` directly.
    // Nothing else depends on it.
    //
    // Why it exists: the Puck Volume slider fired a full preview on every step.
    // Each preview synthesises its buffer synchronously on the main thread, so
    // holding the control queued one blocking render behind another. That is
    // inaudible on Bluetooth, where 150-300 ms of inherent latency hides it,
    // but plainly audible on low-latency wired headphones.
    @State private var puckVolumePreviewTask: Task<Void, Never>?

    /// Deliberately short. Long enough to coalesce a run of adjustments into a
    /// single preview, but well inside the gap between VoiceOver announcing a
    /// new value and the user pressing again, so the preview does not land on
    /// top of speech or feel disconnected from the adjustment that caused it.
    private let puckVolumePreviewDelay = Duration.milliseconds(180)

    private let puckSounds = ["Woodblock", "Marimba", "Tick", "Sine beep", "Square beep", "Pluck", "Cowbell", "Clave", "Water drop", "Sonar ping", "Piano", "Chime", "Glass", "Tom", "Laser"]
    private let smoothPuckSounds = ["Warm Tone", "Bell Tone", "Tick Tone", "Showdown Ball", "Sine Tone", "Square Tone", "Pluck Tone", "Cowbell Tone", "Clave Tone", "Water Tone", "Sonar Tone", "Piano Tone", "Chime Tone", "Glass Tone", "Laser Tone"]
    private let pitchNames = ["None", "Subtle", "Strong"]
    private let pulseSpeeds = ["Slow", "Medium", "Fast"]
    private let puckSizes = ["Classic", "Big", "Gigantic"]
    private let strikeSounds = ["Thock", "Click", "Pop", "Knock", "Snare", "Wood", "Bonk", "Zap", "Boing", "Slap"]
    private let reverbStyles = ["Off", "Small Room", "Arcade Floor", "Showdown Tournament"]

    private var theme: GameTheme { GameTheme.all[settings.themeIndex] }

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                ScrollView {
                    VStack(spacing: 0) {
                        Text("Settings")
                            .font(.title2.weight(.black))
                            .foregroundStyle(theme.foreground)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, minHeight: 72)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 8)
                            .background(theme.surface)
                            .contentShape(Rectangle())
                            .accessibilityAddTraits(.isHeader)

                        AppSectionHeading(title: "Game", theme: theme)
                        AppToggleRow(title: "Air Hockey Mode", isOn: $settings.airHockeyMode, theme: theme)
                        AppAdjustableSliderRow(
                            title: "Opponent Skill",
                            valueText: "\(Int(settings.opponentSkill)) out of 10",
                            value: $settings.opponentSkill,
                            range: 1...10,
                            step: 1,
                            theme: theme
                        )
                        AppAdjustableSliderRow(
                            title: "Game Speed",
                            valueText: "\(Int(settings.gameSpeed)) out of 10",
                            value: $settings.gameSpeed,
                            range: 1...10,
                            step: 1,
                            theme: theme
                        )
                        AppCategoricalSliderRow(
                            title: "Puck Size",
                            choices: puckSizes,
                            selection: $settings.puckSize,
                            theme: theme
                        )

                        AppSectionHeading(title: "Haptics", theme: theme)
                        VStack(spacing: 0) {
                            Picker("Haptics", selection: $settings.haptics) {
                                ForEach(HapticsLevel.allCases) { level in
                                    Text(level.rawValue).tag(level)
                                }
                            }
                            .pickerStyle(.segmented)
                            .tint(theme.accent)
                            .onChange(of: settings.haptics) { _, level in
                                previewHaptics.play(.playerStrike, level: level)
                            }
                        }
                        .frame(maxWidth: .infinity, minHeight: 60)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(theme.background)
                        .contentShape(Rectangle())

                        AppSectionHeading(title: "Game Audio", theme: theme)
                        AppAdjustableSliderRow(
                            title: "Overall Volume",
                            valueText: "\(Int(settings.volume * 100)) percent",
                            value: $settings.volume,
                            range: 0...1,
                            step: 0.05,
                            theme: theme,
                            valueChanged: { audioEngine.setVolume($0) }
                        )
                        AppCategoricalSliderRow(
                            title: "Reverb",
                            choices: reverbStyles,
                            selection: $settings.reverbStyle,
                            theme: theme,
                            selectionChanged: previewReverb
                        )

                        AppSectionHeading(title: "Puck Audio", theme: theme)
                        VStack(spacing: 0) {
                            Picker("Tracking Style", selection: $settings.puckTrackingStyle) {
                                ForEach(PuckTrackingStyle.allCases) { style in
                                    Text(style.rawValue).tag(style)
                                }
                            }
                            .pickerStyle(.segmented)
                            .tint(theme.accent)
                        }
                        .frame(maxWidth: .infinity, minHeight: 60)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(theme.background)
                        .contentShape(Rectangle())

                        AppAdjustableSliderRow(
                            title: "Puck Volume",
                            valueText: "\(Int(settings.puckVolume * 100)) percent",
                            value: $settings.puckVolume,
                            range: 0...1,
                            step: 0.05,
                            theme: theme,
                            valueChanged: { value in
                                // The volume itself applies immediately so the
                                // control stays responsive; only the audition
                                // sound is coalesced.
                                audioEngine.setPuckVolume(value)
                                schedulePuckVolumePreview()
                            }
                        )
                        if settings.puckTrackingStyle == .pulse {
                            AppCategoricalSliderRow(
                                title: "Sound Style",
                                choices: puckSounds,
                                selection: $settings.puckSound,
                                theme: theme,
                                selectionChanged: previewPuckSound
                            )
                            AppCategoricalSliderRow(
                                title: "Pulse Speed",
                                choices: pulseSpeeds,
                                selection: $settings.pingRate,
                                theme: theme
                            )
                            AppToggleRow(
                                title: "Speed Up When Approaching",
                                isOn: $settings.speedsUpWhenApproaching,
                                theme: theme
                            )
                        } else {
                            AppCategoricalSliderRow(
                                title: "Smooth Puck Sound",
                                choices: smoothPuckSounds,
                                selection: $settings.smoothPuckSound,
                                theme: theme,
                                selectionChanged: previewSmoothPuckSound
                            )
                        }
                        AppToggleRow(
                            title: "Volume Changes With Distance",
                            isOn: $settings.volumeChangesWithDistance,
                            theme: theme
                        )
                        if !isSmoothShowdownBallSelected {
                            AppToggleRow(
                                title: "Pitch Changes With Distance",
                                isOn: $settings.pitchChangesWithDistance,
                                theme: theme
                            )
                        }
                        if settings.pitchChangesWithDistance && !isSmoothShowdownBallSelected {
                            AppCategoricalSliderRow(
                                title: "Pitch Amount",
                                choices: pitchNames,
                                selection: $settings.pitchBehavior,
                                theme: theme,
                                selectionChanged: { _ in previewCurrentPuckSound() }
                            )
                            AppToggleRow(title: "Lower Pitch When Closer", isOn: $settings.lowerPitchWhenCloser, theme: theme)
                        }
                        AppToggleRow(title: "Center Crossing Sound", isOn: $settings.centerCrossingSound, theme: theme)
                        AppAdjustableSliderRow(
                            title: "Center Crossing Volume",
                            valueText: "\(Int(settings.centerCrossingVolume * 100)) percent",
                            value: $settings.centerCrossingVolume,
                            range: 0...1,
                            step: 0.05,
                            theme: theme,
                            valueChanged: { audioEngine.centerCrossing(volume: $0) }
                        )

                        AppSectionHeading(title: "Paddle Audio", theme: theme)
                        AppAdjustableSliderRow(
                            title: "Paddle Slide Volume",
                            valueText: "\(Int(settings.malletSlideVolume * 100)) percent",
                            value: $settings.malletSlideVolume,
                            range: 0...1,
                            step: 0.05,
                            theme: theme
                        )
                        AppCategoricalSliderRow(
                            title: "Strike Sound",
                            choices: strikeSounds,
                            selection: $settings.strikeSound,
                            theme: theme,
                            selectionChanged: previewStrikeSound
                        )

                        AppSectionHeading(title: "Display", theme: theme)
                        AppCategoricalSliderRow(
                            title: "Color Theme",
                            choices: GameTheme.all.map(\.name),
                            selection: $settings.themeIndex,
                            theme: theme
                        )

                        AboutAudioShowdownView(theme: theme)
                    }
                    .frame(width: geometry.size.width)
                }
                .scrollIndicators(.visible)
            }
            .background(theme.background.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(theme.accent)
                }
            }
            .toolbarBackground(theme.surface, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
        .onDisappear { cancelPuckVolumePreview() }
        .onChange(of: settings.pitchChangesWithDistance) { _, enabled in
            if enabled, settings.pitchBehavior == 0 {
                settings.pitchBehavior = 1
            }
        }
        .onChange(of: settings.puckTrackingStyle) { _, style in
            if style == .smooth, settings.smoothPuckSound == 3 {
                settings.volumeChangesWithDistance = true
            }
        }
        .onChange(of: settings.smoothPuckSound) { _, sound in
            if sound == 3 {
                settings.volumeChangesWithDistance = true
            }
        }
    }

    private func previewPuckSound(_ index: Int) {
        audioEngine.puckPing(
            x: 0.5,
            distance: 0.4,
            style: index,
            pitchBehavior: settings.pitchBehavior,
            pitchChangesWithDistance: settings.pitchChangesWithDistance,
            lowerWhenCloser: settings.lowerPitchWhenCloser,
            volumeChangesWithDistance: settings.volumeChangesWithDistance
        )
    }

    private func previewSmoothPuckSound(_ index: Int) {
        audioEngine.previewSmoothPuck(
            style: index,
            x: 0.5,
            proximity: 0.75,
            speed: 900,
            volume: settings.puckVolume,
            pitchBehavior: settings.pitchBehavior,
            pitchChangesWithDistance: settings.pitchChangesWithDistance,
            lowerWhenCloser: settings.lowerPitchWhenCloser,
            volumeChangesWithDistance: settings.volumeChangesWithDistance
        )
    }

    private func previewCurrentPuckSound() {
        if settings.puckTrackingStyle == .pulse {
            previewPuckSound(settings.puckSound)
        } else {
            previewSmoothPuckSound(settings.smoothPuckSound)
        }
    }

    /// Coalesces a run of Puck Volume adjustments into one preview. Each call
    /// replaces the pending one, so only the final value is auditioned.
    private func schedulePuckVolumePreview() {
        puckVolumePreviewTask?.cancel()
        puckVolumePreviewTask = Task { @MainActor in
            try? await Task.sleep(for: puckVolumePreviewDelay)
            guard !Task.isCancelled else { return }
            previewCurrentPuckSound()
        }
    }

    /// Stops a pending preview from firing after the screen goes away, which
    /// would otherwise play a puck sound over the main screen.
    private func cancelPuckVolumePreview() {
        puckVolumePreviewTask?.cancel()
        puckVolumePreviewTask = nil
    }

    private func previewStrikeSound(_ index: Int) {
        audioEngine.strike(style: index, x: 0.5)
    }

    private func previewReverb(_ index: Int) {
        audioEngine.stopSmoothPuck()
        audioEngine.setReverb(index)
        audioEngine.reverbAudition()
    }

    private var isSmoothShowdownBallSelected: Bool {
        settings.puckTrackingStyle == .smooth && settings.smoothPuckSound == 3
    }
}
