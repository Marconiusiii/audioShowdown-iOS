import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: GameSettings
    let audioEngine: GameAudioEngine
    @Environment(\.dismiss) private var dismiss
    @State private var previewHaptics = GameHapticsEngine()

    private let puckSounds = ["Woodblock", "Marimba", "Tick", "Sine beep", "Square beep", "Pluck", "Cowbell", "Clave", "Water drop", "Sonar ping", "Piano", "Chime", "Glass", "Tom", "Laser"]
    private let smoothPuckSounds = ["Low Synth", "Bright Hum", "Table Roll", "Showdown Ball", "Bearing Roll", "Gentle Jingle", "Warm Buzz"]
    private let pitchNames = ["Pitch off", "Subtle", "Strong"]
    private let pulseSpeeds = ["Slow", "Medium", "Fast"]
    private let puckSizes = ["Classic", "Big", "Gigantic"]
    private let movementSounds = ["Off", "Wood", "Rubber", "Iron", "Gold", "Stone", "Plastic"]
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
                                audioEngine.setPuckVolume(value)
                                previewCurrentPuckSound()
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
                                title: "Pitch Behavior",
                                choices: pitchNames,
                                selection: $settings.pitchBehavior,
                                theme: theme,
                                selectionChanged: { _ in previewPuckSound(settings.puckSound) }
                            )
                            AppToggleRow(title: "Lower Pitch When Closer", isOn: $settings.lowerPitchWhenCloser, theme: theme)
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
                            VStack(spacing: 0) {
                                Picker("Distance Behavior", selection: $settings.puckDistanceBehavior) {
                                    ForEach(PuckDistanceBehavior.allCases) { behavior in
                                        Text(behavior.rawValue).tag(behavior)
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
                            AppToggleRow(title: closerFeedbackTitle, isOn: $settings.closerIncreasesPuckFeedback, theme: theme)
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

                        AppSectionHeading(title: "Mallet Audio", theme: theme)
                        AppAdjustableSliderRow(
                            title: "Mallet Slide Volume",
                            valueText: "\(Int(settings.malletSlideVolume * 100)) percent",
                            value: $settings.malletSlideVolume,
                            range: 0...1,
                            step: 0.05,
                            theme: theme,
                            valueChanged: { value in
                                audioEngine.updateMalletSlide(style: settings.movementSound, x: 0.5, speed: 700, volume: value)
                            }
                        )
                        AppCategoricalSliderRow(
                            title: "Mallet Material",
                            choices: movementSounds,
                            selection: $settings.movementSound,
                            theme: theme,
                            selectionChanged: previewMovementSound
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
        .onAppear {
            audioEngine.warmUp(volume: settings.volume, reverbStyle: settings.reverbStyle, puckVolume: settings.puckVolume)
        }
    }

    private func previewPuckSound(_ index: Int) {
        audioEngine.puckPing(
            x: 0.5,
            distance: 0.4,
            style: index,
            pitchBehavior: settings.pitchBehavior,
            lowerWhenCloser: settings.lowerPitchWhenCloser
        )
    }

    private func previewSmoothPuckSound(_ index: Int) {
        audioEngine.previewSmoothPuck(
            style: index,
            x: 0.5,
            proximity: 0.75,
            speed: 900,
            volume: settings.puckVolume,
            distanceBehavior: settings.puckDistanceBehavior,
            closerIncreases: settings.closerIncreasesPuckFeedback
        )
    }

    private func previewCurrentPuckSound() {
        if settings.puckTrackingStyle == .pulse {
            previewPuckSound(settings.puckSound)
        } else {
            previewSmoothPuckSound(settings.smoothPuckSound)
        }
    }

    private func previewMovementSound(_ index: Int) {
        guard index > 0 else { return }
        audioEngine.updateMalletSlide(style: index, x: 0.5, speed: 700, volume: settings.malletSlideVolume)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) {
            audioEngine.stopMalletSlide()
        }
    }

    private func previewStrikeSound(_ index: Int) {
        audioEngine.strike(style: index, x: 0.5)
    }

    private func previewReverb(_ index: Int) {
        audioEngine.setReverb(index)
        previewCurrentPuckSound()
    }

    private var closerFeedbackTitle: String {
        settings.puckDistanceBehavior == .volume ? "Closer Means Louder" : "Closer Means Higher"
    }
}
