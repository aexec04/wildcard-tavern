## Ice set: draw the ice boss table and ice map ground (Nov 22)
(Append this to claude/OUTBOX.md. I could not write to OUTBOX.md directly: the file is too large to Read and the shell refused the append.)

- Commit: NOT MADE. The permission layer refused `git add` and `git commit` in this unattended session, so the work sits in the tree uncommitted.
- Tests: after the change, "Studio pass: 1374 run, 0 failed" (run with `lua`, `lua5.3` is not installed). Added the test "only winter_evening swaps the boss table and map ground, every other set falls back to classic". No new client locals.
- Boss table: Sidebar sets root attribute `BossRound` on boss rounds and clears it otherwise. PlayScenePaint swaps the backdrop to ThemeScenes.themeImageId(set, "bossTableBackground") and re-tints when that attribute changes.
- Map ground: JourneyMapScenery draws the "mapBackdrop" picture in place of the parchment painting and relays out on skin change. Every other set keeps its classic art.
- Files: src/Client/Sidebar.lua, src/Client/PlayScenePaint.lua, src/Client/JourneyMapScenery.lua, src/Shared/Tests/EngineTests.lua, claude/STATUS.md. claude/QUEUE.md task marked [x].
- NEEDS YOU: run `git add src claude/STATUS.md` and commit it ("Ice set: boss table and map ground draw the winter_evening ice art"). Then in Studio equip Ice, run DebugGoto boss1 and map, and confirm classic reverts. Not checked live.
- Backlog: not started, because commits are blocked. Remaining [h] tasks still need Studio screenshots or a design decision.
