import SwiftUI

struct SettingsView: View {
    private enum PickerFocus: Hashable {
        case puckSize, pitchBehavior, pingRate, theme
    }

    @ObservedObject var settings: GameSettings
    @Environment(\.dismiss) private var dismiss
    @AccessibilityFocusState private var focusedPicker: PickerFocus?
    @State private var previewAudio = GameAudioEngine()
    @State private var previewHaptics = GameHapticsEngine()

    private let puckSounds = ["Woodblock", "Marimba", "Tick", "Sine beep", "Square beep", "Pluck", "Cowbell", "Clave", "Water drop", "Sonar ping", "Piano", "Chime", "Glass", "Tom", "Laser"]
    private let pitchNames = ["Pitch off", "Subtle", "Strong"]
    private let pingNames = ["Approach pings faster", "Always pings fast", "Always pings medium", "Always pings slow"]
    private let puckSizes = ["Classic", "Big", "Gigantic"]
    private let movementSounds = ["Off", "Hum", "Tick", "Pad", "Wood", "Thud", "Brush", "Pluck", "Bell", "Square"]
    private let strikeSounds = ["Thock", "Click", "Pop", "Knock", "Snare", "Wood", "Bonk", "Zap", "Boing", "Slap"]

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
                        AppMenuPickerRow(
                            title: "Puck Size",
                            valueText: puckSizes[settings.puckSize],
                            selection: refocusingBinding($settings.puckSize, focus: .puckSize),
                            theme: theme
                        ) {
                            indexedOptions(puckSizes)
                        }
                        .accessibilityFocused($focusedPicker, equals: .puckSize)

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
                                previewHaptics.play(.strike, level: level)
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

                        AppSectionHeading(title: "Puck Audio", theme: theme)
                        AppCategoricalSliderRow(
                            title: "Sound Style",
                            choices: puckSounds,
                            selection: $settings.puckSound,
                            theme: theme,
                            selectionChanged: previewPuckSound
                        )
                        AppMenuPickerRow(
                            title: "Pitch Behavior",
                            valueText: pitchNames[settings.pitchBehavior],
                            selection: refocusingBinding($settings.pitchBehavior, focus: .pitchBehavior),
                            theme: theme
                        ) {
                            indexedOptions(pitchNames)
                        }
                        .accessibilityFocused($focusedPicker, equals: .pitchBehavior)
                        AppToggleRow(title: "Lower Pitch When Closer", isOn: $settings.lowerPitchWhenCloser, theme: theme)
                        AppMenuPickerRow(
                            title: "Ping Rate",
                            valueText: pingNames[settings.pingRate],
                            selection: refocusingBinding($settings.pingRate, focus: .pingRate),
                            theme: theme
                        ) {
                            indexedOptions(pingNames)
                        }
                        .accessibilityFocused($focusedPicker, equals: .pingRate)
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
                        AppMenuPickerRow(
                            title: "Color Theme",
                            valueText: GameTheme.all[settings.themeIndex].name,
                            selection: refocusingBinding($settings.themeIndex, focus: .theme),
                            theme: theme
                        ) {
                            ForEach(Array(GameTheme.all.enumerated()), id: \.offset) { index, option in
                                Text(option.name).tag(index)
                            }
                        }
                        .accessibilityFocused($focusedPicker, equals: .theme)

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
        }
    }

    @ViewBuilder private func indexedOptions(_ values: [String]) -> some View {
        ForEach(Array(values.enumerated()), id: \.offset) { index, name in
            Text(name).tag(index)
        }
    }

    private func refocusingBinding<Value>(_ binding: Binding<Value>, focus: PickerFocus) -> Binding<Value> {
        Binding(
            get: { binding.wrappedValue },
            set: { newValue in
                binding.wrappedValue = newValue
                focusedPicker = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    focusedPicker = focus
                }
            }
        )
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
}
