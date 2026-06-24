import SwiftUI

struct GameView: View {
    @ObservedObject var settings: GameSettings
    let training: Bool
    let returnHome: () -> Void
    @StateObject private var model: GameModel
    @State private var showingSettings = false

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

            if !training {
                Text("\(model.playerScore)–\(model.opponentScore)")
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(theme.line)
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .background(theme.background)
                    .contentShape(Rectangle())
                    .accessibilityLabel("Score, \(model.scoreText)")
            }

            if model.isPaused {
                VStack(spacing: 0) {
                    Text("Game Paused")
                        .font(.title2.weight(.black))
                        .foregroundStyle(theme.line)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, minHeight: 72)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                        .background(theme.table)
                        .contentShape(Rectangle())
                        .accessibilityAddTraits(.isHeader)

                    AppButtonRow(title: "End Game", theme: theme) {
                        returnHome()
                    }
                    AppButtonRow(title: "Resume Game", theme: theme, prominent: true) {
                        model.togglePause()
                    }
                    AppButtonRow(title: "Settings", theme: theme) {
                        showingSettings = true
                    }

                    AppTextRow(text: "\(model.scoreText).", theme: theme, alignment: .center)
                    Spacer(minLength: 0)
                }
                .background(theme.background)
            } else {
                GeometryReader { proxy in
                    GameSurfaceView(model: model, theme: theme)
                        .aspectRatio(0.5, contentMode: .fit)
                        .frame(width: proxy.size.width, height: proxy.size.height, alignment: .bottom)
                }
            }
        }
        .background(theme.background.ignoresSafeArea())
        .tint(theme.accent)
        .sheet(isPresented: $showingSettings) { SettingsView(settings: settings) }
        .onReceive(NotificationCenter.default.publisher(for: .trainingFinished)) { _ in returnHome() }
        .task {
            try? await Task.sleep(for: .milliseconds(450))
            model.announceInitialState()
        }
    }

}
