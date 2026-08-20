--[[
	Server/init.server.lua
	Runs once on the server when the game starts. Responsibilities:
	  1. Run the engine unit tests and print PASS/FAIL to the Output window
	     every time you hit Play in Studio -- this is our "very testable"
	     safety net without needing anything installed outside Roblox.
	  2. Set up RemoteEvents for the client to call.
	  3. Own the authoritative RunState per player and respond to their
	     actions (play a hand, discard, buy a patron, advance a round).

	This is intentionally a single flat script for the MVP. Once the core
	loop feels good, split it into smaller modules (e.g. SessionManager,
	RemoteHandlers) -- but don't do that until you actually feel the pain
	of one big file; premature splitting costs more than it saves this week.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Engine = Shared:WaitForChild("Engine")
local Tests = Shared:WaitForChild("Tests")

local RunState = require(Engine.RunState)
local Patrons = require(Engine.Patrons)
local Deck = require(Engine.Deck)
local Recipes = require(Engine.Recipes)
local Packs = require(Engine.Packs)
local HousePasses = require(Engine.HousePasses)

-- ===== 1. Run engine tests on server start =====

do
	local TestRunner = require(Tests.TestRunner)
	local engineTests = require(Tests.EngineTests)
	print("===== Wildcard Tavern: running engine tests =====")
	local results = TestRunner.run(engineTests)
	if results.failed > 0 then
		warn(string.format("%d engine test(s) FAILED -- fix these before trusting the game logic!", results.failed))
	end
	print("===================================================")
end

-- ===== 2. RemoteEvents =====

local remotes = Instance.new("Folder")
remotes.Name = "Remotes"
remotes.Parent = ReplicatedStorage

local function newRemote(name)
	local r = Instance.new("RemoteEvent")
	r.Name = name
	r.Parent = remotes
	return r
end

local PlayHandRemote = newRemote("PlayHand")
local DiscardRemote = newRemote("Discard")
local BuyPatronRemote = newRemote("BuyPatron")
local SellPatronRemote = newRemote("SellPatron") -- "Discard" was already taken by the card-discard remote above
local BuyThemeRemote = newRemote("BuyTheme")
local EquipThemeRemote = newRemote("EquipTheme")
local BuyRecipeRemote = newRemote("BuyRecipe")   -- (player, category, id) -- see the comment above its handler: direct-buy is unreachable from the current UI, kept for direct engine/test use
local UseRecipeRemote = newRemote("UseRecipe")   -- (player, category, id, cardIndices, suit)
local RerollShopRemote = newRemote("RerollShop") -- (player) -- pay tips to reroll Patron/Pack/Voucher offers
local BuyPackRemote = newRemote("BuyPack")       -- (player, packId)
local ResolvePackRemote = newRemote("ResolvePack") -- (player, chosenIds)
local BuyHousePassRemote = newRemote("BuyHousePass") -- (player, passId)
local AdvanceRoundRemote = newRemote("AdvanceRound")
local RestartRunRemote = newRemote("RestartRun")
local StartRunRemote = newRemote("StartRun") -- like RestartRun, but with a chosen Deck Variant + Difficulty
local StateUpdatedRemote = newRemote("StateUpdated") -- server -> client

-- ===== 3. Session management =====

-- Matches the reference game's usual shop layout more closely than our old
-- "3 Patron offers, nothing else" did: 2 Patron offers + 2 Pack offers
-- every visit, plus an occasional single Voucher (House Pass) offer -- see
-- VOUCHER_CHANCE. Reroll cost climbs by REROLL_COST_STEP each reroll
-- within a single shop visit, then resets to REROLL_BASE_COST next visit.
local SHOP_OFFER_COUNT = 2
local PACK_OFFER_COUNT = 2
local VOUCHER_CHANCE = 0.35
local REROLL_BASE_COST = 5
local REROLL_COST_STEP = 2

local sessions = {} -- [player] = { state = RunState, phase = "playing" | "shop" | "gameover", shopOffers = {patron, ...}, packOffers = {pack, ...}, voucherOffer = pass | nil, rerollCost = number }

local function pickShopOffers(state)
	local available = {}
	for _, patron in ipairs(Patrons.Definitions) do
		local alreadyOwned = false
		for _, owned in ipairs(state.ownedPatrons) do
			if owned.id == patron.id then
				alreadyOwned = true
				break
			end
		end
		if not alreadyOwned then
			table.insert(available, patron)
		end
	end

	-- shuffle-ish pick
	local offers = {}
	for _ = 1, math.min(SHOP_OFFER_COUNT, #available) do
		local i = math.random(1, #available)
		table.insert(offers, table.remove(available, i))
	end
	return offers
end

local function pickPackOffers()
	local pool = {}
	for _, pack in ipairs(Packs.Definitions) do
		table.insert(pool, pack)
	end
	local offers = {}
	for _ = 1, math.min(PACK_OFFER_COUNT, #pool) do
		local i = math.random(1, #pool)
		table.insert(offers, table.remove(pool, i))
	end
	return offers
end

-- Only offers a House Pass the player doesn't already own, and only some of
-- the time -- "shows up from time to time," not every visit, same as the
-- reference game's Voucher slot.
local function pickVoucherOffer(state)
	if math.random() > VOUCHER_CHANCE then
		return nil
	end
	local available = {}
	for _, pass in ipairs(HousePasses.Definitions) do
		if not state.housePasses[pass.id] then
			table.insert(available, pass)
		end
	end
	if #available == 0 then
		return nil
	end
	return available[math.random(1, #available)]
end

-- Rerolls just the offers, keeping whatever the current rerollCost climbed
-- to (the caller bumps it after using this). Opening a fresh shop visit
-- uses this too, via openShop below, which additionally resets the cost.
local function rollShopOffers(session)
	session.shopOffers = pickShopOffers(session.state)
	session.packOffers = pickPackOffers()
	session.voucherOffer = pickVoucherOffer(session.state)
end

local function openShop(session)
	rollShopOffers(session)
	session.rerollCost = REROLL_BASE_COST
end

local function serializeCard(card)
	return { rank = card.rank, suit = card.suit, garnish = card.garnish, special = card.special, stamp = card.stamp }
end

local function serializeState(session)
	local state = session.state
	local hand = {}
	for _, card in ipairs(state.hand) do
		table.insert(hand, serializeCard(card))
	end

	local owned = {}
	for _, patron in ipairs(state.ownedPatrons) do
		table.insert(owned, { id = patron.id, name = patron.name, description = patron.description })
	end

	-- Prices below go through RunState.patronPrice/packPrice so the client
	-- never has to duplicate House Pass discount math -- it just displays
	-- whatever price it's sent.
	local shopOffers = {}
	for _, patron in ipairs(session.shopOffers) do
		table.insert(shopOffers, {
			id = patron.id, name = patron.name, description = patron.description,
			price = RunState.patronPrice(state, patron),
		})
	end

	local packOffers = {}
	for _, pack in ipairs(session.packOffers or {}) do
		table.insert(packOffers, {
			id = pack.id, name = pack.name, icon = pack.icon, description = pack.description,
			price = RunState.packPrice(state, pack),
		})
	end

	local voucherOffer = nil
	if session.voucherOffer then
		voucherOffer = {
			id = session.voucherOffer.id, name = session.voucherOffer.name, icon = session.voucherOffer.icon,
			description = session.voucherOffer.description, price = session.voucherOffer.price,
		}
	end

	local housePassIds = {}
	for passId in pairs(state.housePasses) do
		table.insert(housePassIds, passId)
	end

	-- Themes are static content data (colors, price) that the client can
	-- already read directly from ReplicatedStorage.Shared.Engine.Themes --
	-- we only need to tell the client WHICH ones this player owns/has
	-- equipped, not resend the whole catalog every update.
	local ownedThemeIds = {}
	for themeId in pairs(state.ownedThemes) do
		table.insert(ownedThemeIds, themeId)
	end

	local bossModifier = nil
	if state.bossModifier then
		bossModifier = {
			id = state.bossModifier.id,
			name = state.bossModifier.name,
			description = state.bossModifier.description,
		}
	end

	return {
		phase = session.phase,
		night = state.night,
		round = state.round,
		tips = state.tips,
		hand = hand,
		handsRemaining = state.handsRemaining,
		discardsRemaining = state.discardsRemaining,
		roundScore = state.roundScore,
		targetScore = state.targetScore,
		ownedPatrons = owned,
		patronSlotLimit = RunState.patronSlotLimit(state),
		shopOffers = shopOffers,
		packOffers = packOffers,
		voucherOffer = voucherOffer,
		rerollCost = RunState.rerollCost(state, session.rerollCost or REROLL_BASE_COST),
		-- pendingPack is already the lightweight { packId, category, pickCount,
		-- items = {id,name,icon,description} } shape RunState.openPack builds
		-- -- safe to ship as-is, same as deckCounts/handLevels below.
		pendingPack = state.pendingPack,
		housePassIds = housePassIds,
		ownedThemeIds = ownedThemeIds,
		equippedTheme = state.equippedTheme,
		deckVariantId = state.deckVariantId,
		difficultyId = state.difficultyId,
		bossModifier = bossModifier,
		handStats = state.handStats,
		handLevels = state.handLevels,
		-- Recipes.HouseRecipes/MenuRecipes/SecretRecipes are static content
		-- the client already reads straight from
		-- ReplicatedStorage.Shared.Engine.Recipes (same pattern as Themes
		-- above) -- we only need to say WHICH ones this player owns.
		houseRecipeInventory = state.houseRecipeInventory,
		menuRecipeInventory = state.menuRecipeInventory,
		secretRecipeInventory = state.secretRecipeInventory,
		-- Deck.remainingCounts is [suit] = { [rank] = count } -- RemoteEvents
		-- serialize nested tables fine, so this ships as-is.
		deckCounts = Deck.remainingCounts(state.deck),
	}
end

local function pushState(player)
	local session = sessions[player]
	if not session then
		return
	end
	StateUpdatedRemote:FireClient(player, serializeState(session))
end

-- deckVariantId/difficultyId are optional -- RunState.new falls back to the
-- standard/standard defaults for nil or unrecognized ids.
local function startNewSession(player, deckVariantId, difficultyId)
	sessions[player] = {
		state = RunState.new({ deckVariantId = deckVariantId, difficultyId = difficultyId }),
		phase = "playing",
		shopOffers = {},
		packOffers = {},
		voucherOffer = nil,
		rerollCost = REROLL_BASE_COST,
	}
	pushState(player)
end

Players.PlayerAdded:Connect(startNewSession)
Players.PlayerRemoving:Connect(function(player)
	sessions[player] = nil
end)

-- In Studio, PlayerAdded may have already fired for existing test players.
for _, player in ipairs(Players:GetPlayers()) do
	startNewSession(player)
end

-- ===== 4. Remote handlers =====
-- NOTE: every handler re-validates on the server. Never trust the client --
-- a player could fire these remotes directly with bogus data.

local function isValidIndexList(list, handSize)
	if type(list) ~= "table" or #list < 1 or #list > 5 then
		return false
	end
	local seen = {}
	for _, i in ipairs(list) do
		if type(i) ~= "number" or i < 1 or i > handSize or seen[i] then
			return false
		end
		seen[i] = true
	end
	return true
end

PlayHandRemote.OnServerEvent:Connect(function(player, cardIndices)
	local session = sessions[player]
	if not session or session.phase ~= "playing" then
		return
	end
	if not isValidIndexList(cardIndices, #session.state.hand) then
		return
	end

	local ok, result = pcall(RunState.playHand, session.state, cardIndices)
	if not ok then
		warn("PlayHand error for " .. player.Name .. ": " .. tostring(result))
		return
	end

	if result.roundWon then
		session.phase = "shop"
		openShop(session)
	elseif result.runOver then
		session.phase = "gameover"
	end

	pushState(player)
end)

DiscardRemote.OnServerEvent:Connect(function(player, cardIndices)
	local session = sessions[player]
	if not session or session.phase ~= "playing" then
		return
	end
	if not isValidIndexList(cardIndices, #session.state.hand) then
		return
	end
	if session.state.discardsRemaining <= 0 then
		return
	end

	local ok, err = pcall(RunState.discard, session.state, cardIndices)
	if not ok then
		warn("Discard error for " .. player.Name .. ": " .. tostring(err))
		return
	end

	pushState(player)
end)

BuyPatronRemote.OnServerEvent:Connect(function(player, patronId)
	local session = sessions[player]
	if not session or session.phase ~= "shop" then
		return
	end
	-- Finish resolving an open Pack reveal before doing anything else in the
	-- shop -- same as the reference game, a Pack takes over the whole shop
	-- screen until you pick (or skip).
	if session.state.pendingPack then
		return
	end
	if type(patronId) ~= "string" then
		return
	end

	-- Only allow buying patrons that were actually offered this shop visit.
	local offered = false
	for _, patron in ipairs(session.shopOffers) do
		if patron.id == patronId then
			offered = true
			break
		end
	end
	if not offered then
		return
	end

	local ok = RunState.buyPatron(session.state, patronId)
	if ok then
		-- Remove the bought offer so it can't be bought twice this visit.
		for i, patron in ipairs(session.shopOffers) do
			if patron.id == patronId then
				table.remove(session.shopOffers, i)
				break
			end
		end
	end

	pushState(player)
end)

-- Discarding an owned Patron, like theme purchases below, isn't gated to
-- the shop phase -- it's tidying up your table, not a purchase decision
-- tied to a specific shop visit's offers.
SellPatronRemote.OnServerEvent:Connect(function(player, patronId)
	local session = sessions[player]
	if not session then
		return
	end
	if type(patronId) ~= "string" then
		return
	end

	RunState.sellPatron(session.state, patronId)
	pushState(player)
end)

-- ===== Recipes (House/Menu/Secret) -- Phase 1b =====
-- Buying AND using are both gated to the shop phase: House/Secret
-- Recipes target cards in state.hand, and the only hand a player can see
-- while the shop overlay is open is whatever's left over from the round
-- they just won -- so "shop visit" is the one moment using one makes
-- sense in the current UI. Menu Recipes don't need cards at all but are
-- gated the same way for a single consistent rule.

local RECIPE_CATEGORIES = {
	house = { catalog = Recipes.HouseRecipes, buy = RunState.buyHouseRecipe, use = RunState.useHouseRecipe },
	menu = { catalog = Recipes.MenuRecipes, buy = RunState.buyMenuRecipe, use = RunState.useMenuRecipe },
	secret = { catalog = Recipes.SecretRecipes, buy = RunState.buySecretRecipe, use = RunState.useSecretRecipe },
}

local function findRecipe(catalog, id)
	for _, recipe in ipairs(catalog) do
		if recipe.id == id then
			return recipe
		end
	end
	return nil
end

BuyRecipeRemote.OnServerEvent:Connect(function(player, category, id)
	local session = sessions[player]
	if not session or session.phase ~= "shop" then
		return
	end
	if session.state.pendingPack then
		return
	end
	local def = RECIPE_CATEGORIES[category]
	if not def or type(id) ~= "string" or not findRecipe(def.catalog, id) then
		return
	end

	local ok, err = pcall(def.buy, session.state, id)
	if not ok then
		warn("BuyRecipe error for " .. player.Name .. ": " .. tostring(err))
		return
	end

	pushState(player)
end)

UseRecipeRemote.OnServerEvent:Connect(function(player, category, id, cardIndices, suit)
	local session = sessions[player]
	if not session or session.phase ~= "shop" then
		return
	end
	if session.state.pendingPack then
		return
	end
	local def = RECIPE_CATEGORIES[category]
	if not def or type(id) ~= "string" then
		return
	end
	local recipe = findRecipe(def.catalog, id)
	if not recipe then
		return
	end

	local opts = {}
	if recipe.cardCount then
		if not isValidIndexList(cardIndices, #session.state.hand) then
			return
		end
		if #cardIndices < recipe.cardCount.min or #cardIndices > recipe.cardCount.max then
			return
		end
		opts.cardIndices = cardIndices
	end
	if recipe.needsSuit then
		if type(suit) ~= "string" then
			return
		end
		opts.suit = suit
	end

	local ok, err = pcall(def.use, session.state, id, opts)
	if not ok then
		warn("UseRecipe error for " .. player.Name .. ": " .. tostring(err))
		return
	end

	pushState(player)
end)

-- ===== Reroll / Packs / House Passes (Vouchers) =====
-- The shop is now randomized every visit (2 Patron offers + 2 Pack offers +
-- an occasional Voucher, see openShop/pickVoucherOffer above) instead of a
-- static full-catalog browse -- matches the reference game and makes the
-- Reroll button a real decision (spend Tips now for a fresh set of offers).

RerollShopRemote.OnServerEvent:Connect(function(player)
	local session = sessions[player]
	if not session or session.phase ~= "shop" then
		return
	end
	if session.state.pendingPack then
		return
	end
	local cost = RunState.rerollCost(session.state, session.rerollCost or REROLL_BASE_COST)
	if session.state.tips < cost then
		return
	end
	session.state.tips = session.state.tips - cost
	rollShopOffers(session)
	session.rerollCost = (session.rerollCost or REROLL_BASE_COST) + REROLL_COST_STEP
	pushState(player)
end)

BuyPackRemote.OnServerEvent:Connect(function(player, packId)
	local session = sessions[player]
	if not session or session.phase ~= "shop" then
		return
	end
	if session.state.pendingPack then
		return
	end
	if type(packId) ~= "string" then
		return
	end

	-- Only allow buying packs that were actually offered this shop visit --
	-- same rule as Patron offers above.
	local offered = false
	for _, pack in ipairs(session.packOffers) do
		if pack.id == packId then
			offered = true
			break
		end
	end
	if not offered then
		return
	end

	local ok, revealOrErr = pcall(RunState.openPack, session.state, packId)
	if not ok then
		warn("BuyPack error for " .. player.Name .. ": " .. tostring(revealOrErr))
		return
	end
	if not revealOrErr then
		-- Logical failure (e.g. not enough tips) -- leave the offer in place,
		-- nothing was charged.
		return
	end

	for i, pack in ipairs(session.packOffers) do
		if pack.id == packId then
			table.remove(session.packOffers, i)
			break
		end
	end
	pushState(player)
end)

ResolvePackRemote.OnServerEvent:Connect(function(player, chosenIds)
	local session = sessions[player]
	if not session or session.phase ~= "shop" then
		return
	end
	if type(chosenIds) ~= "table" or #chosenIds > 10 then
		return
	end
	for _, id in ipairs(chosenIds) do
		if type(id) ~= "string" then
			return
		end
	end

	local ok, err = pcall(RunState.resolvePack, session.state, chosenIds)
	if not ok then
		warn("ResolvePack error for " .. player.Name .. ": " .. tostring(err))
		return
	end

	pushState(player)
end)

BuyHousePassRemote.OnServerEvent:Connect(function(player, passId)
	local session = sessions[player]
	if not session or session.phase ~= "shop" then
		return
	end
	if session.state.pendingPack then
		return
	end
	if type(passId) ~= "string" then
		return
	end
	if not session.voucherOffer or session.voucherOffer.id ~= passId then
		return
	end

	local ok = RunState.buyHousePass(session.state, passId)
	if ok then
		session.voucherOffer = nil
	end
	pushState(player)
end)

-- Cosmetic theme purchases/equips are allowed any time (not gated to the
-- shop phase) -- they don't affect gameplay, so there's no reason to lock
-- them to between-round moments the way Patron purchases are.

BuyThemeRemote.OnServerEvent:Connect(function(player, themeId)
	local session = sessions[player]
	if not session then
		return
	end
	if type(themeId) ~= "string" then
		return
	end

	local ok, err = pcall(RunState.buyTheme, session.state, themeId)
	if not ok then
		warn("BuyTheme error for " .. player.Name .. ": " .. tostring(err))
		return
	end

	pushState(player)
end)

EquipThemeRemote.OnServerEvent:Connect(function(player, themeId)
	local session = sessions[player]
	if not session then
		return
	end
	if type(themeId) ~= "string" then
		return
	end

	local ok, err = pcall(RunState.equipTheme, session.state, themeId)
	if not ok then
		warn("EquipTheme error for " .. player.Name .. ": " .. tostring(err))
		return
	end

	pushState(player)
end)

AdvanceRoundRemote.OnServerEvent:Connect(function(player)
	local session = sessions[player]
	if not session or session.phase ~= "shop" then
		return
	end
	-- Resolve (or skip) any open Pack before leaving the shop.
	if session.state.pendingPack then
		return
	end

	local ok, err = pcall(RunState.advanceToNextRound, session.state)
	if not ok then
		warn("AdvanceRound error for " .. player.Name .. ": " .. tostring(err))
		return
	end

	session.phase = "playing"
	session.shopOffers = {}
	session.packOffers = {}
	session.voucherOffer = nil
	-- Safety net, not the normal path: a pack should always be resolved
	-- (or skipped) before Next Round is even clickable client-side, but
	-- don't leave a stale one open across the round boundary if it happens.
	session.state.pendingPack = nil
	pushState(player)
end)

RestartRunRemote.OnServerEvent:Connect(function(player)
	local session = sessions[player]
	if not session then
		return
	end
	-- Quick restart: keep whatever Deck Variant/Difficulty this player last
	-- used. Use StartRun instead to pick fresh ones via the Run Setup screen.
	startNewSession(player, session.state.deckVariantId, session.state.difficultyId)
end)

StartRunRemote.OnServerEvent:Connect(function(player, deckVariantId, difficultyId)
	if not sessions[player] then
		return
	end
	if type(deckVariantId) ~= "string" then
		deckVariantId = nil
	end
	if type(difficultyId) ~= "string" then
		difficultyId = nil
	end
	startNewSession(player, deckVariantId, difficultyId)
end)
