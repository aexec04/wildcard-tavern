--[[
	MapEvents.lua
	Two safe event nodes on the Tavern Map road, on Nights 4, 7 and 10 only. Pure Lua, no Roblox APIs; the server runs them.

	  Shrine  while the Night boon pick is open, pay SHRINE_COST Tips for ONE new draft of three boons (none of the ones
	          just shown while the pool allows it). Once per Night. Declining costs nothing: just pick a boon as usual.
	  Market  at Round Select on the first round of the Night, pay MARKET_PRICE Tips to put a mark of your choice
	          (Gilded, Lucky or Lively) on a deck card. Once per Night.

	Normal runs only (the same runs that get boons). Server authoritative: every call validates the Night, the phase,
	the Tips and the once per Night limit, and a refusal changes nothing. Kid safe text, no random wording.
]]

local Card = require(script.Parent.Card)
local Marks = require(script.Parent.Marks)
local NightBoons = require(script.Parent.NightBoons)

local MapEvents = {}

MapEvents.NIGHTS = { 4, 7, 10 }
MapEvents.SHRINE_COST = 3
MapEvents.MARKET_PRICE = 4

function MapEvents.isEventNight(night)
	for _, n in ipairs(MapEvents.NIGHTS) do
		if n == night then return true end
	end
	return false
end

-- ===== Shrine =====

-- What the boon pick plate shows: nil when there is no shrine here, else { cost, canAfford, used }.
function MapEvents.shrineView(state, choice)
	if type(choice) ~= "table" or choice.kind ~= "boon" or not MapEvents.isEventNight(state.night) then return nil end
	local used = state.shrineNight == state.night
	return { cost = MapEvents.SHRINE_COST, canAfford = (state.tips or 0) >= MapEvents.SHRINE_COST, used = used,
		text = "Shrine: pay " .. MapEvents.SHRINE_COST .. " Tips for a new set of boons." }
end

-- Pays and returns ok, message, newChoice. A refusal returns false, reason and leaves the Tips and the choice alone.
function MapEvents.rerollBoon(state, choice, rng)
	local view = MapEvents.shrineView(state, choice)
	if not view then return false, "No shrine here." end
	if view.used then return false, "The shrine has already helped this Night." end
	if not view.canAfford then return false, "Need " .. MapEvents.SHRINE_COST .. " Tips for the shrine." end
	rng = rng or state.rng or math.random
	local shown = {}
	for _, o in ipairs(choice.options or {}) do shown[o.id] = true end
	local fresh, rest = {}, {}
	for _, def in ipairs(NightBoons.Definitions) do
		table.insert(shown[def.id] and rest or fresh, def)
	end
	local pool = #fresh >= NightBoons.OFFERS and fresh or NightBoons.Definitions
	local options = {}
	local copy = {}
	for _, def in ipairs(pool) do copy[#copy + 1] = def end
	for _ = 1, math.min(NightBoons.OFFERS, #copy) do
		local def = table.remove(copy, rng(#copy))
		options[#options + 1] = { id = def.id, name = def.name, icon = def.icon, line1 = def.text, line2 = "" }
	end
	state.tips = state.tips - MapEvents.SHRINE_COST
	state.shrineNight = state.night
	local new = { kind = "boon", title = choice.title, text = "A fresh set from the shrine.", icon = choice.icon, options = options }
	return true, "The shrine glows. A new set of boons appears.", new
end

-- ===== Market =====

-- nil when there is no market here right now, else { price, canAfford, marks = { { id, name, text } } }.
function MapEvents.marketView(state, phase)
	if phase ~= "roundSelect" or not MapEvents.isEventNight(state.night) then return nil end
	if state.round ~= 1 or state.roundOver then return nil end
	if state.marketNight == state.night then return nil end
	local marks = {}
	for _, id in ipairs(Card.MarkOrder) do
		marks[#marks + 1] = { id = id, name = Card.Marks[id].name .. " Mark", text = Marks.packText(id) }
	end
	return { price = MapEvents.MARKET_PRICE, canAfford = (state.tips or 0) >= MapEvents.MARKET_PRICE, marks = marks }
end

-- Buys the chosen mark for the chosen deck card (rank and suit). Returns ok, message.
function MapEvents.marketBuy(state, phase, markId, rank, suit)
	if not MapEvents.marketView(state, phase) then return false, "No market here." end
	local ok, message = Marks.buy(state, markId, rank, suit, MapEvents.MARKET_PRICE)
	if ok then state.marketNight = state.night end
	return ok, message
end

return MapEvents
