import SwiftUI

struct GameView: View {
    @ObservedObject var settings: GameSettings
    let audioEngine: GameAudioEngine
    let training: Bool
    let returnHome: () -> Void
    @StateObject private var session: GameSession
    @State private var showingSettings = false
    @AccessibilityFocusState private var pauseHeadingFocused: Bool

    init(settings: GameSettings, audioEngine: GameAudioEngine, training: Bool, returnHome: @escaping () -> Void) {
        self.settings = settings
        self.audioEngine = audioEngine
        self.training = training
        self.returnHome = returnHome
        _session = StateObject(wrappedValue: GameSession(settings: settings, training: training, audio: audioEngine))
    }

    var body: some View {
        let theme = GameTheme.all[settings.themeIndex]
        VStack(spacing: 0) {
            Text(training ? "Where the duck is the puck?" : "Audio Showdown")
                .font(.headline)
                .foregroundStyle(theme.foreground)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, minHeight: 52)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(theme.surface)
                .contentShape(Rectangle())
                .accessibilityAddTraits(.isHeader)

            if !training {
                Text("\(session.model.playerScore)–\(session.model.opponentScore)")
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(theme.foreground)
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .background(theme.background)
                    .contentShape(Rectangle())
                    .accessibilityLabel("Score, \(session.scoreText)")
            }

            GeometryReader { proxy in
                let bottomGestureClearance = max(proxy.safeAreaInsets.bottom + 18, 46)
                GameSurfaceView(session: session, theme: theme, bottomGestureClearance: bottomGestureClearance)
                    .frame(width: proxy.size.width, height: proxy.size.height, alignment: .bottom)
            }
        }
        .background(theme.background.ignoresSafeArea())
        .tint(theme.accent)
        .sheet(isPresented: $showingSettings) { SettingsView(settings: settings, audioEngine: audioEngine) }
        .fullScreenCover(isPresented: Binding(get: { session.isPaused }, set: { isPresented in
            if !isPresented, session.isPaused { session.togglePause() }
        })) {
            pauseModal(theme: theme)
        }
        .onReceive(NotificationCenter.default.publisher(for: .trainingFinished)) { _ in
            session.stopContinuousAudio()
            returnHome()
        }
        .onReceive(NotificationCenter.default.publisher(for: .gameOverReturnHome)) { _ in
            session.stopContinuousAudio()
            returnHome()
        }
        .onDisappear {
            session.stopContinuousAudio()
        }
        .task {
            try? await Task.sleep(for: .milliseconds(450))
            session.announceInitialState()
        }
    }

    private func pauseModal(theme: GameTheme) -> some View {
        VStack(spacing: 0) {
            Text("Game Paused")
                .font(.title2.weight(.black))
                .foregroundStyle(theme.foreground)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, minHeight: 72)
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                .background(theme.surface)
                .contentShape(Rectangle())
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused($pauseHeadingFocused)

            AppTextRow(text: "\(session.scoreText).", theme: theme, alignment: .center)

            AppButtonRow(title: "End Game", theme: theme) {
                returnHome()
            }
            AppButtonRow(title: "Resume Game", theme: theme, prominent: true) {
                session.togglePause()
            }
            AppButtonRow(title: "Settings", theme: theme) {
                showingSettings = true
            }

            Spacer(minLength: 0)
        }
        .background(theme.background.ignoresSafeArea())
        .tint(theme.accent)
        .task {
            try? await Task.sleep(for: .milliseconds(250))
            pauseHeadingFocused = true
        }
    }

}
