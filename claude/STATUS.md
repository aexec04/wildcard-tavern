# Wildcard Tavern — Status

- **3D room:** removed. The tavern is a 2D painted backdrop (Client/ArtAssets.lua); there is no 3D scene, building load, camera or Lighting setup. `TavernScene.server.lua` and its marketplace building load were deleted in `d68922f`; stale comments pointing at them were cleaned up on 2026-11-03.
- **Tests:** `lua5.3 tools/run_tests_local.lua` (any Lua 5.1+ works) — 358 passing as of 2026-11-03.
- **Client hub:** `src/Client/init.client.lua` is at the 200-local limit for its main chunk. Add new code in modules or `do...end` blocks.
