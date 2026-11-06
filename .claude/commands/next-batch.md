---
description: Static art wiring check, extend art pipeline to Boss Rounds/Recipes/House Passes/Titles, ship-check, tests, STATUS update
model: sonnet
---
Read CLAUDE.md and claude/STATUS.md first. Never read src/Client/init.client.lua in full; use grep and targeted line ranges only. Never use the word "Balatro" in game text, assets or the Roblox page. Avoid em dashes in any text you write.

Work through these in order. Commit locally after each step (never push). Keep going without asking unless blocked. Never run image generation or upload (it spends credits).

1. Commit any uncommitted changes (tools/patron_art/generate_patron_art.py, .claude/commands/patron-art.md).

2. Static check of patron art wiring. Grep every place a Patron is drawn (Shop rows, Sidebar, Collection, pack opening, GameOver, Journey) and confirm each uses PatronArt.lua image ids. Fix any that leave the icon slot blank when an id exists, get hidden by ZIndex layering, lose the image after a redraw or button:Clone() (children must be parented to the button), or show locked Collection entries as near-black silhouettes (use a readable dimmed version plus a lock badge). List what changed.

3. Extend tools/patron_art to Boss Rounds, Recipes, House Passes and Titles in the same "Roblox avatar characters in a tavern" style: prompts in prompts.json (35 Boss Rounds, all Recipes, 7 House Passes, 10 Titles; kid-safe, no alcohol, no casino or gambling words), a category argument in generate_patron_art.py (keep parallel workers, loud stop on credit or auth errors, stale tracking, QA), generated maps BossRoundArt.lua, RecipeArt.lua, HousePassArt.lua, TitleArt.lua in src/Shared/Engine (never hand-edit), update /patron-art and the CLAUDE.md art section, and wire images everywhere these are drawn (Collection tabs first, then Shop, Round Select, boss intro, Journey, Game Over) with the existing emoji as fallback when no id exists. Print the exact generation commands, Boss Rounds first, with image counts and a cost estimate at IMAGE_QUALITY=low.

4. Run /ship-check. Fix everything that is code. For blockers that need me (gamePassId = 0 in GamePasses.lua, placeholder productId in DeveloperProducts.lua) list them clearly. Grep src for rbxassetid://203785492, find what loads it, and fix or remove it.

5. Keep the name "Wildcard Tavern". Rename nothing.

6. Run lua5.3 tools/run_tests_local.lua until it passes. Rewrite claude/STATUS.md as a one-page current snapshot.

Finish with: commits made, anything blocked, and the exact commands for me to run next.
