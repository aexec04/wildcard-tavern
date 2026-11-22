## Balance sweep: Night 1 to 3 targets, boss health and Patron power (Nov 22)
(Written to a new file because OUTBOX.md is over 10,000 lines and too large to read for append. Please fold in or read here.)

- Commit: none. No balance change was made, so there is nothing to commit. Tests: 0 failed before, no code touched.
- Method: `lua tools/run_sim.lua --ladder --runs 400 --jobs 4 --max-night 3`, plus `--bot greedy --runs 600` and `--bot decent --runs 400`. Standard difficulty, standard deck, stake 1.
- Results (share of all runs that die in that Night, so clear = 100 minus the sum):
  - random bot: N1 82.5%, N2 7.0%, N3 3.2%. Clears Night 1 in 17.5% of runs. Target 40%.
  - greedy bot (best hand, no discards): N1 3.7%, N2 3.7%, N3 2.3%. Clears Night 1 in 96% of runs and all three Nights in about 90%. Boss deaths: bouncer 11, house_rules 4, sleepy_cook 4 of 600 runs. Boss clear rates 92.7% to 100%.
  - decent bot (best hand plus discards): 0 deaths in 400 runs through Night 3. Every Night 1 to 3 boss clears 100%.
- Against the targets: plain bot Night 1 is 96% (target about 80%), plain bot Night 3 boss about 97% (target about 35%), weak bot Night 1 is 17.5% (target about 40%). The plain bot is far too strong and the random bot far too weak.
- Decision: I did NOT nudge the round target multiplier. One multiplier cannot fix both ends: raising it moves greedy toward target but pushes random to 0%. The sim bots also play hands better than a new human, so matching 35% at the Night 3 boss on a bot would likely make Nights 1 to 3 too hard for real players. Tutorial, difficulty and deck multipliers stack on this knob and are pinned by tests.
- NEEDS YOU (design decision): say which player the targets should describe. (a) Keep as is: Nights 1 to 3 are a gentle on-ramp. (b) Raise Night 2 and 3 targets about 15 to 25% so the greedy bot lands near 70% through Night 3, with a pinned-range test. (c) Get real clear data from Studio playtests first. I recommend (c) then (b).
- Backlog: all items are DONE. Remaining [h] tasks (map road, Studio test failures, Card Set screens, Flair audit, first five minutes) still need Studio screenshots or a design decision.
