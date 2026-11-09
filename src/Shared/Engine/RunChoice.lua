--[[
	RunChoice.lua
	The "pick one" moments of a run, as plain data the server keeps in `session.choice` and ships to the client
	as `state.choice`. Pure Lua, no Roblox APIs.

	  * Start-of-run DRAFT (normal runs only): first 1 of 3 starting Patrons (never rare or better), then 1 of 3
	    run modifiers (a blessing with a matching curse, Engine/RunModifiers.lua).
	  * Between Nights, about half the time, one random EVENT card (Engine/RunEvents.lua) with a safe Decline.

	A choice is { kind = "patron" | "modifier" | "event", title, text, icon, eventId?, options = { { id, name, icon,
	line1, line2 } } } where every field is a plain string, safe to send to the client.

	Daily, Weekly, Seed and the tutorial never get a choice: callers pass `allowed = false` (fixed boards must
	stay fair, and the tutorial is scripted).
]]

local Patrons = require(script.Parent.Patrons)
local RunModifiers = require(script.Parent.RunModifiers)
local RunEvents = require(script.Parent.RunEvents)
local RunState = require(script.Parent.RunState)
local Unlocks = require(script.Parent.Unlocks)
local CollectionBook = require(script.Parent.CollectionBook)
local BossRush = require(script.Parent.BossRush)

local RunChoice = {}

RunChoice.DRAFT_SIZE = 3
RunChoice.MAX_START_RARITY = 2 -- index in CollectionBook.RarityOrder: common (1) or uncommon (2)

local function rngOf(state)
	return state.rng or math.random
end

local function rarityIndex(patron)
	local rarity = CollectionBook.rarityOf({ tab = "patrons", id = patron.id, def = patron })
	for i, id in ipairs(CollectionBook.RarityOrder) do
		if id == rarity then return i end
	end
	return #CollectionBook.RarityOrder
end

-- Draws `count` distinct entries from a list (does not change the list).
local function draw(list, count, rng)
	local pool = {}
	for _, v in ipairs(list) do pool[#pool + 1] = v end
	local out = {}
	for _ = 1, math.min(count, #pool) do
		out[#out + 1] = table.remove(pool, rng(#pool))
	end
	return out
end

-- Patrons that may be offered as a starting pick: open for this run, common or uncommon, not a road reward.
function RunChoice.startingPatrons(state)
	local list = {}
	for _, patron in ipairs(Unlocks.filter(state, "patron", Patrons.Definitions)) do
		if not patron.biome and rarityIndex(patron) <= RunChoice.MAX_START_RARITY then
			list[#list + 1] = patron
		end
	end
	return list
end

local function patronChoice(state)
	local picks = draw(RunChoice.startingPatrons(state), RunChoice.DRAFT_SIZE, rngOf(state))
	if #picks == 0 then
		return nil
	end
	local options = {}
	for _, p in ipairs(picks) do
		options[#options + 1] = { id = p.id, name = p.name, icon = p.icon, line1 = p.description or "", line2 = "" }
	end
	return { kind = "patron", title = "Choose your first Patron", text = "They sit at your table from the first hand.", icon = "🧑‍🍳", options = options }
end

local function modifierChoice(state)
	local picks = draw(RunModifiers.Definitions, RunChoice.DRAFT_SIZE, rngOf(state))
	local options = {}
	for _, m in ipairs(picks) do
		options[#options + 1] = { id = m.id, name = m.name, icon = m.icon, line1 = "+ " .. m.blessing, line2 = "- " .. m.curse }
	end
	return { kind = "modifier", title = "Choose a blessing", text = "Every blessing comes with a catch.", icon = "🎁", options = options }
end

-- BOSS RUSH: take BossRush.PICKS Patrons along, one pick at a time from the same open list (no rarity limit).
-- `taken` lists the ids already picked, so each step shows the rest.
function RunChoice.rushDraft(state, step, taken)
	step = step or 1
	taken = taken or {}
	local pool = {}
	for _, patron in ipairs(Unlocks.filter(state, "patron", Patrons.Definitions)) do
		local used = false
		for _, id in ipairs(taken) do
			if id == patron.id then used = true end
		end
		if not used and not patron.biome then pool[#pool + 1] = patron end
	end
	local picks = draw(pool, BossRush.OFFERS, rngOf(state))
	if #picks == 0 then
		return nil
	end
	local options = {}
	for _, p in ipairs(picks) do
		options[#options + 1] = { id = p.id, name = p.name, icon = p.icon, line1 = p.description or "", line2 = "" }
	end
	return {
		kind = "rushPatron", step = step, taken = taken,
		title = string.format("Boss Rush: pick Patron %d of %d", step, BossRush.PICKS),
		text = "No shop here. These Patrons are all you get.", icon = "⚔️", options = options,
	}
end

-- The first choice of a fresh normal run, or nil when `allowed` is false (seeded and tutorial runs).
function RunChoice.startDraft(state, allowed)
	if allowed == false then
		return nil
	end
	return patronChoice(state) or modifierChoice(state)
end

local function eventChoice(event)
	local options = {}
	for _, o in ipairs(event.options) do
		options[#options + 1] = { id = o.id, name = o.label, icon = o.id == "decline" and "✋" or event.icon, line1 = o.detail or "", line2 = "" }
	end
	return { kind = "event", eventId = event.id, title = event.name, text = event.text, icon = event.icon, options = options }
end

-- Maybe an event between Nights (about RunEvents.CHANCE_PERCENT). nil = none this time or not allowed.
function RunChoice.rollEvent(state, allowed)
	if allowed == false then
		return nil
	end
	local rng = rngOf(state)
	if rng(100) > RunEvents.CHANCE_PERCENT then
		return nil
	end
	local list = RunEvents.availableFor(state)
	if #list == 0 then
		return nil
	end
	return eventChoice(list[rng(#list)])
end

-- Dev preview: builds the card for one event id whatever the roll or Night (Studio only, the server gates it). nil if unknown.
function RunChoice.forceEvent(eventId)
	local event = type(eventId) == "string" and RunEvents.getById(eventId) or nil
	return event and eventChoice(event) or nil
end

-- A choice can only be answered while Round Select is up, a choice is open and the id is a string.
function RunChoice.canAnswer(phase, choice, optionId)
	return phase == "roundSelect" and type(choice) == "table" and type(optionId) == "string"
end

-- Applies the player's pick to the run. Returns ok, message, nextChoice (the modifier step after the Patron step).
-- A failed pick (not an offered id, or an event that cannot be paid) changes nothing and keeps the choice open.
function RunChoice.pick(state, choice, optionId)
	if type(choice) ~= "table" or type(optionId) ~= "string" then
		return false, "No choice open."
	end
	local offered = false
	for _, o in ipairs(choice.options) do
		if o.id == optionId then offered = true end
	end
	if not offered then
		return false, "That is not one of the options."
	end
	if choice.kind == "patron" then
		local ok, message = RunState.grantPatron(state, optionId)
		if not ok then return false, message end
		state.startPatronId = optionId
		return true, message, modifierChoice(state)
	elseif choice.kind == "rushPatron" then
		local ok, message = RunState.grantPatron(state, optionId)
		if not ok then return false, message end
		local taken = {}
		for _, id in ipairs(choice.taken or {}) do taken[#taken + 1] = id end
		taken[#taken + 1] = optionId
		if #taken >= BossRush.PICKS then
			return true, message, nil
		end
		return true, message, RunChoice.rushDraft(state, #taken + 1, taken)
	elseif choice.kind == "modifier" then
		local ok, message = RunModifiers.apply(state, optionId)
		return ok, message, nil
	elseif choice.kind == "event" then
		local ok, message = RunEvents.resolve(state, choice.eventId, optionId, rngOf(state))
		return ok, message, nil
	end
	return false, "Unknown choice."
end

return RunChoice
