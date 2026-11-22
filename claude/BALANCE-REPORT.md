# Balance report: clear rates by Night

Seeded headless runs (300 per bot, seeds 1 to 300), standard difficulty and deck, through the real engine. Regenerate with `lua tools/balance_nights.lua 300 1`.

Bots: random (random legal hand, no discards), greedy (best scoring hand, no discards), decent (greedy that discards when behind pace). All three share one shop policy that buys the best value Patron on offer, so the shop bot is not a separate column.

Targets for a new player: Night 1 about 80%, Night 2 about 55%, Night 3 about 35% of runs clearing the Night.

## random bot (win rate 1.0%)

| Night | Runs reaching | Runs clearing | Cleared (of all runs) | Avg score over target |
|---|---|---|---|---|
| 1 | 300 | 42 | 14.0% | 111% |
| 2 | 42 | 24 | 8.0% | 141% |
| 3 | 24 | 18 | 6.0% | 149% |
| 4 | 18 | 11 | 3.7% | 139% |
| 5 | 11 | 9 | 3.0% | 146% |
| 6 | 9 | 7 | 2.3% | 142% |
| 7 | 7 | 6 | 2.0% | 124% |
| 8 | 6 | 3 | 1.0% | 135% |

## greedy bot (win rate 23.7%)

| Night | Runs reaching | Runs clearing | Cleared (of all runs) | Avg score over target |
|---|---|---|---|---|
| 1 | 300 | 284 | 94.7% | 227% |
| 2 | 284 | 275 | 91.7% | 260% |
| 3 | 275 | 267 | 89.0% | 245% |
| 4 | 267 | 254 | 84.7% | 209% |
| 5 | 254 | 230 | 76.7% | 184% |
| 6 | 230 | 186 | 62.0% | 155% |
| 7 | 186 | 129 | 43.0% | 141% |
| 8 | 129 | 71 | 23.7% | 130% |

## decent bot (win rate 54.3%)

| Night | Runs reaching | Runs clearing | Cleared (of all runs) | Avg score over target |
|---|---|---|---|---|
| 1 | 300 | 300 | 100.0% | 230% |
| 2 | 300 | 300 | 100.0% | 263% |
| 3 | 300 | 300 | 100.0% | 246% |
| 4 | 300 | 297 | 99.0% | 212% |
| 5 | 297 | 295 | 98.3% | 187% |
| 6 | 295 | 277 | 92.3% | 155% |
| 7 | 277 | 224 | 74.7% | 140% |
| 8 | 224 | 163 | 54.3% | 131% |

## Patrons (decent bot): bought and win rate

| Patron | Runs bought | Win rate when bought |
|---|---|---|
| stack_of_plates | 113 | 77% |
| repeat_customer | 102 | 57% |
| tasting_menu | 102 | 56% |
| rising_dough | 98 | 61% |
| regulars_chair | 97 | 52% |
| lantern_lighter | 93 | 59% |
| slow_cooker | 93 | 69% |
| the_regular | 93 | 55% |
| house_tab | 91 | 67% |
| regulars_round | 90 | 57% |
| cobweb_shelf | 86 | 56% |
| lighthouse_keeper | 86 | 47% |
| pair_bonds | 86 | 56% |
| estate_sale | 83 | 78% |
| lucky_dice | 81 | 56% |

## Recommendation

- Night 1 (goal 80%): random 14%, greedy 95%, decent 100%. Looks too easy for the decent bot.
- Night 2 (goal 55%): random 8%, greedy 92%, decent 100%. Looks too easy for the decent bot.
- Night 3 (goal 35%): random 6%, greedy 89%, decent 100%. Looks too easy for the decent bot.

Bots see every card combination (better than a new player) but do not plan Patron builds (worse than a practiced one). Read the random bot as a floor and the decent bot as a practiced ceiling; a new player should land between them. Targets were not changed.

## Late game: Nights 5 to 12 (Nights 9 and up are Endless)

Run `lua tools/balance_late.lua 100 1` (standard difficulty and deck, endless on, 100 seeded runs per bot). It is a separate script, so regenerating the top of this report leaves it alone; paste its output here.

Greedy bot (runs reaching / clearing / avg score over target): N5 82/74/180%, N6 74/59/159%, N7 59/36/139%, N8 36/22/133%, N9 22/13/125%, N10 13/4/107%, N11 4/0/104%.

Decent bot: N5 99/98/179%, N6 98/91/149%, N7 91/75/136%, N8 75/51/126%, N9 51/29/121%, N10 29/14/120%, N11 14/4/113%, N12 4/1/105%.

Findings, no values changed:
- Targets rise every Night (base x2.15 per Night; Boss multiplier climbs to 2.5x at Night 8 and holds). Clear rates fall smoothly and the score margin tightens toward 100% by Night 10 to 12, which is the intended Endless wall.
- Bosses do not repeat inside a run until the pool is used up (BossRounds.pick), so about 96% of Night 6+ bosses are a new rule for that run. 13 tier 3 rules cover Nights 6 to 12 with room to spare.
- Both bots keep buying and winning on Patrons through Night 12, so rewards keep Patrons relevant. Nothing clearly off, so nothing tuned.
- Pinned by test "Late game: targets rise every Night from 5 to 12...".
