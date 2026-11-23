# Boss rule x Night boon sim, Nights 7 to 12

`lua tools/run_sim.lua --boss-boons --runs 16 --jobs 8 --bot decent`. For each of the 46 boss rules the boss is forced on every boss round from Night 7 up, runs are Endless to Night 12 with random Patron buys, and the bot takes the same boon every Night (none is the baseline). A cell is the boss clear percent over every boss round of those 16 runs (about 20 to 40 attempts, so one cell is good to roughly 10 points).

Flag rule: a cell under 5 percent (unwinnable) or over 95 percent (trivial) with 20 or more attempts. Result: **none flagged.**

## Mean boss clear rate per boon (all 46 bosses)

| Boon | Mean boss clear |
| --- | --- |
| none | 53.0 |
| Spare Hand (before the Boss) | 50.1 |
| Spare Discard | 55.5 |
| Wider Grip | 69.0 |
| Opening Flourish | 52.6 |
| Warm Welcome | 55.0 |
| Pocket Change | 54.7 |
| Free Reroll | 60.8 |
| Friendly Prices | 58.4 |
| Pack Deal | 48.7 |
| Boss Ready | 50.1 |
| Boss Prep | 56.7 |
| Steady Pace | 49.8 |

## Findings

- Nothing is unwinnable or trivial. The hardest bosses stay between 14 and 64 percent whatever the boon (Everything's Out mean 40, Big Tab 41, Bare Bones 42, Lights Out 43, Thin Chips 43). The easiest is One at a Time (mean 85, range 70 to 100), the only boss that is close to a free clear; The Tab and Four Top follow at 64 to 66.
- **Wider Grip is the one boon that moves boss rounds a lot**: +16 points over no boon on average (69 against 53), and +10 to +20 against almost every boss. The earlier boon sim measured +9 to +16 across a whole run; here only boss rounds count, so the boss is where its extra card pays. It stays under the 12 point whole-run line in the decent bot, but if a later pass wants to trim it, 2 less Discards is the next step.
- Boss Ready, Spare Hand, Pack Deal and Steady Pace sit at or slightly under the no boon baseline against bosses (49 to 50), within the 10 point noise. They help the plain rounds, not the boss.
- Duplicate rows: Thin Soup equals Slow Simmer and Thin Chips equals Flat Mult in every cell, so each pair behaves the same rule. That is content, not a sim fault; if the pairs are meant to feel different, one of each needs its own number.
- Worst single cells (Lights Out + Spare Hand 17, Bare Bones + Friendly Prices 14, Lights Out + Steady Pace 17) are 6 to 7 attempts each and not repeated by the neighbouring boons, so they are noise.

No value changed.
