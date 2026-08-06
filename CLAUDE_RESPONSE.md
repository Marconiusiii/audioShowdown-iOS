# Serve Rule Change — Two Serves Per Turn

## What Changed

### Game code

In `AudioShowdown/GameModel.swift` I added a named constant, `servesPerTurn`, set to two, with a comment noting it comes from competitive Power Showdown. `nextShowdownServe` now compares against that constant instead of the hard-coded five. That was the only logic change needed. Every other part of the game reads the serve rule through this one function, so service changes, the serve ordinal in the spoken announcement, and Board Ball service advancement all followed automatically.

Air Hockey Mode is untouched, as it should be. It alternates serves after every goal and never consulted the Showdown serve count.

### Tests

In `AudioShowdownTests/AudioShowdownTests.swift`:

- Renamed and rewrote the service-change test for the new boundary. It now confirms serve one advances to serve two with the same server, and serve two hands service to the opponent and resets the count.
- Added a round-trip test that walks a full service cycle for both players and confirms service comes back to the player with the count reset. It is written in terms of `servesPerTurn`, so it will keep testing the right thing if the rule ever changes again.
- Adjusted the serve announcement test, which was checking the phrase "your third serve." A third serve is unreachable now, so that assertion was testing a state the game can no longer enter. It checks the first serve wording instead, which still covers the ordinal-word conversion the test exists for.

### Copy

Updated in three places so nothing still claims five:

- `AudioShowdown/HowToPlayView.swift`, in the Showdown Rules section, and in the Serving section where the example now reads "your second serve" and explains that service changes after it.
- `README.md`
- `marketing/index.html`

I checked `appStore/GameCenterReleaseGuide.md`. Its mentions of serves are a generic manual test checklist, not a statement of the rule, so it needed no change.

## Test Results

Both serve tests pass, along with the rest of the unit suite.

Four tests failed in the full run. None are related to this change:

- Three UI tests failed because the simulator refused to launch the UI test runner process. These are launch-denial errors from the simulator, not assertion failures. This is environment flakiness.
- `puckPingsAccelerateTowardPlayer` fails, and it is a genuine pre-existing failure unrelated to serves. I verified this by stashing my changes and running the unit suite on clean `main`, where it fails identically.

## About That Pre-Existing Failure

The test asserts that the pulse interval at speed two, full proximity, equals about 0.058. Reading `puckPulseInterval`, that call returns `nearIntervals[2]`, which is 0.092. The other assertion in the same test expects about 0.25 for the far end, and the code produces 0.092 plus 0.192, which is 0.284. So both magnitude assertions disagree with the current constants, while the two ordering assertions in that test still hold.

That pattern suggests the ping timing constants were retuned at some point and this test was not updated. The ordering behavior it was really guarding, pings getting faster as the puck approaches, still works correctly. I have not touched it, since it is outside this task. Say the word and I will either update the expected numbers to match the current tuning or dig into whether the constants themselves drifted from what you intended.

## Commit Message

Changed Showdown service to switch after two serves instead of five, matching competitive Power Showdown rules. The serve count now lives in a named constant on GameModel rather than a bare literal in the service-advance function, so the rule is stated in one place. Because service changes, the spoken serve ordinal, and Board Ball service advancement all route through that one function, no other game logic needed changing, and Air Hockey Mode is unaffected since it alternates serves after every goal. Updated the service-change test to the new boundary and added a round-trip test covering a full cycle back to the original server, written against the constant so it survives future rule changes. Also moved the serve announcement test off a third serve, which the game can no longer reach. Instructions, README, and the marketing page were updated to say two serves.
