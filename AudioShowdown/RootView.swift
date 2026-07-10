import SwiftUI

struct RootView: View {
    enum Destination { case home, game, training }
    @StateObject private var settings = GameSettings()
    @State private var audioEngine: GameAudioEngine?
    @State private var destination: Destination = .home

    var body: some View {
        Group {
            switch destination {
            case .home:
                StartView(
                    settings: settings,
                    audioEngine: ensureAudioEngine,
                    startGame: {
                        _ = ensureAudioEngine()
                        destination = .game
                    },
                    startTraining: {
                        _ = ensureAudioEngine()
                        destination = .training
                    }
                )
            case .game:
                if let audioEngine {
                    GameView(settings: settings, audioEngine: audioEngine, training: false) { destination = .home }
                } else {
                    StartView(settings: settings, audioEngine: ensureAudioEngine) {
                        _ = ensureAudioEngine()
                        destination = .game
                    } startTraining: {
                        _ = ensureAudioEngine()
                        destination = .training
                    }
                }
            case .training:
                if let audioEngine {
                    GameView(settings: settings, audioEngine: audioEngine, training: true) { destination = .home }
                } else {
                    StartView(settings: settings, audioEngine: ensureAudioEngine) {
                        _ = ensureAudioEngine()
                        destination = .game
                    } startTraining: {
                        _ = ensureAudioEngine()
                        destination = .training
                    }
                }
            }
        }
        .preferredColorScheme(GameTheme.all[settings.themeIndex].isLight ? .light : .dark)
    }

    private func ensureAudioEngine() -> GameAudioEngine {
        if let audioEngine { return audioEngine }
        let engine = GameAudioEngine()
        audioEngine = engine
        return engine
    }

}
