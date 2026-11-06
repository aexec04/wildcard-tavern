---
description: Generate, upload and wire up Patron art end to end (images -> Roblox assets -> PatronArt.lua -> live Studio check)
model: haiku
---
Run the Patron art pipeline. Tool: `tools/patron_art/generate_patron_art.py` (run from the project root). Prompts live in `tools/patron_art/prompts.json`; images go to `art-wip/patrons/` (gitignored).

Arguments: $ARGUMENTS (optional: `--only id1,id2`, `--limit N`, `--stale`, `--force`, `--workers N`).

Speed: `generate` and `upload` run 4 requests in parallel by default (`--workers N` to change; use 2 if OpenAI or Roblox returns rate-limit errors). A full 50-patron run takes minutes, not 20+. Use the cheap model; the scripts do the work, so keep your own commentary minimal.

Style: the active look is `style` in prompts.json (Roblox avatar characters in a tavern). The older looks are kept as `style_painterly_v1` and `style_blocky_v1`. Changing `style` or a subject marks images stale; regenerate them with `--stale`.

1. `python3 tools/patron_art/generate_patron_art.py status` to see what is missing, stale or already done. If a Patron in `src/Shared/Engine/Patrons.lua` has no entry in prompts.json, write one (same tone: tavern, kid-safe, no alcohol, no text in the image) before continuing.
2. `python3 tools/patron_art/generate_patron_art.py generate $ARGUMENTS` (needs OPENAI_API_KEY in tools/patron_art/.env). Skips images that already exist. Look at the first few results before generating the rest; stop and report if the style is off.
3. Upload. Prefer the Studio route (no Roblox key needed): run `... queue`, then for each entry call the Roblox Studio MCP tool `open_cloud_invoke` with POST `/assets/v1/assets`, scopes ["asset:read","asset:write"], body `{"request":{"assetType":"Decal","displayName":<displayName>,"description":"Wildcard Tavern patron art","creationContext":{"creator":{"userId":"<owner id>"}}}}` and `files: [{name:"fileContent", path:<path>}]`. Poll GET `/assets/v1/operations/{id}` until done, then `python3 tools/patron_art/generate_patron_art.py record <id> <assetId>`. (The art-wip directory must be approved in Studio's Assistant Settings > MCP Permissions. If ROBLOX_API_KEY is set in .env, just run `... upload` instead.)
4. Resolve Image ids. Open Cloud uploads create DECALS, and an ImageLabel needs the IMAGE id inside the Decal (the Decal id fails with "Asset type does not match" / AssetFetchStatus Failure). With the Studio MCP, run `execute_luau` (Edit datamodel, or Server datamodel if Studio is in Play mode; InsertService:LoadAsset works in both). Do all patrons in ONE call and return a compact `id,imageId;id,imageId` string, then record them in one Python snippet instead of one command per patron that calls `game:GetService("InsertService"):LoadAsset(decalId)` for each uploaded patron that has no entry in art-wip/patrons/image-ids.json, reads the first Decal's `.Texture`, extracts the digits, then run `python3 tools/patron_art/generate_patron_art.py record-image <id> <imageId>` for each. The Studio user must be allowed to read the asset (the place must be owned by the account that uploaded it).
5. `python3 tools/patron_art/generate_patron_art.py lua` regenerates `src/Shared/Engine/PatronArt.lua` using IMAGE ids and warns about any patron still missing one.
6. Studio check: with the Studio MCP, confirm the open place has `ReplicatedStorage.Shared.Engine.PatronArt` with the new ids (Rojo should have synced it; if not, say so), then start play and check the console for load errors.
7. Run `lua5.3 tools/run_tests_local.lua`, commit locally (do not push), and report: how many Patrons have art, which failed QA or moderation.

Never print API keys. Never commit `.env` or `art-wip/`.
