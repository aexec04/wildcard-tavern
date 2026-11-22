# Balance report: clear rates by Night

Seeded headless runs (100 per bot, seeds 1 to 100), standard difficulty and deck, through the real engine. Regenerate with `lua tools/balance_nights.lua 100 1`.

Bots: random (random legal hand, no discards), greedy (best scoring hand, no discards), decent (greedy that discards when behind pace). All three share one shop policy that buys the best value Patron on offer, so the shop bot is not a separate column.

Targets for a new player: Night 1 about 80%, Night 2 about 55%, Night 3 about 35% of runs clearing the Night.

## random bot (win rate 1.0%)

| Night | Runs reaching | Runs clearing | Cleared (of all runs) | Avg score over target |
|---|---|---|---|---|
| 1 | 100 | 15 | 15.0% | 109% |
| 2 | 15 | 8 | 8.0% | 149% |
| 3 | 8 | 5 | 5.0% | 146% |
| 4 | 5 | 4 | 4.0% | 172% |
| 5 | 4 | 3 | 3.0% | 157% |
| 6 | 3 | 1 | 1.0% | 111% |
| 7 | 1 | 1 | 1.0% | 132% |
| 8 | 1 | 1 | 1.0% | 115% |

## greedy bot (win rate 22.0%)

| Night | Runs reaching | Runs clearing | Cleared (of all runs) | Avg score over target |
|---|---|---|---|---|
| 1 | 100 | 93 | 93.0% | 222% |
| 2 | 93 | 85 | 85.0% | 217% |
| 3 | 85 | 80 | 80.0% | 200% |
| 4 | 80 | 78 | 78.0% | 194% |
| 5 | 78 | 66 | 66.0% | 171% |
| 6 | 66 | 56 | 56.0% | 159% |
| 7 | 56 | 35 | 35.0% | 145% |
| 8 | 35 | 22 | 22.0% | 143% |

## decent bot (win rate 45.0%)

| Night | Runs reaching | Runs clearing | Cleared (of all runs) | Avg score over target |
|---|---|---|---|---|
| 1 | 100 | 100 | 100.0% | 229% |
| 2 | 100 | 100 | 100.0% | 236% |
| 3 | 100 | 100 | 100.0% | 206% |
| 4 | 100 | 99 | 99.0% | 195% |
| 5 | 99 | 97 | 97.0% | 180% |
| 6 | 97 | 83 | 83.0% | 149% |
| 7 | 83 | 69 | 69.0% | 138% |
| 8 | 69 | 45 | 45.0% | 128% |

## Patrons (decent bot): bought and win rate

| Patron | Runs bought | Win rate when bought |
|---|---|---|
| repeat_customer | 37 | 51% |
| regulars_chair | 36 | 47% |
| stack_of_plates | 34 | 68% |
| slow_cooker | 32 | 62% |
| tasting_menu | 32 | 50% |
| the_regular | 32 | 53% |
| bread_starter | 30 | 57% |
| rising_dough | 30 | 57% |
| lighthouse_keeper | 29 | 34% |
| suit_sampler | 28 | 46% |
| cobweb_shelf | 27 | 52% |
| pair_bonds | 26 | 54% |
| the_bard | 26 | 42% |
| house_tab | 25 | 64% |
| tab_regulars | 25 | 44% |

## Recommendation

- Night 1 (goal 80%): random 15%, greedy 93%, decent 100%. Looks too easy for the decent bot.
- Night 2 (goal 55%): random 8%, greedy 85%, decent 100%. Looks too easy for the decent bot.
- Night 3 (goal 35%): random 5%, greedy 80%, decent 100%. Looks too easy for the decent bot.

Bots see every card combination (better than a new player) but do not plan Patron builds (worse than a practiced one). Read the random bot as a floor and the decent bot as a practiced ceiling; a new player should land between them. Targets were not changed.
