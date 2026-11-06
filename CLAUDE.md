# Wildcard Tavern: Claude Code Instructions

Roblox poker-hand roguelike deckbuilder. Read `claude/STATUS.md` first for current state.

## Rules for every task
- Run `lua5.3 tools/run_tests_local.lua` before and after your changes. Do not finish with failing tests. Add tests for any new engine logic.
- Work in small steps. If something is ambiguous, pick the simplest option and note it in your summary.
- Commit locally with a clear message. Do not push (I push from my own terminal).
- Update `claude/STATUS.md` when a task is done. Keep it to one page: say what exists now, not how it was built. Do not add build-history paragraphs.
- For tasks that touch many files, propose a short plan before editing.

## Token efficiency
- Never read `src/Client/init.client.lua` in full. Use Grep to find what you need, then Read with offset and limit to view only those lines.
- Prefer Grep and Glob over reading whole files. Do not re-read files you just edited.

## Lua and Roblox constraints
- `init.client.lua` is at Lua's 200-local limit. Use `do ... end` blocks or function-scoped locals, and prefer new modules over adding locals to the hub.
- `UIListLayout` needs `SortOrder = LayoutOrder`. It lays out every sibling, so keep decorative frames out of the layout's parent.
- Never touch `UIGradient.Transparency` (it makes things see-through, not glossy). Only change `Color` stops.
- Reset both `TextTransparency` and `TextStrokeTransparency`.
- Floor numbers before using `%d` in string formatting.
- Wrap risky Lighting writes in `pcall`.
- Elements meant to survive `button:Clone()` must be parented to the button, not its slot.
- Shadow or overlay frames sized to the parent need a backdrop whose `Visible = false` hides them.

## Content rules
- Kid-safe names only. No alcohol references.
- Never use the word "Balatro" anywhere in the game, assets, or Roblox page. Never copy its art, text, or code. Mechanics are fine.
- Registries in `src/Shared/Engine/` (Patrons, BossRounds, Recipes, Packs, HousePasses, Tags, CosmeticSets, Achievements) are the source of truth for content. Do not hardcode content lists in UI code.

## Art pipeline
`/patron-art` runs it end to end (see `.claude/commands/patron-art.md`), one category at a time via `-c patrons|bosses|recipes|housepasses|titles`. Prompts: `tools/patron_art/prompts.json` (`subjects`, `boss_subjects`, `recipe_subjects`, `housepass_subjects`, `title_subjects`). Output maps, generated and never hand-edited, in `src/Shared/Engine/`: `PatronArt.lua`, `BossRoundArt.lua`, `RecipeArt.lua`, `HousePassArt.lua`, `TitleArt.lua`. UI draws them through `Client/PatronPlaque.lua` (`category` option) and falls back to the entry's emoji icon when an id is missing. New registry entries need a prompts.json entry.
