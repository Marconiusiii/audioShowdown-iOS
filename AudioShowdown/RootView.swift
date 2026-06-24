import SwiftUI

struct RootView: View {
    enum Destination { case home, game, training }
    @StateObject private var settings = GameSettings()
    @State private var destination: Destination = .home

    var body: some View {
        Group {
            switch destination {
            case .home:
                StartView(
                    settings: settings,
                    startGame: { destination = .game },
                    startTraining: { destination = .training }
                )
            case .game:
                GameView(settings: settings, training: false) { destination = .home }
            case .training:
                GameView(settings: settings, training: true) { destination = .home }
            }
        }
        .preferredColorScheme(settings.themeIndex == 1 ? .light : .dark)
    }
}
