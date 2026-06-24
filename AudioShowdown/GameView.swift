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
        VStack(spacing: 0) {
            Text(training ? "Where the Fuck is the Puck?" : "Audio Showdown")
                .font(.headline)
                .foregroundStyle(theme.line)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, minHeight: 52)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(theme.table)
                .contentShape(Rectangle())
                .accessibilityAddTraits(.isHeader)

            if training {
                Button(action: returnHome) {
                    Text("Home")
                        .frame(maxWidth: .infinity, minHeight: 56)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(theme.accent)
                .background(theme.background)
                .accessibilityHint("Returns to the start screen")
            } else {
                HStack(spacing: 0) {
                    gameBarButton("Home") { showingHomeConfirmation = true }

                    Text("\(model.playerScore)–\(model.opponentScore)")
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(theme.line)
                        .frame(maxWidth: .infinity, minHeight: 56)
                        .background(theme.background)
                        .contentShape(Rectangle())
                        .accessibilityLabel("Score, \(model.scoreText)")

                    gameBarButton(model.isPaused ? "Resume" : "Pause") {
                        model.togglePause()
                    }
                    .disabled(model.isGameOver)
                }
            }

            if model.isPaused {
                AppButtonRow(title: "Settings", theme: theme, prominent: true) {
                    showingSettings = true
                }
            }

            GeometryReader { proxy in
                GameSurfaceView(model: model, theme: theme)
                    .aspectRatio(0.5, contentMode: .fit)
                    .frame(width: proxy.size.width, height: proxy.size.height, alignment: .bottom)
            }
        }
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

    private func gameBarButton(_ title: String, action: @escaping () -> Void) -> some View {
        let theme = GameTheme.all[settings.themeIndex]
        return Button(action: action) {
            Text(title)
                .font(.body.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, minHeight: 56)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(theme.accent)
        .background(theme.background)
        .contentShape(Rectangle())
    }
}
