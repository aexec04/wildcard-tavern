# Balance notes

Results of Phases 2, 3, 4 and 6 of `docs/BALANCE_PLAN.md`. All numbers come from `tools/run_sim.lua`, which drives the real `RunState`, `Scoring` and `Shop`.

Difficulty is Standard unless stated. "Decent" and "greedy" are the plan's bots, sharing one shop policy.

The first section below is the current state, after Phases 4 and 6. Everything after it describes Phase 3; two of its numbers have since changed (night growth and the High Roller deck).

## Current state (after Phases 4 and 6)

Ladder: 5,000 runs per bot, seeds 2100001+, never used for tuning.

| Bot | Target | Result | Status |
|---|---|---|---|
| random | dies Night 1-2, over 90% | 94.3% | Pass |
| greedy win | 2-6% | 5.2% | Pass |
| greedy median death | Night 5-6 | Night 6 | Pass |
| greedy Night-1 deaths | 10% or less | 9.1% | Pass |
| decent win | 12-20% | 14.6% | Pass |
| decent median death | Night 7 | Night 7 | Pass |

Greedy has less margin than these numbers suggest. On a separate 2,000-run sample (seeds 2500001+) it won 6.7%, just over the band.

| Check | Result |
|---|---|
| Soft-locks | 0 in 30,300 runs, including forced Wild Crowd, Full Table and Four Top with Double Shift and Late Kitchen |
| Boss clear rate | Lowest is Everything's Out at 0.52x the all-boss average |
| Deck variants | Steady Hand 13.1%, High Roller 15.0%, Marathon 16.8%, all within 20% of Standard's 14.3% (3,000 runs each) |
| Difficulty | Casual 38.0%, Standard 14.3%, High Stakes 9.0% |
| Menu levels | Pair + Two Pair are 39% of levels, against a 90% limit |
| Banking bot (never spends below 25 Tips) | 51.8%, unchanged from Phase 3 |
| Tests | 350 engine tests and all sim checks pass |

### Phase 4: scaling Patrons

Every scaling Patron reads run-long counters on the run's state (rounds cleared, bosses cleared, hands played, discards used, Patrons sold, and hand counts before the current hand). `RunState.runCounters` builds that table once. The server scores with it, ships it to the client, and the client preview scores with the same table, so the two cannot disagree. A test checks the preview against the real score for every scaling Patron.

The plan's suggested numbers were far too strong once added to a pool of 50 Patrons: the decent bot won 94.8% and greedy 74.0%. Scoring is multiplicative, so +40 Chips per Night multiplied a Night-8 hand by about 8. Every one was cut, and night growth then moved from 2.105 to 2.26 to absorb what remained.

| Patron | Plan's number | Shipped | Price |
|---|---|---|---|
| slow_cooker | x0.1 Mult per round cleared, up to x3 | x0.025 per round cleared, up to x2 | 7 |
| house_tab | x0.25 Mult per boss cleared | x0.08 per boss cleared | 8 |
| regulars_chair | +0.5 Mult per hand played, up to +60 | +1 per 6 hands played, up to +15 | 6 |
| cobweb_shelf | +1 Mult per Discard used, up to +50 | +1 per 3 Discards used, up to +15 | 5 |
| tasting_menu | +4 Mult per hand type played, up to +36 | +1 per hand type played (up to +9) | 7 |
| estate_sale | +6 Mult per Patron sold, up to +60 | +2 per Patron sold, up to +20 | 6 |
| pair_bonds | +1 Mult per Pair or Two Pair, up to +40 | +1 per 4 Pairs or Two Pairs, up to +15 | 6 |
| veterans_table | +40 Chips per Night after Night 1 | +8 Chips per Night after Night 1 | 8 |

Other changes in Phase 4:

| Item | Old | New | Why |
|---|---|---|---|
| `TARGET_NIGHT_GROWTH` | 2.105 | 2.26 | Most runs now find several scaling Patrons |
| High Roller starting Tips | 14 | 12 | It was 30% above Standard, because early Tips buy scaling Patrons |
| High Roller target | x0.9 | x0.95 | Same |

The plan's goal was that two scaling Patrons found early beat two static ones. Each pair below was owned from Night 1, 1,500 runs each, decent bot; the same bot with no free Patron wins about 14%. Standard error is about 1 point.

| Scaling pair | Price | Win | Static pair | Price | Win |
|---|---|---|---|---|---|
| slow_cooker + house_tab | 15 | 28.8% | night_owl + steady_hand | 15 | 22.7% |
| tasting_menu + veterans_table | 15 | 26.1% | the_bard + small_plate | 13 | 20.8% |
| cobweb_shelf + estate_sale | 11 | 22.2% | ace_of_the_house + vip_table | 12 | 21.1% |
| regulars_chair + pair_bonds | 12 | 19.5% | full_house_crowd + early_bird | 16 | 29.6% |

Three of the four scaling pairs beat a similarly priced static pair, two of them clearly. regulars_chair + pair_bonds does not, and the static x-Mult pair (full_house_crowd + early_bird) beats everything. So the goal holds for most scaling Patrons but not all; those two are the ones to buff if you want every scaling Patron ahead.

Owned alone from Night 1 (400 runs each, control 12.2%), the economy Patrons still lead at +18 to +21 points, then veterans_table (+15.5), slow_cooker (+13.5) and house_tab (+12.2). The rest are within about +2 to +8 points, inside this sample's noise of about 2.4 points around each other.

In the Patron marginal-value probe, veterans_table reads 1.75x the median at Night 5, a little above the 1.6x band. It is left there on purpose, since a scaling Patron should outgrow a static one by late game. The probe shows the other scaling Patrons at zero because it starts with empty counters.

### Phase 6: onboarding

| Change | Detail |
|---|---|
| Walkthrough selection | It used to advance on the first card clicked and then dim the hand, so a new player's first play was forced to be a single-card High Card. Selecting now ends with a "Done picking" button that appears once a card is selected. |
| Discard taught first | Discard is now shown before the first Play. If the selection only makes a High Card, the text warns about it and the button reads "Play it anyway". Using Discard returns to selecting, because the hand has changed. |
| High Card hint | The first time a player plays a High Card with a Discard left, a banner explains discarding. It waits until the tutorial is over, appears once per profile, and is saved as `hasSeenHighCardHint`. |
| New-player discard | +1 discard each round of Night 1, for a profile's first 3 runs. Seeded runs (Daily, Weekly, Seed Code) never get it. |
| Saves | Existing saves load with the hint unseen and no other change. |

The new-player discard does nothing for the bots: decent 13.0% with or without it, and greedy's Night-1 deaths stay at 8.7%, because greedy never discards. A player who doesn't discard isn't helped by having more discards, so the walkthrough change is the part aimed at them. The bonus only helps players who already discard.

With every Phase 6 feature in place, a normal run plays identically: the same 2,000 seeds gave the same result to the decimal before and after.

The Daily and Weekly leaderboard depth counts rounds reached, `(night - 1) * 3 + (round - 1)`. That is unaffected by the target changes. It does count a skipped round as progress, which was true before this work; `state.roundsCleared` now exists if you'd rather rank by rounds actually cleared.

None of the client changes (walkthrough, banner) have been run in Roblox Studio. They parse as Lua, and the rules behind them are covered by tests.

## Result

Final ladder: 5,000 runs per bot, seeds 1300001+, never used for tuning.

| Bot | Target | Before | After | Status |
|---|---|---|---|---|
| random | dies Night 1-2, over 90% | 98.7% | 94.0% | Pass |
| greedy win | 2-6% | 0.2% | 5.9% | Pass |
| greedy median death | Night 5-6 | Night 5 | Night 6 | Pass |
| greedy Night-1 deaths | 10% or less | 17.7% | 7.6% | Pass |
| decent win | 12-20% | 0.2% | 12.8% | Pass |
| decent median death | Night 7 | Night 6 | Night 7 | Pass |

Before-numbers are 1,000 runs per bot. Standard error at 5,000 runs is about 0.33% for greedy and 0.47% for decent, so greedy's 5.9% is inside the band but close to its edge.

After, by Night (share of all runs):

| Bot | N1 | N2 | N3 | N4 | N5 | N6 | N7 | N8 | Won |
|---|---|---|---|---|---|---|---|---|---|
| greedy | 7.6% | 4.0% | 2.5% | 5.3% | 12.0% | 28.9% | 24.7% | 9.1% | 5.9% |
| decent | 0% | 0% | 0.1% | 0.5% | 2.9% | 23.1% | 38.8% | 21.9% | 12.8% |

### Other acceptance checks

| Check | Result |
|---|---|
| Soft-locks | 0 in 30,300 runs: 5,000 per bot, plus 1,700 per bot each on forced Wild Crowd, Full Table and Four Top with Double Shift and Late Kitchen |
| Boss effective difficulty | All 2.5x or less, enforced by a test |
| Boss clear rate | Lowest is One at a Time at 0.51x the all-boss average (table below) |
| Deck variants | All within 20% of Standard's 12.7% (table below) |
| Menu levels | Pair + Two Pair are 39% of levels, against a 90% limit |
| Economy Patrons | Each pays at least twice its price per run (table below) |
| General scoring Patrons | 0.77x to 1.65x of median gain per price; see the exceptions below |
| Tests | 337 engine tests and all sim checks pass |

Deck, Patron-lift, banking and soft-lock results were measured just before One at a Time went from x0.4 to x0.35. The ladder and boss table were re-run after that change. Ladder win rates moved by at most 0.1 points.

## Decisions for the owner

1. **Banking Tips is very strong.** The decent bot wins 52% if it simply never spends below 25 Tips, because +5 interest per round compounds. The plan expects a skilled human at 30-50%, so this one habit already reaches the top of that range. Economy Patrons owned from Night 1 show the same effect, at about +7 to +14 points of win rate. Tuning this was outside Phase 3, so it is unchanged. The direct levers are the interest cap (currently +5) and interest rate.
2. **The Big Blind equals the Boss Blind on Night 1.** Both are now 2x. The bot ladder needed this, but the two rounds have the same target on Night 1, and the gap only grows to 0.5x by Night 8.
3. **Boss rounds are a smaller share of deaths.** Decent's boss share fell from 97% to 61%. Bosses are still the largest single danger, but Big Blinds now matter too.
4. **Hand-type Patrons are unproven.** See the exceptions below.

## Changes

Every number changed, old to new. Each description string was updated to match.

### Target curve (`RunState.lua`)

| Constant | Old | New | Plan's start |
|---|---|---|---|
| `TARGET_BASE_SCORE` | 100 | 65 | not in plan |
| `TARGET_NIGHT_GROWTH` | 2.5 | 2.105 | 2.0 |
| `BLIND_MULTIPLIER_BIG` | 1.5 | 2 | not in plan |
| `BOSS_BLIND_MULTIPLIER_MAX` | 6 | 2.5 | 2.5 |

| Night | Small old | Small new | Big new | Boss old | Boss new |
|---|---|---|---|---|---|
| 1 | 100 | 65 | 130 | 200 | 130 |
| 3 | 625 | 288 | 576 | 1,964 | 617 |
| 5 | 3,906 | 1,276 | 2,552 | 16,741 | 2,917 |
| 6 | 9,765 | 2,686 | 5,372 | 47,433 | 6,332 |
| 8 | 61,035 | 11,903 | 23,807 | 366,210 | 29,758 |

### Boss modifiers (`BossRounds.lua`)

| Boss | Field | Old | New | Effective difficulty |
|---|---|---|---|---|
| stale_bread | chips and mult | 0.5 | 0.75 | 4.0 to 1.78 |
| bare_bones | chips and mult | 0.4 | 0.7 | 6.25 to 2.04 |
| everythings_out | chips and mult | 0.3 | 0.68 | 11.1 to 2.16 |
| thin_chips | chips | 0.5 | 0.6 | 2.0 to 1.67 |
| flat_mult | mult | 0.5 | 0.6 | 2.0 to 1.67 |
| big_tab | target | 3 | 2 | 3.0 to 2.0 |
| lights_out | target | none | 0.5 | 4.0 to 2.0 |
| quick_service | target | none | 0.75 | 2.0 to 1.5 |
| one_at_a_time | target | none | 0.35 | not capped by the formula |
| last_chance | discards | 0 | 1 | |
| empty_handed | discards | 0 | 1 | |

### Patrons (`Patrons.lua`)

| Patron | Effect old | Effect new | Price |
|---|---|---|---|
| steady_hand | +18 Mult | +5 Mult | 6 to 7 |
| small_plate | +20 Mult | +8 Mult | 5 to 6 |
| night_owl | +3 Mult per Night | +1 Mult per Night | 7 to 8 |
| the_bard | +2 Mult per card | +1 Mult per card | 5 to 7 |
| big_portions | +50 Chips | +25 Chips | 5 to 7 |
| lucky_dice | +20 Chips | +15 Chips | 5 |
| penny_pincher | +2 Mult per 5 Tips | +1 Mult per 3 Tips | 6 to 7 |
| tab_regulars | +1 Chip per 2 Tips | +1 Chip per Tip | 5 |
| discard_special | +3 Mult per Discard left | +1 Mult per Discard left | 6 |
| spare_change | 2 Tips per Discard left | 1 Tip per Discard left | 6 |
| full_house_crowd | x1.2 per other Patron | x1.15 per other Patron | 8 |
| all_matching | +10 Mult | +18 Mult | 6 |
| straight_shooter | +12 Mult | +18 Mult | 6 |
| threes_company | +12 Mult | +18 Mult | 5 |
| house_special | +14 Mult | +22 Mult | 8 |
| all_hands_in | +10 Mult | +25 Mult | 7 |
| ace_of_the_house | +5 Mult per Ace | +8 Mult per Ace | 7 to 6 |
| jack_of_all_trades | +5 Mult per Jack | +9 Mult per Jack | 6 to 5 |
| queens_gambit | +5 Mult per Queen | +9 Mult per Queen | 6 to 5 |
| perfect_ten | +5 Mult per Ten | +8 Mult per Ten | 6 |

### Hands (`Scoring.lua`)

| Hand | Field | Old | New |
|---|---|---|---|
| Flush | base | 35 chips x 4 | 40 chips x 5 |
| Three of a Kind | per level | +20 chips, +2 mult | +25 chips, +3 mult |
| Straight | per level | +25 chips, +2 mult | +30 chips, +3 mult |
| Flush | per level | +20 chips, +2 mult | +25 chips, +3 mult |
| Full House | per level | +25 chips, +2 mult | +30 chips, +3 mult |

### Decks and House Passes

| Item | Field | Old | New |
|---|---|---|---|
| Steady Hand deck | discards per round | +1 | +2 |
| High Roller deck | starting Tips | 6 | 14 |
| High Roller deck | target | x1 | x0.9 |
| Late Kitchen pass | price | 10 | 5 |

## Where this differs from the plan

The plan's values were starting points, and these bots are stronger than the plan's: they use Recipes, rerolls and Patron swaps. On the plan's curve alone, decent won 42.6%, and 57.6% once the boss clamps were in.

- **Night-1 deaths could not be fixed by growth.** Only the starting target moves them, so base went from 100 to 65.
- **The win ratio needed discard-specific changes.** Decent has to win about twice as often as greedy, and curve changes move both together. Each of these favours the bot that discards: a higher Big Blind, Flush 40x5, 1 discard on Last Chance and Empty-Handed, a cheaper Late Kitchen, and weaker Discard Special and Spare Change, which paid most to a player who never discards.
- **A 4th base discard was tested and rejected.** It did not help the ratio.
- **The plan's Patron nerfs were not enough.** steady_hand at +12 was still 4.9x the median, so the outliers went further, often with a price rise. double_down stays at +10, not the plan's +14, because the Pair-based probe already rates it at 2.0x.
- **One at a Time needed x0.35, not x0.6.** At x0.6 it cleared only about 21% of the time.
- **Tags (section 4.6, optional) were not changed.**

### Exceptions to the Patron band

| Patrons | Reading | Why they are outside the check |
|---|---|---|
| threes_company, all_matching, straight_shooter, house_special | 0.20x to 0.41x | The probe is a Pair build, so these rarely trigger |
| all_hands_in | 0 | Four of a Kind never appears in the probe |
| double_down | 2.0x | The same probe favours it |
| the_apprentice, second_opinion | 2.92x, 1.54x | They copy a Patron from the probe's fixed table |
| the_understudy | 0 | Nothing sits to its right in the probe |
| curtain_call, repeat_customer | 0 | The probe doesn't set up their trigger |

Forced-ownership lift at 400 runs has a standard error near 2.4 points, and these all land within about 3.5 points of control. That shows none is a large outlier, but it does not prove any is well priced. The bots don't build around a hand type, so they can't fully test these Patrons.

## Supporting tables

### Boss clear rate

Each boss is forced on Night 6, 282 attempts each, decent bot. The all-boss average is 76.9%.

| Boss | Before | After | x average |
|---|---|---|---|
| one_at_a_time | 12.8% | 39.0% | 0.51 |
| everythings_out | 0.0% | 43.6% | 0.57 |
| bare_bones | 2.6% | 47.2% | 0.61 |
| big_tab | 5.1% | 49.3% | 0.64 |
| stale_bread | 2.6% | 57.4% | 0.75 |
| thin_chips | 17.9% | 60.3% | 0.78 |
| flat_mult | 17.9% | 60.3% | 0.78 |
| lights_out | 6.4% | 63.1% | 0.82 |
| four_top | 17.9% | 67.7% | 0.88 |

The other 26 bosses are at 0.91x to 1.23x. Before-numbers are 78 attempts each. wild_crowd is a Night-6 boss but among the easiest at 1.21x, so its tier may be worth a look.

### Decks and difficulty

Decent bot, win rate.

| Setting | Before (500 runs) | After (3,000 runs) |
|---|---|---|
| Standard deck | 0.0% | 12.7% |
| Steady Hand deck | 0.8% | 10.8% |
| High Roller deck | 0.2% | 15.0% |
| Marathon deck | 0.0% | 13.8% |
| Casual | 2.4% | 31.5% |
| High Stakes | 0.0% | 7.5% |

### Economy Patrons

Owned free from Night 1, 400 runs, against a control of 14.0%. The check is that Tips per run reach twice the price.

| Patron | Price | Tips per run | Win lift |
|---|---|---|---|
| tip_jar | 6 | 27.3 | +13.2 |
| big_spender | 7 | 23.8 | +14.2 |
| boss_bane | 7 | 21.6 | +13.0 |
| spare_change | 6 | 19.4 | +12.5 |
| rainy_day_fund | 6 | 15.6 | +7.0 |

nest_egg was tested on the banking bot, where it moved the win rate from 52.0% to 55.1% over 2,000 runs. That is about the size of the noise, so its value is unconfirmed. Tips are not tracked for it directly.

## Bugs found by this work

All are fixed, with tests, in their own commits.

- **Copying Patrons could loop forever.** The Understudy seated leftmost with Second Opinion on its right copied each other without end, which affects every scored hand with that seating.
- **Seeded runs rolled the shop voucher twice.** A failed seeded roll fell through to an unseeded one, so Daily, Weekly and Seed Code runs saw vouchers about 58% of the time instead of 35%, and their shops were not reproducible.
- **Crowd Favorite depended on table order** when two hands tied for most played.

Not fixed: `RunState.playHand` rolls Lucky and Brittle procs with `math.random`, not `state.rng`, so seeded runs are not fully reproducible. The sim works around this by reseeding `math.random` per run.

## Running the sim

Any Lua 5.3 interpreter works. `lua5.3` isn't installed on this machine and Homebrew no longer offers it, so these runs used TinyTeX's `texlua`, which is Lua 5.3. Parallel runs use the interpreter from `arg[-1]`, or `SIM_LUA` if set.

```sh
lua5.3 tools/run_tests_local.lua                 # engine tests
lua5.3 tools/test_sim.lua                        # sim checks
lua5.3 tools/run_sim.lua --ladder --runs 1000 --jobs 8
lua5.3 tools/run_sim.lua --variants --runs 1000 --jobs 8
lua5.3 tools/run_sim.lua --bosses --runs 300 --jobs 8
lua5.3 tools/run_sim.lua --patron-table
lua5.3 tools/run_sim.lua --patron-lift --runs 400 --jobs 8
```

The first 1,000 seeds are not a fair check of the final numbers: one candidate read 5.9% / 13.3% there but 7.6% / 11.9% on fresh seeds. Use at least 3,000 runs and a new `--seed` when judging a change.

## Ladder check, Nov 13 2026 (after the engine stabilization pass)

The simulator had been stopping with "Make room first" since the pack make-room rule went in (a bot with a full table opened a pack). `tools/sim/Sim.lua` now has the bot leave the pack in that case, so every mode runs again.

Quick ladder, 150 runs per bot, seed 1, one job (a small sample, so read it as a direction, not a final number):

| Bot | Target | Now | Before tonight's engine changes (same simulator) |
|---|---|---|---|
| random dies Night 1 to 2 | over 90% | 92.0% | 92.0% |
| greedy win | 2 to 6% | 20.0% | 22.0% |
| greedy median death | Night 5 to 6 | Night 7 | Night 7 |
| decent win | 12 to 20% | 33.3% | 37.3% |
| decent median death | Night 7 | Night 8 | Night 8 |

Reading (corrected, see "Build check, Nov 13 2026" below): the Target column is the old Phase 3 band and is not the yardstick. The last tuning was balance pass 3 on Nov 8, decent 29.0% on Regular. Against that the game is about 10 points easier, and it already was before the stabilization commits (the two engine columns agree within noise). The drift comes from content added since that tuning, almost all of it Patron Bonds. Nothing was retuned in this pass; pick the target first, then run `lua5.3 tools/run_sim.lua --ladder --runs 5000 --jobs 8` on fresh seeds.

Patron value table (`--patron-table`, score gain per Tip at mid-build, relative to the median Patron):
- Strongest: the_apprentice x2.97, pair_parade x2.70, double_down x2.37, suit_sampler x2.03.
- Weakest with a scoring effect: royal_road x0.01, flush_fan x0.03, full_suit_feast x0.03, kitchen_duo x0.04, stair_climber x0.04, triple_treat x0.08, long_road x0.10.
- Pattern: Patrons that reward Pairs sit at the top and Patrons that reward Flushes, Straights and Full Houses sit at the bottom, because the bots' mid-game hands are mostly Pairs. Corrected: that is the bots' habit, not a dominant line of play. They spend about 7 of the 70 discards a run offers and this table never discards at all. A player who spends discards plays Flush (`--chase-table`, "Build check" below).
- 28 Patrons show 0 in this table because their value is economy, scaling or utility, which this static measure does not see.

Rule change in this pass that touches scoring: five cards of one rank are now Four of a Kind with all five scoring (they used to fall through to High Card). There is still no Five of a Kind hand.

## Build check, Nov 13 2026

This section corrects the "Ladder check, Nov 13 2026" section where the two disagree. Two readings there were wrong.

The numbers in this section were measured on the engine at `f92c688` with this pass's changes applied (the Mac could not be reached that day). The stabilization commits after `f92c688` change no Patron, target or shop number, and the last subsection repeats the ladder on the real HEAD.

### 1. The yardstick was out of date

That section compared against the Phase 3 band (decent 12 to 20%). The last tuning was balance pass 3 on Nov 8 (`bb7558e`): decent 29.0% on Regular, falling to 6.0% on Legend, recorded in `claude/STATUS.md` and `tools/test_sim.lua`. Measured against that, the game is about 10 points easier on Regular, not twice as easy.

Where the 10 points came from. Each row is that commit's own engine and simulator on the same 600 seeds, decent bot, Regular:

| Change | Commit | Before | After |
|---|---|---|---|
| Patron Bonds added | `33d402d`, Nov 9 | 29.0% | 35.7% |
| Big round 2x to 1.5x | `2588e35`, Nov 11 | 35.7% | 35.7% |
| Crowded Counter lets 4 Patrons score (was 2); packs gained Make room and the Skip refund | `e3188cc`, `28c1f2d`, `51d6847`, Nov 12 | 35.7% | 39.5% |

The Big round change moved deaths from Big rounds to bosses without changing the win rate on those seeds. On today's code it is worth about 2 points (36.7% with a 2x Big round, 38.8% with 1.5x, 600 runs each). The three Nov 12 commits were not separated.

Nothing was retuned after Bonds went in. Whether to take those points back is a difficulty decision, listed under Open below.

### 2. "Pair builds dominate" described the bots, not the game

The decent bot discards only when its best play is behind pace. That is about 7 discards in a whole run (the builder bot, which discards on the same rule, logs 6.6) out of about 70 it could spend, and it judges every shop Patron on hands as dealt. It plays Pair or Two Pair on 59% of hands because that is what an undiscarded hand usually holds. `--patron-table` has the same blind spot: its fixed build is leveled in Pair and Two Pair and it never discards. So every Patron that pays for a Flush, a Straight or a Full House read as weak, and the Pair Patrons read as strong.

A player who spends their discards sees a different game (next section): Flush is the most common best hand even with nobody seated, and All Matching is the strongest 6 Tip Patron on every table tried.

### New tools

| Tool | What it does |
|---|---|
| `--chase-table` | Patron value for a player who spends discards. Plays the same fixed deals with each Patron added to a table, spending `--discards N` on each hand (default 2) the way the builder bot picks its draws, and reports the average hand, the gain and the hand type played most. `--build open` is Night 1 with nobody seated. `--build mid` seats The Regular and The Bard (they pay every hand the same) with every hand leveled twice. Economy Patrons, Patrons that grow over a run and Patrons that need a set-up read as zero. All Patrons take several minutes; `--patron-list ID,ID` limits the rows. |
| `--bot builder` | As decent (discards only when behind pace), but it picks the draw: it tries holding its best play, a Flush draw, a Straight draw, its pairs and its high cards on sampled redraws, and goes for whichever scores best with its own Patrons. |
| `hands played` and `draws chased` lines | Every full report shows the share of hands by type, and for the builder bot which draw each discard went for. |
| Bots know more Boss Rounds | The bots' play search uses `Engine/BossRules`, so they stop playing Flushes into Picky Eater and High Cards into Pair Patrol, count only 4 Patrons on Crowded Counter and halve the first hand on Sleepy Cook. Decent moved from 38.5% to 39.3% on the same 1,200 seeds. |

`tools/test_sim.lua` checks all four.

### What a player who discards sees

`--chase-table --runs 300`, numbers before this pass. Gain is the average hand with the Patron over the average hand without it.

| Average hand without the Patron | Night 1, nobody seated | Mid-build |
|---|---|---|
| 2 discards a hand | 334, mostly Flush (47% of hands) | 2,389, mostly Flush (34%) |
| 1 discard a hand | 261, mostly Flush (34%) | 2,090, mostly Flush (24%) |

Two discards a hand:

| Patron | Price | Opening gain | Mid-build gain | Plays mostly (opening) |
|---|---|---|---|---|
| all_matching | 6 | +289% | +57% | Flush 64% |
| house_special | 8 | +188% | +41% | Full House 41% |
| straight_shooter | 6 | +186% | +39% | Straight 51% |
| jack_of_all_trades | 5 | +179% | +29% | Flush 25% |
| threes_company | 5 | +168% | +36% | Full House 39% |
| pair_parade | 6 | +147% | +27% | Full House 40% |
| regulars_round | 5 | +128% | +23% | Full House 40% |
| steady_hand | 7 | +105% | +25% | Flush 36% |
| the_regular | 4 | +91% | (seated) | Flush 42% |
| ladder_builder | 6 | +90% | +17% | Straight 49% |
| double_down | 6 | +74% | +3% | Two Pair 76% |
| long_road | 6 | +60% | +16% | Straight 47% |
| triple_treat | 6 | +48% | +8% | Three of a Kind 43% |
| full_suit_feast | 8 | +35% | +26% | Flush 53% |
| all_hands_in | 7 | +33% | +8% | Flush 39% |
| twin_spoons | 5 | +29% | +1% | Two Pair 68% |
| flush_fan | 6 | +27% | +11% | Flush 53% |
| color_matcher | 5 | +16% | +9% | Flush 50% |
| big_portions | 7 | +10% | +6% | Flush 39% |
| stair_climber | 6 | +9% | +4% | Flush 34% |
| kitchen_duo | 6 | +9% | +6% | Flush 39% |
| foursome_table | 8 | +6% | +7% | Flush 44% |
| lucky_dice | 5 | +5% | +6% | Flush 43% |
| royal_road | 8 | +2% | +4% | Flush 42% |

Reading it:

- The Mult piece for each big hand is strong (All Matching, Straight Shooter, House Special, Three's Company). Those were raised in Phase 3 because the Pair probe never triggered them. For a player who discards, All Matching is the best 6 Tip Patron by a wide margin. It also leads with one discard a hand (+235% opening, +38% mid-build, against Pair Parade's +153% and +27%).
- The Chips piece for the same hands was close to worthless. Stair Climber added 4% at mid-build against Straight Shooter's 39% for the same 6 Tips. A Sweet Garnish on a single card is also +30 Chips.
- Royal Road sat at the bottom of the table, and it is a four-win unlock that costs 8.
- So a Straight or Full House build had one good piece and nothing worth a second seat.

### Changes

Five Patrons, number and card text together. Nothing was lowered.

| Patron | Old | New | Opening gain | Mid-build gain |
|---|---|---|---|---|
| flush_fan | +30 Chips | +80 Chips | +27% to +76% | +11% to +32% |
| stair_climber | +30 Chips | +80 Chips | +9% to +28% | +4% to +26% |
| kitchen_duo | +40 Chips | +100 Chips | +9% to +29% | +6% to +24% |
| long_road | +8 Mult | +12 Mult | +60% to +110% | +16% to +23% |
| royal_road | x1.5 Mult | x2 Mult | +2% to +9% | +4% to +11% |

Why these numbers:

- Each Chips piece still sits below the Mult piece for the same hand on both tables, so the order a player learns (Mult first, Chips second) holds. A test pins the opening order for Flush and Straight.
- Stair Climber stops at +80 because of Bonds. At +100 the Bond with Straight Shooter lifted a plain Straight by 10.2%, over the 10% line the Bonds balance test holds on everyday hands.
- Royal Road stops at x2 for the same reason. A Bond adds 7% of an x-Mult above 1 as a further multiplier, so x3 meant a 20.5% Bond lift on an Ace Straight. At x2 the largest Bond lift anywhere is 13.1% (Straight Shooter with Royal Road on an Ace Straight). Before this pass it was 12.9% (All Hands In with Foursome Table on Four of a Kind). The new test pins 14% for rare hands.

### Ladder after the change

Fresh seeds 3100001+, final simulator.

| Bot | Runs | Win | Median death | Night 1 deaths |
|---|---|---|---|---|
| random | 600 | 0.8% | Night 1 | 83.3% (88.8% by Night 2) |
| greedy | 1,200 | 18.5% | Night 7 | 6.7% |
| decent | 1,200 | 39.3% | Night 8 | 0% |
| builder | 1,200 | 42.8% | Night 8 | 0% |

The five changes do not move the ladder: decent on the same 1,200 seeds was 39.7% with the old numbers and 39.3% with the new ones (standard error 1.4). These bots rarely own the changed Patrons.

Decent by stake, 600 runs each, seeds 1+:

| Stake | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 |
|---|---|---|---|---|---|---|---|---|
| Nov 13 | 40.3% | 33.7% | 28.3% | 24.0% | 20.2% | 19.2% | 12.2% | 10.7% |
| Pass 3, Nov 8 | 29.0% | 26.3% | 23.0% | 20.2% | 16.5% | 12.8% | 7.0% | 6.0% |

Where the decent bot dies on Regular, share of all runs: Nights 1 to 5 together 1.9%, Night 6 10.8%, Night 7 23.5%, Night 8 24.4%, and 90% of deaths are on a Boss Round. For a bot that always finds its best hand, the first five Nights are close to free and the run is decided by the last three bosses. Real new players are far less efficient than that, so this says more about practiced players than about a first session.

### Open

1. **Difficulty on Regular.** Bonds made the game about 7 points easier and nothing was retuned. Leaving it is defensible for new players. Taking it back is one number. Decent on the same 600 seeds: 40.3% today, 30.3% with target growth 2.2 instead of 2.15 (pass 3 was 29.0%), 22.7% with 2.25, and 34.7% with the Bond bonus halved (`Bonds.RATIO` 0.035). Not changed here.
2. **Flush is the default line for a player who discards**, and All Matching is ahead of every other 6 Tip Patron. If Flush turns out to be the only build testers play, the lever is All Matching's number: at +14 it sits level with its siblings at mid-build (+42%, against Straight Shooter's +39% and House Special's +41%) and still opens strongest (+223%). Lowering the Flush base from 40 x 5 to 35 x 5 changes little (Flush share at opening 47% to 41%, All Matching still +285%). Not changed here; it needs real players first.
3. **Royal Road is still near the bottom** at x2. The Ace rule is the limit, not the number. "x2 Mult if a Straight has a face card or an Ace" measured about +30% opening and +34% at mid-build, which is where an 8 Tip unlock belongs. That is a rule change, so it waits for a yes.
4. **Other low rows**, not touched: triple_treat (+12 Mult, beaten by threes_company at +18 for 1 Tip less), twin_spoons and double_down at mid-build, foursome_table and all_hands_in (Four of a Kind is too rare to build on), lucky_dice, big_portions, color_matcher. Lucky Dice and Big Portions were lowered in Phase 3 on the Pair probe's reading, which over-read them.
5. **The bots still cannot commit to a build in the shop.** They judge Patrons on hands as dealt and level the hand they play most, so every bot drifts to Two Pair whatever it is given. Run-level win rates therefore cannot yet say whether a committed Flush table beats a committed Straight table; the chase table is the evidence for that. Two things were tried and dropped in this pass. A bot that spent discards on every hand won less than one that plays to pace (33% against 39% on fresh seeds), probably because a discard spent early in a round cannot rescue a bad hand later in it. A shop policy that judged Patrons on hands the bot could reach made it worse still (27%), probably because picking the best of several sampled draws flatters every Patron that needs a draw.

### Later the same day: changes that do not move the ladder

Each was measured on the same engine with the change applied.

- **Last Chance and Empty Handed leave one discard on every stake.** Their cards say "only 1 discard", and from the Busy Night stake up the player had none. Decent bot on stakes 2, 4, 6 and 8, 600 seeds each: 33.7%, 23.8%, 18.8%, 10.8%, against 33.7%, 24.0%, 19.2%, 10.7% before.
- **Patron card audit.** Three's Company fires on Four of a Kind (its card says "contains a Three of a Kind"). Five cards that said "a Pair (or better)" say "contains a Pair" now, with no rule change. On the same 1,200 seeds as the build check: decent 39.4% (39.3% before), builder 42.7% (42.8% before).
- **The hand preview is engine code now** (`Engine/HandPreview`), so the number shown before a play is the number paid. No score changes.

`tools/run_fuzz.lua` is new: random runs with invariants checked after every action. First full run: 12,000 runs, 1.3 million actions, every Boss Round and every Recipe, 0 findings, and 220,943 previews equal to their plays.

### Re-measured on HEAD, Nov 14 2026

Everything above was applied to the repository on Nov 14 (commit `ec58eec`) and the ladder was run again on that tree, with its own simulator.

Decent by stake, 600 runs each, seeds 1+:

| Stake | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 |
|---|---|---|---|---|---|---|---|---|
| HEAD, Nov 14 | 37.5% | 32.7% | 29.8% | 23.3% | 20.7% | 17.3% | 12.5% | 11.7% |
| Sandbox, Nov 13 | 40.3% | 33.7% | 28.3% | 24.0% | 20.2% | 19.2% | 12.2% | 10.7% |
| Pass 3, Nov 8 | 29.0% | 26.3% | 23.0% | 20.2% | 16.5% | 12.8% | 7.0% | 6.0% |

Fresh seeds 3100001+, 1,200 runs each: random 1.1% (dead by Night 1 in 83.5% of runs, by Night 2 in 89.2%), greedy 19.1%, decent 39.2%, builder 43.3%.

The two rows agree within the noise of 600 runs (about 2 points either way). HEAD rolls a seeded run's luck from the run's own rng, so the same seed is not the same run as in the sandbox. The reading stands: about 8 to 10 points easier on Regular than at pass 3, and the difficulty decision under Open is unchanged.
