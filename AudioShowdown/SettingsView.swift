import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: GameSettings
    @Environment(\.dismiss) private var dismiss
    private let puckSounds = ["Woodblock", "Marimba", "Tick", "Sine beep", "Square beep", "Pluck", "Cowbell", "Clave", "Water drop", "Sonar ping", "Piano", "Chime", "Glass", "Tom", "Laser"]
    private let pitchNames = ["Pitch off", "Subtle", "Strong"]
    private let pingNames = ["Approach pings faster", "Always pings fast", "Always pings medium", "Always pings slow"]
    private let puckSizes = ["Classic", "Big", "Gigantic"]
    private let movementSounds = ["Off", "Hum", "Tick", "Pad", "Wood", "Thud", "Brush", "Pluck", "Bell", "Square"]
    private let strikeSounds = ["Thock", "Click", "Pop", "Knock", "Snare", "Wood", "Bonk", "Zap", "Boing", "Slap"]

    var body: some View {
        NavigationStack {
            Form {
                Section("Game") {
                    Toggle("Air Hockey Mode", isOn: $settings.airHockeyMode)
                    settingSlider("Opponent skill", value: $settings.opponentSkill, range: 1...10)
                    settingSlider("Game speed", value: $settings.gameSpeed, range: 1...10)
                    Picker("Puck size", selection: $settings.puckSize) { indexedOptions(puckSizes) }
                    Picker("Haptics", selection: $settings.haptics) {
                        ForEach(HapticsLevel.allCases) { level in Text(level.rawValue).tag(level) }
                    }
                    .pickerStyle(.segmented)
                }
                Section("Puck audio") {
                    Picker("Sound style", selection: $settings.puckSound) { indexedOptions(puckSounds) }
                    Picker("Pitch behavior", selection: $settings.pitchBehavior) { indexedOptions(pitchNames) }
                    Toggle("Lower pitch when closer", isOn: $settings.lowerPitchWhenCloser)
                    Picker("Ping rate", selection: $settings.pingRate) { indexedOptions(pingNames) }
                    Toggle("Center crossing sound", isOn: $settings.centerCrossingSound)
                    settingSlider("Center crossing volume", value: $settings.centerCrossingVolume, range: 0...1, step: 0.05, percent: true)
                }
                Section("Mallet audio") {
                    Picker("Movement sound", selection: $settings.movementSound) { indexedOptions(movementSounds) }
                    Picker("Strike sound", selection: $settings.strikeSound) { indexedOptions(strikeSounds) }
                }
                Section("Display and audio") {
                    Picker("Color theme", selection: $settings.themeIndex) {
                        ForEach(Array(GameTheme.all.enumerated()), id: \.offset) { index, theme in Text(theme.name).tag(index) }
                    }
                    settingSlider("Volume", value: $settings.volume, range: 0...1, step: 0.05, percent: true)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }

    @ViewBuilder private func indexedOptions(_ values: [String]) -> some View {
        ForEach(Array(values.enumerated()), id: \.offset) { index, name in Text(name).tag(index) }
    }

    @ViewBuilder private func settingSlider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, step: Double = 1, percent: Bool = false) -> some View {
        VStack(alignment: .leading) {
            Text(title)
            Slider(value: value, in: range, step: step) {
                Text(title)
            } minimumValueLabel: {
                Text(percent ? "0%" : "\(Int(range.lowerBound))")
            } maximumValueLabel: {
                Text(percent ? "100%" : "\(Int(range.upperBound))")
            }
            .accessibilityValue(percent ? "\(Int(value.wrappedValue * 100)) percent" : "\(Int(value.wrappedValue)) out of \(Int(range.upperBound))")
        }
        .accessibilityElement(children: .contain)
    }
}
