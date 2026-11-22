## Endless and late Night scaling (Nov 22)
Commit: 319e8e3 Endless scaling: ScoreText formats huge scores and targets safely, round score capped, tests push extremes through the real functions
Tests: 1391 passed, 0 failed (local and Studio-style pass). Client locals still 127 of 127.

Findings
- Targets were already finite: RunState.targetForRound clamps at EndlessRules.TARGET_CAP (9e15). Checked Nights up to 5000 through targetScoreFor: no inf, NaN or negative.
- Round score was not capped. A huge hand could push it to inf or past the integer range, and string.format("%d") on that errors. Now capped at 9e15 in RunState.playHand.
- Displays used raw "%d" (Gameplay2 numeral, progress line, Target, "Score N to clear", Run Over final score). VictoryLook.commas and LedgerPages.fmt had separate formatters with no short form.
- Run end: Endless has no win cap. Targets stop growing at 9e15 and the run ends only by losing a round. So there is no cap ending to error out of. A hard "Endless complete" win screen at some Night would be a design call.

Fix
- New Engine/ScoreText.lua: full (commas), short (1.2M, 3.5T, commas below 10K), plate (commas to 999,999,999, then short). Safe on nil, NaN, inf, negatives.
- Wired into Gameplay2 (numeral, "X of Y", Target, goal line), GameOver final score, VictoryLook.commas, LedgerPages.fmt. Scores 1,000 to 9,999 now show a comma.
- One new test pushes extremes through the real functions. Three tests that pinned the old "%d" source strings were updated.

Needs you
- Not checked in Studio: that the numeral fits the Score plate at 1B+ values. Short forms are 7 characters at most and fitSize already shrinks by length.

Queue state: no [ ] tasks left. The remaining [h] tasks all need you (Tavern Map screenshots, Card Sets screen layout, Card Set themes Studio check, Flair and cosmetics audit with image spend, First five minutes design call).
