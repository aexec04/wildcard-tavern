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
local BuyThemeRemote = newRemote("BuyTheme")
local EquipThemeRemote = newRemote("EquipTheme")
local AdvanceRoundRemote = newRemote("AdvanceRound")
local RestartRunRemote = newRemote("RestartRun")
local StateUpdatedRemote = newRemote("StateUpdated") -- server -> client

-- ===== 3. Session management =====

local SHOP_OFFER_COUNT = 3
local sessions = {} -- [player] = { state = RunState, phase = "playing" | "shop" | "gameover", shopOffers = {patron, ...} }

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

local function serializeCard(card)
	return { rank = card.rank, suit = card.suit }
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

	local shopOffers = {}
	for _, patron in ipairs(session.shopOffers) do
		table.insert(shopOffers, {
			id = patron.id, name = patron.name, description = patron.description, price = patron.price,
		})
	end

	-- Themes are static content data (colors, price) that the client can
	-- already read directly from ReplicatedStorage.Shared.Engine.Themes --
	-- we only need to tell the client WHICH ones this player owns/has
	-- equipped, not resend the whole catalog every update.
	local ownedThemeIds = {}
	for themeId in pairs(state.ownedThemes) do
		table.insert(ownedThemeIds, themeId)
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
		shopOffers = shopOffers,
		ownedThemeIds = ownedThemeIds,
		equippedTheme = state.equippedTheme,
	}
end

local function pushState(player)
	local session = sessions[player]
	if not session then
		return
	end
	StateUpdatedRemote:FireClient(player, serializeState(session))
end

local function startNewSession(player)
	sessions[player] = {
		state = RunState.new(),
		phase = "playing",
		shopOffers = {},
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
		session.shopOffers = pickShopOffers(session.state)
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

	local ok, err = pcall(RunState.advanceToNextRound, session.state)
	if not ok then
		warn("AdvanceRound error for " .. player.Name .. ": " .. tostring(err))
		return
	end

	session.phase = "playing"
	session.shopOffers = {}
	pushState(player)
end)

RestartRunRemote.OnServerEvent:Connect(function(player)
	if not sessions[player] then
		return
	end
	startNewSession(player)
end)
