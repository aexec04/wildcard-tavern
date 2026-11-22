# Next slice for Fable (session 2): tester readiness first, then the last flat pieces

Read this whole file first. Then read claude/handoff-13.md and claude/STATUS.md. Read nothing else until a milestone needs it. Handoff 13 is the state of the world: milestones 1, 2, 3 and part of 5 from claude/NEXT-SLICE.md are done and committed.

## Rules for this session
- Do not audit the project, do not rerun the full test suite until the last milestone, and do not fix unrelated bugs. If you notice one, add one line to claude/QUEUE.md and keep going.
- One milestone at a time, in this order. After each: check it in Studio Play with a screenshot, run only the tests for the code you touched, commit locally (never push, never publish), then continue. If a milestone fails twice, stop it, note why, and go on to the next.
- Server-authoritative gameplay stays. Every click target keeps working. Touch devices keep the 2D table.
- No em dashes in anything you write. 12-hour times with am or pm. Never write the word "Balatro" in the game.
- Effort: medium. Use high only for milestones 3 and 5.
- Do not ask for approval on polish or art choices. Decide and do it.
- Studio is muted by the SoundService attribute StudioAudio = false (the user's choice, for now). Do not change it.
- At the end: write claude/handoff-14.md (changed, seen in Studio, not seen), update claude/STATUS.md, add any new lesson to the matching file in claude/skills/.

## How to drive Studio (unchanged from NEXT-SLICE.md, plus two new notes)
- Studio's viewport is about 1506 x 751 but screen_capture is 1920 wide. Never click from screenshot pixels. Read AbsolutePosition + AbsoluteSize / 2 with execute_luau (Client) and moveTo those numbers.
- GameUI.MenuRoot and GameUI.TutorialOverlay stay on top after Play starts. Hide them with execute_luau before screenshots and clicks, and again if a capture shows the menu. For the tutorial milestone, do not hide TutorialOverlay: that is the thing under test.
- Path to a round: Deal Me In, Begin Run, first Patron (button named Pick under ChoiceBackdrop), blessing (same), RoundPanel1.SelectButton, then the table.
- A capture can be a frame behind: wait 2 to 3 seconds after an action.
- If Studio restarts its studio_id changes: call list_roblox_studios again.
- Live-tune with execute_luau, then write winning values into the theme files. Live changes vanish when Play stops.
- Play sometimes closed by itself ("Target is closed"): just start it again.
- Do not raise global Lighting Brightness, ambient or exposure. Exposure -1.0 and Brightness 0.35 are right for the cards.

## Milestones

### 1. Tester readiness (this is the priority, mostly watching and fixing)
Play each with a screenshot and fix real problems only:
- The forced tutorial from the first click to the end, against the shifted Patron row, the new boards and the signs. Check every arrow and highlight lands on the thing it names. This is the first thing a tester sees.
- A Patron scoring during a reveal (the standing piece reacts, its value and name plaque stay readable).
- A full Boss Round, start to finish, including the Boss strip, the intro, win and lose.
- A Two Pair, a Flush and a lost round reveal.
- A shop reroll, and buying a second Patron.
- Calm mode and Fast animation speed (code paths exist, never seen).
- A short window and a 1280 x 720 window.
- "TARGET CLEARED!" still fading when the Counter opens.
- Played cards drawn smaller than hand cards.
- The open look notes in claude/STATUS.md (SpectateOverlay has no exit, boss name shown twice on the boss sidebar, uneven plate fonts).
Done when each of these has been seen working in Play, or has a fix, or a one-line entry in claude/QUEUE.md saying why it was left.

### 2. Small look fixes from handoff 13
- Table candle flames are faint: make them read.
- Post tops show between the lower edges of the hand cards: hide or lower them.
- The fireplace stone reads as rough block masonry: try the smaller alternates TavernStone1 to TavernStone3 in MaterialService.AssistantMaterials and keep the best.

### 3. The left board as a small standing board built for the purpose
The first attempt (backing the 751 px panel) put a board at the camera and covered a third of the table, so it was taken out. Do it properly: rebuild the rows (Night and Round, target bar and reward, the round rule, Hands, Discards, the five Patron rings, Tips, the Patron summary) on a small standing board, sized for the table, with the same live updates. Keep every value updating and every hover and click working. Keep a flat fallback behind the existing switch for touch.

### 4. The reveal readout on a board
Put the Chips x Mult pill and the hand name (ScorePopup.ReadoutPill and HandPill) on a board standing where the played lane ends, with the number animation intact.

### 5. Look tuning, then the camera (only if usage remains)
Take a "before" screenshot first. Tune color grading, bloom threshold and size, depth of field focus on the back wall, haze, and each local light. Then, only if the table is stable, try lowering the camera pitch to about 14 to 18 degrees and closer; recheck hand lift, laneTop, Patron boards, the new boards and score ghosts at 1506 x 751 and a short window. If it is worse, revert it.

### 6. Final check
Run the full test suite once. Fix real failures only. Write handoff-14.

## Cut order if usage runs short
1, 2, 3, 4, then 5. Never skip 1.

## User-only steps (do not try these)
- Save the place in Studio (Cmd+S): the MaterialVariants, generated meshes and the StudioAudio mute live in the place file.
- Set Lighting.LightingStyle to Realistic (and try Technology = Future).
- Push local commits to GitHub. Publish to Roblox. Check that the generated mesh and texture assets are usable by the published experience before publishing.
- A real phone test (3D is off on touch by design, so phones show the painted 2D table).
- Creator Hub page items: thumbnail, icon, title, gameplay video, Game Passes, Developer Products, Badges and their ids, audio ids.
- Studio API services access, so progress saves in Play.

## Done when
The tutorial, a Patron scoring, a full Boss Round, the reveals, the Counter, Calm mode, Fast speed and a short window have each been seen working in Play. The left board and the reveal readout stand on the table, or are noted as not done with the reason. The full test suite passes. Local commits exist, nothing is published, and handoff-14 says exactly what was and was not seen.
