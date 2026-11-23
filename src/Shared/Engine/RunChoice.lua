--[[
	RunChoice.lua
	The "pick one" moments of a run, as plain data the server keeps in `session.choice` and ships to the client
	as `state.choice`. Pure Lua, no Roblox APIs.

	  * Start-of-run DRAFT (normal runs only): first 1 of 3 starting Patrons (never rare or better), then 1 of 3
	    run modifiers (a blessing with a matching curse, Engine/RunModifiers.lua).
	  * Between Nights, about half the time, one random EVENT card (Engine/RunEvents.lua) with a safe Decline.
	  * When a new Night opens (Night 2 on), a REWARD for clearing the last one: 1 of 3 Patrons you do not own, with a Skip
	    (`RunChoice.rewardDraft`, kind "reward"). Never on fixed boards, never with a full table.

	A choice is { kind = "patron" | "modifier" | "event", title, text, icon, eventId?, options = { { id, name, icon,
	line1, line2 } } } where every field is a plain string, safe to send to the client.

	Daily, Weekly, Seed and the tutorial never get a choice: callers pass `allowed = false` (fixed boards must
	stay fair, and the tutorial is scripted).
]]

local Patrons = require(script.Parent.Patrons)
local RunModifiers = require(script.Parent.RunModifiers)
local RunEvents = require(script.Parent.RunEvents)
local NightBoons = require(script.Parent.NightBoons)
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
	return { kind = "patron", title = "Choose your first Patron", icon = "🧑‍🍳", options = options }
end

-- A blessing line opens with "+" and a curse line with "-" (Engine/RunModifiers.line: one sign, never two).
local function marked(sign, text)
	return RunModifiers.line(sign, text)
end

local function modifierChoice(state)
	local picks = draw(RunModifiers.Definitions, RunChoice.DRAFT_SIZE, rngOf(state))
	local options = {}
	for _, m in ipairs(picks) do
		options[#options + 1] = { id = m.id, name = m.name, icon = m.icon, line1 = marked("+", m.blessing), line2 = marked("-", m.curse) }
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

-- NIGHT CLEAR REWARD: three Patrons not on the table, rarer as the run goes on (Night 2 up to Uncommon, one tier more every two
-- Nights, never the top tier). nil when the table is full, `allowed` is false (Daily, Weekly, Seed, tutorial) or nothing is left.
-- The answer is one offered id, or "decline" (Skip): nothing changes.
RunChoice.REWARD_SIZE = 3
function RunChoice.rewardMaxRarity(night)
	local top = math.max(1, #CollectionBook.RarityOrder - 1)
	return math.min(top, 2 + math.floor((math.max(2, tonumber(night) or 2) - 2) / 2))
end

function RunChoice.rewardDraft(state, allowed)
	if allowed == false or type(state) ~= "table" then return nil end
	if #state.ownedPatrons >= RunState.patronSlotLimit(state) then return nil end
	local owned = {}
	for _, o in ipairs(state.ownedPatrons) do owned[o.id] = true end
	local cap = RunChoice.rewardMaxRarity(state.night)
	local pool = {}
	for _, patron in ipairs(Unlocks.filter(state, "patron", Patrons.Definitions)) do
		if not patron.biome and not owned[patron.id] and rarityIndex(patron) <= cap then pool[#pool + 1] = patron end
	end
	local picks = draw(pool, RunChoice.REWARD_SIZE, rngOf(state))
	if #picks == 0 then return nil end
	local options = {}
	for _, p in ipairs(picks) do
		options[#options + 1] = { id = p.id, name = p.name, icon = p.icon, line1 = p.description or "", line2 = "" }
	end
	return { kind = "reward", title = "Night cleared: pick a Patron", text = "A thank you from the tavern. Take one, or skip.", icon = "🎁", options = options, skip = true }
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
		options[#options + 1] = { id = o.id, name = o.label, icon = o.id == "decline" and "✋" or event.icon, kind = RunEvents.OPTION_KINDS[o.id], line1 = o.detail or "", line2 = "" }
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

-- The Night boon pick that opens a new Night (Nights 2 to 12). The Patron reward or event that used to open the Night follows it.
function RunChoice.boonDraft(state, allowed)
	return NightBoons.draft(state, allowed)
end

-- What comes after a Night boon pick (or after a reward): the Patron reward first, then a rolled event.
function RunChoice.afterBoon(state, allowed)
	return RunChoice.rewardDraft(state, allowed) or RunChoice.rollEvent(state, allowed)
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

-- Studio QA (DebugGoto round1:mod=): makes sure an open blessing draft offers `modId`, replacing the first option when it
-- is not already there. Returns true when the draft now offers it, false (nothing changed) for any other choice or an unknown id.
function RunChoice.forceOption(choice, modId)
	if type(choice) ~= "table" or choice.kind ~= "modifier" or type(choice.options) ~= "table" then return false end
	for _, o in ipairs(choice.options) do
		if o.id == modId then return true end
	end
	local m = RunModifiers.getById(modId)
	if not m then return false end
	choice.options[1] = { id = m.id, name = m.name, icon = m.icon, line1 = marked("+", m.blessing), line2 = marked("-", m.curse) }
	return true
end

-- Applies the player's pick to the run. Returns ok, message, nextChoice (the modifier step after the Patron step).
-- A failed pick (not an offered id, or an event that cannot be paid) changes nothing and keeps the choice open.
function RunChoice.pick(state, choice, optionId)
	if type(choice) ~= "table" or type(optionId) ~= "string" then
		return false, "No choice open."
	end
	local offered = choice.kind == "reward" and optionId == "decline" -- Skip is always allowed on a reward
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
	elseif choice.kind == "reward" then
		if optionId == "decline" then return true, "", nil end
		local ok, message = RunState.grantPatron(state, optionId)
		return ok, message, nil
	elseif choice.kind == "modifier" then
		if state.runModifierId then
			return false, "You already chose a blessing." -- one blessing a run, a second pick never stacks
		end
		local ok, message = RunModifiers.apply(state, optionId)
		return ok, message, nil
	elseif choice.kind == "boon" then
		local ok, message = NightBoons.apply(state, optionId)
		if not ok then return false, message end
		return true, message, RunChoice.afterBoon(state, true)
	elseif choice.kind == "event" then
		local ok, message = RunEvents.resolve(state, choice.eventId, optionId, rngOf(state))
		return ok, message, nil
	end
	return false, "Unknown choice."
end

return RunChoice
