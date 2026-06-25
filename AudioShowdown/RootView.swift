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
                        syncAudioEngine()
                        destination = .game
                    },
                    startTraining: {
                        syncAudioEngine()
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
        .releaseAudioWarmUp(settings: settings, syncAudioEngine: syncAudioEngine)
    }

    private func syncAudioEngine() {
        audioEngine.warmUp(
            volume: settings.volume,
            reverbStyle: settings.reverbStyle,
            puckVolume: settings.puckVolume
        )
    }
}

private extension View {
    @ViewBuilder func releaseAudioWarmUp(settings: GameSettings, syncAudioEngine: @escaping () -> Void) -> some View {
        #if DEBUG
        self
        #else
        self
        .task {
            // Give VoiceOver's first launch announcement time to finish before activating and priming AVAudioEngine.
            // Debug builds skip automatic launch warm-up because Xcode-tethered launches can distort VoiceOver speech.
            try? await Task.sleep(for: .milliseconds(1_500))
            syncAudioEngine()
        }
        .onChange(of: settings.volume) { _, _ in syncAudioEngine() }
        .onChange(of: settings.reverbStyle) { _, _ in syncAudioEngine() }
        .onChange(of: settings.puckVolume) { _, _ in syncAudioEngine() }
        #endif
    }
}
