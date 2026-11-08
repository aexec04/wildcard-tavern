-- End-of-run summary (server-side data): best hand, Night reached, route taken, Patrons used, and the
-- shareable badge. Pure; RunState.playHand feeds recordHand, the server ships build(state) at Game Over.
local Patrons = require(script.Parent.Patrons)
local WorldMap = require(script.Parent.WorldMap)

local RunSummary = {}

-- Badge tiers use the CollectionBook rarity ids so the client can reuse RarityFrame.
-- Minimum Night reached for each tier (a win always counts as at least legendary).
RunSummary.BadgeTiers = {
	{ rarity = "common", minNight = 1 },
	{ rarity = "uncommon", minNight = 2 },
	{ rarity = "rare", minNight = 4 },
	{ rarity = "epic", minNight = 6 },
	{ rarity = "legendary", minNight = 8 },
	{ rarity = "mythical", minNight = 12 },
}

function RunSummary.badgeRarity(night, won)
	local result = "common"
	for _, tier in ipairs(RunSummary.BadgeTiers) do
		if (night or 0) >= tier.minNight then
			result = tier.rarity
		end
	end
	if won and (result == "common" or result == "uncommon" or result == "rare" or result == "epic") then
		result = "legendary"
	end
	return result
end

-- Called once per scored hand (after the score is known).
function RunSummary.recordHand(state, handName, score)
	if type(score) ~= "number" then
		return
	end
	if not state.bestHand or score > state.bestHand.score then
		state.bestHand = { name = handName, score = score }
	end
	state.patronsUsedIds = state.patronsUsedIds or {}
	for _, patron in ipairs(state.ownedPatrons or {}) do
		if patron.id and not state.patronsUsedIds[patron.id] then
			state.patronsUsedIds[patron.id] = true
			state.patronsUsedOrder = state.patronsUsedOrder or {}
			table.insert(state.patronsUsedOrder, patron.id)
		end
	end
end

-- Stops of the road taken, in order: { { id, name, icon, region } }.
function RunSummary.routeFor(state)
	local route = {}
	for _, id in ipairs(state.worldRoute or {}) do
		local stop = WorldMap.Stops[id]
		if stop then
			table.insert(route, { id = id, name = stop.name, icon = stop.icon, region = stop.region })
		end
	end
	return route
end

-- Plain data for the client. `titleText` is the equipped title's display text (the server knows it).
function RunSummary.build(state, titleText)
	local patrons = {}
	for _, id in ipairs(state.patronsUsedOrder or {}) do
		local def = Patrons.getById(id)
		if def then
			table.insert(patrons, { id = id, name = def.name, icon = def.icon })
		end
	end
	local won = state.wonRun == true
	local night = state.night or 1
	local route = RunSummary.routeFor(state)
	local routeIds = {}
	for i, stop in ipairs(route) do
		routeIds[i] = stop.id
	end
	return {
		won = won,
		night = night,
		round = state.round,
		bestHand = state.bestHand and { name = state.bestHand.name, score = math.floor(state.bestHand.score) } or nil,
		handsPlayed = state.handsPlayedTotal or 0,
		route = route,
		routeIds = routeIds,
		patrons = patrons,
		rarity = RunSummary.badgeRarity(night, won),
		titleText = titleText,
	}
end

-- What gets saved as the profile badge: ids and numbers only, rebuilt into display data on read.
function RunSummary.badgeFromSummary(summary)
	return {
		night = math.floor(summary.night),
		won = summary.won == true,
		rarity = summary.rarity,
		routeIds = summary.routeIds,
		bestHandName = summary.bestHand and summary.bestHand.name or nil,
		bestHandScore = summary.bestHand and summary.bestHand.score or nil,
	}
end

-- Validates a saved badge (migrate). Returns a clean badge or nil.
function RunSummary.cleanBadge(raw)
	if type(raw) ~= "table" or type(raw.night) ~= "number" or raw.night ~= raw.night then
		return nil
	end
	local valid = false
	for _, tier in ipairs(RunSummary.BadgeTiers) do
		valid = valid or tier.rarity == raw.rarity
	end
	if not valid then
		return nil
	end
	local routeIds = {}
	if type(raw.routeIds) == "table" then
		for i, id in ipairs(raw.routeIds) do
			if type(id) == "string" and WorldMap.Stops[id] and i <= 32 then
				table.insert(routeIds, id)
			end
		end
	end
	return {
		night = math.max(1, math.min(9999, math.floor(raw.night))),
		won = raw.won == true,
		rarity = raw.rarity,
		routeIds = routeIds,
		bestHandName = type(raw.bestHandName) == "string" and string.sub(raw.bestHandName, 1, 40) or nil,
		bestHandScore = type(raw.bestHandScore) == "number" and raw.bestHandScore == raw.bestHandScore
			and math.max(0, math.floor(raw.bestHandScore)) or nil,
	}
end

return RunSummary
