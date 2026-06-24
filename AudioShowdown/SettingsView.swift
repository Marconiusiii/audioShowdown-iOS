import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: GameSettings
    @Environment(\.dismiss) private var dismiss
    @State private var previewAudio = GameAudioEngine()
    @State private var previewHaptics = GameHapticsEngine()

    private let puckSounds = ["Woodblock", "Marimba", "Tick", "Sine beep", "Square beep", "Pluck", "Cowbell", "Clave", "Water drop", "Sonar ping", "Piano", "Chime", "Glass", "Tom", "Laser"]
    private let pitchNames = ["Pitch off", "Subtle", "Strong"]
    private let pingNames = ["Approach pings faster", "Always pings fast", "Always pings medium", "Always pings slow"]
    private let puckSizes = ["Classic", "Big", "Gigantic"]
    private let movementSounds = ["Off", "Hum", "Tick", "Pad", "Wood", "Thud", "Brush", "Pluck", "Bell", "Square"]
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
                            .foregroundStyle(theme.line)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, minHeight: 72)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 8)
                            .background(theme.table)
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
                            valueChanged: { previewAudio.setVolume($0) }
                        )
                        AppCategoricalSliderRow(
                            title: "Reverb",
                            choices: reverbStyles,
                            selection: $settings.reverbStyle,
                            theme: theme,
                            selectionChanged: previewReverb
                        )

                        AppSectionHeading(title: "Puck Audio", theme: theme)
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
                            title: "Ping Rate",
                            choices: pingNames,
                            selection: $settings.pingRate,
                            theme: theme
                        )
                        AppToggleRow(title: "Center Crossing Sound", isOn: $settings.centerCrossingSound, theme: theme)
                        AppAdjustableSliderRow(
                            title: "Center Crossing Volume",
                            valueText: "\(Int(settings.centerCrossingVolume * 100)) percent",
                            value: $settings.centerCrossingVolume,
                            range: 0...1,
                            step: 0.05,
                            theme: theme,
                            valueChanged: { previewAudio.centerCrossing(volume: $0) }
                        )

                        AppSectionHeading(title: "Mallet Audio", theme: theme)
                        AppCategoricalSliderRow(
                            title: "Movement Sound",
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
            .toolbarBackground(theme.table, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
        .onAppear {
            previewAudio.prepare(volume: settings.volume)
            previewAudio.setReverb(settings.reverbStyle)
        }
    }

    private func previewPuckSound(_ index: Int) {
        previewAudio.puckPing(
            x: 0.5,
            distance: 0.4,
            style: index,
            pitchBehavior: settings.pitchBehavior,
            lowerWhenCloser: settings.lowerPitchWhenCloser
        )
    }

    private func previewMovementSound(_ index: Int) {
        guard index > 0 else { return }
        previewAudio.malletMovement(style: index, x: 0.5)
    }

    private func previewStrikeSound(_ index: Int) {
        previewAudio.strike(style: index, x: 0.5)
    }

    private func previewReverb(_ index: Int) {
        previewAudio.setReverb(index)
        previewPuckSound(settings.puckSound)
    }
}
