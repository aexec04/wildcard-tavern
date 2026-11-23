# Difficulty curve audit (Nights 1 to 8, 300 seeds)

Run: `lua tools/run_sim.lua --bot greedy|random --runs 300 --max-night 8 --jobs 4 --json out.json`
Standard deck, standard difficulty, no forced Patrons. Clear rate is the share of runs that reached the Night and cleared it. Boss rates are natural (the boss each run happened to draw), so late bosses only count players who survived that far.

## Clear rate per Night

| Night | Greedy reached | Greedy clear | Random reached | Random clear |
|---|---|---|---|---|
| 1 | 300 | 99.7% | 300 | 63.3% |
| 2 | 299 | 99.7% | 190 | 88.4% |
| 3 | 298 | 99.0% | 168 | 78.0% |
| 4 | 295 | 97.6% | 131 | 65.6% |
| 5 | 288 | 82.3% | 86 | 59.3% |
| 6 | 237 | 71.7% | 51 | 56.9% |
| 7 | 170 | 64.7% | 29 | 65.5% |
| 8 | 110 | 50.0% | 19 | 36.8% |

Whole run win rate: greedy 18.3%, random 2.3%. No soft locks in 600 runs.

## Flags

- Greedy clears under 40 percent on a Night: none (lowest is Night 8 at 50.0%).
- Random clears over 90 percent on a Night: none (highest is Night 2 at 88.4%).
- Greedy clears under 40 percent on a boss (10 or more attempts): none. Closest, with small samples: stale_bread 40.0% of 10, crowded_counter 41.7% of 12, bare_bones 43.8% of 16.
- Random clears over 90 percent on a boss (10 or more attempts): short_staffed 90.0% of 10 (not over), thin_soup 90.5% of 63, short_notice 91.8% of 49, slow_simmer 93.5% of 46, hearts_are_out 93.8% of 16, cold_start 94.0% of 50, the_tab 95.9% of 49, bouncer 98.1% of 54, rowdy_crowd 100% of 13.

## Decision

No change. The flagged easy bosses are rules (not targets), and a random player who reaches them has survived Nights 1 to 7 on luck, so the rate is selection biased. None of them is a one line target fix. The same bosses are cleared 95 to 100 percent by the greedy bot, which matches the intended "easy boss" role in the pool. The three low sample greedy bosses sit just above 40 percent and need a larger sample (`--bosses --boss-night N`, about 10 minutes per bot) before any tuning.

## Greedy bot, bosses with 20 or more attempts, lowest first

pair_patrol 77.1%, rushed_order 77.5%, thin_chips 78.3%, picked_over 79.1%, no_repeats 80.5%, quiet_corner 84.6%, flat_mult 86.5%, clubs_are_out 88.9%.

## Boss rule audit (Nov 23)

One test per boss (46, all Nights) in `EngineTests.lua`, named "Boss audit: <id> ...". Each makes the rule live in a real boss round, checks hand size, discards, hands, target and starting Tips against a no boss control, plays real hands through `RunState.playHand` (blocked hand types score 0, debuffs score less, Chips and Mult factors, first hand factor, no repeat, Patron cap, sit out, Chips factor, no scoring Tips, Tips per card, tossed cards, Tips wipe, exact and minimum card counts) and checks the rule is gone with the next round.

Differences found: none. `claude/reference` holds only painted art targets (no rule text), so the rule text on each card was checked against the engine fields instead.

## Night 1 to 8 table (Nov 23, pinned by the "Night table" test)

Config: 8 cards, 4 hands, 3 discards, 3 rounds per Night, 4 Tips per round win (8 on the Boss round), interest 1 per 5 Tips held (cap 5).

| Night | Small | Big | Boss |
|---|---|---|---|
| 1 | 65 | 97 | 130 |
| 2 | 156 | 234 | 324 |
| 3 | 360 | 540 | 772 |
| 4 | 710 | 1065 | 1573 |
| 5 | 1736 | 2604 | 3968 |
| 6 | 3284 | 4927 | 7742 |
| 7 | 6420 | 9630 | 15591 |
| 8 | 13803 | 20704 | 34508 |

Observation, not changed: from Night 4 the next Night's Small round is lower than the Boss round before it (Night 4 Small 710 vs Night 3 Boss 772, Night 8 Small 13803 vs Night 7 Boss 15591), because the Boss multiplier climbs to 2.5x while a Night grows 2.15x. Every Night's Small round is still above the Big round before it. `claude/reference` has no number table (art only), so the formula in `RunState` is the source; say if you want the Boss spike flattened.
