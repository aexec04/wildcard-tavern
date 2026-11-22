## Run variety audit: Events, Tags and Blessings (Nov 22)
- Audited 7 Events (RunEvents), 3 skip Tags (Tags), 6 Blessings (RunModifiers). No engine changes needed.
- Reachable: every Event can be offered in a normal run (traveling_patron needs an owned Patron, the rest need 2 to 5 Tips). Blessings all draft after Begin Run. Tags are picked every skippable round.
- Soft locks: none. Every Event ends with a Decline that always succeeds; a refused option (not enough Tips, no Discard to trade) returns false and leaves the run unchanged. on_the_house falls back to Tips when seats are full. Every number in the Event, Tag and Blessing text matches the code (prices, +Hands, Sale Day 3 Tips, bossTargetPct 10, rerollExtra 1).
- Added test "Run variety audit": every option at 0, 1, 3 and 20 Tips, a price in the text works with exactly that many Tips, Tags with and without ctx, every Blessing applies and leaves a playable run, short lines with no banned word or em dash.
- Tests: 1384 passed, 0 failed. STATUS health line updated.
- Needs you: nothing.
