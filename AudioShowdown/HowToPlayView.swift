import SwiftUI

struct HowToPlayView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Meet the table") {
                    Text("Audio Showdown is played in portrait. Your half is the bottom half of the table, and your opponent is waiting at the top.")
                    Text("Wear headphones. The puck moves through the stereo field, grows louder as it gets closer, and pings faster when danger is headed your way.")
                }
                Section("Get moving") {
                    Text("On your serve, touch your half to place the puck. Keep your finger down and swipe through it to send it flying.")
                    Text("Drag anywhere on your half to move your mallet. Protect your goal and wallop the puck into your opponent’s.")
                }
                Section("Showdown rules") {
                    Text("Goals are worth two points. First to eleven wins, but you need a two-point lead. Each player gets five serves before service changes.")
                    Text("A monster hit can smack the center board. That’s a Board Ball: your opponent gets one point and the next serve begins.")
                }
                Section("Air Hockey Mode") {
                    Text("Turn on Air Hockey Mode in Settings for classic one-point goals and alternating serves. First to seven wins.")
                }
                Section("Stay in control") {
                    Text("Score, Pause, and Home sit above the table. VoiceOver can reach them without entering the playing area.")
                    Text("After the match, double-tap the table to play again, or choose Home to head back.")
                }
                Section("Where the Fuck is the Puck?") {
                    Text("Training mode lets you drag the puck anywhere and chase its sound without a score breathing down your neck. Double-tap the table when you’re done.")
                }
            }
            .navigationTitle("How to Play")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}
