import SwiftUI

struct GameView: View {
    @ObservedObject var settings: GameSettings
    let training: Bool
    let returnHome: () -> Void
    @StateObject private var model: GameModel
    @State private var showingSettings = false
    @State private var showingHomeConfirmation = false

    init(settings: GameSettings, training: Bool, returnHome: @escaping () -> Void) {
        self.settings = settings
        self.training = training
        self.returnHome = returnHome
        _model = StateObject(wrappedValue: GameModel(settings: settings, training: training))
    }

    var body: some View {
        let theme = GameTheme.all[settings.themeIndex]
        VStack(spacing: 8) {
            Text(training ? "Where the Fuck is the Puck?" : "Audio Showdown")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)

            HStack {
                Button("Home") {
                    if training { returnHome() } else { showingHomeConfirmation = true }
                }
                    .accessibilityHint(training ? "Returns to the start screen" : "Ends this game and returns to the start screen")
                Spacer()
                Text(model.scoreText)
                    .font(.headline.monospacedDigit())
                    .accessibilityLabel("Score, \(model.scoreText)")
                Spacer()
                if !training {
                    Button(model.isPaused ? "Resume" : "Pause") { model.togglePause() }
                        .disabled(model.isGameOver)
                }
            }
            .padding(.horizontal)

            if model.isPaused {
                Button("Settings") { showingSettings = true }
                    .buttonStyle(.borderedProminent)
            }

            GeometryReader { proxy in
                GameSurfaceView(model: model, theme: theme)
                    .aspectRatio(0.5, contentMode: .fit)
                    .frame(width: proxy.size.width, height: proxy.size.height, alignment: .bottom)
            }
            .padding(.horizontal, 6)
        }
        .padding(.top, 4)
        .background(theme.background.ignoresSafeArea())
        .tint(theme.accent)
        .sheet(isPresented: $showingSettings) { SettingsView(settings: settings) }
        .confirmationDialog("End this game?", isPresented: $showingHomeConfirmation) {
            Button("End Game and Return Home", role: .destructive, action: returnHome)
            Button("Keep Playing", role: .cancel) {}
        }
        .onReceive(NotificationCenter.default.publisher(for: .trainingFinished)) { _ in returnHome() }
        .task {
            try? await Task.sleep(for: .milliseconds(450))
            model.announceInitialState()
        }
    }
}
