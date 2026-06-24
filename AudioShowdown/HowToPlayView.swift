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
                        .foregroundStyle(theme.line)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, minHeight: 72)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                        .background(theme.table)
                        .contentShape(Rectangle())
                        .accessibilityAddTraits(.isHeader)

                    section("Meet the Table", rows: [
                        "Audio Showdown is played in portrait. Your half is the bottom half of the table, and your opponent is waiting at the top.",
                        "Wear headphones. The puck moves through the stereo field, grows louder as it gets closer, and pings faster when danger is headed your way."
                    ])
                    section("Get Moving", rows: [
                        "On your serve, touch your half to place the puck. Keep your finger down and swipe through it to send it flying.",
                        "Drag anywhere on your half to move your mallet. Protect your goal and wallop the puck into your opponent’s."
                    ])
                    section("Showdown Rules", rows: [
                        "Goals are worth two points. First to eleven wins, but you need a two-point lead. Each player gets five serves before service changes.",
                        "A monster hit can smack the center board. That’s a Board Ball: your opponent gets one point and the next serve begins."
                    ])
                    section("Air Hockey Mode", rows: [
                        "Turn on Air Hockey Mode in Settings for classic one-point goals and alternating serves. First to seven wins."
                    ])
                    section("Stay in Control", rows: [
                        "Double-tap the table to pause. The table steps aside so you can resume, change settings, or end the game with ordinary VoiceOver controls.",
                        "After the match, double-tap the table to play again. To leave a match, pause and choose End Game."
                    ])
                    section("Where the Fuck is the Puck?", rows: [
                        "Training mode lets you drag the puck anywhere and chase its sound without a score breathing down your neck. Double-tap the table when you’re done."
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
            .toolbarBackground(theme.table, for: .navigationBar)
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
