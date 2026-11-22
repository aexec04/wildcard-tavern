## Accessibility pass: suit readability and text contrast (2026-11-22)

Commit: see git log, subject "Accessibility: tutorial highlight pulse respects Calm, test card ink contrast on card paper".
Tests: 1382 passed, 0 failed (was 1381).

Findings
- Suits: every face draws the suit glyph (spade, heart, diamond, club), so suits differ by shape on every Card Set. The corner letter (S/H/D/C) and per-suit inks appear only with Settings > Colorblind Suits. Left as is.
- Contrast: button, plate, icon and HUD palette text already had tests (4.5:1). New test covers cardLook red and black ink against that set's card paper, for every set, plus red and black ink differing. All sets pass with no colour changes.
- Looping motion: audited 25 looping tweens (TweenInfo repeat -1) and every Heartbeat or RenderStepped connection in src/Client. All are gated by Calm, Reduce Motion or Reduce Flashing (ClientSettings.get("reduceShake") is true when any of the three is on, motionAllowed, TavernKit.still, or per-file calm helpers) except one.
- Fixed: the tutorial highlight pulse in TutorialWalkthrough looped even in Calm. It now stays still when any calm option is on.
- Not verified in Studio: the gating is by code reading, not a play test.

Needs the user: nothing.
