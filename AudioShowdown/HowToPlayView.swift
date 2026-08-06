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

                    section("Before You Start", rows: [
                        "Grab headphones and hold your device in portrait. Everything in this game happens in stereo, so headphones are not optional.",
                        "VoiceOver users: turn Direct Touch on for Audio Showdown in the rotor before you start a match. The table is a Direct Touch area, so your drags reach the paddle instead of being read as gestures.",
                        "Your goal is at the bottom of the table. The computer’s goal is at the top. You play the bottom half, the computer plays the top."
                    ])
                    section("Your First Point", rows: [
                        "1. The serve announcement tells you whose serve it is and what the score is.",
                        "2. On your serve, press a finger anywhere on your half to set the puck down there.",
                        "3. Keeping that finger down, swipe through the puck to send it up the table.",
                        "4. Follow the puck by ear as it travels up, and listen for the computer to knock it back.",
                        "5. As it comes back toward you it gets louder and the pulses quicken. Drag to slide your paddle into its path and send it back.",
                        "6. Get it past the computer’s paddle and into the top goal, and you score."
                    ])
                    section("Reading the Sound", rows: [
                        "Left and right tell you where the puck is across the table. Center it in your ears and it is heading down the middle.",
                        "Volume tells you how close it is to your goal. The louder it gets, the sooner you need to be in front of it.",
                        "The pulse rate quickens as the puck closes in on you, so a rising urgency means it is coming your way.",
                        "The center crossing sound marks the puck passing the halfway line. Hearing it means the puck has entered your half and the point is now yours to defend.",
                        "Whether pitch rises or falls with distance is yours to set in Settings. Pick the direction that matches how you hear it."
                    ])
                    section("Moving Your Paddle", rows: [
                        "Drag anywhere on your half of the table and the paddle follows your finger. Keep the finger down through the hit so the paddle stays where you expect it.",
                        "Swing through the puck rather than meeting it flat. The faster your finger is moving on contact, the harder the puck leaves.",
                        "Guard the bottom goal, then send the puck back up toward the computer’s goal at the top."
                    ])
                    section("Serving", rows: [
                        "On your serve, press your half of the table to place the puck, keep your finger down, then swipe up through it to serve.",
                        "On the computer’s serve, settle in and defend. The announcement counts your serves, so “your second serve” means service changes after this one."
                    ])
                    section("Showdown Rules", rows: [
                        "Goals are worth two points. First to eleven wins, and you need a two-point lead to take it.",
                        "Each player serves twice, then service changes.",
                        "Send the puck across the center line fast enough and it may catch the center board. That is a Board Ball: it does not happen on every hard shot, but when it does the other player takes a point and the next serve begins. Board Balls are Showdown only and both you and the computer can get them."
                    ])
                    section("Air Hockey Mode", rows: [
                        "Turn on Air Hockey Mode in Settings for a shorter, simpler match.",
                        "Goals are worth one point, serves alternate after every goal, and the first to seven wins outright with no two-point lead required. There are no Board Balls."
                    ])
                    section("Gestures", rows: [
                        "During a match, double-tap the table to pause. The pause screen sits outside Direct Touch, so your usual VoiceOver navigation works there for resuming, Settings, or End Game.",
                        "After a match, double-tap the table to play again, or triple-tap to return home.",
                        "In practice, double-tap the table to return home.",
                        "Leaving the app mid-match pauses the game for you. It is still waiting when you come back."
                    ])
                    section("Practice", rows: [
                        "Where the duck is the puck? is the place to learn the sounds before any of them cost you a point. Nothing is scored and nothing is chasing you.",
                        "Drag the puck around the table and listen to how position, distance, and the center line each change what you hear. Double-tap the table when you are done to return home."
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
