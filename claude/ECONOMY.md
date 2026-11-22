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
