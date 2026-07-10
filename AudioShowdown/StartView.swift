import SwiftUI

struct StartView: View {
    @ObservedObject var settings: GameSettings
    let audioEngine: () -> GameAudioEngine
    let startGame: () -> Void
    let startTraining: () -> Void
    @State private var showingHowToPlay = false
    @State private var showingSettings = false
    @State private var settingsAudioEngine: GameAudioEngine?
    private var theme: GameTheme { GameTheme.all[settings.themeIndex] }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    VStack(spacing: 4) {
                        Text("Audio Showdown")
                            .font(.largeTitle.bold())
                        Text("By Chancey Fleet and Marco Salsiccia")
                            .font(.headline)
                    }
                    .foregroundStyle(theme.foreground)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, minHeight: 112)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(theme.surface)
                    .contentShape(Rectangle())
                    .accessibilityElement(children: .combine)
                    .accessibilityAddTraits(.isHeader)

                    AppButtonRow(title: "Start Game", theme: theme, prominent: true, action: startGame)
                    AppButtonRow(title: "How to Play", theme: theme) { showingHowToPlay = true }
                    AppButtonRow(title: "Settings", theme: theme) {
                        settingsAudioEngine = audioEngine()
                        showingSettings = true
                    }
                    AppButtonRow(title: "Where the duck is the puck?", theme: theme, action: startTraining)
                }
                .frame(maxWidth: .infinity)
            }
            .background(theme.background)
            .navigationBarHidden(true)
        }
        .background(theme.background.ignoresSafeArea())
        .sheet(isPresented: $showingHowToPlay) { HowToPlayView(theme: theme) }
        .sheet(isPresented: $showingSettings) {
            if let settingsAudioEngine {
                SettingsView(settings: settings, audioEngine: settingsAudioEngine)
            }
        }
    }
}
