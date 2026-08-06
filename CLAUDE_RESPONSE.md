# The Ping Test Failure — Explained and Fixed

## Short Version

My earlier guess was wrong. I said the timing constants had probably been retuned and the test was left behind. The opposite happened. The constants are correct and the test expectations are the stale part, and they went stale because of a revert.

## What Actually Happened

You did a run of multiplayer-readiness refactors and then reverted all five of them. The relevant one is `fb2fe17`, which extracted gameplay rules into a dedicated `GameRules` type, and `554f7a1`, which reverted it.

Here is the sequence for this test:

1. Before the refactor, the test expected 0.25 and 0.058.
2. Commit `fb2fe17` extracted the rules into `GameRules`. As part of that work, the ping timing constants were retuned, and the test was correctly updated in the same commit to expect 0.284 and 0.092.
3. Commit `554f7a1` reverted that refactor. The revert pulled the test expectations back to the old 0.25 and 0.058, but the retuned constants stayed in `GameModel`.

So the revert was partial in effect. It undid the test's expectations but not the constant values they were measuring. That is why the test has been failing on `main` ever since, with no single commit that looks like it broke anything.

## Confirming the Numbers

`puckPulseInterval` at speed two currently uses a near interval of 0.092 and a far addition of 0.192. Working the formula by hand:

- At proximity 0, the puck is at the far end: 0.092 plus 0.192 gives 0.284.
- At proximity 1, the puck is at your goal: 0.092 with no addition.

Those are exactly the values the test expected after the refactor, and exactly what the revert stripped out. The current gameplay tuning is the intended one.

## The Fix

I restored the two expectations in `AudioShowdownTests/AudioShowdownTests.swift` to 0.284 and 0.092. That is the only change. I did not touch `GameModel`, because the constants there were never wrong.

Worth noting: the two ordering assertions in that test, that intervals shrink as the puck approaches, passed the entire time. The behavior the test exists to protect never regressed. Only the exact magnitude checks were out of date, which is why this went unnoticed.

## Test Results

The full unit suite passes, twenty-eight tests across `AudioShowdownTests` and `AudioRoutingTests`, including both new serve tests and the repaired ping test.

The three UI test failures from the earlier run are unrelated and still environmental. The simulator was denying launch of the UI test runner process, which is not an assertion failure and not something in the code.

## One Thing Worth Checking

Four other reverts landed in that same batch, covering a gameplay snapshot type, a passive event stream, a codable input model, and a multiplayer session boundary. If any of those also retuned a constant while updating its tests, the same partial-revert pattern could be sitting in the codebase unnoticed. Nothing is currently failing, so if it happened elsewhere it did not leave a broken test behind. I have not gone looking. Say the word if you want me to audit those four reverts for the same shape of problem.

## Commit Message

Repaired the puck ping interval test, which had been failing on main since the GameRules refactor was reverted. The refactor retuned the pulse timing constants and updated this test's expected values in the same commit, but the revert rolled back only the test expectations and left the retuned constants in place, so the test has been measuring current behavior against pre-refactor numbers ever since. The constants are correct, so this restores the expected values to 0.284 and 0.092 to match what puckPulseInterval actually produces at speed two. The ordering assertions in this test never failed, which is why the drift went unnoticed: the behavior under test was fine and only the magnitude checks were stale.
