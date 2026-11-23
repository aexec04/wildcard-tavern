# Balance sim across the 14 Card Sets

Same seed, every set: a test (`Card Sets are cosmetic: the same seeded run scores identically ...`) equips each of the 14 sets in turn, plays the same seeded round and checks the hand scores and round score match classic exactly. They do.

Card Sets are cosmetic. The engine, the scoring and the sim never read `CosmeticSets` (a test pins this), so all 14 sets give the same Night clear rates. One run stands for every set.

Regenerate with `lua tools/sim_sets.lua 150 1` (150 seeded runs per bot, default deck, standard difficulty). Each cell is the share of runs that reached the Night and cleared it, with runs reaching it in brackets.

| Bot | N1 | N2 | N3 | N4 | N5 | N6 | N7 | N8 |
|---|---|---|---|---|---|---|---|---|
| random | 61% (150) | 86% (91) | 77% (78) | 65% (60) | 54% (39) | 52% (21) | 55% (11) | 50% (6) |
| greedy | 99% (150) | 99% (149) | 99% (148) | 97% (146) | 82% (141) | 71% (115) | 65% (82) | 47% (53) |
| decent | 100% (150) | 100% (150) | 100% (150) | 100% (150) | 97% (150) | 87% (145) | 72% (126) | 46% (91) |

## Flags (under 20 percent or over 95 percent)

- None under 20 percent.
- Over 95 percent: greedy Nights 1 to 4 (97 to 99), decent Nights 1 to 5 (97 to 100).
  - Nights 1 to 4 are easy on purpose so a new player wins early (the random bot clears Night 1 at 61 percent). No change suggested.
  - Suggested one number fix if you want Night 5 harder for strong bots: raise the Night 5 step (currently 1.25) to 1.35. Expect decent Night 5 to land near 90 percent.
