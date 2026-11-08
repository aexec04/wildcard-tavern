--[[
	Shared/Engine/SideStops.lua
	Optional spurs of the world map that are visited on Round Select at the start of a Night
	(claude/MAP_DESIGN.md section 6). Pure rules, no Roblox APIs; the server runs them behind the phase gate.

	  shop    a small Counter with Shop.OFFER_COUNT patrons and no reroll (normal Tips prices)
	  shrine  pay SHRINE_COST Tips for a random free House Pass for the NEXT Night only
	  rest    pick one: bank a second One More Round, or +1 Hand in every round of the NEXT Night

	A side stop can be used once per run. They only open while the run is on the first round of a Night and
	the player is standing at the parent Night stop. Minigames (steps 7a/7b) are side stops of kind "minigame"
	and live in their own module.
]]

local WorldMap = require(script.Parent.WorldMap)
local Shop = require(script.Parent.Shop)
local HousePasses = require(script.Parent.HousePasses)
local RunState = require(script.Parent.RunState)

local SideStops = {}

SideStops.SHRINE_COST = 3
SideStops.MAX_EXTRA_CONTINUES = 1

-- Why a stop cannot be used right now (nil = it can). Reason codes: wrong_phase, not_started (not the first
-- round of the Night), unknown, not_here, visited.
function SideStops.blockedReason(state, stopId, phase)
	if not WorldMap.phaseAllowsRoadChoice(phase) then return "wrong_phase" end
	if type(stopId) ~= "string" then return "unknown" end
	local stop = WorldMap.Stops[stopId]
	if not stop or stop.kind ~= "side" then return "unknown" end
	if state.round ~= 1 or state.roundOver then return "not_started" end
	if WorldMap.pendingChoices(state) then return "not_here" end -- pick the road first
	if WorldMap.currentStop(state) ~= stop.parent then return "not_here" end
	if state.sideVisited and state.sideVisited[stopId] then return "visited" end
	return nil
end

-- Side stops the player can use right now: ids in a stable order.
function SideStops.available(state, phase)
	local out = {}
	if not WorldMap.phaseAllowsRoadChoice(phase) then return out end
	for _, id in ipairs(WorldMap.sideStopsAt(WorldMap.currentStop(state))) do
		if SideStops.blockedReason(state, id, phase) == nil and WorldMap.Stops[id].side ~= "minigame" then
			out[#out + 1] = id
		end
	end
	return out
end

local function markVisited(state, stopId)
	state.sideVisited = state.sideVisited or {}
	state.sideVisited[stopId] = true
end

-- Rolls the shop stop's offers: up to Shop.OFFER_COUNT patrons, same pool and rules as the Counter.
function SideStops.rollShop(state)
	local offers = Shop.rollOffers(state).patrons
	local out = {}
	for i = 1, math.min(Shop.OFFER_COUNT, #offers) do
		out[i] = offers[i]
	end
	return out
end

-- Buys one of `offers` (a list the server rolled for this stop). Removes it from the list on success.
-- The stop is marked visited once the player has bought something or leaves it empty-handed via close().
function SideStops.buy(state, stopId, phase, offers, patronId)
	local why = SideStops.blockedReason(state, stopId, phase)
	if why then return false, why end
	if WorldMap.Stops[stopId].side ~= "shop" then return false, "not_a_shop" end
	if type(patronId) ~= "string" or type(offers) ~= "table" then return false, "bad_id" end
	for i, patron in ipairs(offers) do
		if patron.id == patronId then
			local ok, msg = RunState.buyPatron(state, patronId)
			if not ok then return false, msg end
			table.remove(offers, i)
			return true
		end
	end
	return false, "not_offered"
end

-- Leaves a stop for good (closes the shop). Counts as the visit.
function SideStops.finish(state, stopId, phase)
	local why = SideStops.blockedReason(state, stopId, phase)
	if why then return false, why end
	markVisited(state, stopId)
	return true
end

-- Shrine: pay Tips, get a random House Pass without a one-time effect (`onBuy`) for the next Night only.
function SideStops.shrine(state, stopId, phase)
	local why = SideStops.blockedReason(state, stopId, phase)
	if why then return false, why end
	if WorldMap.Stops[stopId].side ~= "shrine" then return false, "not_a_shrine" end
	if state.tips < SideStops.SHRINE_COST then return false, "not_enough_tips" end
	local pool = {}
	for _, pass in ipairs(HousePasses.Definitions) do
		if not pass.onBuy and not state.housePasses[pass.id] then
			pool[#pool + 1] = pass
		end
	end
	if #pool == 0 then return false, "nothing_to_give" end
	local rng = state.rng
	local pick = pool[(type(rng) == "function" and rng(#pool)) or 1] or pool[1]
	state.tips = state.tips - SideStops.SHRINE_COST
	state.tempPass = { id = pick.id, night = (state.night or 1) + 1 }
	markVisited(state, stopId)
	return true, pick
end

-- Rest: choice "continue" banks a second One More Round (at most MAX_EXTRA_CONTINUES), choice "hand" gives
-- +1 Hand in every round of the next Night.
function SideStops.rest(state, stopId, phase, choice)
	local why = SideStops.blockedReason(state, stopId, phase)
	if why then return false, why end
	if WorldMap.Stops[stopId].side ~= "rest" then return false, "not_a_rest" end
	if choice == "continue" then
		if (state.extraContinues or 0) >= SideStops.MAX_EXTRA_CONTINUES then return false, "already_banked" end
		state.extraContinues = (state.extraContinues or 0) + 1
	elseif choice == "hand" then
		state.bonusHandsNight = (state.night or 1) + 1
	else
		return false, "bad_choice"
	end
	markVisited(state, stopId)
	return true
end

return SideStops
