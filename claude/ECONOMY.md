# Economy check: a week of 20 minute sessions

Simulated by `src/Shared/Engine/EconomySim.lua` through the real Daily chest ladder, Daily quests, run XP and Season XP. Reprint with `lua tools/economy_report.lua [startDay]`. A test (`Economy week`) pins the floors below.

Session model: two runs, each 12 hands, 4 rounds cleared, 1 Boss Round, Night 3 reached, one Pack, one House Pass, one Recipe, no win. Tips are Tips banked for the next run (chest, quests); in-run Tips never leave the run. Season XP only counts inside a running Season.

Week of 2026-11-23 (the Harvest Moon Season):

| Day | Chest | Quests done | Tips banked | Rank XP | Season XP |
| --- | --- | --- | --- | --- | --- |
| 1 | 3 Tips | 2 | 16 | 294 | 294 |
| 2 | 40 XP | 2 | 4 | 254 | 214 |
| 3 | 5 Tips | 2 | 18 | 234 | 234 |
| 4 | 60 XP | 3 | 9 | 384 | 324 |
| 5 | 6 Tips | 3 | 17 | 264 | 264 |
| 6 | 80 XP | 3 | 11 | 354 | 274 |
| 7 | Card back: Festival Ribbon | 3 | 7 | 284 | 284 |
| Week | | | 82 | 2068 | 1888 |

## Findings
- Rank XP and Season XP stay level: every day lands between 234 and 384 XP, so no day is over 3x or under a third of the others.
- Tips: days with an XP chest (2, 4, 6) bank fewer Tips because the chest pays none, and a day that rolls two cheap quests can land under a third of a three quest day (4 against a mean of 13 on day 2; about one week in four shows one such day). No day is ever over 3x.
- Nothing here is pay to win or random for Robux: chest, quests and XP all come from play and the daily login only.
- A 20 minute session gains about 2 ranks a day early on (rank 2 needs 80 XP, each rank 20 more) and the Season ladder (90 XP per tier, 30 tiers) finishes in about 10 sessions of this size, which fits a 30 day Season with room to skip days.

## Change made
None. The only outlier is Tips on a day with an XP chest and two cheap quests. It comes from which quests were rolled, not from a wrong value, and raising quest Tips would lift every day instead of closing the gap. The test pins a floor of 2 Tips and 150 XP per day instead.

## Night 1 to 8 win rates (sim, 100 runs, seeds 1 to 100)
Full table in BALANCE-REPORT.md. Bots: random, greedy, decent (legal-hand bots at three skill levels).
- Before: decent bot cleared Nights 1 to 3 in 300 of 300 runs; greedy cleared Night 2 in 92% and Night 3 in 89% of runs.
- Change: Night 2 base target x1.12 and Night 3 x1.2 (RunState NIGHT_TUNE). Night 1 (WelcomeEase) and Night 4 on are unchanged.
- After: greedy clears Night 2 in 85% and Night 3 in 80%; random 15% / 8% / 5% for Nights 1 to 3; decent still clears Nights 1 to 3 every run but with scores 236% and 206% of target (was 263% and 246%). The bots see every hand, so a new player lands lower.

## Night 5 to 8 and Boss Rounds (sim, 100 runs, seeds 1 to 100, `lua tools/balance_nights.lua 100 1`)
Clear rate of the whole Night (all runs) and of its Boss Round (of those who faced it):

| Night | Random | Greedy | Decent | Boss: greedy | Boss: decent |
| --- | --- | --- | --- | --- | --- |
| 5 | 3% | 66% | 97% | 90% | 98% |
| 6 | 1% | 56% | 83% | 90% | 87% |
| 7 | 1% | 35% | 69% | 67% | 86% |
| 8 | 1% | 22% | 45% | 67% | 67% |

- Whole run win rate: random 1%, greedy 22%, decent 45%. Difficulty rises steadily and no Night is trivial or impossible for the greedy and decent bots, so no target changed.
- Boss Rounds are not the wall: Night 7 and 8 Bosses clear 67% for greedy while the whole Night clears less often, so the plain rounds do most of the damage. Night 5 is the easiest late Night for the decent bot (180% of target).
- The report now has a Boss Round column per Night (NightTable counts boss rounds).

## Patron and Counter price fairness (sim, 60 runs, decent and builder bots, `lua tools/_probe_shop_econ.lua`)
Tips on arrival at each Counter visit (average, min):

| Visit | Avg Tips | Min | Visits where nothing is affordable and no reroll |
| --- | --- | --- | --- |
| Night 1 Round 1 | 4.0 | 4 | 44 of 60 |
| Night 1 Round 2 | 6.8 | 4 | 12 |
| Night 1 Round 3 | 9.9 | 8 | 0 |
| Night 2 Round 1 | 6.9 | 4 | 3 |
| Night 2 Round 2 | 6.5 | 4 | 8 |
| Night 2 Round 3 | 11.1 | 8 | 0 |
| Night 3 Round 1 | 7.1 | 4 | 6 |
| Night 3 Round 2 | 7.5 | 4 | 8 |

- A first run can afford a Patron by Night 2: the cheapest Patron costs 4 and the bots bought 5.4 Patrons per run on average, so every Night 2 Round 1 visit holds at least 4 Tips.
- Never stuck: the shop only costs Tips, hands and discards come from the round, so 0 Tips never removes a hand. The first visit of a run often shows only 5 to 7 Tip Patrons against 4 Tips; the next visit fixes it, so the Night 1 Round 3 visit is never a dead shop.
- Change made: none. A 15 percent move on a 4 Tip price or the 4 Tip start rounds back to the same whole number, so no price or reward changed. The existing price range test stays and a new test pins the cheapest Patron at or under the first round win.

## Run variety: 200 seeds with random Patron picks (2026-11-22)
`lua tools/run_sim.lua --combos --bot decent --runs 200 --seed 1 --jobs 4` buys whatever Patron is on offer in random order (no value judgement, no selling) and counts the final seats.
- Win rate with random picks: 17.5 percent (the value picking bot wins far more, so Patron choice matters).
- Most picked Patrons: queens_gambit 28 runs (17.9 percent win), rising_dough 23 (34.8), summit_guide 23 (17.4), tip_jar 23 (30.4), all_matching 22 (18.2).
- Best looking: rising_dough and tip_jar at 30 to 35 percent, far below 90. No Patron and no pair with at least 5 runs wins more than 90 percent, so no Patron numbers changed. Pairs are thin at 200 runs (no pair seen more than 6 times); raise --runs for pair detail.

## Night 4 to 8 clear rate per Patron count (`--late`)
`lua tools/run_sim.lua --late --runs 200 --bot decent` starts at Night 4 with 3, 4 or 5 random Patrons and prints the share of runs that cleared each Night after entering it.

| Patrons | N4 | N5 | N6 | N7 | N8 |
|---|---|---|---|---|---|
| 3 before tune | 86.0% | 89.0% | 66.7% | 57.8% | 42.4% |
| 4 before tune | 91.5% | 89.1% | 71.2% | 55.2% | 64.1% |
| 5 before tune | 93.0% | 91.9% | 73.1% | 64.8% | 54.3% |
| 3 after | 86.0% | 82.0% | 63.8% | 51.1% | 45.7% |
| 4 after | 89.0% | 86.5% | 75.3% | 64.7% | 53.3% |
| 5 after | 91.0% | 91.8% | 74.9% | 60.0% | 48.0% |

Nothing is under 25%. Night 4 and 5 were over 85% for a 4 Patron build, so their base targets got one 10% step (`NIGHT_TUNE` 1.1 in RunState, pinned by test). They still sit a little over 85%: the sim hands out free Patrons, so a real first build is weaker. No second step taken.

## Endless Nights 9 to 15 (`lua tools/run_sim.lua --endless --max-night 30 --runs 600 --jobs 4`, decent bot, random Patrons)
A good run (one that clears Night 8) should end between Night 10 and 14. Only 94 of 600 runs get past Night 8; the table is the clear rate per Night among runs that entered it.

| Endless growth per Night | Median Night (runs past 8) | N9 | N10 | N11 | N12 | N13 | N14 | N15 |
|---|---|---|---|---|---|---|---|---|
| 2.15 (before, 200 seeds) | 9 | 28.6% | 20.0% | 0.0% | 0.0% | 0.0% | 0.0% | 0.0% |
| 1.5 (now) | 10 | 57.4% | 48.1% | 61.5% | 62.5% | 50.0% | 40.0% | 50.0% |

Nights 9 and up multiply Night 8's base score by 1.5 per Night (RunState ENDLESS_NIGHT_GROWTH); Nights 1 to 8 are unchanged. 1.6 left the median at 9, 1.4 also gave 10, so 1.5 is the gentlest step in band. Pinned by a test. The median over all runs stays Night 7 because most runs end before Night 8.

## First run pacing, Nights 1 to 3 (`lua tools/run_sim.lua --pacing --runs 200 --jobs 4 --bot decent`)
Welcome ease on (Nights 1 and 2 targets x0.85), 200 seeds, a bot that always plays its best legal hand.

| Night | Hands per round | Discards per round | Night clear |
|---|---|---|---|
| 1 | 1.47 | 0.07 | 100.0% |
| 2 | 1.41 | 0.08 | 100.0% |
| 3 | 1.50 | 0.11 | 100.0% |

The `builder` bot gives the same numbers. A bot that plays random cards (`--bot random`, a floor, not a player) clears 27 / 16 / 9 percent with 3.3 / 2.6 / 2.6 hands per round.
Night 1 is over the 90 percent goal. Night 3 is at 100 percent, above the 60 to 85 percent band, but WelcomeEase only touches Nights 1 and 2 and can only make targets easier, so no WelcomeEase number was changed. The best-play bot is stronger than a new player, and Night 3 was already raised 20 percent. If real first runs show Night 3 as too easy, that is a Night 3 target step (NIGHT_TUNE), a design call for the user.

## Patron balance: clear rate per Patron (`lua tools/run_sim.lua --patron-rates --runs 800 --bot decent --jobs 4`)
800 random builds of 4 Patrons start at Night 4 and play to Night 8. Each Patron is scored by the share of Night 4 to 8 rounds cleared by builds that started with it. The average is 92.4 percent. Each Patron appears in 27 to 46 builds, so one Patron's number carries about 2 points of noise.

| Patron group | Clear rate | vs average |
|---|---|---|
| Best 5 (full_house_crowd, good_company, rising_dough, tip_jar, vip_table) | 94.4 to 95.2% | +2.0 to +2.8 |
| Middle 70 or so | 90.5 to 93.6% | -1.9 to +1.2 |
| Worst 3 (second_opinion, color_matcher, long_road) | 89.7 to 90.2% | -2.2 to -2.7 |

No Patron is more than 15 points from the average (the widest gap is 2.8). Builds are random, so every Patron appears in about the same share of builds; none is picked under 5 or over 40 percent. No Patron number or price changed. Round clear is a gentle measure; the `--late` table above shows the per Night picture.

## Shop economy: Tips against Patron prices, Nights 1 to 8 (`lua tools/run_sim.lua --shop-econ --runs 200 --bot decent --jobs 4`)
Tips on arrival at each Counter visit and Patrons already held on arrival, 200 seeds (runs that reach the visit).

| Visit | Avg Tips | Patrons held | | Visit | Avg Tips | Patrons held |
|---|---|---|---|---|---|---|
| N1 R1 | 4.0 | 0.00 | | N5 R1 | 8.8 | 5.11 |
| N1 R2 | 6.8 | 0.05 | | N5 R3 | 12.0 | 5.13 |
| N1 R3 | 10.1 | 0.69 | | N6 R1 | 8.6 | 5.16 |
| N2 R1 | 7.5 | 1.65 | | N6 R3 | 12.0 | 5.18 |
| N2 R3 | 10.8 | 3.10 | | N7 R1 | 9.1 | 5.21 |
| N3 R1 | 8.0 | 4.07 | | N7 R3 | 12.0 | 5.25 |
| N3 R3 | 11.9 | 4.80 | | N8 R1 | 9.1 | 5.28 |
| N4 R1 | 8.8 | 5.00 | | N8 R2 | 8.9 | 5.31 |

- Never a dead shop: the lowest average on arrival is 4.0 (the Night 1 start, exactly the cheapest Patron), and every later visit averages 6.8 or more.
- Patrons by Night 4: the bot holds 5.0 on arrival, above the 2 to 3 target. By Night 8 it holds about 5.3 (the seat limit is 5, extra seats come from a voucher), which is the 4 to 5 target.
- Why no change: the bot buys every affordable Patron on sight and never keeps Tips back, so it fills the 5 seats by Night 3. A real player picks and saves, and the first visit of a run is exactly 4 Tips with the cheapest Patron at 4, so lowering the round Tips payout or raising rerolls by even one Tip would make the first shops dead or the Night 1 buy impossible. The 5 seat cap, not income, is what bounds Patron count, so nothing here makes later Nights richer. No payout or reroll number changed. If real players show Night 4 with 5 Patrons, the lever is seat count or Patron price, a design call.

## Quests: can a 20 minute session finish each one?

`lua tools/quest_report.lua` (Engine/EconomySim `questReport`, pinned by the test `Quests: every daily quest finishes in 3 runs or fewer`). The session model is two runs of 12 hands, 5 discards, 4 rounds, 1 Boss Round, Night 3, one Pack, one House Pass, one Recipe. A session is 2 runs, so a quest that needs 3 runs or fewer is finishable in one or two sittings.

| Quest | Counter | Goal | Per model run | Runs to finish |
| --- | --- | --- | --- | --- |
| pairs_3 | pairs | 3 | 4 | 1 |
| flush_clear | flushWins | 1 | 0 | by play (goal 1) |
| buy_pack | packs | 1 | 1 | 1 |
| discard_5 | discards | 5 | 5 | 1 |
| boss_win | bosses | 1 | 1 | 1 |
| hands_10 | hands | 10 | 12 | 1 |
| straight_play | straights | 1 | 1 | 1 |
| full_house_play | fullHouses | 1 | 0 | by play (goal 1) |
| trips_play | trips | 2 | 1 | 2 |
| big_swing | bigHands | 1 | 0 | by play (goal 1) |
| tips_left | richClears | 1 | 1 | 1 |
| quick_win | quickClears | 1 | 0 | by play (goal 1) |
| buy_pass | housePasses | 1 | 1 | 1 |
| use_recipe | recipes | 1 | 1 | 1 |
| discard_cards_10 | cardsDiscarded | 10 | 10 | 1 |
| boss_streak | bosses | 2 | 1 | 2 |
| hands_15 | hands | 15 | 12 | 2 |
| reach_night_3 | night | 3 | 3 | 1 |
| rounds_5 | rounds | 5 | 4 | 2 |
| pairs_8 | pairs | 8 | 4 | 2 |
| discard_8 | discards | 8 | 5 | 2 |
| straight_2 | straights | 2 | 1 | 2 |
| packs_2 | packs | 2 | 1 | 2 |
| rounds_3 | rounds | 3 | 4 | 1 |

Result: no quest needs more than 2 runs, so no goal was lowered and no Tips or XP reward changed. Four quests (Flush Finish, Full House Party, Big Swing, Swift Win) depend on the hand you draw, not on volume. Their goal is already 1 and cannot go lower, so a player gets them by play. The model run earns none of those four, so the table calls them "by play".

## Patron offers: repeats, owned and dead picks

`lua tools/run_sim.lua --offers --runs 200 --jobs 4` (decent bot, first Patron roll of every Counter visit, Night 1 to 8). "same offer" is the exact same Patrons as the previous visit, "any repeated" is at least one Patron seen on the previous visit, "nothing affordable" is a visit where every offer cost more than the Tips on hand although a cheaper Patron existed in the pool (a picker fault). "poor" is a visit where Tips were under the cheapest Patron of the whole pool, which no picker can fix.

Before the fix (one combined count, 4362 visits): repeats 3.2 percent, owned 0.0 percent, nothing affordable 28.2 percent.

After (4262 visits):

| Night | visits | same offer | any repeated | owned | nothing affordable | poor |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | 600 | 0.0% | 2.8% | 0.0% | 0.0% | 33.3% |
| 2 | 600 | 0.0% | 3.0% | 0.0% | 0.0% | 17.2% |
| 3 | 600 | 0.0% | 2.5% | 0.0% | 0.0% | 12.6% |
| 4 | 600 | 0.0% | 3.0% | 0.0% | 0.0% | 9.1% |
| 5 | 595 | 0.0% | 2.2% | 0.0% | 0.0% | 0.0% |
| 6 | 562 | 0.0% | 3.7% | 0.0% | 0.0% | 0.0% |
| 7 | 465 | 0.0% | 3.4% | 0.0% | 0.0% | 0.0% |
| 8 | 240 | 0.0% | 5.0% | 0.0% | 0.0% | 0.0% |
| all | 4262 | 0.0% | 3.1% | 0.0% | 0.0% | 23.3% |

- Repeats (3 percent) and owned Patrons (0 percent, the picker already skips them) are under the 10 percent line, so the picker is unchanged for those.
- Dead picks were the problem: when a seat was free and nothing offered fit the Tips on hand, the shop could still show two Patrons the player could not buy. `Shop.rollOffers` now swaps the last offer for a random Patron that fits when one exists. A full table is left alone. Prices are untouched and nothing is paid for. Pinned by the test `Shop offers: never a Patron already owned, never a dead pick`.
- The "poor" column is the economy, not the picker (see also the Boss rules section below): the bot spends everything on sight, so early second and third visits arrive under 4 Tips. See the shop economy section above; no number changed.

## Boss rules: clear rate per boss on Nights 3, 6 and 9

`lua tools/run_sim.lua --boss-rules --runs 400 --jobs 6` (decent bot, full runs with random Patron buys, the boss forced on that Night; the cell counts only runs that reached the boss, shown as n). About 30 minutes. A start at the Night with 4 fresh Patrons was tried first and rejected: it skips the shop visits and hand levels a real run has, so every boss read 0 to 25 percent whatever its rule.

Clear rate before the change (n = 400 on Night 3, 353 on Night 6, 45 on Night 9):

| Boss | Night 3 | Night 6 | Night 9 |
| --- | --- | --- | --- |
| bouncer | 100.0 | 66.3 | 57.8 |
| short_notice | 100.0 | 76.8 | 68.9 |
| house_rules | 100.0 | 61.8 | 42.2 |
| the_tab | 100.0 | 83.6 | 71.1 |
| thin_soup | 100.0 | 70.5 | 48.9 |
| slow_simmer | 100.0 | 70.5 | 48.9 |
| rowdy_crowd | 100.0 | 85.3 | 75.6 |
| no_repeats | 100.0 | 70.5 | 55.6 |
| hearts_are_out | 100.0 | 75.6 | 64.4 |
| spades_are_out | 100.0 | 77.9 | 62.2 |
| no_vips | 100.0 | 75.9 | 68.9 |
| empty_pockets | 100.0 | 83.6 | 71.1 |
| full_table | 100.0 | 87.0 | 75.6 |
| last_chance | 99.5 | 71.1 | 60.0 |
| short_staffed | 99.2 | 61.2 | 55.6 |
| diamonds_are_out | 100.0 | 75.6 | 66.7 |
| clubs_are_out | 100.0 | 75.9 | 64.4 |
| steep_tab | 100.0 | 83.6 | 71.1 |
| thin_chips | 100.0 | 49.3 | 24.4 |
| flat_mult | 100.0 | 49.3 | 24.4 |
| double_tab | 100.0 | 73.4 | 53.3 |
| lights_out | 99.2 | 62.6 | 44.4 |
| quick_service | 100.0 | 69.1 | 51.1 |
| stale_bread | 100.0 | 44.5 | 15.6 |
| one_at_a_time | 100.0 | 56.9 | 80.0 |
| big_tab | 99.8 | 37.4 | 8.9 |
| wild_crowd | 100.0 | 88.4 | 68.9 |
| empty_handed | 98.8 | 52.7 | 42.2 |
| everythings_out | 99.8 | 32.3 | 8.9 |
| four_top | 99.5 | 63.5 | 46.7 |
| slow_night | 100.0 | 84.7 | 66.7 |
| house_minimum | 100.0 | 73.9 | 53.3 |
| picked_over | 99.8 | 59.2 | 53.3 |
| rushed_order | 100.0 | 71.4 | 48.9 |
| bare_bones | 99.8 | 35.4 | 8.9 |
| sleepy_cook | 100.0 | 63.5 | 48.9 |
| cold_start | 100.0 | 83.6 | 71.1 |
| pair_patrol | 100.0 | 82.7 | 66.7 |
| heavy_hands | 100.0 | 83.6 | 71.1 |
| quiet_corner | 99.8 | 71.7 | 66.7 |
| picky_eater | 100.0 | 66.3 | 51.1 |
| crowded_counter | 100.0 | 65.4 | 33.3 |
| penny_wise | 100.0 | 83.6 | 71.1 |

- Night 3 is 98.8 to 100 percent for every boss. That is the welcome ramp (Night 3 clears 100 percent in the pacing sim), not a boss problem, so it was left alone; raising 40 boss numbers to push Night 3 under 95 would undo it.
- Night 9 reads only 45 runs per boss (few runs get there), so its cells move by about 7 points per run and were not used for changes. They still show the same three Night 6 outliers plus thin_chips, flat_mult, stale_bread and crowded_counter low; worth a re-run with more seeds if Night 9 feels brutal.
- Night 6 under 40 percent: big_tab 37.4, bare_bones 35.4, everythings_out 32.3. Each got its own number eased by one step: Big Tab target 2.0x to 1.9x ("nearly double"), Everything's Out 0.68 to 0.70 (cut 30 percent), Bare Bones 0.70 to 0.72 (cut 28 percent). The order Stale Bread 0.75, Bare Bones, Everything's Out still holds.
- After, Night 6: big_tab 40.5, bare_bones 39.1, everythings_out 35.4, stale_bread 44.5 (unchanged). Everything's Out is still 4.6 under the line and Bare Bones 0.9 under (inside sampling noise); one more step would squeeze the three tier 3 cuts into 25, 28 and 30 percent apart, so I stopped at one step. Needs the user only if they want Everything's Out higher: a further step to 0.72 means rebalancing Bare Bones and Stale Bread too.
- Pinned by the test `Boss rule sim pin` plus the updated Everything's Out, Bare Bones and boss target tests.
