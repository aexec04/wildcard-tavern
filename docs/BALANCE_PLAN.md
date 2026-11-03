1. Baseline findings (the "before" picture — keep for regression)
1.1 Death distribution (Standard difficulty, current numbers, n=300 each, assumed shop = real shop)
Bot	Win (clear Night-8 boss)	Where runs die
random	0%	N1 92%, N2 8%
greedy (best hand, never discards)	0%	N1 16%, N2 9%, N3 10%, N4 27%, N5 30%, N6 7%
decent (discards when behind pace)	0%	N3 4%, N4 28%, N5 52%, N6 15%, N7 1%

Generous shop (3 Patrons + 3 Packs + 50% voucher) changes little: decent median death still Night 5. Nobody wins.

1.2 What kills runs
Decent bot, by round: Night 4 → 82 of 300 deaths on the boss round vs 2 on rounds 1–2; Night 5 → 142 boss vs 13 non-boss. ~97% of all deaths are on the Boss round. Small/Big blinds are income tickets, not difficulty.
Median % of target reached at death: 54%.
Top killers: flat_mult, thin_chips, no_repeats, house_rules, house_minimum, short_staffed, picked_over, full_table, thin_soup, last_chance.
1.3 Target curve (current: TARGET_BASE_SCORE=100, TARGET_NIGHT_GROWTH=2.5, boss blind multiplier 2×→6× by Night 8)
night | small      big        boss        boss mult
 1    |      100        150          200   2.00x
 3    |      625        937        1,964   3.14x
 5    |    3,906      5,859       16,741   4.29x
 6    |    9,765     14,648       47,433   4.86x
 8    |   61,035     91,552      366,210   6.00x

Night-1 → Night-8 boss growth is ~1,830×. (Genre peers grow on the order of ~170×, from memory — verify if you care about parity.) Three things compound: 2.5×/Night growth, the boss blind multiplier ramp, and a boss modifier on top.

1.4 Boss-modifier effective difficulty is wildly uneven

Effective extra difficulty = targetMult / (chipsMult × multMult), × 4/handsOverride for hand caps. This multiplies on top of the 2–6× boss blind:

Effective ×	Modifier	minNight
11.1	everythings_out (chips ×0.3 AND mult ×0.3)	6
6.25	bare_bones (0.4/0.4)	6
4.0	stale_bread (0.5/0.5), lights_out (1 hand)	6
3.0	big_tab (target ×3)	6
2.0	thin_chips, flat_mult, quick_service	3 / 3 / 6
≤1.4	everything else	

Pool mean effective difficulty: Night 1–2 ×1.14, Night 3–5 ×1.23, Night 6+ ×1.87 (max ×11).

1.5 Tuning sweep (win rates; growth / bossMax; modifiers UNCHANGED)
growth / bossMax	greedy win	decent win	decent median death
2.5 / 6 (current)	0%	0%	N5
2.5 / 3	0%	0%	N5
2.2 / 3	0.7%	0.7%	N6
2.2 / 2	0.7%	0.7%	N6
2.0 / 3	2.0%	4.7%	N7
2.0 / 2.5	4.7%	11.3%	N7
2.0 / 2.0	7.3%	16.0%	N7
1.8 / 3	16.0%	24.0%	N8
1.6 Patron marginal value (mid-build: 2 flat-mult Patrons owned, Pair/Two Pair level 3; average best hand = 1274; gain shown as % of that; 24 sampled hands)

Top: steady_hand +115% (price 6), small_plate +68% (5), the_bard +63% (5), night_owl +56% (7), big_portions +50%, penny_pincher +50%, regulars_round +44%, full_house_crowd +44% (8), discard_special +37%, double_down +37%. Bottom (pure scoring effect): all_matching +2%, house_special +1%, threes_company +4%, ace_of_the_house +6%, perfect_ten +11%, jack_of_all_trades +11%. Caveat: tip_jar, spare_change, rainy_day_fund, big_spender, nest_egg, boss_bane read 0% only because the probe measures score; curtain_call, repeat_customer, all_hands_in read 0% because the probe doesn't set their trigger. They are not proven dead — evaluate with dedicated EV checks. Menu levels bought by the decent bot: Pair 280, Two Pair 264, Straight 21, Three of a Kind 15, Full House 7, Flush 6, High Card 4 (avg only ~2 levels per run). Pair/Two-Pair + flat-mult Patrons is the dominant strategy.

1.7 Deck variants and difficulties (decent bot, curve 2.0/2.5, n=150)
Setting	Mean night reached	Win
deck=standard	7.03	11.3%
deck=steady_hand	6.55	6.7%
deck=high_roller	6.77	8.0%
deck=marathon	7.02	10.0%
difficulty=casual	7.77	0.0% (bug, see 2.1)
difficulty=high_stakes	6.73	4.0%
1.8 Night-1 onboarding

Greedy bot (never discards) dies on Night 1 in ~16–19% of runs, independent of curve tuning. About 11% of random 8-card hands contain no pair; High Card scores ~16 vs. 25–50 needed per hand.

2. PHASE 1 — Bug fixes (do these first; each needs tests)
2.1 BUG: Casual difficulty can never win (and loses boss-round rewards)

Cause: in RunState.playHand, the run-win check is if state.bossModifier and state.night == state.config.nightCap then state.wonRun = true end, and the boss double-reward is if state.bossModifier then reward = reward + ... end. state.bossModifier is nil whenever bossRoundsEnabled == false (Casual). Patrons.boss_bane's onRoundWin also gates on state.bossModifier. Casual players can never get wonRun, never get the boss double reward, never earn "Tavern Keeper"/"Regular"/"Tavern Legend", and Boss's Bane never pays. Note RunState.blindMultiplierFor already applies the 2×–6× boss target multiplier to the last round of every Night regardless of bossRoundsEnabled — so Casual still has a boss-sized last round, just without a modifier.

Fix:

In RunState.startRound set (independent of bossRoundsEnabled):
lua
   state.isBossRound = BossRounds.isBossRound(state.round, state.config.roundsPerNight)

and initialize isBossRound = false in RunState.new's state table. 2. Add a helper (keeps manually-constructed test states working — several tests set state.bossModifier directly, see EngineTests.lua ~lines 883 and 1365–1383, inspect them):

lua
   function RunState.isBossRound(state)
       return state.bossModifier ~= nil or state.isBossRound == true
   end
In playHand's round-win block replace the three state.bossModifier checks used as "is this a boss round" (the wonRun check, the reward doubling) with RunState.isBossRound(state). Keep state.bossModifier for the actual modifier effects.
In Patrons.lua boss_bane.onRoundWin: if state.bossModifier or state.isBossRound then ... (Patrons.lua can't require RunState — cycle).
grep -rn bossModifier Shared Server Client and review every hit for "used as boss-round proxy" (e.g. Server/init.server.lua depth computation, client banners). Banner/PhaseA usage of state.bossModifier is fine (Casual has no modifier to announce).
Design decision to resolve: DifficultyTiers.casual.description says "Boss Rounds are off", but the last round still gets the 2×–6× boss target. Recommended: keep the multiplier (it's the Night's third blind) and change the text to "No Boss modifiers. Round targets are 20% lower." Alternative: flatten Casual's last round to the 1.5× Big multiplier.

Tests to add: (a) Casual state, round = roundsPerNight, night = nightCap, targetScore = 0, play a hand → wonRun == true; (b) Casual boss-round reward equals 2 * tipsPerRoundWin (+ interest/patron bonuses accounted for); (c) boss_bane pays 10 on a Casual boss round; (d) Standard behaviour unchanged.

2.2 BUG: deck-exhaustion soft-lock

Cause: Deck.draw returns fewer cards when the draw pile is empty, and the discard pile is only pooled back in RunState.startRound. A round can consume more than 52 cards: e.g. boss wild_crowd (3 forced discards per hand, each replaced from the deck, plus 5 cards played) + Double Shift (+1 hand) + Late Kitchen (+1 discard) + spending discards. Reproduced in simulation (seed 136, night 7, wild_crowd): hand 0 cards, deck 0, discard 52, hands remaining 1. playHand asserts #cardIndices >= 1 and there's no guard, so the round is unplayable. Boss rounds with requiredCardsPerHand (4 or 5) soft-lock the same way as soon as the hand has fewer cards than required. Brittle Garnish shatters and "86 It" (deck trimming) make it worse over a run.

Fix:

Add to RunState.lua (near removeIndicesFromHand):
lua
   -- Draws `count` cards; if the draw pile runs dry mid-round, shuffles the discard pile back in
   -- and keeps drawing, so a round can never run out of cards while any exist in the run.
   local function drawCards(state, count)
       local drawn = Deck.draw(state.deck, count)
       if #drawn < count and #state.discardPile > 0 then
           for _, card in ipairs(state.discardPile) do
               table.insert(state.deck, card)
           end
           state.discardPile = {}
           Deck.shuffle(state.deck, state.rng)
           for _, card in ipairs(Deck.draw(state.deck, count - #drawn)) do
               table.insert(drawn, card)
           end
       end
       return drawn
   end
Replace every mid-round Deck.draw(state.deck, n) in playHand (refill, forced-discard replacement) and discard with drawCards(state, n). startRound's initial deal (after pooling everything) stays as is. grep -rn "Deck.draw" Shared Server Client and check Recipes (well_stocked, mystery_guest, etc.) too.
Ordering nicety: draw the replacement before inserting the just-played/thrown card into discardPile, so a reshuffle can't instantly hand you back the card you just threw. In the forced-discard loop:
lua
   local thrown = table.remove(state.hand, rng(#state.hand))
   for _, c in ipairs(drawCards(state, 1)) do table.insert(state.hand, c) end
   table.insert(state.discardPile, thrown)

and in playHand compute the refill before moving playedCards into discardPile. 4. Add a last-resort guard so a genuinely unplayable state ends the run instead of hanging (possible only if total cards in the run < required count):

lua
   function RunState.hasLegalPlay(state)
       if #state.hand == 0 then return false end
       local req = state.bossModifier and state.bossModifier.requiredCardsPerHand
       if req and #state.hand < req then return false end
       return true
   end

At the end of playHand (round not won, not last hand) and at the end of discard: if not RunState.hasLegalPlay(state) and state.handsRemaining > 0 → state.roundOver = true; state.runOver = true and return softLocked = true in the result table. 5. Server: inspect the PlayHand and DiscardHand remote handlers in Server/init.server.lua (around lines 1195–1360 and the result.runOver branch near 1208). Make sure a runOver produced by discard() (new) also transitions the session to "gameover" and saves stats; today only playHand's result is checked. 6. Deck.remainingCounts (Deck Tracker) only counts the draw pile; after an in-round reshuffle the counts jump up — acceptable, but consider noting in the tracker title.

Tests: (a) state with deck = {} and 20 cards in discardPile, play 5 → hand refilled to full size from the reshuffled discard pile, discardPile emptied; (b) wild_crowd + double_shift + late_kitchen + 4 discards used → never ends with an empty hand while cards exist; (c) deck+discard+hand total < requiredCardsPerHand → runOver == true and no assert/hang; (d) total card count invariant: #hand + #deck + #discardPile is unchanged by draws (existing test near line 1014–1017 shows the pattern).

2.3 BUG: SeededRng uses the weakest bits of an LCG

Cause: return (state % math.floor(n)) + 1 after state = (1664525*state + 1013904223) % 2^32. For a power-of-two modulus the low bits have tiny periods: rng(2) strictly alternates, rng(4) repeats a 4-cycle. This biases shuffles, rng(4) Brittle breaks, rng(2)-style picks, and the Daily/Weekly/Seed-Code fairness the file's header promises.

Fix: use high bits: return (math.floor(state / 65536) % math.floor(n)) + 1. (Plain + - * / % math.floor only — keep it Luau-portable; the existing header explains the no-bitwise constraint.) Update the header comment ("not perfectly uniform" note) to say it now uses the upper 16 bits. Consequence to tell the owner: this changes every seeded sequence, so existing Daily/Weekly/seed-code runs will play differently after deploy. If live leaderboards matter, bump a SeededRng.VERSION and key the day/week DataStore buckets on it.

Tests: same seed → identical sequence (determinism); over 20,000 draws of rng(2), count of 1s within 48–52%; assert rng(2) is not strictly alternating (e.g. not all of the first 64 outputs alternate); rng(52) over 52,000 draws has every bucket within ±15% of expectation; rng(1) always returns 1.

2.4 Minor: UnlockPopup connection leak

showUnlockPopup calls unlockPopupDismissCatcher.MouseButton1Click:Connect(dismiss) on every call, so connections accumulate for the session (harmless thanks to the token check, but it leaks). Connect once outside showUnlockPopup with a handler that hides the popup and bumps the token; keep the timed task.delay dismiss token-guarded.

2.5 Hygiene (low priority)

Several ids collide across registries: DeckVariant steady_hand vs Patron steady_hand; Recipe golden_hour vs Theme golden_hour. Harmless today (separate lookups) but add a test that each registry has unique ids internally and consider a grep for any code that looks up ids across registries.

3. PHASE 2 — Headless simulator in Luau + extract the shop (needed to tune anything)

Goal: make every balance change measurable in seconds with the existing lua5.3 test setup.

3.1 Extract shop generation into Shared/Engine/Shop.lua (pure)

Today pickShopOffers, pickPackOffers, pickVoucherOffer, and the constants live inside Server/init.server.lua where they need Roblox. Move the pure logic out:

Shop.OFFER_COUNT = 2; Shop.PACK_OFFER_COUNT = 2; Shop.VOUCHER_CHANCE = 0.35
Shop.REROLL_BASE_COST = 5; Shop.REROLL_COST_STEP = 2
Shop.rollOffers(state) -> { patrons = {...}, packs = {...}, voucher = pass|nil }

Keep exact current semantics: Patron offers are drawn without replacement from un-owned Patrons using state.rng or math.random; Pack offers are drawn without replacement from all Packs.Definitions uniformly; voucher is rolled with rng(10000) <= floor(VOUCHER_CHANCE*10000) (or math.random() <= chance if no seeded rng), then picked uniformly from un-owned HousePasses. The server then just calls Shop.rollOffers. Don't change behaviour in this step (tests should pass unchanged).

3.2 Build tools/sim/Sim.lua (+ tools/run_sim.lua)

Port the logic of sim_reference/tavern.py to Luau-compatible Lua that drives the real RunState (not a re-implementation), so balance work can never drift from the engine. Requirements:

Bots (take an rng seeded from SeededRng.new(seed)): random (random legal selection), greedy (always plays the highest-scoring subset of the hand, never discards), decent (as greedy, but if bestScore < (target - roundScore)/handsRemaining and discards remain, discard the non-kept cards using the chooseKeep heuristic: keep a ≥4-card suit group, else keep all paired ranks, else keep the 3 highest). Best-subset search = enumerate all 1–5 card subsets of the hand (or exactly requiredCardsPerHand), score each with Scoring.calculate using a never-lucky rng (function(n) return n end, same trick TrueWildcard.lua uses), respect noRepeatHandTypes.
Shop policy (bot): roll offers via Shop.rollOffers; buy a voucher if affordable and in {double_shift, late_kitchen, extra_seating (only with ≥5 Patrons), grand_opening}; buy the Patron with the highest dynamic marginal value (average best-hand score gain over ~3 sampled 8-card hands, comparing table-with-patron vs table-without); buy affordable Packs of category patron/menu/standard/mixed; in a menu pack level up the hand type the bot plays most (default Pair); in a standard pack keep a card if its modifier priority ≥ 3 (priority: rainbow 9, brittle 8, iron 7, gold 6, zesty 5, silver/lucky 4, sweet/encore 3). Improve on the Python bot where cheap: use rerolls when rich, use House Recipes (apply garnishes to played cards), use Menu recipes from the box.
Parameters: difficultyId, deckVariantId, number of runs, maxNight (default 10), seed base, bot, shop-generosity overrides.
Outputs (print + CSV/JSON): death-night distribution; win rate (clear boss of nightCap); % of deaths on boss rounds; per-boss clear rate (needs ≥ ~100 attempts per boss — run many seeds or force-pick each modifier); per-Patron win-rate lift and pick rate; Patron marginal value table (as in §1.6); median % of target reached at death; soft-lock count (must be 0 after Phase 1); Tips floating at each shop visit; menu-level distribution by hand type.
Must be deterministic per seed and fast enough for ≥1000 runs/bot in a few minutes.
3.3 Reference

sim_reference/ contains the Python bots and analysis scripts (tavern.py, sweep.py, ana2.py, ana3.py). Known approximations in it: House/Secret recipe packs are ignored, no rerolls, pack picks simplified, patron_value samples only 3 hands and sizes {2,3,5}. Treat it as a spec for the harness, not as ground truth.

4. PHASE 3 — Balance changes (validate each with the Phase-2 sim; iterate)

Target bot ladder (the acceptance bar after tuning):

random: dies Night 1–2 (>90%).
greedy (never discards): median death Night 5–6, win 2–6%, Night-1 death rate ≤ 10%.
decent: median death Night 7, win 12–20%.
A skilled human should land around 30–50% (can't be measured; keep headroom, i.e. don't tune the decent bot above ~20%).
Boss rounds should still be the main danger, but no single boss modifier should have a clear rate below ~50% of the all-boss average (per-boss report).
Per-Patron: scoring Patrons within roughly 0.6×–1.6× of the median gain-per-price at mid-build (excluding conditional/economy Patrons, which get their own EV test).
4.1 Target curve (RunState.lua constants)
TARGET_NIGHT_GROWTH = 2.5 → 2.0
BOSS_BLIND_MULTIPLIER_MAX = 6 → 2.5 (keep MIN = 2; the ramp formula stays linear from Night 1 to nightCap).
Note this makes Night N+1's Small blind (2.0×base_N) slightly below Night N's boss (~2.4×base_N). That's what the sim ran with and is fine; don't "fix" it. Update any hard-coded expectations in EngineTests.lua (tests at ~398–403 and ~1317–1322 compute from the functions and should still pass, but grep for literal target numbers).
After the modifier clamps below the decent bot will win more than the 11.3% measured with 2.0/2.5. If it exceeds ~20%, raise growth toward 2.1–2.2 rather than touching the boss cap.
4.2 Clamp boss modifiers (BossRounds.lua) — and update description strings to match exactly
id	field(s)	old → new	notes
stale_bread	chips/mult mult	0.5/0.5 → 0.75/0.75	"reduced by 25%" (eff ×1.78)
bare_bones	chips/mult mult	0.4/0.4 → 0.7/0.7	"reduced by 30%" (eff ×2.04)
everythings_out	chips/mult mult	0.3/0.3 → 0.65/0.65	"reduced by 35%" (eff ×2.37)
thin_chips	chips mult	0.5 → 0.6	"reduced by 40%"
flat_mult	mult mult	0.5 → 0.6	"reduced by 40%"
big_tab	target mult	3 → 2	
lights_out	add targetScoreMultiplier	— → 0.5	"only 1 hand, but the target is halved"
quick_service	add targetScoreMultiplier	— → 0.75	"only 2 hands, target ×0.75"
Keeps the ordering stale_bread < bare_bones < everythings_out. Then run the per-boss clear-rate report and soften any boss whose clear rate is < ~50% of the average (likely candidates to check: one_at_a_time — High-Card-only, exactly 1 card; four_top; no_repeats; full_table; empty_pockets). Suggested first tweaks if they fail: one_at_a_time.targetScoreMultiplier = 0.6, four_top.targetScoreMultiplier = 0.85.	
Add a test that enforces a ceiling on every modifier's effective difficulty so future additions can't recreate the ×11 problem:	
effective = (targetScoreMultiplier or 1) / ((chipsMultiplier or 1) * (multMultiplier or 1))
if handsPerRoundOverride then effective = effective * (4 / handsPerRoundOverride) end
assert(effective <= 2.5)
4.3 Patron rebalance (Patrons.lua) — starting values

Nerf the flat-mult outliers: steady_hand +18 → +12 mult; small_plate +20 → +12 mult; night_owl 3*night → 2*night. Buff the hand-specific Patrons so playing Flush/Straight/Full House is a real strategy: all_matching +10 → +18; straight_shooter +12 → +18; threes_company +12 → +18; house_special +14 → +22; all_hands_in +10 → +25; double_down +10 → +14; ace_of_the_house per-Ace +5 → +7. Update every description string to match the numbers. Re-run the marginal-value table; iterate until the spread rule in §4 holds. Evaluate separately (dedicated EV tests in the sim): tip_jar (+4/round win), spare_change (+2/remaining discard), rainy_day_fund (+1/remaining hand), big_spender (+1/Patron), nest_egg (interest cap 5→10; only matters if the bot banks ≥25 Tips — add a banking bot variant), boss_bane (+10 per boss), curtain_call (×1.5 last hand), repeat_customer (×3 on a repeated hand type), all_hands_in. If an economy Patron's total Tips-over-a-run < ~its price × 2, buff it.

4.4 Hand level growth (Scoring.HandLevelGrowth) — candidate buffs to make non-Pair hands worth leveling

Three of a Kind {20,2}→{25,3}; Straight {25,2}→{30,3}; Flush {20,2}→{25,3}; Full House {25,2}→{30,3}. Leave Pair/Two Pair/High Card. Validate with the sim: goal is the decent bot's level purchases are not ≥ 90% Pair+Two Pair (baseline: 544 of ~600).

4.5 Deck variants (DeckVariants.lua) — each must be a real tradeoff, none strictly worse than Standard

Baseline: Standard 11.3%, Steady Hand 6.7%, High Roller 8.0%, Marathon 10.0% (n=150; noise ±4%, so only Steady Hand and High Roller clearly lag). Starting changes:

steady_hand: discardsPerRound = 1 → 2 (keep handSize = -1).
high_roller: startingTips 6 → 14, add targetScoreMultiplier = 0.9 (keep handsPerRound = -1).
marathon: leave (≈ Standard). Re-run until every variant's win rate is within ~±20% (relative) of Standard's with the decent bot. Optionally add 2 new variants with distinct identities (e.g. a "Lucky Deck" starting with one Lucky Garnish card + 1 fewer discard; a "Gilded Deck" starting with 3 random garnished cards + 2 Patron slot -1) once the base ladder is right.
4.6 Tags (Tags.lua) — optional

Skipping is almost never right (Tip Jar pays 2–3 Tips; you lose the round's income and shop). Either raise tipJarAmount (e.g. ceil(tipsPerRoundWin × 0.75)) or add two new tags: Menu Tag (free level-up of your most-played hand) and Standard Tag (free card with a random garnish added to your deck). Skip-vs-play EV test in the sim.

5. PHASE 4 — New content: scaling Patrons (fixes "nothing snowballs")

Every current Patron is static. Add 8 scaling Patrons. Because definitions are shared (rule 4), counters live on state.

5.1 Plumbing (do this first, with tests)

Add to RunState.new's state table: roundsCleared = 0, bossesCleared = 0, handsPlayedTotal = 0, discardsUsedTotal = 0, patronsSold = 0. Increment points: roundsCleared and (if RunState.isBossRound(state)) bossesCleared in playHand's round-win block before the onRoundWin loop; handsPlayedTotal in playHand after scoring; discardsUsedTotal in discard(); patronsSold in sellPatron (not for Clean Sweep). Add to the Scoring.calculate context in three places (RunState.playHand's scoring call, RunState.playHand's TrueWildcard buildContext, and the client's computeHandPreview): roundsCleared, bossesCleared, handsPlayedTotal, discardsUsedTotal, patronsSold, handStatsBefore. handStatsBefore must be a snapshot taken before state.handStats[handName] is incremented (the engine increments before scoring today; the client preview runs before the play, so passing the pre-increment counts keeps both identical). serializeState in Server/init.server.lua must ship the new counters so the client preview has them. Add a test asserting preview-context == server-context field-by-field for these keys.

5.2 The 8 Patrons (names/prices are suggestions; keep emoji kid-friendly and unique)
id	name	price	effect	cap
slow_cooker	Slow Cooker 🍲	7	×(1 + 0.1 × roundsCleared) Mult	×3.0
house_tab	House Tab 📒	8	×(1 + 0.25 × bossesCleared) Mult	none (≈×2.75 by Night 8)
regulars_chair	Regular's Chair 🪑	6	+0.5 Mult per hand played this run (floor)	+60
cobweb_shelf	Cobweb Shelf 🕸️	5	+1 Mult per Discard used this run	+50
tasting_menu	Tasting Menu 📜	7	+4 Mult per distinct hand type played this run (count keys of handStatsBefore)	+36
estate_sale	Estate Sale 🏷️	6	+6 Mult per Patron sold this run	+60
pair_bonds	Pair Bonds 💞	6	+1 Mult per Pair/Two Pair played this run	+40
veterans_table	Veteran's Table 🎖️	8	+40 Chips per Night reached after Night 1 (so chips scale too)	none
Each needs: a description that states the formula, an effect(handResult, context) returning { mult = ... } / { chips = ... } / { multMultiplier = ... }, and a test (including: two separate RunStates don't share counters). Check anything hard-coding the Patron count: Achievements.every_patron uses #Patrons.Definitions (fine), but grep -rn "42" in Client/Collection and docs. Packs/shop/Tags/New Regular all iterate Patrons.Definitions, so new Patrons appear automatically. Tune numbers with the sim: goal is that a run that finds 2 scaling Patrons early has a clearly better late game (win-rate lift of the scaling set > the static set at equal price).	
6. PHASE 5 — Progression and meta (needs product decisions; do as separate PRs)

Problem: nothing is unlocked by playing (all 42 Patrons, all variants available run 1), Tips-priced Themes (8–18 Tips = 1–3 Patrons) make a cosmetic purchase able to lose you a run, and the only persistent hooks are Collection discoveries and Achievements/Titles.

6.1 Stake ladder (highest value)
PlayerProfile.stats.winsByDifficulty = {} ([difficultyId] = count); add to new(), migrate() (type-check number ≥ 0), and recordRunWon(profile, difficultyId) (server passes the run's state.difficultyId).
DifficultyTiers: add 2 tiers above High Stakes with new engine knobs, e.g. veteran (target ×1.2, boss modifiers' minNight shifted −1 via a new bossMinNightShift) and nightmare (target ×1.4, bossMinNightShift = -2, interest cap −2). Unlock rule: a tier is selectable once the player has a win on the previous tier (Casual and Standard always selectable).
Server must validate the requested difficulty is unlocked in the StartRun/StartSeedRun/Daily/Weekly handlers (reject and fall back to Standard). Client/RunSetup.lua renders locked tiers greyed with the unlock hint.
New achievements (stateless, computed from winsByDifficulty): e.g. "Win on High Stakes", "Win on every difficulty".
6.2 Separate cosmetic currency from run power

Add profile.tokens (permanent), earned at run end (e.g. 5 × nightsCleared + 25 × win, once per run, idempotent on the server). RunState.buyTheme currently spends state.tips — change Theme purchases to spend profile.tokens (update BuyThemeRemote handler, Themes.price semantics, Client/Themes.lua "Buy (N)" check which currently reads latest.tips). Existing owned themes in ownedThemeIds stay owned. Game-Pass Themes unchanged.

6.3 Content unlocks (optional, bigger)

Start each profile with ~24 Patrons in the shop pool; unlock the rest via achievements/wins/discovery. Implement one helper (Patrons.pool(profile) or state.unlockedPatronIds) and use it in all four places that enumerate Patrons: Shop.rollOffers, RunState.openPack (patron + mixed branches), Tags.unownedPatrons, and the new_regular recipe. Never let the pool shrink below ~12 or Pack reveals will be thin.

7. PHASE 6 — Onboarding
A no-discard player dies on Night 1 ~16–19% of the time. Make Client/TutorialWalkthrough.lua teach discarding before anything else (highlight Discard when the selected best hand is High Card and discards remain), and add a one-time contextual hint (use MessageBanner.showWarning) the first time a player plays a High Card with ≥1 discard left.
Consider starting new profiles (stats.runsStarted < 3) with +1 discard on Night 1 only. Gate it on the profile so it never affects daily/weekly/seed fairness.
Leaderboards: computeDailyDepth counts rounds cleared; after the curve change check it still orders runs sensibly.
8. Acceptance criteria (must all hold at the end)
lua5.3 tools/run_tests_local.lua passes, including all new tests from §2–§5; Shared/Engine still parses under both Lua 5.3 and Luau.
Soft-lock count = 0 across ≥ 5,000 simulated runs per bot, including forced Wild Crowd / Full Table / Four Top with Double Shift + Late Kitchen.
Casual: wonRun reachable; boss double reward and Boss's Bane work.
Sim ladder per §4 (random N1–2; greedy median N5–6 / win 2–6%; decent median N7 / win 12–20%); Night-1 greedy death ≤ 10%.
No boss modifier with effective difficulty > 2.5 (enforced by test) and no boss with clear rate < ~50% of average.
Scoring Patrons within the 0.6×–1.6× marginal-value-per-price band; menu levels for the decent bot not ≥ 90% Pair + Two Pair.
Every Deck Variant within ±20% (relative) of Standard's decent-bot win rate.
Client previews equal server scores for every new context field (test).
Existing DataStore profiles load unchanged; new fields default safely.
A short docs/BALANCE_NOTES.md listing every number changed (old → new) and the sim results that justified it.
9. Suggested order of work

Phase 1 (bugs, tests) → Phase 2 (shop extraction, Luau sim) → record baseline sim results with the unchanged numbers (to confirm the Luau sim reproduces §1) → Phase 3 (curve, modifiers, Patrons, growth, decks) iterating on sim output → Phase 4 (scaling Patrons) → Phase 6 (onboarding) → Phase 5 (meta; confirm product decisions with the owner first).

10. File map (where things are)

Shared/Engine/: RunState.lua (targets nightBaseScoreFor/blindMultiplierFor/targetScoreFor, startRound, playHand, discard, shop prices, openPack/resolvePack, skipRound, sellPatron), Scoring.lua (HandBase, HandLevelGrowth, calculate), Patrons.lua (42), BossRounds.lua (35 modifiers, pick(rng, night), categoryOf), DifficultyTiers.lua, DeckVariants.lua, Tags.lua, Packs.lua, HousePasses.lua, Recipes.lua, TrueWildcard.lua, SeededRng.lua, PlayerProfile.lua, Achievements.lua, Themes.lua, GamePasses.lua. Server: Server/init.server.lua (shop constants ~lines 316–322, pickShopOffers/pickPackOffers/pickVoucherOffer ~360–430, remote handlers ~1195–1400, serializeState ~540–570). Client: Client/init.client.lua (computeHandPreview, render), RunSetup.lua, Themes.lua, TutorialWalkthrough.lua, UnlockPopup.lua. Tests: EngineTests.lua (~3,200 lines, ~315 tests), TestRunner.lua.