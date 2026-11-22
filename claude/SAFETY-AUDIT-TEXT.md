# Safety audit: player facing text

Scope: every `src` string hit for alcohol, tobacco, drug, gambling and violence words (ale, beer, wine, rum, brew, smoke, pipe, bet, wager, gamble, jackpot, kill, blood, die, dead, skull, gun and more), reviewed in context.

## Changed (display names only, ids and art keys unchanged)
- Event "A Stranger's Wager" is now "The Dice Stranger"; its line "Double or nothing?" is now "Care for a lucky roll?" and the option "Take the bet" is now "Take the roll".
- Event "The Gambler's Table" is now "The Trading Table".
- Deck variant "High Roller" is now "Bold Start".

## Reviewed and left alone
- "dead end" (map check message, developer only), "dead code" comments, "Smoke" (a chimney effect frame), "die" in "rolls a die" and the Minigame "Roll a die!" (dice, no money), "pot" (a soup pot, a boss flavor line), "defeated" (boss lines: "You win this round!").
- The Creator Store track title with an alcohol word is already shown as "The Dragon's Hearth" (MusicRotation).
- Internal ids such as `stranger_wager`, `gamblers_table`, `bet` and `high_roller` stay because art maps (EventArt, OptionArt) and saves key on them. Not player visible. The game is unpublished, so they can be renamed later, but art keys would need regenerating.
- Existing banned word tests (Patron lines, boss lines, names) were already in place.

## New guard
Test "Safety: no risky word in registry names, descriptions, flavor or event text" walks Patrons, CosmeticSets, DeckVariants, BossRounds, Recipes, HousePasses, Packs, Tags, Achievements and RunEvents and fails on any whole word from the banned list (ids, icons and art keys skipped).

## Not covered by the test
Strings built by functions (event result messages), Client UI literals, and quest and store text outside those registries were grepped by hand only.
