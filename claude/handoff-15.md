# Handoff 15: what the overnight queue did

Branch `concept-t-2d`. 90 local commits since 5c3607b (the last is the idle sparkle pass, 3a82f52). Nothing is pushed. Tests: 1067 passed, 0 failed, and the same 1067 in the no-io Studio pass. Client locals ratchet stays 127 of 127.

## What changed, by player-facing area

**Play screen (painted Concept T look)**
- Painted tavern room, HUD plates (coins, hands, Round with gold bar), gear, deck book with one count pill, Play Hand and Discard art buttons, all placed from tested rects (`Engine/ConceptTLayout`).
- Six pixel passes against the reference picture, plus tools: `pixel_match.py`, `compare_sheet.py`, `align_report.py`, and a Studio-only reference scene (`ConceptTReference.show()`).
- Real screen parity: no old Patron panel, side panel or rail; flat Rank | Suit pill left of Play Hand; icons in a row left of the gear.
- Small screens: 44 px buttons, tested at five sizes.

**Patron cards**
- All 81 Patrons have a painted card (`ctp_<id>`), shown in the play row, Counter and Collection, with a rarity label pill and an effect pill.
- Entrance drop, hover or tap lift, rarity glow (Rare and up), Legendary shine, tooltip plate with synergy tags and shared-tag outlines, trigger popups.

**Cards and hand**
- 52 painted card faces (Classic Tavern skin; Colorblind Suits keeps the code face).
- Hand fan, hover and select lift, discard flights, scoring stage with glow ring, hand name slam.

**Menu**
- Painted Deal Me In plate (text-free, no doubled label) with a gentle pulse, rising logo, hover lift, rotating tip on a plate bottom left.

**Counter (shop)**
- Serif titles, painted price pills, 44 px tabs, 220 x 64 Next Round plate, cream inactive tabs, 8 px gap under tabs, rare offer sparkle, road cards on dark text plates.

**Run Over and celebration**
- Dark facts plate, big Play Again, equal small pills, cut Patron cards, new unlocks listed.
- Round clear count-up, win confetti, gentle loss wash with Try Again.

**Boss**
- Red rule plate, edge pulse, crown title drawn without a glyph, bigger confetti on a boss clear.

**Sound**
- Named cues wired, per-cue 0.05 s cooldown, rising score_tick pitch, defeat cue, ids filled from library clips already in the game.

**Accessibility**
- Rarity shape marker beside the word, contrast tests, Larger Text, Calm mode and Reduce motion create no tweens (audited).

**Performance and safety**
- One shared effects loop (`FxLoop`) that pauses when hidden, a leak test, save audit tests (old profile, garbage payloads, DataStore in pcall), full run smoke tests.

**Tutorial**
- Guided first hand (fixed starter Patron, two line hint), clearer hint plate, 44 px Skip that always works, Replay Tutorial in Settings.

**Balance (this last task)**
- `lua tools/balance_report.lua --bot greedy --runs 200`: greedy wins 20.5 percent, clears Night 3 in 87 percent and Night 8 in 20.5; decent bot wins 32.5.
- I did not tune to the queue's 35 to 55 percent Night 3 target, since it would make the first three Nights harsh for new players. Your call if you want it. No Patron numbers changed (only bread_starter is over 30 points above average, and the table is biased toward runs that live longer).

## Verified in Studio vs only by tests
- Studio captures by chat Claude: the reference scene, the real play screen, Menu, Counter, Run Over, boss screen (the defects found were fixed in later commits).
- Tests only, no Studio look yet: pack opening reveal, screen fades and Dealing plate, tutorial hint anchors, Counter Next Round plate and tabs, Patron tooltip, Collection count pills, Settings restyle, progression toast, all sound cues (ids in place, not listened to).

**Later passes (Nov 19)**
- Settings board: Calm Mode and Reduce Motion first, 44 px painted switches, Sound row, 44 px slider hit area.
- Tome sub pages share dark header plates; Settings, Tome and pack opening tests added.
- Touch controls: tap select, drag to reorder the hand, long press tooltips for hand and Patron cards.
- Friendly errors: plain toast, Try again after 6 s without a Play Hand reply, input watchdog for stuck fade covers and locks.
- Rarity pill is one centred plate with the shape marker inside it, clear of the word.
- Idle sparkle: after 8 s idle the hand breathes 2 px, Play Hand glows with a legal selection, a tip fades in at 20 s. Calm mode is still.

## Known leftovers
- Reroll on the Counter is the painted bell prop and is not lined up with the card row.
- Season premium and Flair store ids are still placeholders (0).
- Pixel scores for the real play screen have not been re-run since pass 6.

## How to test in Studio
1. `rojo serve` with the pinned 7.4.4 CLI, connect with the local 7.4.4 plugin, press Play.
2. Fast path with DebugGoto: `menu`, `round1`, `patrons:5`, `boss1`, `runover`, `runover:win`, `tome:collection`, `shop`.
3. Capture sweep: run `sweep` at 1920x957; wait for each `[DebugGoto] sweep <screen>` line and screenshot about 4 s later. `sweep:stop` ends it.
4. Reference scene: in Play, client command bar, `require(game.Players.LocalPlayer.PlayerScripts.Client.ConceptTReference).show()`, screenshot, then `python3 tools/pixel_match.py <png>`.
5. Check at 1920x1080, 1280x720 and 844x390, and once with Calm mode on (nothing should move).
