# Earpiece Audio Regression — Found and Fixed

Found it. This is a real bug with three interacting causes, and it explains
every symptom you described, including the strange ones.

## Root cause

The audio session was being configured with `.measurement` mode whenever the
game thought headphones were attached.

iOS treats `.measurement` as a **call-like mode**. Combined with the `.playback`
category, it selects the built-in *receiver* — the earpiece you hold to your ear
— instead of the speaker. That is exactly the behaviour you heard: game audio
relegated to the earpiece and nearly silent.

The reason VoiceOver still worked through the speaker is that VoiceOver owns its
own audio session, entirely separate from the game's. So the system voice stayed
correct while the game was stranded on the earpiece. Same for the pause screen,
which is why pausing appeared to fix things.

## Why it stayed broken

Two further problems kept it stuck there:

**The route was misclassified.** `currentOutputProfile()` returned "headphones"
whenever the route list was empty or held an unfamiliar port. The route *is*
empty in the moments before the session activates — so on a phone with nothing
plugged in, the game picked headphone mode at startup and set `.measurement`.
That is why starting a round without headphones failed immediately.

**Route changes never re-applied the session.** `refreshOutputProfile` updated
spatial rendering when the route changed, but never re-ran the session
configuration. So the `.measurement` mode chosen at launch persisted for the
entire app lifetime. That is why pulling out AirPods dropped you back to a
silent earpiece — the route changed, but the session mode never followed.

The volume-button behaviour fits too: pressing volume nudges iOS into
re-evaluating the route, audio moves to the speaker briefly, then the stale
session configuration reasserts itself and it falls back to the earpiece.

## The fixes

All three, in `GameAudioEngine.swift`:

1. **`.measurement` is gone.** The session now uses `.default` for every route.
   This costs nothing audible — the spatial work is done by
   `AVAudioEnvironmentNode` (HRTF for headphones, equal-power panning for the
   speaker), not by the session mode. The mode was never buying the spatial
   quality it appeared to.

2. **An unknown or empty route now means speaker.** Only genuine personal-audio
   ports — wired headphones, Bluetooth A2DP/HFP/LE, AirPlay, USB, and car audio
   — select headphone rendering. The earpiece is explicitly classified as
   loudspeaker playback. USB and car audio are new; they were previously
   misfiled as speaker output.

3. **The route is reasserted on every change.** A new
   `routeAwayFromReceiverIfNeeded()` calls `overrideOutputAudioPort(.speaker)`
   whenever playback lands on the receiver, and it runs both at session setup
   and on every route change. It deliberately does nothing when headphones are
   attached, so it can never steal audio away from your AirPods.

Interruption recovery already re-runs the session setup, so it inherits all of
this automatically.

## Tests

There was **no test coverage at all** for output routing, which is how a
regression this severe shipped in 1.0.5.

`AudioShowdownTests/AudioRoutingTests.swift` now covers it — 10 tests, all
passing, including your two stated requirements directly:

- No route, built-in speaker, built-in receiver, and unknown ports all resolve
  to speaker rendering.
- Wired, Bluetooth, AirPlay, USB, and car audio all resolve to personal audio.
- Headphones win when the route momentarily lists both (AirPods connecting
  mid-match).
- Removing headphones returns to speaker rendering.
- And a direct guard that the session mode is **never** `.measurement`.

## What I could not verify

I confirmed this builds and that the routing logic is correct under test, but I
**cannot verify the actual audio output** — the Simulator does not reproduce
real device routing, and you have no device at hand. The logic error is
unambiguous and the fix is well-understood iOS behaviour, but the real
confirmation is you starting a round on a phone with no headphones and hearing
the puck through the speaker.

Worth testing on device, in this order:

1. Start a round with no headphones — puck, mallet, and all cues through the
   speaker.
2. Insert AirPods mid-match — audio should move to them.
3. Remove them mid-match — audio should return to the speaker, not the earpiece.
4. Take a phone call mid-match and hang up — audio should recover to the
   speaker.

## One unrelated thing

`AudioShowdownTests.puckPingsAccelerateTowardPlayer()` fails, but it fails
identically at clean HEAD (3c74ff4) — I checked against a fresh worktree, so it
predates my changes. It concerns pulse-interval timing math, nothing to do with
audio routing. Say the word and I will look at it separately.

## Screenshots

Set aside, as you asked. The staging system is complete and working — both
gameplay shots and all nine theme captures came out at correct App Store
dimensions for iPhone and iPad. The only piece left is the Settings capture,
which fails on a simulator launch quirk, and compositing the theme sampler.
