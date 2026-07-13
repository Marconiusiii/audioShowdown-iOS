import SwiftUI

struct HowToPlayView: View {
    let theme: GameTheme
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    Text("How to Play")
                        .font(.title2.weight(.black))
                        .foregroundStyle(theme.foreground)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, minHeight: 72)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                        .background(theme.surface)
                        .contentShape(Rectangle())
                        .accessibilityAddTraits(.isHeader)

                    AppTextRow(
                        text: "Welcome to Audio Showdown! Showdown is a blend of air hockey and ping pong played on a large wooden table. Players use paddles to whack the puck into their opponent’s goal. This game recreates that experience with touch gestures and audio, minus the painful part where the puck slams into your knuckles.",
                        theme: theme
                    )

                    section("Meet the Table", rows: [
                        "Audio Showdown is played in portrait with headphones. Your goal is at the bottom of the table, and the computer’s goal is at the top.",
                        "If you use VoiceOver, use the rotor to turn on Direct Touch for Audio Showdown. Once the match starts, the table becomes a Direct Touch play area. Touch and drag on the table itself to play."
                    ])
                    section("Follow the Puck", rows: [
                        "Listen for the puck moving left and right in your headphones. It gets louder as it comes closer to your goal, and danger cues speed up when the puck is coming your way.",
                        "Drag your finger on your half of the table to move your mallet. Protect your goal at the bottom, then smack the puck toward the computer’s goal at the top.",
                        "Quick taps and short swipes can hit the puck, but dragging keeps your mallet under your finger."
                    ])
                    section("Serving", rows: [
                        "When it is your serve, touch your half of the table to place the puck. Keep your finger down, then swipe through the puck to serve it.",
                        "When it is the computer’s serve, get ready to defend. The serve announcement tells you whose serve it is and what the score is."
                    ])
                    section("Showdown Rules", rows: [
                        "In the main game, goals are worth two points. First to eleven wins, but you need a two-point lead.",
                        "Each player gets five serves before service changes.",
                        "A very hard hit can strike the center board. That is a Board Ball. The other player gets one point, and the next serve begins."
                    ])
                    section("Air Hockey Mode", rows: [
                        "Turn on Air Hockey Mode in Settings for a simpler rule set: goals are worth one point, serves alternate after each goal, and first to seven wins."
                    ])
                    section("Pausing and Leaving", rows: [
                        "Double-tap the table to pause. The pause screen opens outside Direct Touch so you can use standard VoiceOver controls to resume, change settings, or end the game.",
                        "After the match, double-tap the table to play again or triple-tap to return home. To leave during a match, pause and choose End Game."
                    ])
                    section("Practice", rows: [
                        "Use Where the duck is the puck? to practice without scoring. Drag the puck around the table, listen to how it moves, and double-tap the table when you are done to return to the Home screen."
                    ])
                }
            }
            .background(theme.background.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(theme.accent)
                }
            }
            .toolbarBackground(theme.surface, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
    }

    @ViewBuilder private func section(_ title: String, rows: [String]) -> some View {
        AppSectionHeading(title: title, theme: theme)
        ForEach(rows, id: \.self) { row in
            AppTextRow(text: row, theme: theme)
        }
    }
}
