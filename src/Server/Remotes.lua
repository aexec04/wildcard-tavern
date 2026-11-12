-- All server RemoteEvents/RemoteFunctions, created once. Split out of init.server.lua to keep its main chunk under Lua's 200 local limit.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local remotes = Instance.new("Folder")
remotes.Name = "Remotes"
remotes.Parent = ReplicatedStorage

local function newRemote(name)
	local r = Instance.new("RemoteEvent")
	r.Name = name
	r.Parent = remotes
	return r
end

local Rem = {} -- every remote, keyed by its remote name
Rem.PlayHand = newRemote("PlayHand")
Rem.Discard = newRemote("Discard")
Rem.BuyPatron = newRemote("BuyPatron")
Rem.SellPatron = newRemote("SellPatron") -- "Discard" was already taken by the card-discard remote above
Rem.BuyCosmeticSet = newRemote("BuyCosmeticSet") -- (player, setId)
Rem.EquipCosmeticSet = newRemote("EquipCosmeticSet") -- (player, setId)
Rem.ClaimLoginReward = newRemote("ClaimLoginReward") -- (player, rewardDay)
Rem.SaveBadge = newRemote("SaveBadge") -- (player): saves the finished run's badge as the profile badge
Rem.EquipCardBack = newRemote("EquipCardBack") -- (player, backId or nil to follow the set)
Rem.EquipJourneyReward = newRemote("EquipJourneyReward") -- JOURNEY: (player, night) equips that node's earned reward
Rem.ClaimDiscovery = newRemote("ClaimDiscovery") -- (player, spotId): claims a revealed map spot
Rem.RevealDiscoveries = newRemote("RevealDiscoveries") -- (player, region): spends a compass charge to reveal a region's spots
Rem.SpectateAction = newRemote("SpectateAction") -- (player, action "watch"|"stop"|"react"|"block"|"unblock", argument)
Rem.EquipFlair = newRemote("EquipFlair") -- (player, slot id, flair id): Engine/Flair.lua, validated and saved
Rem.ClaimCollectionReward = newRemote("ClaimCollectionReward") -- (player, group id, percent) or (player, "all")
Rem.UseRuleBan = newRemote("UseRuleBan") -- (player): spend a Rule Ban token on this Night's boss (validated by RunState.useRuleBan)
Rem.StoreOpened = newRemote("StoreOpened") -- (player): the Store panel was opened (tuning data only)
Rem.HintSeen = newRemote("HintSeen") -- (player, hint id): a first time hint was shown, never show it again
Rem.ResetHints = newRemote("ResetHints") -- (player): Settings > Replay Hints
Rem.ClaimSeason = newRemote("ClaimSeason") -- (player, tier number or "all"): Tavern Season track rewards
Rem.ClaimLiveEvent = newRemote("ClaimLiveEvent") -- (player, eventId): claims the rewards of a running event once
Rem.StorePurchase = newRemote("StorePurchase") -- (player, itemId): prompts the purchase, or grants a placeholder free in Studio
Rem.Choice = newRemote("Choice") -- (player, optionId): answers the open draft or event card
Rem.ChooseRoad = newRemote("ChooseRoad") -- WORLD MAP: (player, stopId) picks the next road at a fork, roundSelect only
Rem.Minigame = newRemote("Minigame") -- WORLD MAP: (player, stopId, action, arg) map minigames, scored on the server
Rem.SideStop = newRemote("SideStop") -- WORLD MAP: (player, stopId, action, arg) shop/shrine/rest side stops
Rem.EquipBadge = newRemote("EquipBadge") -- BADGES: (player, badgeId|nil) equips an owned badge
Rem.UnlockRoad = newRemote("UnlockRoad") -- WORLD MAP: (player, stopId) spends a Key to open a locked road at a pending fork
Rem.UseCompass = newRemote("UseCompass") -- WORLD MAP: (player) spends a compass charge at a fork
Rem.EquipTitle = newRemote("EquipTitle") -- ACHIEVEMENTS + TITLES (Phase 16): (player, achievementId or nil)
Rem.PreviewMode = newRemote("PreviewMode") -- (player, on boolean): Card Set Preview is look-only, run remotes are rejected while on (Engine/PreviewGuard)
Rem.SetSetting = newRemote("SetSetting") -- (player, key string, value) -- see PlayerProfile.SETTING_SPECS
Rem.MarkTutorialSeen = newRemote("MarkTutorialSeen") -- TUTORIAL (Phase 16): (player) -- fired once the walkthrough is dismissed/skipped
Rem.BuyRecipe = newRemote("BuyRecipe")   -- (player, category, id) -- see the comment above its handler: direct-buy is unreachable from the current UI, kept for direct engine/test use
Rem.UseRecipe = newRemote("UseRecipe")   -- (player, category, id, cardIndices, suit)
Rem.RerollShop = newRemote("RerollShop") -- (player) -- pay tips to reroll Patron/Pack/Voucher offers
Rem.Haggle = newRemote("Haggle") -- (player, action "start"|"stop", kind "patron"|"pack", id): Engine/Haggle.lua, timed on the server clock
Rem.Stranger = newRemote("Stranger") -- (player, action "accept"|"decline"): the Wandering Stranger's Dealer's Bargain (Engine/Strangers.lua)
Rem.BuyPack = newRemote("BuyPack")       -- (player, packId)
Rem.ResolvePack = newRemote("ResolvePack") -- (player, chosenIds)
Rem.BuyHousePass = newRemote("BuyHousePass") -- (player, passId)
Rem.AdvanceRound = newRemote("AdvanceRound")
-- ROUND SELECT FEATURE: fired from Client/RoundSelect.lua, the screen
-- shown whenever phase == "roundSelect" (start of a run, and every time
-- after leaving the shop -- see below). SelectRound confirms "play this
-- round"; SkipRound takes this round's revealed Tag instead (see
-- RunState.canSkipRound/skipRound/Tags.lua).
Rem.SelectRound = newRemote("SelectRound") -- (player)
Rem.SkipRound = newRemote("SkipRound") -- (player)
Rem.RestartRun = newRemote("RestartRun")
Rem.AbandonRun = newRemote("AbandonRun") -- Settings > Restart Run (confirmed on the client); no args
Rem.StartTutorial = newRemote("StartTutorial") -- Menu Tutorial tile only: starts the scripted tutorial run
Rem.StartRun = newRemote("StartRun") -- like RestartRun, but with a chosen Deck Variant + Difficulty
Rem.StateUpdated = newRemote("StateUpdated") -- server -> client
-- DAILY CHALLENGE (Phase 11): a seeded standard/standard run, same for
-- every player on the same UTC day -- see Shared/Engine/SeededRng.lua's
-- header for exactly what "same" means once player choices start
-- diverging. GetDailyLeaderboard is a RemoteFunction (request/response,
-- not fire-and-forget) since the client needs the actual leaderboard data
-- back -- Roblox's RemoteFunction handles that yield/return shape
-- directly, no separate "here's your answer" RemoteEvent needed.
Rem.StartDailyChallenge = newRemote("StartDailyChallenge") -- (player)
local GetDailyLeaderboardRemote = Instance.new("RemoteFunction")
GetDailyLeaderboardRemote.Name = "GetDailyLeaderboard"
GetDailyLeaderboardRemote.Parent = remotes
Rem.GetDailyLeaderboard = GetDailyLeaderboardRemote

-- WEEKLY CHALLENGE (Phase 16): same shape as Daily Challenge above, just
-- bucketed into 7-day windows (SeededRng.weeklySeed/weeklyDateKey)
-- instead of calendar days -- gives the two of you a longer-running
-- comparison than the Daily board resets away every midnight.
Rem.StartWeeklyChallenge = newRemote("StartWeeklyChallenge") -- (player)
local GetEndlessLeaderboardRemote = Instance.new("RemoteFunction") -- ENDLESS board: highest Night reached, then best hand
GetEndlessLeaderboardRemote.Name = "GetEndlessLeaderboard"
GetEndlessLeaderboardRemote.Parent = remotes
Rem.GetEndlessLeaderboard = GetEndlessLeaderboardRemote
local MakeChallengeSeedRemote = Instance.new("RemoteFunction") -- run summary: a fresh seed code to challenge a friend with
MakeChallengeSeedRemote.Name = "MakeChallengeSeed"
MakeChallengeSeedRemote.Parent = remotes
Rem.MakeChallengeSeed = MakeChallengeSeedRemote
local GetWeeklyLeaderboardRemote = Instance.new("RemoteFunction")
GetWeeklyLeaderboardRemote.Name = "GetWeeklyLeaderboard"
GetWeeklyLeaderboardRemote.Parent = remotes
Rem.GetWeeklyLeaderboard = GetWeeklyLeaderboardRemote

-- PHASE B ("mind-blowing plan", Alive & Social): server -> client only,
-- see the "Phase B: Alive & Social" section further down for both.
-- LeaderboardTicker is a BROADCAST (FireAllClients) -- same Daily
-- Challenge top-N everyone already sees in the Daily board, just pushed
-- ambiently instead of only on request. FriendPresence is PER-PLAYER
-- (FireClient) -- each player's own friends-in-this-server list is
-- nobody else's business.
Rem.LeaderboardTicker = newRemote("LeaderboardTicker")
Rem.FriendPresence = newRemote("FriendPresence")

-- SHAREABLE SEED CODES (Phase 16): (player, code) -- starts a seeded
-- standard/standard run from a player-typed/shared code
-- (SeededRng.codeToSeed) instead of a date-derived seed. No leaderboard
-- of its own -- this is for two friends comparing a specific run
-- on demand, not a ranked board, so it's deliberately just the one
-- fire-and-forget remote.
Rem.StartSeedRun = newRemote("StartSeedRun") -- (player, code)

-- PAID CONTINUE: (player) -- fired from the Game Over panel's Continue
-- button. Prompts the "continue" Developer Product; the actual grant
-- happens in ProcessReceipt (see "Paid Continue" further down).
Rem.RequestContinue = newRemote("RequestContinue")

-- STATE RESYNC: (player) -- the client asks for the current table once its StateUpdated listener is connected (the push
-- sent at join can arrive before the client script has finished loading and is then lost, which left an empty table).
Rem.RequestState = newRemote("RequestState")

Rem._new = newRemote -- for remotes the main script creates later (init.server.lua)
Rem._folder = remotes

return Rem
