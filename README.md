# Audio Showdown

An accessible iPhone game of Showdown — a blend of air hockey and ping pong — played entirely by ear.

By Chancey Fleet and Marco Salsiccia.

Showdown is a real sport, played by blind and sighted players on a large wooden table with a raised rim and a center board. Players use paddles to whack a puck into their opponent's goal. Audio Showdown recreates that game on iPhone with spatial audio, touch, and haptics — minus the painful part where the puck slams into your knuckles.

## Played by ear, not by sight

Audio Showdown was built from the start to be played without looking at the screen. The puck moves left and right in your headphones. It gets louder as it comes closer to your goal, and danger cues speed up when it is heading your way. You track it, you meet it, and you send it back.

Every screen — menus, settings, matches, and the practice mode — works with VoiceOver.

## Features

- **Spatial puck tracking.** Hear where the puck is as it crosses the table, with volume and pitch that respond to distance and approach speed.
- **Direct Touch play.** Drag your finger on your half of the table to move your paddle. The paddle stays under your finger.
- **Two tracking styles.** Choose *Pulse* for a repeating ping whose rate rises as the puck closes in, or *Smooth* for a continuous tone that glides across the stereo field.
- **Deeply adjustable audio.** Fifteen pulse sounds, fifteen smooth tones, ten strike sounds, four reverb spaces, and independent volume for the puck, paddle slides, and center crossings.
- **Haptics.** Feel hits, walls, and goals through the iPhone's haptic engine, at subtle or intense strength, or off entirely.
- **Nine high-contrast color themes.** White on black, black on white, orange on black, orange on white, yellow on navy, blue on cream, teal on charcoal, plus Colorful and Cosmic.
- **Set your own challenge.** Adjust opponent skill, game speed, and puck size to find a match that suits you.
- **Practice mode.** *Where the duck is the puck?* lets you drag the puck around the table and learn its sound with nothing on the line.

## How a match works

1. Put on headphones and hold your iPhone in portrait. Your goal is at the bottom of the table; the computer's goal is at the top.
2. When it is your serve, touch your half of the table to place the puck. Keep your finger down, then swipe through the puck to serve it.
3. Listen for the puck moving left and right. Drag your paddle to meet it, then smack it back toward the computer's goal.
4. Double-tap the table at any time to pause. The pause screen opens outside Direct Touch, so standard VoiceOver controls work normally.

If you use VoiceOver, use the rotor to turn on Direct Touch for Audio Showdown. Once the match starts, the table becomes a Direct Touch play area.

## The rules

**Showdown.** Goals are worth two points. First to eleven wins, but you need a two-point lead. Each player gets five serves before service changes. A very hard hit can strike the center board — that is a Board Ball, the other player gets one point, and the next serve begins.

**Air Hockey Mode.** A simpler rule set you can switch on in Settings: goals are worth one point, serves alternate after each goal, and first to seven wins.

## Accessibility

Accessibility is not a feature list here; it is the design.

- Fully playable without vision, using audio and touch alone.
- Complete VoiceOver support across every screen, with a Direct Touch play area during matches.
- Native SwiftUI controls throughout, so VoiceOver behaves the way players already expect.
- Nine high-contrast color themes for players with low vision.
- Adjustable haptics, including an option to turn them off.
- Independent volume controls for the puck, paddle slides, strikes, and center crossings.
- Spoken announcements for serves and scores.

## Requirements

- iPhone or iPad running iOS 17.6 or later
- Headphones strongly recommended — the game depends on stereo positioning
- Xcode 15 or later to build from source

## Building from source

Clone the repository, open `AudioShowdown.xcodeproj` in Xcode, select your device or simulator, and run. There are no third-party dependencies; the game is built entirely on SwiftUI, AVFoundation, and Core Haptics. All game sounds are synthesized at runtime by `GameAudioEngine`, so there are no audio assets to fetch.

Haptics require a physical device — the simulator will run the game but will not vibrate.

## Project layout

| File | What it does |
| --- | --- |
| `AudioShowdownApp.swift` | App entry point |
| `RootView.swift` | Switches between the home screen and an active match |
| `StartView.swift` | Home screen and its menu |
| `GameView.swift`, `GameSurfaceView.swift` | The playfield and its touch handling |
| `GameModel.swift` | Match state, physics, scoring, and the computer opponent |
| `GameAudioEngine.swift` | Runtime sound synthesis, spatialization, and audio session handling |
| `GameHapticsEngine.swift` | Core Haptics patterns for hits, walls, and goals |
| `GameSettings.swift` | Player preferences, persisted to `UserDefaults` |
| `SettingsView.swift`, `HowToPlayView.swift`, `AboutAudioShowdownView.swift` | Settings, instructions, and about |
| `AppControlRows.swift` | Shared accessible row components |
| `GameTheme.swift` | The nine color themes |

## Feedback

We would like to hear how the game plays for you. Email <marco@marconius.com> and tell us what is working and what is not. Bug reports and accessibility feedback are especially welcome — please open an issue or send mail.

## Privacy

Audio Showdown collects no data. Settings are stored on your device only. The full policy is at <https://marconius.com/asPrivacy/>.

## License

Released under the MIT License. See [LICENSE](LICENSE) for details.
