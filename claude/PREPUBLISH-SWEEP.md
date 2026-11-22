# Pre publish sweep

Result: no gaps found in the code. One regression test was added.

## Debug and test tools
- Client/DebugGoto.lua returns at once unless RunService:IsStudio().
- Four server debug remotes (DebugGrantPatrons, DebugSetTag, DebugSetMod, DebugSetTarget) each start with `if not RunService:IsStudio() then return end`. A live server ignores them, so a client cannot grant Patrons or change a target.
- The engine test run at startup is wrapped in IsStudio.
- Free grants in the store only happen in Studio when an item has no Robux id. Live players see "coming soon".

## Remote handlers
- Every `OnServerEvent` handler in src/Server/init.server.lua either calls RateLimit.allow or is Studio gated (tested).
- Handlers that grant things (ClaimLoginReward, ClaimCollectionReward, ClaimSeason, StorePurchase, BuyPack, Choice) check argument types and re-check the rules on the server (streak day, XP, ownership, run phase). The client sends ids only, never amounts.
- RemoteFunctions: MakeChallengeSeed has a 1 second throttle, GetMenuTicker is rate limited and cached, the leaderboard functions are read only.
- SaveBadge rebuilds the badge from the server run state and takes no client data.

## TODOs, prints, user ids
- No TODO or FIXME markers in src (one mention of claude/ART_TODO.md in a comment).
- Server prints are Studio gated (Shop trace, DebugGoto server, test banner). Nothing prints in the live path.
- No hard coded user ids on the server (tested).

## Test
"Pre publish sweep" in Shared/Tests/EngineTests.lua fails if a new Debug remote is not Studio gated, a new remote has no rate limit, or a numeric UserId comparison appears.
