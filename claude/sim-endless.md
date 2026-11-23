# Endless scaling sim, Nights 9 to 30

`lua tools/run_sim.lua --night-rates --runs 1500 --jobs 8 --bot decent --max-night 30` (Classic deck, no boons, no marks, random Patron buys, Endless past the Night 8 win). A Night counts as cleared when every round, boss included, was cleared. "Reached" is how many of the 1500 runs entered the Night.

| Night | Reached | Cleared | Target of the boss round |
| --- | --- | --- | --- |
| 8 | 941 | 46.2% | 34,508 |
| 9 | 435 | 62.5% | |
| 10 | 272 | 63.2% | 77,643 |
| 11 | 172 | 68.6% | |
| 12 | 118 | 65.3% | 174,697 |
| 13 | 77 | 63.6% | |
| 14 | 49 | 55.1% | |
| 15 | 27 | 55.6% | 589,605 |
| 16 | 15 | 46.7% | 884,407 |
| 17 | 7 | 28.6% | |
| 18 | 2 | 0.0% | 1,989,917 |
| 20 | 0 | | 4,477,315 |
| 25 | 0 | | 33,999,614 |
| 30 | 0 | | 258,184,570 |

## Reading it

- Median Night reached: 8 over all runs (941 of 1500 enter Night 8, 435 enter Night 9). Among the runs that clear Night 8, the median is Night 10.
- Furthest run: Night 18. Nobody reaches 19 to 30 in 1500 runs.
- The clear rate among survivors stays 55 to 69 percent through Night 15 because only strong builds get there. The honest wall is the share of all runs that clear a Night: Night 12 is 5 percent, Night 15 is 1.1 percent (17 of 1500), Night 17 is 0.1 percent.
- Of the 435 runs that start Night 9, 15 clear Night 15 (3.4 percent), under the 10 percent line for Night 15.
- Targets grow 1.5x per Night from Night 9 (RunState ENDLESS_NIGHT_GROWTH) and stay far below EndlessRules.TARGET_CAP (9e15) through Night 30, so no number overflows and no Night is free.

No value changed. Pinned by the test "Endless curve Night 13 to 30".
