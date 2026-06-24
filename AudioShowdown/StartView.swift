import SwiftUI

struct StartView: View {
    @ObservedObject var settings: GameSettings
    let startGame: () -> Void
    let startTraining: () -> Void
    @State private var showingHowToPlay = false
    @State private var showingSettings = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    VStack(spacing: 6) {
                        Text("Audio Showdown")
                            .font(.largeTitle.bold())
                        Text("By Chancey Fleet and Marco Salsiccia")
                            .font(.headline)
                    }
                    .multilineTextAlignment(.center)
                    .accessibilityElement(children: .combine)
                    .accessibilityAddTraits(.isHeader)

                    VStack(spacing: 14) {
                        Button("Start Game", action: startGame)
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                        Button("How to Play") { showingHowToPlay = true }
                        Button("Settings") { showingSettings = true }
                        Button("Where the Fuck is the Puck?", action: startTraining)
                    }
                    .frame(maxWidth: .infinity)

                    Divider()
                    AboutAudioShowdownView()
                }
                .frame(maxWidth: 560)
                .padding()
            }
            .navigationBarHidden(true)
        }
        .sheet(isPresented: $showingHowToPlay) { HowToPlayView() }
        .sheet(isPresented: $showingSettings) { SettingsView(settings: settings) }
    }
}
