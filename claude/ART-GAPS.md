# Art gaps report

Scanned: every `src/Shared/Engine/*Art.lua` registry (66 files, loaded and walked), the five content maps against their registries (Patrons, Boss Rounds, Recipes, House Passes, Titles), Packs, and the `rbxassetid://0` uses in `src/Client`.

## Clean (guarded by a test)
- No registry holds `rbxassetid://0`, `rbxassetid://` or an empty id. `Generated art registries never hold a placeholder id` in EngineTests fails if one appears.
- Patrons 81 of 81, Boss Rounds 43 of 43, Recipes 81 of 81, House Passes 13 of 13, Titles 98 of 98 have art.
- No id is shared between two different registry files.

## Gaps, most visible first
1. **Menu and table share one image.** `src/Client/ArtAssets.lua`: `menuBackground` and `gameplayBackground` are both `rbxassetid://103951896085634`. Seen on: the Menu and the table fallback (when a Card Set has no room art). Both are fallbacks behind newer painted scenes, but a player on a set with no table art sees the menu picture at the table.
2. **Jumbo and Mega packs: resolved.** The Counter rows draw the base pack art with a JUMBO or MEGA corner tag (`Packs.sizeInfo`); a test checks every pack id resolves to art, never an emoji. The pack open screen shows the picked cards, not pack art.
3. **Hardcoded fallback ids in `ArtAssets.lua`.** `shopBackground` and `gameOverWinBackground` fall to `rbxassetid://0` if `BackgroundArt` loses `shop_bg` or `game_over_win_bg`. Both keys exist today, so nothing shows. Seen on: Counter and the win screen if a key is ever removed.
4. **Empty generated maps.** `StorePageArt` is empty by design (store page uploads, not drawn in game). `CardFaceArt`, `CourtFaceArt`, `PlayRoomArt` and `RewardArt` are resolvers, not id maps, so they hold no ids.
5. **Biome Card Sets use other backdrop maps.** `SetBackdropArt` has 10 entries and does not list `classic_tavern`, `winter_evening`, `festival_night`, `closing_time` or `golden_gala`. Those five take their backdrop from `BackgroundArt` (`backdrop_*`), which has `winter_evening`, `festival_night`, `closing_time` and `golden_gala`. `classic_tavern` uses the default menu and table art by design.

## Not covered
- Per-slot emoji fallbacks inside individual Client screens (dozens of `or "..."` icon uses) were not each walked. The registries behind them are complete, so an emoji only shows when an id is truly missing.
- Ids reused inside one registry file (for example a shared frame) were not flagged.
