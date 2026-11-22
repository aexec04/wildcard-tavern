# Next slice for Fable: make the table look modern, finish the room, get the build tester-ready

Read this whole file first. It is the brief for this session. Also read claude/handoff-11.md and claude/handoff-12.md (the 3D table and the room) and claude/STATUS.md. Do not read anything else until a milestone needs it.

## Rules for this session
- Do not audit the project, do not rerun the full test suite until the last milestone, and do not fix unrelated bugs. If you notice one, add one line to claude/QUEUE.md and keep going.
- One milestone at a time, in the order below. After each milestone: check it in Studio Play with a screenshot, run only the tests for the code you touched, commit locally (never push, never publish), then continue. Stop and report if a milestone fails twice.
- Keep gameplay server-authoritative. Keep every click target working. Touch devices keep the 2D table.
- No em dashes in anything you write. Times in 12-hour format with am or pm. Never write the word "Balatro" anywhere in the game.
- Effort: medium by default. Use high only for milestones 4 and 5 (camera math, the left board).
- Do not ask for approval on polish or art choices. Decide and do it. Ask only for things that are irreversible, or that are the user's own steps (see "User-only steps").
- At the end: write claude/handoff-13.md (what changed, what was seen in Studio, what was not seen), update claude/STATUS.md, and add any new lesson to the matching file in claude/skills/.

## Where the look stands (screenshots taken on Nov 16 and 17)
The room is a good layout built from plain Parts, which reads as old Roblox. Specific problems:
1. The fire is a pile of yellow Ball parts (Props.lua, the Fireplace block around lines 197 to 224). It reads as floating bubbles.
2. The stone and the wall look like low-detail cork and flat red brick. Built-in materials at this scale do not fix it. It needs real textures.
3. Props are blocks and cylinders: candles, tankards, lanterns, banners, bottles, barrels. The ones closest to the camera need real meshes.
4. The deck pile is a tilted white slab cut off by the right screen edge, and its 44/52 count pill floats away from it.
5. The left board (score, target, hands, discards, tips, the Patron summary) is still a flat 2D panel on top of the 3D room. It is the largest thing on screen and the biggest clash.
6. The Multiplier box and the reveal readout (Chips x Mult, hand name) are flat dark boxes. A bottle and a candle overlap the Multiplier box corner.
7. Play Hand, Discard and the sort toggle sit on plain red boxes.
8. Two yellow bars in the top right (the wall lantern glow) look like a pause button.
9. The Patron slots are flat dark rectangles, not things standing on the table.
10. The seed box showing DEBUG2 is visible in the left panel.

## What not to do (learned the hard way)
- Do not raise Lighting.Brightness, ambient or exposure to make the room "brighter". The cards take the room's light (Lighting.cards.lightInfluence 0.85) and blow out to flat yellow. The baseline of exposure -1.0 and Brightness 0.35 is correct for the cards. Light the room with local lights and emissive props, not the global settings.
- Lighting.LightingStyle and Lighting.Technology cannot be read or written by a script (capability error). They are the user's manual step.
- Post-processing already exists in TableThemes/Tavern/Lighting.lua (bloom, color correction, depth of field, atmosphere). Tune it only after the props and fire are done, and compare against the "before" screenshot.

## Milestones

### 1. Real flames (smallest, most visible)
Replace the Ball-part fire with a particle flame: a ParticleEmitter (or the Fire instance as a fallback if the emitter texture will not load), plus a few embers and a slow smoke wisp, keeping the existing fire light and its flicker. Make the emitters theme data in Props.lua (a part can say it carries an emitter with its properties) so a second theme can have a different fire. Keep the logs, hearth and soot parts. Done when the fire reads as flame from the play camera.

### 2. Real materials
- Add support for a material variant name on a theme material (Materials.lua entries gain an optional `variant` field, and TableTheme.check and the scene builder honor it). First verify how Studio's generated MaterialVariants are stored (MaterialService in the place file versus created at runtime), because the place file is the user's. If variants must live in the place file, say so in the handoff and make every material fall back cleanly to its current built-in material when the variant is missing.
- Generate with Studio's generate_material tool (it returns a BaseMaterial and a variant name): worn oak for the table rail and the beams, dark planks for the wall and floor, fabric felt, worn grey stone for the hearth and chimney, cloth for the banners. Describe each carefully (color family, wear, grain scale). Keep the existing palette colors so the cards still read.
- Fix the texture scale so it does not look like cork on the chimney.
Done when the wall, hearth, table rail and felt show real surface detail in a Play screenshot.

### 3. Meshes for the props nearest the camera
Use Studio's mesh generation tools (generate_mesh, generate_procedural_model) or reviewed Creator Store assets (insert_asset, search_asset). Family friendly only, no alcohol imagery (tankards hold "ale" as plain amber liquid, as now). Do these first, in this order: tankards and goblets, candles (tapered, with wax drips and a real flame sprite), the hanging and wall lanterns (with glass), the chandelier (new, hangs above the table), barrels, shelf bottles. Keep them as entries in Props.lua with positions in studs from the table's middle. If a generated mesh gets an asset id, record the id in Props.lua. Also add a window and more shelving only if a milestone finishes early.
Done when the closest props have rounded edges and read as objects, not boxes.

### 4. Camera and composition
Move toward the reference (claude/ has the reference image if the user attached it; otherwise: eye level, closer, table receding, hand fanned in front). Today the camera is 55 degree lens, 24 degrees down, 12 studs above the felt (Engine/TableScene.CAMERA), fixed. Try lowering the pitch to about 14 to 18 degrees and bringing it closer, check that every card in an 8 card hand and the 5 card played lane stays readable and clickable at 1506 x 751 and at a short window, then choose the best. Changing the camera changes the placement math in Cards.lua and Stand.lua, so recheck hand lift, played lane size (laneTop), Patron boards and the score ghosts. Keep the camera fixed.

### 5. Move the flat HUD onto the table
In this order, using Stand.lua (move by stored reference is safe, parts the hub finds by name need `backer`; check each piece before moving it):
a. The left board (Night and Round, target bar and reward, round rule text, Hands, Discards, the five Patron-count rings, Tips, the Patron summary, the seed field). Make it a standing wooden board on the felt or beside it. Hide the seed field unless a debug flag is on.
b. The reveal readout (the Chips x Mult pill and the hand name) onto a board that stands where the lane ends.
c. The Multiplier panel: fix the overlap with the bottle and candle, and give it the board treatment.
d. The deck pile: a block of real card backs fully in frame, with the count on a small plaque touching it.
e. Play Hand, Discard and the sort toggle: replace the plain red boxes with carved wooden signs on posts (the reference has a sign on a post for Reroll).
f. The wall lantern glow that looks like a pause button: move it or remove the flat glow so nothing looks clickable that is not.
g. Patrons: make the Patron slots small standing pieces on the table (a painted card on a stand with a base), keeping name plaques and the click and hover behavior.

### 6. Tune the whole look
Only now retune Lighting.lua and the theme colors against a "before" screenshot taken at the start of this milestone. Keep exposure and Brightness as they are. Adjust color grading, bloom threshold and size, depth of field focus on the back wall, atmosphere haze, and each local light (fireplace, lanterns, candles, PlayerCandle). The goal is warmer, deeper contrast between lit areas and shadow, a softly blurred back wall.

### 7. Tester readiness (these need a human-like pass, not just tests)
Play and look at each, with a screenshot:
- The forced tutorial from the first click: the arrows and highlights against the shifted Patron row and the new boards.
- Owned Patrons standing and scoring during a reveal (only empty slots were checked before).
- A Boss Round with the new camera, including the Boss strip and the Boss intro.
- The reveal beat for a Pair, Two Pair, a Flush and a loss.
- The Counter (shop) opening after a win, reroll, buying a Patron.
- Calm mode and Fast animation speed (the code paths exist, never seen).
- A short window and a 16:9 window at about 1280 x 720.
- The small look notes in claude/STATUS.md that are still open (SpectateOverlay has no exit, boss name shown twice on the boss sidebar, uneven plate fonts).
- Run the full test suite once here and fix real failures only.
Also fix: the "TARGET CLEARED!" text still fading when the Counter opens (handoff 11), and played cards drawn smaller than hand cards.

## Decisions to make yourself (do not wait)
- Night 1 targets: the Small, Big and Boss rounds all land at 130 or close to it. Use a Small, Big, Boss ramp of 1x, 1.5x and 2x of the base. Note the change in the handoff.
- If a milestone is taking more than twice what you expected, cut the stretch items and finish the rest. Order of value if you must cut: 1, 2, 5a, 5d, 5e, 3, 6, 5g, 4.

## How to drive Studio without wasting usage
- Studio's viewport is about 1506 x 751, but screen_capture images are 1920 wide. Never click from screenshot pixels. Read AbsolutePosition + AbsoluteSize / 2 of the button with execute_luau (Client) and moveTo those numbers.
- After Play starts, GameUI.MenuRoot and GameUI.TutorialOverlay stay visible on top of everything. Hide them with execute_luau (set Visible = false) before taking screenshots or clicking. MenuRoot comes back after some screens, so hide it again if a capture shows the menu.
- Path to a round: Deal Me In, Begin Run, pick a first Patron (button named Pick, under ChoiceBackdrop), pick a blessing (same), then the round select (RoundPanel1.SelectButton), then the table. Find each button by name with execute_luau and click its center.
- A screenshot can show the previous frame. Wait 2 to 3 seconds after an action before capturing.
- If Studio restarts, its studio_id changes. Call list_roblox_studios again and use the entry that matches Wildcard Tavern.
- Live-tune in Play with execute_luau (Lighting, parts, materials), take screenshots, then write the winning values into the theme files. Live changes vanish when Play stops, and nothing syncs back, so always write the final values to the files.
- Rojo must be connected for file changes to reach Studio. Restart Play after a file change.

## User-only steps (do not try to do these)
- Set Lighting.LightingStyle to Realistic in Studio, and try Technology = Future if candle shadows are still missing. Save the place.
- Save the place after any generated MaterialVariants or meshes are added, if they live in the place file.
- Push the local commits to GitHub. Publish to Roblox. Both need the user's say.
- A real phone test (3D is off on touch devices by design, so phones show the painted 2D table).
- Creator Hub page items: thumbnail, icon, title, gameplay video, Game Passes, Developer Products and Badges with their ids, audio ids.
- Make sure Studio has API services access turned on so progress saves in Play.

## Definition of done for this session
A player sees a lit tavern with real flames, textured wood, stone and cloth, nearby props with real shapes, a left board and score readout that stand on the table, a deck pile fully in frame, signs for the buttons, and no flat panel or debug field that breaks the room. The tutorial, a Boss Round, Patrons scoring, the Counter, Calm mode and Fast speed have each been seen working in Play. The full test suite passes. Local commits exist, nothing is published, and handoff-13 says exactly what was and was not seen.
