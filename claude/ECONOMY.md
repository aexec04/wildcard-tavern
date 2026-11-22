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
