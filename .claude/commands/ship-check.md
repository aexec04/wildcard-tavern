---
description: Pre-publish checklist for Wildcard Tavern (content rules, placeholders, tests)
model: haiku
---
Run every check, then report a pass/fail list. Fix nothing silently: list problems and ask before changing content.

1. Tests: `lua5.3 tools/run_tests_local.lua` must show 0 failed.
2. Forbidden name: grep (case-insensitive) all of src/, docs/, claude/, and the README or Roblox page text in the repo for "balatro". Any hit is a fail (CLAUDE.md content rule). The folder name "Roblox Balotro Game" in a Claude Project is not in the repo and doesn't count.
3. Kid-safe names: grep src/ for alcohol and mature words using WORD BOUNDARIES (beer, wine, whiskey, whisky, liquor, vodka, rum, mead, ale, cocktail, booze, drunk, tipsy, brew). Show each hit with its line and judge it: "ale" inside "sale" or "table" is not a hit, "brew" meaning cocoa is still worth my review.
4. Placeholders: list every `gamePassId = 0` (src/Shared/Engine/GamePasses.lua) and every `productId = 0` (src/Shared/Engine/DeveloperProducts.lua). These need real Creator Dashboard IDs before launch. Report which are still 0 and what each one unlocks.
5. Leftovers: grep src/ for `print(`, `TODO`, `FIXME`, `rbxassetid://0`, and "placeholder". List counts and any in player-facing paths.
6. Art ids: every id in src/Shared/Engine/PatronArt.lua and src/Client/ArtAssets.lua must look like `rbxassetid://<digits>`. If the Studio MCP is available, start a play session and read the console for "failed due to" asset errors; report the ids involved.
7. Git: `git status --short` must be clean except for intended changes. Make sure `.env` and `art-wip/` are not tracked.
8. Update claude/STATUS.md "Open items" so it matches this report (one page, no history).

End with SHIP / DON'T SHIP and the blocking items in order.
