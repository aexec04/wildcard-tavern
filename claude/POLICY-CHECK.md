# Roblox policy check: game page and monetization text

Scope: claude/LAUNCH-ASSETS.md, src/Shared/Engine GamePasses, DeveloperProducts, Store, Packs, Quests.

## Findings
- **Paid random items: none.** Robux items are Game Passes (Fast Forward, VIP, Music Pack, Golden Gala Set), the One More Round product, and fixed cosmetic bundles (Starter Pack, Card Set Bundle, Flair pieces, season premiums). Each has fixed, listed contents. No chest, crate, loot or mystery item is sold.
- **Random Packs are Tips only.** Patron, Recipe and Standard Packs cost in-game Tips, which cannot be bought with Robux or cashed out. Their text already says "Reveals N random ..., pick 1", so the reveal is disclosed. Because no Robux is involved, no drop odds table is required, so no Odds line was added. If a pack is ever sold for Robux, show odds first.
- **No gambling language.** The only hit was the internal event id `gamblers_table`; its player text is "The Trading Table". Tips are virtual only.
- **No outside links or brands** in player text or store text (no URLs, Discord, YouTube, social names). Nothing asks players to leave Roblox.
- **Alcohol, tobacco, drugs:** covered by the earlier text safety audit (SAFETY-AUDIT-TEXT.md).
- **Quests:** reward Tips or cosmetics, no Robux wording.
- **Page text:** LAUNCH-ASSETS description and keywords are clean. Re-check the age questionnaire wording in Creator Hub before publishing.

## Fixed
- tools/patron_art/prompts.json: `boss_emblem` prompt said "white skull"; reworded to a cartoon ogre face. It was already failing the banned word test on this branch. No image was regenerated.

## Pinned by test
"Roblox policy: Robux items are fixed ..." fails if any pass, product or store item text gains random, chance, chest, crate, loot, odds, link or similar words, or if a pack gets a Robux price or product id.

## For the owner
Before launch, confirm in Creator Hub that Paid Random Items is answered No.
