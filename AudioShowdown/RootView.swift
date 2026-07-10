import SwiftUI

struct RootView: View {
    enum Destination { case home, game, training }
    @StateObject private var settings = GameSettings()
    @State private var audioEngine = GameAudioEngine()
    @State private var destination: Destination = .home

    var body: some View {
        Group {
            switch destination {
            case .home:
                StartView(
                    settings: settings,
                    audioEngine: audioEngine,
                    startGame: {
                        destination = .game
                    },
                    startTraining: {
                        destination = .training
                    }
                )
            case .game:
                GameView(settings: settings, audioEngine: audioEngine, training: false) { destination = .home }
            case .training:
                GameView(settings: settings, audioEngine: audioEngine, training: true) { destination = .home }
            }
        }
        .preferredColorScheme(GameTheme.all[settings.themeIndex].isLight ? .light : .dark)
    }

}
