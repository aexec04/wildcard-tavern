# Patron synergy check (queue run)
Probes: tools/_probe_synergy.lua (alone, every pair, 8 hand types, 2 contexts) and tools/_probe_dead.lua. Test: "Patron synergy: ..." in EngineTests.

## Top pairs (best ratio to the bare hand, 40 hands played, so late-run numbers)
1. small_plate + repeat_customer x27.0 (High Card)
2. repeat_customer + vip_table x27.0 (High Card)
3. house_favorite + vip_table x23.4 (High Card)
4. vip_table + color_matcher x21.0
5. small_plate + color_matcher x21.0
6. threes_company + repeat_customer x21.0 (Three of a Kind)
7. small_plate + stack_of_plates x21.0
8. vip_table + stack_of_plates x21.0
9. small_plate + house_favorite x20.2
10. repeat_customer + house_special x19.5 (Full House)
On Pair or better the top is regulars_round + stack_of_plates at x20.4, the only normal-hand pair past 20x. Singles: small_plate and vip_table x9.0 on a High Card.

## Runaways
9 pairs pass 20x, all on a bare High Card (base about 5 points, so a flat +8 Mult or +80 Chips reads big) except threes_company + repeat_customer (x21 on Three of a Kind, needs a repeated hand type). None is a bug: every one is two plain bonuses adding up. Not rebalanced, per the task. Candidate for you: repeat_customer (x3) is in 4 of the top 10.

## Dead Patrons
0 bugs. 81 Patrons, 0 errors. 27 add nothing in a plain sample but each is explained: copiers (understudy, apprentice, second_opinion, shown to copy in the test), Tip or interest earners (tip_jar, big_spender, spare_change, rainy_day_fund, boss_bane, savings_club, quick_service, nest_egg, sand_merchant, lucky_penny_jar), rule changers (bargain_hunter, extra_chair, second_helpings, overtime), and rank, hold or run-counter conditions (ace_of_the_house, jack_of_all_trades, queens_gambit, perfect_ten, warm_hearth, marsh_gardener, royal_road, tasting_menu, pair_bonds, full_house_crowd). The test feeds richer contexts and requires each Patron to change a score, earn Tips or carry a hook.

## Code changes
No engine change (no bug found). Added the test and the two probes.
Needs you: nothing. Optional design call on repeat_customer x3.
