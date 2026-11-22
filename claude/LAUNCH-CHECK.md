# Launch check (2026-11-22)

Result: nothing regressed. `claude/CREATOR-HUB-FILL-IN.md` does not exist in this branch, so only `claude/PREPUBLISH-SWEEP.md` was walked.

## Still holds
- Debug remotes: every `Debug*` handler in src/Server/init.server.lua is Studio gated; Client/DebugGoto returns at once outside Studio.
- Rate limits: every `OnServerEvent` handler calls RateLimit.allow or is Studio gated. The "Pre publish sweep" test enforces both and passes.
- Banned word: the only hits in src are the BANNED guard list in Engine/WinCard.lua and the tests. No game text uses it.
- Tests: 1431 passed, 0 failed, locals ratchet 127 of 127.

## Product id placeholders (user must fill before launch)
- Game passes in Engine/GamePasses.lua: one entry has gamePassId = 0 (line 46); the others hold real ids.
- Engine/Store.lua items with productId = 0 (live players see "coming soon"): starter_pack, card_set_bundle, flair items, flair_bundle, premium_harvest_moon, premium_winter_welcome. The VIP pass id is also pending in Creator Hub.
- Create each in Creator Hub, then paste the id into the registry. No code change needed.
