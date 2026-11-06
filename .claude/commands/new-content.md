---
description: Add a Patron, Boss Round or Recipe end to end (registry, test, balance, art)
---
Add the content described in: $ARGUMENTS. If the type (Patron, Boss Round, House/Menu/Secret Recipe) or the effect isn't clear, ask one short question first.

Rules: registries in src/Shared/Engine/ are the source of truth. Kid-safe names only, no alcohol, never "Balatro". Don't read init.client.lua in full.

1. Read the registry file for the type (Patrons.lua, BossRounds.lua or Recipes.lua) and copy the exact field shape and tone of a similar existing entry. Pick an id that is unique (there is a registry id-uniqueness test) and an icon emoji that is unique among Patrons.
2. Add the entry. The `description` must state the real numbers, since a balance test checks Patron descriptions and prices against effects. Price it using the same tier logic as similar Patrons.
3. Add tests in src/Shared/Tests/EngineTests.lua next to the related ones: the effect fires, does not fire when it shouldn't, and scales/caps as described. For Patrons that read run counters, also check the client preview context matches playHand.
4. Run `lua5.3 tools/run_tests_local.lua` before and after. Fix failures. If tools/sim exists, run a short sim and tell me if the new entry is wildly over or under powered compared with its price.
5. Patrons only: add an entry to tools/patron_art/prompts.json (tavern, kid-safe, no text in the image, subject drawn from the name and ability), then run `/patron-art --only <id>`.
6. Update claude/STATUS.md counts (e.g. number of Patrons) and commit locally with a clear message. Do not push.
7. Report in 3 lines: what was added, test count before/after, any balance concern.
