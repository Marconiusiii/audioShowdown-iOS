import SwiftUI

struct EndingSoundTestView: View {
    let theme: GameTheme
    let audioEngine: GameAudioEngine

    @Environment(\.dismiss) private var dismiss
    @State private var status = "Choose an ending sound."

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    AppSectionHeading(title: "Ending Sound Test", theme: theme)
                    AppTextRow(
                        text: "Preview the real game ending sounds without playing a full match. These use the same audio engine as gameplay.",
                        theme: theme
                    )

                    AppButtonRow(title: "Play Win Fanfare", theme: theme, prominent: true) {
                        audioEngine.matchWon()
                        status = "Played win fanfare."
                    }
                    AppButtonRow(title: "Play Loss Fanfare", theme: theme) {
                        audioEngine.matchLost()
                        status = "Played loss fanfare."
                    }
                    AppButtonRow(title: "Play Goal For You", theme: theme) {
                        audioEngine.goal(playerScored: true)
                        status = "Played player goal sound."
                    }
                    AppButtonRow(title: "Play Goal For Computer", theme: theme) {
                        audioEngine.goal(playerScored: false)
                        status = "Played computer goal sound."
                    }
                    AppButtonRow(title: "Play Board Ball", theme: theme) {
                        audioEngine.boardBall()
                        status = "Played board ball sound."
                    }

                    AppTextRow(text: status, theme: theme)
                }
                .frame(maxWidth: .infinity)
            }
            .background(theme.background)
            .navigationTitle("Ending Sound Test")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
        }
        .background(theme.background.ignoresSafeArea())
    }
}
