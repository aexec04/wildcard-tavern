# Remote security audit

Every remote the client can fire is rate limited per player (`Engine/RateLimit`, a token bucket of 20 a second sustained, burst 40) on the first line of its server handler, and its arguments are checked on the server before anything changes (type, range, ownership and phase through `Engine/PayloadGuard` and the RunState functions; the fuzz tests send nil, strings, huge tables and negative indexes to each). Debug remotes return outside Studio. Server to client remotes have no handler. A test (`Remote audit`) fails when a remote is added to `src/Server/Remotes.lua` or `init.server.lua` without a row here, or when a client fired remote has no rate limit line.

| Remote | Kind | Limit | Arguments |
|---|---|---|---|
| PlayHand | client to server | `Rem.PlayHand` bucket | none |
| Discard | client to server | `Rem.Discard` bucket | none |
| BuyPatron | client to server | `Rem.BuyPatron` bucket | none |
| SellPatron | client to server | `Rem.SellPatron` bucket | "Discard" was already taken by the card-discard remote above |
| UndoSellPatron | client to server | `Rem.UndoSellPatron` bucket | (player): puts the last sold Patron back within 5 seconds (Engine/SellUndo) |
| MovePatron | client to server | `Rem.MovePatron` bucket | (player, patronId, dir) dir -1 or 1: swap a Patron with its neighbour |
| BuyCosmeticSet | client to server | `Rem.BuyCosmeticSet` bucket | (player, setId) |
| EquipCosmeticSet | client to server | `Rem.EquipCosmeticSet` bucket | (player, setId) |
| ClaimLoginReward | client to server | `Rem.ClaimLoginReward` bucket | (player, rewardDay) |
| MarkSeenNew | client to server | `Rem.MarkSeenNew` bucket | (player, array of "kind:id" keys): clears New ribbons, validated against what the profile owns |
| DismissWhatsNew | client to server | `Rem.DismissWhatsNew` bucket | (player): the What's new plate was dismissed, saved as the current version |
| SaveBadge | client to server | `Rem.SaveBadge` bucket | (player): saves the finished run's badge as the profile badge |
| EquipCardBack | client to server | `Rem.EquipCardBack` bucket | (player, backId or nil to follow the set) |
| EquipJourneyReward | client to server | `Rem.EquipJourneyReward` bucket | JOURNEY: (player, night) equips that node's earned reward |
| ClaimDiscovery | client to server | `Rem.ClaimDiscovery` bucket | (player, spotId): claims a revealed map spot |
| RevealDiscoveries | client to server | `Rem.RevealDiscoveries` bucket | (player, region): spends a compass charge to reveal a region's spots |
| SpectateAction | client to server | `Rem.SpectateAction` bucket | (player, action "watch"/"stop"/"react"/"block"/"unblock", argument) |
| EquipFlair | client to server | `Rem.EquipFlair` bucket | (player, slot id, flair id): Engine/Flair.lua, validated and saved |
| ClaimCollectionReward | client to server | `Rem.ClaimCollectionReward` bucket | (player, group id, percent) or (player, "all") |
| UseRuleBan | client to server | `UseRuleBanRemote` bucket | (player): spend a Rule Ban token on this Night's boss (validated by RunState.useRuleBan) |
| StoreOpened | client to server | `Rem.StoreOpened` bucket | (player): the Store panel was opened (tuning data only) |
| HintSeen | client to server | `Rem.HintSeen` bucket | (player, hint id): a first time hint was shown, never show it again |
| ResetHints | client to server | `Rem.ResetHints` bucket | (player): Settings > Replay Hints |
| ClaimSeason | client to server | `Rem.ClaimSeason` bucket | (player, tier number or "all"): Tavern Season track rewards |
| RedeemCode | client to server | `Rem.RedeemCode` bucket | (player, text): Codes box, validated and rate limited on the server (Engine/Codes.lua) |
| ClaimLiveEvent | client to server | `Rem.ClaimLiveEvent` bucket | (player, eventId): claims the rewards of a running event once |
| StorePurchase | client to server | `Rem.StorePurchase` bucket | (player, itemId): prompts the purchase, or grants a placeholder free in Studio |
| Choice | client to server | `Rem.Choice` bucket | (player, optionId): answers the open draft or event card |
| ChooseRoad | client to server | `Rem.ChooseRoad` bucket | WORLD MAP: (player, stopId) picks the next road at a fork, roundSelect only |
| Minigame | client to server | `Rem.Minigame` bucket | WORLD MAP: (player, stopId, action, arg) map minigames, scored on the server |
| SideStop | client to server | `Rem.SideStop` bucket | WORLD MAP: (player, stopId, action, arg) shop/shrine/rest side stops |
| EquipBadge | client to server | `Rem.EquipBadge` bucket | BADGES: (player, badgeId/nil) equips an owned badge |
| UnlockRoad | client to server | `Rem.UnlockRoad` bucket | WORLD MAP: (player, stopId) spends a Key to open a locked road at a pending fork |
| UseCompass | client to server | `Rem.UseCompass` bucket | WORLD MAP: (player) spends a compass charge at a fork |
| EquipTitle | client to server | `Rem.EquipTitle` bucket | ACHIEVEMENTS + TITLES (Phase 16): (player, achievementId or nil) |
| PreviewMode | client to server | `Rem.PreviewMode` bucket | (player, on boolean): Card Set Preview is look-only, run remotes are rejected while on (Engine/PreviewGuard) |
| DebugGrantPatrons | Studio only | returns outside Studio | STUDIO ONLY (ignored elsewhere): (player, n 0..8) seats n different Patrons through RunState.grantPatron, for DebugGoto patrons:<n> |
| DebugSetTag | Studio only | returns outside Studio | STUDIO ONLY (ignored elsewhere): (player, tagId) makes that Tag the current round's skip Tag, for DebugGoto round1:tag=<id> |
| DebugSetMod | Studio only | returns outside Studio | STUDIO ONLY (ignored elsewhere): (player, modId, report) makes the open blessing draft offer modId (report=true prints the applied numbers instead), for DebugGoto round1:mod=<id> |
| DebugSetTarget | Studio only | returns outside Studio | (player, n) sets the current round target, for DebugGoto playhand:keep |
| DebugJump | Studio only | returns outside Studio | (player, key string) puts a real screen on the live run (night, bossN, reward, shop, recipes, victory, endrun ...), Engine/DebugJump |
| DebugEquipSet | Studio only | returns outside Studio | STUDIO ONLY (ignored elsewhere): (player, setId) equips that Card Set without the ownership check, for DebugGoto equip:<setId> |
| DebugFreshSave | Studio only | returns outside Studio | STUDIO ONLY (ignored elsewhere): (player) resets the profile to PlayerProfile.new(), for DebugGoto freshsave; profile only, never a run |
| SetSetting | client to server | `Rem.SetSetting` bucket | (player, key string, value) -- see PlayerProfile.SETTING_SPECS |
| MarkTutorialSeen | client to server | `Rem.MarkTutorialSeen` bucket | TUTORIAL (Phase 16): (player) -- fired once the walkthrough is dismissed/skipped |
| BuyRecipe | client to server | `Rem.BuyRecipe` bucket | (player, category, id) -- see the comment above its handler: direct-buy is unreachable from the current UI, kept for direct engine/test use |
| UseRecipe | client to server | `Rem.UseRecipe` bucket | (player, category, id, cardIndices, suit) |
| SellRecipe | client to server | `Rem.SellRecipe` bucket | (player, category, id): sells a held Recipe from the table tray |
| RerollShop | client to server | `Rem.RerollShop` bucket | (player) -- pay tips to reroll Patron/Pack/Voucher offers |
| Haggle | client to server | `Rem.Haggle` bucket | (player, action "start"/"stop", kind "patron"/"pack", id): Engine/Haggle.lua, timed on the server clock |
| Stranger | client to server | `Rem.Stranger` bucket | (player, action "accept"/"decline"): the Wandering Stranger's Dealer's Bargain (Engine/Strangers.lua) |
| BuyPack | client to server | `Rem.BuyPack` bucket | (player, packId) |
| ResolvePack | client to server | `Rem.ResolvePack` bucket | (player, chosenIds) |
| BuyHousePass | client to server | `Rem.BuyHousePass` bucket | (player, passId) |
| BuyMark | client to server | `Rem.BuyMark` bucket | (player, markId, rank, suit) |
| MapEvent | client to server | `Rem.MapEvent` bucket | (player, "shrine") or (player, "market", markId, rank, suit): Engine/MapEvents |
| AdvanceRound | client to server | `Rem.AdvanceRound` bucket | none |
| SelectRound | client to server | `Rem.SelectRound` bucket | (player) |
| SkipRound | client to server | `Rem.SkipRound` bucket | (player) |
| RestartRun | client to server | `Rem.RestartRun` bucket | none |
| AbandonRun | client to server | `Rem.AbandonRun` bucket | Settings > Restart Run (confirmed on the client); no args |
| StartTutorial | client to server | `Rem.StartTutorial` bucket | Menu Tutorial tile only: starts the scripted tutorial run |
| StartRun | client to server | `Rem.StartRun` bucket | like RestartRun, but with a chosen Deck Variant + Difficulty |
| StateUpdated | server to client | none (no handler) | server -> client |
| StartDailyChallenge | client to server | `Rem.StartDailyChallenge` bucket | (player) |
| GetDailyLeaderboard | RemoteFunction | per player cooldown or rate limit in its handler | none |
| StartWeeklyChallenge | client to server | `Rem.StartWeeklyChallenge` bucket | (player) |
| GetEndlessLeaderboard | RemoteFunction | per player cooldown or rate limit in its handler | none |
| MakeChallengeSeed | RemoteFunction | per player cooldown or rate limit in its handler | none |
| GetWeeklyLeaderboard | RemoteFunction | per player cooldown or rate limit in its handler | none |
| LeaderboardTicker | server to client | none (no handler) | none |
| FriendPresence | server to client | none (no handler) | none |
| StartSeedRun | client to server | `Rem.StartSeedRun` bucket | (player, code) |
| RequestContinue | client to server | `Rem.RequestContinue` bucket | none |
| RequestState | client to server | `Rem.RequestState` bucket | none |
| SpectateStream | server to client | none (no handler) | (server to client) whitelisted spectate events |
