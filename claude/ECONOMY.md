# Economy check: a week of 20 minute sessions

Simulated by `src/Shared/Engine/EconomySim.lua` through the real Daily chest ladder, Daily quests, run XP and Season XP. Reprint with `lua tools/economy_report.lua [startDay]`. A test (`Economy week`) pins the floors below.

Rank rewards (30 ranks, pinned by a test): ranks have no names of their own, the names players see are the five reward titles (rank 5 Table Regular, 10 Favorite Guest, 15 House Captain, 20 Hall Warden, 30 Grand Host), all unique and kid safe. Card backs at ranks 4, 8, 14 and 23, Card Sets at 12 (winter_evening) and 24 (festival_night). Tips for the next run climb 3, 3, 4, 4, 5, 5, 5, 6, 6, 7, 7, 7, 7, 8, 8, 10, 10, 10, 115 in total and never fall from one Tips rank to the next. Audit fix: ranks 19, 28 and 29 used to dip (6, 9, 9) and are now 7, 10, 10. XP per rank is 80 for rank 1 to 2, then 20 more each rank.

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

## Endless curve, Night 7 to 20, three bots

`lua tools/run_sim.lua --endless --max-night 20 --runs 600 --bot <random|greedy|decent>` (random Patron buys, Night clear rate among runs that entered the Night; "in" is how many runs got there).

| Bot | median Night | past Night 8 | Night 7 | 8 | 9 | 10 | 11 | 12 | 13 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| random | 3 | 3 of 600 | 50.0 (in 24) | 25.0 (12) | 0.0 (3) | none | | | |
| greedy | 6 | 30 of 600 | 47.5 (179) | 35.3 (85) | 43.3 (30) | 38.5 (13) | 20.0 (5) | 0.0 (1) | none |
| decent | 7 | 72 of 600 | 48.8 (361) | 40.9 (176) | 44.4 (72) | 50.0 (32) | 31.2 (16) | 60.0 (5) | 33.3 (3) |

- Nothing is free for a bad bot: the random bot never clears Night 9 and none of its runs reach Night 10. A good bot is not walled: the decent bot clears Nights 9 to 13 between 31 and 60 percent. Night 14 and later had 1 run or none, so those cells say nothing; the curve there is the 1.5x per Night growth from the earlier Endless task.
- No number changed. The test `Endless curve Night 7 to 20` pins that every round target grows with the Night, the boss round stays above round 2, and the base grows 1.5x per Night from Night 10 on.

## Daily twists: win rate against the no twist baseline

`lua tools/run_sim.lua --daily-twists --runs 500 --jobs 4` (decent bot, same 500 seeds for every row, standard run to Night 10). Baseline with no twist: 42.2 percent. The band is 15 points either way (27.2 to 57.2).

| Twist | win | vs base |
| --- | --- | --- |
| short_hands | 45.2 | +3.0 |
| golden_start | 51.8 | +9.6 |
| extra_seat | 50.2 | +8.0 |
| big_box | 42.2 | +0.0 |
| loud_crowd | 52.2 | +10.0 |
| spare_cards | 47.8 | +5.6 |
| quick_deal | 50.4 | +8.2 |
| wide_table | 38.4 | -3.8 |
| penny_pincher | 42.4 | +0.2 |
| solo_star (before) | 0.0 | -42.2 |
| solo_star (after) | 30.8 | -11.4 |
| thrifty_table | 47.4 | +5.2 |
| steady_hands | 51.8 | +9.6 |

- Solo Star was the one outlier: one Patron seat at 2x was worth far less than the 4 to 5 seats a normal run builds, so nobody won (0 of 500). Tried 3.5x (1.3 percent), 4x with +1 Hand and Discard (2.3), 4x with +2 and +2 and one more card (11.0), then 4x with +3 Hands, +4 Discards, +1 card and 8 start Tips: 30.8 percent. Its plate line now reads "One seat, effect counts 4x, +3 Hands, +4 Discards, +8 Tips." (60 characters or less; it still needs a look on the Menu plate at 800x450). Pinned by the test `Daily twists balance pin`.
- Found by this sim and fixed: Loud Crowd, Penny Pincher and Solo Star multiplied Patron Tips bonuses and left fractional Tips (2 x 1.25 = 2.5), which crashed `%d` text in Recipes (Tip Doubler) and would show wrong numbers elsewhere. A Patron's Tips bonus is now floored in `Scoring.calculate`. Test `Daily twists: Patron power twists never leave fractional Tips`.

## Hand level cost, reroll cost and Patron sell value

Baseline sim (`lua tools/run_sim.lua --runs 600 --jobs 4 --bot decent`): win 43.2 percent, median Night 8, Tips at the Counter mean 8.8 (median 8), 4.78 hand levels and 0.15 rerolls per run.

- Hand levels: every level Recipe costs 3 Tips, the same at every level and for all 9 hands (`Recipes.MenuRecipes`). The first Counter visit has at least 4 Tips, so one level is always affordable and a run is never stuck; the bot buys about 0.7 levels per Night because it spends on Patrons and Packs first. Cost kept flat. Pinned by the test `Hand level and reroll cost curves`.
- Reroll cost: 5, 7, 9, 11 ... (base 5, +2 per reroll in a visit). The first reroll costs more than a round win pays (4), so it is a choice, and the bot uses 0.15 a run. Frequent Visitor and Bargain Hunter lower it but `RunState.rerollCost` floors it at 1 Tip, so it is never free. No change.
- Patron sell value: half the list price rounded down. A lasting discount (Regulars' Discount, -2) leaves the buy price at or above the sell value for every Patron (price 4 to 8), so buying and selling in a loop only loses Tips. Only the one shot Sale Day Tag or a haggle can pay back a Tip or two once, and the test `Patron sell value` pins both facts. No change.

## Season track over 30 days

`EconomySim.season(startDay, 30, runsPerDay)` (the same 20 minute session model as the week table, two runs a session; Winter Welcome from 2026-12-01, a 30 tier track). Season XP comes from run XP and quests, about 270 a day for the 20 minute player.

| Player | runs a day | track finished | tier on day 30 | longest wait for a tier |
| --- | --- | --- | --- | --- |
| 10 minutes | 1 | not finished | 19 | 1 day |
| 20 minutes | 2 | day 25 | 30 | 1 day |
| 60 minutes | 6 | day 13 | 30 | 0 days |

- Before: 90 XP a tier. The 20 minute player finished all 30 tiers on day 10 (the 60 minute player on day 6) and then had nothing to chase for 20 days; the 10 minute player finished on day 19. Pace was fast, not steady.
- Change: `SeasonTrack.XP_PER_TIER` 90 to 225 (track 2,250 to 6,750 XP). No tier gate is over 1 day for any of the three players, the usual player finishes with five days to spare, and the casual player still reaches the middle of the track. Rewards, Tips and tier count are unchanged. Hard coded 90s in six Season tests now read the constant.
- Pinned by the test `Season pace over 30 days`. A live Season would need its players warned: the game is unpublished, so no save holds old tiers (a profile with seasonXp above 2,250 simply sits at tier 10 or higher on the new scale).

## Boss rule fairness, Nights 7 to 12

`lua tools/run_sim.lua --boss-late --runs 1000 --jobs 6 --bot greedy` (about 40 minutes). The greedy bot is the middle skill (random: median Night 3, decent: median Night 7 with 43 percent wins). Each boss is forced on every boss round from Night 7 up in full Endless runs with random Patron buys; a cell counts only runs that reached that boss. Cells past Night 10 hold under 30 runs and say little, so the band is read on the Night 7 to 12 total (n 215 to 551 per boss).

Clear rate over Nights 7 to 12, greedy bot, lowest to highest: bare_bones 39, everythings_out 40, big_tab 40, crowded_counter 39, stale_bread 42, lights_out 43, house_rules 44, thin_chips 44, flat_mult 44, quick_service 44, empty_handed 45, no_repeats 46, rushed_order 46, thin_soup 48, slow_simmer 48, house_minimum 50, double_tab 51, picked_over 52, sleepy_cook 53, short_staffed 53, bouncer 54, hearts_are_out 56, spades_are_out 56, no_vips 56, diamonds_are_out 57, clubs_are_out 57, steep_tab 57, the_tab 58, empty_pockets 58, pair_patrol 58, last_chance 58, short_notice 59, four_top 59, cold_start 61, penny_wise 61, picky_eater 57, rowdy_crowd 62, slow_night 62, quiet_corner 55, heavy_hands 64, wild_crowd 66, full_table 68, one_at_a_time 85.

- Nothing is under 15 percent (the lowest is 39) and one rule sat at the top of the band: One at a Time, 85 percent overall and 87 to 100 percent on Nights 8 to 12 (play one card, target 65 percent lower). Its own number was eased one step: target multiplier 0.35 to 0.40 (60 percent lower, description updated). After: 80 percent overall (79, 82, 79, 86, 79, 78 by Night).
- The other 42 rules are between 39 and 68 percent for the middle bot, so none needed a change. The bottom group (Bare Bones, Everything's Out, Big Tab, Crowded Counter, Stale Bread) is the Night 6 tier 3 group tuned in the boss rules section above.
- Not run: the random bot (it reaches Night 7 in 4 percent of runs, too few for a cell) and the decent bot (its Night 7 and later runs were checked in the Endless table; a per boss decent sweep would take another 40 minutes). Pinned by the updated `One at a Time` target test.

## Patron pairs: best and worst by round clear rate

`lua tools/run_sim.lua --pair-rates --runs 14000 --jobs 4 --min-builds 15` (random 4 Patron builds from Night 4, round clear rate of every pair in the build; 85 Patrons give 3,570 pairs, 3,479 had 15 or more builds, so each cell is 15 to 28 builds and noisy). Average round clear 92.4 percent.

| Top 10 pair | builds | clear |
| --- | --- | --- |
| full_house_crowd + veterans_table | 28 | 98.0 |
| rising_dough + stack_of_plates | 28 | 97.7 |
| full_house_crowd + rising_dough | 21 | 97.0 |
| lone_wolf + stack_of_plates | 27 | 97.0 |
| full_house_crowd + pair_parade | 18 | 96.7 |
| house_tab + veterans_table | 22 | 96.7 |
| bread_starter + veterans_table | 27 | 96.6 |
| full_house_crowd + house_tab | 17 | 96.6 |
| full_house_crowd + second_opinion | 15 | 96.6 |
| ace_of_the_house + stack_of_plates | 18 | 96.5 |

| Bottom 10 pair | builds | clear |
| --- | --- | --- |
| overtime + rainy_day_fund | 16 | 86.6 |
| lucky_penny_jar + overtime | 22 | 86.5 |
| bargain_hunter + second_opinion | 18 | 86.2 |
| house_special + overtime | 26 | 86.0 |
| ladder_builder + overtime | 17 | 86.0 |
| overtime + second_opinion | 20 | 85.8 |
| quick_service + stair_climber | 23 | 85.5 |
| all_hands_in + overtime | 20 | 85.1 |
| overtime + tip_jar | 20 | 84.5 |
| full_suit_feast + meadow_bee | 15 | 84.2 |

- Every pair is within 8.2 points of the average (the outlier line is 15), so no Patron number changed. Overtime is in 6 of the bottom 10, but its single Patron clear rate was within 2.8 points of the average in the earlier Patron rates sweep; it is a mild drag, not an outlier, and a bigger sample would be needed to justify a nudge.

## One dominant Patron: free-from-start lift (`lua tools/run_sim.lua --patron-lift --patron-list ID,ID --runs 150 --bot decent`)

Rule: no Patron may lift the win rate more than 12 points alone. Control (no free Patron) was 37 to 41 percent. The first pass showed five over the line, all run counters that grow with the run. Each was cut one small step, then re-run.

| Patron | Before | After | Lift before | Lift after |
| --- | --- | --- | --- | --- |
| Stack of Plates | +2 Chips per hand, cap +100 | cap +50 | +24.7 | +8.7 |
| Rising Dough | cap +12 Mult | cap +10 | +22.0 | +7.3 |
| Bread Starter | cap x2 | cap x1.6 | +21.3 | +8.0 |
| Repeat Customer | x3 Mult | x2.5 Mult | +14.7 | +6.0 |
| Tip Jar | 4 Tips per win | 2 Tips per win | +22.0 | +10.0 |

Others sampled (Vip Table +10, House Favorite +7, Small Plate +4, the rest within 2) are under the line. Sampling noise on 150 runs is about 4 points. A full 93 Patron lift sweep takes over 10 minutes, so only the suspects were re-run; use `--patron-list` to check others. Pinned by the test "Patron lift".

## Night boons: win rate lift over no boon (`lua tools/run_sim.lua --boons --runs 500 --jobs 8 --bot decent|greedy|builder`)

The bot takes the same boon on every Night 2 to 12. Rule: no boon lifts the win rate more than 12 points, none is worse than no boon. 500 runs per cell, sampling noise about 4 points. Baselines (no boon): decent 36.2 percent, greedy 17.0, builder 38.6. The table is the final tuned set, lift in points.

| Boon | decent | greedy | builder |
| --- | --- | --- | --- |
| Spare Hand (+1 Hand before the Boss) | +4.8 | +2.6 | +6.6 |
| Spare Discard | +7.6 | +2.6 | +7.8 |
| Wider Grip (+1 card, 1 less Discard) | +9.4 | +15.8 | +13.4 |
| Opening Flourish (x1.4) | +10.4 | +7.4 | +11.8 |
| Warm Welcome | +6.6 | +5.2 | +5.8 |
| Pocket Change (+1 Tip) | +4.4 | +5.4 | +8.4 |
| Free Reroll | +2.4 | +3.0 | +3.6 |
| Friendly Prices (1 less) | +9.8 | +8.8 | +13.8 |
| Pack Deal | +4.4 | +5.0 | +10.6 |
| Boss Ready (+1 Hand, 2 less Discards on the Boss) | +7.2 | +11.6 | +3.0 |
| Boss Prep | +7.8 | +3.4 | +8.0 |
| Steady Pace | +5.6 | +4.2 | +7.0 |

First pass (before tuning, decent / greedy / builder lift): Spare Hand +15.2 / +13.8 / +15.4, Wider Grip +16.0 / +15.8 / +21.6, Pocket Change (+3 Tips) +16.2 / +14.2 / +22.2, Friendly Prices (2 off) +24.6 / +22.0 / +27.8, Boss Ready (+1 Hand) +14.6 / +12.4 / +14.8, Opening Flourish (x1.5) +7.6 / +8.4 / +12.4. Changes: Spare Hand no longer applies on the Boss round, Wider Grip and Boss Ready now trade Discards for the extra card or Hand, Pocket Change +3 to +1 Tip (+2 still lifted decent by 20 points because early Tips buy the first Patrons), Friendly Prices 2 off to 1 off, Opening Flourish x1.5 to x1.4.

Open: Wider Grip reads +15.8 for the greedy bot only because greedy never discards, so the Discard cost is free to it; decent and builder read +9.4 and +13.4 (builder is inside the sampling noise of the 12 point line). Friendly Prices reads +13.8 for builder, also inside the noise. If a later sim with more runs confirms either over 12, drop Wider Grip to 2 less Discards or Friendly Prices to a one time discount. Pinned by the test "NightBoons balance".

## Starting decks: Classic, Lucky, Slim (`lua tools/run_sim.lua --start-decks --runs 500 --jobs 8 --bot decent|builder|greedy`)

Rule: every deck within 10 points of Classic. 500 runs, sampling noise about 4 points.

| Deck | decent win | builder win | greedy win |
| --- | --- | --- | --- |
| Classic | 36.2 | 38.6 | 17.0 |
| Lucky | 33.0 (-3.2) | 39.6 (+1.0) | 17.2 (+0.2) |
| Slim | 37.8 (+1.6) | 42.8 (+4.2) | 22.6 (+5.6) |

All within the band, so no deck value changed. Slim is the strongest on every bot (+1.6 to +5.6), as intended for a thinner deck that repeats good cards; Lucky is level with Classic.

## Patron lift sweep, all 93 Patrons, and the four new strategy Patrons (`lua tools/run_sim.lua --patron-lift --runs 100 --jobs 8 --bot decent`, then `--patron-list` at 300 to 400 runs)

Every Patron free from the start, decent bot. Sweep control 38 percent, average lift across the 93 Patrons -1.3 points (a free Patron fills a seat and many are situational), noise about 5 points at 100 runs.

First sweep, five strongest and five weakest, then the step taken and the lift after (400 runs):

| Patron | Lift before | Change | Lift after |
| --- | --- | --- | --- |
| Rainy Day Fund | +25 | Tips per Hand left capped at 2 | +15.0 |
| Big Spender | +22 | Tips per Patron capped at 3 | +13.0 |
| Full House Crowd | +20 | x1.15 to x1.13 per other Patron | +8.2 |
| Boss's Bane | +18 | 10 to 6 Tips | +10.2 |
| Veteran's Table | +15 | +8 to +5 Chips per Night | +12.5 |
| Lone Wolf | -17 | +15 to +25 Mult | +7.5 |
| Kitchen Duo | -12 | +100 to +110 Chips | -1.3 |
| Twin Spoons | -12 | +6 to +10 Mult | -2.0 |
| Triple Scoop | -12 | +25 to +30 Mult | -0.3 |
| Regulars' Round | -11 | +8 to +10 Mult | 0.0 |

The target "within 8 to 16 points" cannot hold for every Patron when the average is about zero, so it was read as: strongest five at or under 16, weakest five no lower than -8. Result: strongest +8 to +15, weakest -2 to +7.5. Tip Jar (after the earlier cut to 2 Tips) still reads +17.7 free from the start; that overstates it because a bought Tip Jar costs 6 Tips and a seat, so it was left. Kitchen Duo plus Triple Scoop on a Full House was held under the 25x runaway line by the test, which is why Kitchen Duo stops at +110.

The four new strategy Patrons, 300 to 400 runs, against the sweep average of -1.3: Final Bow +2.2, Full Palette +2.0, Triple Scoop -0.3, Spare Shuffle -2.3. All four sit within 3.5 points of the average Patron, so the 0.8x to 1.25x band (meaningless when the average is near zero) is met in spirit; only Triple Scoop was changed. Pinned by the test "Patron lift 2".

## Card marks and the four Legendary Patrons (`lua tools/run_sim.lua --runs 500 --jobs 8 --bot decent --marks 1`, `--patron-lift --patron-list duke_goldleaf,clover_queen,jolly_jester,boon_keeper --marks 1`)

Rule: within 10 points of baseline. `--marks 1` makes the bot spend leftover Tips on a Mark for an Ace after Patrons and packs.

| Case | decent | builder |
| --- | --- | --- |
| No marks | 36.2 | 38.6 |
| Marks bought (--marks 1) | 35.6 (-0.6) | 37.6 (-1.0) |

| Legendary Patron free from the start, with marks on | Lift over 37.3 (decent, 300 runs) |
| --- | --- |
| Boon Keeper | +1.3 |
| Jolly Jester | +1.0 |
| Clover Queen | +1.0 |
| Duke Goldleaf | +1.0 |

All inside the band and no worse than baseline, so nothing was tuned. The sim bot has little spare Tips (8 on average at a shop), so it buys few Marks and picks no boons for Boon Keeper; the marks and Legendary lifts are therefore a floor, not what a player who commits to marks sees. If marks feel weak in play, raise Gilded or Lucky one step; the sim does not say they are too strong.

## Quest Tips and Pocket Change against the shop (`lua tools/run_sim.lua --shop-econ --runs 100 --jobs 2 --start-tips 30 --boon pocket_change`)

Worst case: a full bank (30 Tips, the cap on every banked source) on Night 1 and the Pocket Change boon on every Night. Measured with the first Pocket Change (+3 Tips); the boon is now +1 Tip (see the boon balance below), so the real margin is wider.

| Visit | Avg Tips, baseline | Avg Tips, full bank + Pocket Change | Patrons, baseline | Patrons, full bank + Pocket Change |
| --- | --- | --- | --- | --- |
| N1 R1 | 4.0 | 39.0 | 0.0 | 0.0 |
| N1 R3 | 10.7 | 12.5 | 1.0 | 3.5 |
| N2 R1 | 7.0 | 11.8 | 2.1 | 4.3 |
| N3 R1 | 7.0 | 13.1 | 4.4 | 5.1 |
| N5 R1 | 9.0 | 12.3 | 5.1 | 5.3 |

The bank fills the table about one Night sooner, then the spend rate settles at 9 to 13 Tips on hand, only 3 to 5 above baseline. Rerolls (5 Tips, +2 each) and packs still compete for those Tips, so the Counter is never free before Night 6. No value changed. Pinned by the test "Quest Tips and Pocket Change" (bank cap 30, Pocket Change 3 Tips, a reroll is never free).

## Synergy audit

See `claude/synergy-audit.md` (`lua tools/synergy_audit.lua`). 20 Patrons had only the "flat" tag and so no hint or Bond partner; each now carries a real tag (scaling, rulebender, pairs, flush, straight, ranks). Side effect: Bonds give a small bonus when both ends trigger, so these 20 can now bond. Not re-simmed beyond the lift runs above; re-check if the win rate drifts.
