# Wildcard Tavern — Status

- **3D room:** removed. The tavern is a 2D painted backdrop (Client/ArtAssets.lua); there is no 3D scene, building load, camera or Lighting setup. `TavernScene.server.lua` and its marketplace building load were deleted in `d68922f`; stale comments pointing at them were cleaned up on 2026-11-03.
- **Tests:** `lua5.3 tools/run_tests_local.lua` (any Lua 5.1+ works) — 358 passing as of 2026-11-03.
- **Client hub:** `src/Client/init.client.lua` is at the 200-local limit for its main chunk. Add new code in modules or `do...end` blocks.
- **Paid continue:** a one-per-run "continue" Developer Product (placeholder `productId = 0` in `DeveloperProducts.lua`; Studio grants it free). Revived runs go to separate "Revived" Daily/Weekly boards (store names bucketed on `SeededRng.VERSION`) and don't count toward `bestNightReached`/`runsWon`. The leaderboard screen only shows the Standard boards so far.
- **UI skin:** `VisualHelpers.polishPanel`/`polishButton` give every panel and button the sidebar look: gold ring, gold inner rim, gold corner brackets and studs on panels at least 56px, and a standard 6px corner radius (radius 20+ is kept for round medallions). `polishPanel(x, r, "wood")` is for menus and dialogs, `"parchment"` for reading screens. The ornaments are skipped on ScrollingFrames, see-through elements and anything holding a UIListLayout/UIGridLayout.
