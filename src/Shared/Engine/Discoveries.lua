--[[
	Discoveries.lua
	Hidden discovery spots on the Tavern Map. Each region has SPOTS_PER_REGION spots, placed by a fixed formula from
	the region id and the spot index (the same for every player). A region's spots stay hidden until the player has
	finished some of that road (cleared one of its Night stops) or spends a compass charge to reveal them.
	Tapping a revealed spot on the map claims it once. Pure Lua, no Roblox APIs.

	Kinds:
	  chest         Tips banked for the next run (odd regions) or a card back (even regions)
	  merchant      a Tips discount on the first shop visit of the next normal run
	  secret_patron opens a Patron that is still closed (Engine/Unlocks), or Tips if none is left

	Counter: "Discovered N of TOTAL". Bonus titles at half of the spots and at all of them
	(Discoveries.Milestones). With SPOTS_PER_REGION = 2 and 9 regions that is 18 spots, titles at 9 and 18;
	set SPOTS_PER_REGION = 4 for 36 spots with titles at 18 and 36 (everything below follows the constant).

	Profile: discoveries ([spot id] = true, claimed), discoveryRevealed ([region] = true, compass reveals),
	merchantDiscount (Tips off the next normal run's first shop visit, cap MAX_MERCHANT_DISCOUNT).
	Ranked and fixed seed runs are untouched: nothing here changes a run, except the merchant discount, which is
	applied only when a normal run starts.
]]

local WorldMap = require(script.Parent.WorldMap)
local Unlocks = require(script.Parent.Unlocks)
local TavernRank = require(script.Parent.TavernRank)

local Discoveries = {}

Discoveries.SPOTS_PER_REGION = 2
Discoveries.MAX_MERCHANT_DISCOUNT = 4
Discoveries.CHEST_TIPS = 6
Discoveries.MERCHANT_DISCOUNT = 2

-- card backs a chest can hold (existing cosmetics), picked by region
Discoveries.CHEST_BACKS = { "hall_banner", "kitchen_checks", "gilded_ledger", "winter_frost" }

local function ordinalOf(region)
	for i, id in ipairs(WorldMap.RegionOrder) do
		if id == region then return i end
	end
	return nil
end

-- A small stable integer hash of a string (every product stays below 2^53).
local function hash(text)
	local h = 7
	for i = 1, #text do
		h = (h * 31 + text:byte(i)) % 1000003
	end
	return h
end

function Discoveries.spotId(region, index)
	return region .. "#" .. index
end

function Discoveries.kindOf(region, index)
	if index == 1 then
		return "chest"
	end
	local ordinal = ordinalOf(region) or 1
	return (ordinal % 2 == 1) and "merchant" or "secret_patron"
end

-- Every spot, in a stable order: { id, region, index, kind }
function Discoveries.spots()
	local list = {}
	for _, region in ipairs(WorldMap.RegionOrder) do
		for index = 1, Discoveries.SPOTS_PER_REGION do
			list[#list + 1] = { id = Discoveries.spotId(region, index), region = region, index = index, kind = Discoveries.kindOf(region, index) }
		end
	end
	return list
end

function Discoveries.total()
	return #WorldMap.RegionOrder * Discoveries.SPOTS_PER_REGION
end

function Discoveries.getSpot(id)
	for _, spot in ipairs(Discoveries.spots()) do
		if spot.id == id then return spot end
	end
	return nil
end

-- Where a spot sits, relative to its region: dx -1..1 across the region's width, lift 0.18..0.40 of the map height
-- above (side -1) or below (side +1) the road band. Same answer everywhere.
function Discoveries.place(region, index)
	local h = hash(region .. ":" .. index)
	local dx = ((h % 1000) / 1000) * 1.6 - 0.8
	local lift = 0.18 + (((h // 1000) % 100) / 100) * 0.22
	local side = ((h // 100000) % 2 == 0) and -1 or 1
	if index % 2 == 0 then
		side = -side -- the two spots of a region lie on opposite sides of the road
	end
	return { dx = dx, lift = lift, side = side }
end

-- Milestone titles: half of the spots and all of them.
Discoveries.Milestones = {
	{ id = "half", fraction = 0.5, titleId = "curious_explorer", label = "Curious Explorer" },
	{ id = "all", fraction = 1, titleId = "grand_explorer", label = "Grand Explorer" },
}

function Discoveries.milestoneCount(milestone)
	return math.ceil(Discoveries.total() * milestone.fraction)
end

function Discoveries.foundCount(profile)
	local n = 0
	for _, spot in ipairs(Discoveries.spots()) do
		if profile.discoveries and profile.discoveries[spot.id] then n = n + 1 end
	end
	return n
end

-- Is this region's set of spots visible? A cleared Night stop on that road, or a compass reveal.
function Discoveries.isRevealed(profile, region)
	if profile.discoveryRevealed and profile.discoveryRevealed[region] then
		return true
	end
	return ((profile.worldBiomeClears or {})[region] or 0) >= 1
end

-- Spends one compass charge to reveal a region's spots. Returns ok, message.
function Discoveries.reveal(profile, region)
	if not WorldMap.Regions[region] then
		return false, "Unknown region."
	end
	if Discoveries.isRevealed(profile, region) then
		return false, "Already revealed."
	end
	if (profile.compassCharges or 0) < 1 then
		return false, "You need a compass charge."
	end
	profile.compassCharges = profile.compassCharges - 1
	profile.discoveryRevealed = profile.discoveryRevealed or {}
	profile.discoveryRevealed[region] = true
	return true, "Your compass points to hidden spots."
end

local function secretPatronFor(profile, ordinal)
	local ids = {}
	for id, rule in pairs(Unlocks.Rules.patron) do
		if rule.kind ~= "grant" then ids[#ids + 1] = id end
	end
	table.sort(ids)
	if #ids == 0 then return nil end
	local start = (ordinal * 7) % #ids
	for step = 0, #ids - 1 do
		local id = ids[((start + step) % #ids) + 1]
		if not Unlocks.isUnlocked(profile, "patron", id) then
			return id
		end
	end
	return nil
end

-- Claims a revealed spot once. Returns ok, result where result = { icon, text, kind } or a message on failure.
-- `names` (optional) = { patron = fn(id) -> name, cardBack = fn(id) -> name } for the reward text.
function Discoveries.claim(profile, spotId, names)
	local spot = Discoveries.getSpot(spotId)
	if not spot then
		return false, "Unknown spot."
	end
	profile.discoveries = profile.discoveries or {}
	if profile.discoveries[spotId] then
		return false, "Already found."
	end
	if not Discoveries.isRevealed(profile, spot.region) then
		return false, "Not revealed yet."
	end
	names = names or {}
	local ordinal = ordinalOf(spot.region) or 1
	local result
	if spot.kind == "chest" then
		if ordinal % 2 == 1 then
			profile.pendingStartTips = math.min(TavernRank.MAX_PENDING_TIPS, (profile.pendingStartTips or 0) + Discoveries.CHEST_TIPS)
			result = { icon = "🧰", kind = "chest", text = "A hidden chest! +" .. Discoveries.CHEST_TIPS .. " Tips next run" }
		else
			local backId = Discoveries.CHEST_BACKS[((ordinal // 2 - 1) % #Discoveries.CHEST_BACKS) + 1]
			profile.unlockedCardBackIds = profile.unlockedCardBackIds or {}
			profile.unlockedCardBackIds[backId] = true
			result = { icon = "🧰", kind = "chest", text = "A hidden chest! Card back: " .. ((names.cardBack and names.cardBack(backId)) or backId) }
		end
	elseif spot.kind == "merchant" then
		profile.merchantDiscount = math.min(Discoveries.MAX_MERCHANT_DISCOUNT, (profile.merchantDiscount or 0) + Discoveries.MERCHANT_DISCOUNT)
		result = { icon = "🛒", kind = "merchant", text = "A traveling merchant! " .. Discoveries.MERCHANT_DISCOUNT .. " Tips off your next shop visit" }
	else
		local patronId = secretPatronFor(profile, ordinal)
		if patronId then
			profile.unlockedContent = profile.unlockedContent or {}
			profile.unlockedContent["patron:" .. patronId] = true
			result = { icon = "🔓", kind = "secret_patron", text = "A secret Patron: " .. ((names.patron and names.patron(patronId)) or patronId) }
		else
			profile.pendingStartTips = math.min(TavernRank.MAX_PENDING_TIPS, (profile.pendingStartTips or 0) + Discoveries.CHEST_TIPS)
			result = { icon = "🔓", kind = "secret_patron", text = "A secret stash! +" .. Discoveries.CHEST_TIPS .. " Tips next run" }
		end
	end
	profile.discoveries[spotId] = true
	-- bonus titles
	local found = Discoveries.foundCount(profile)
	profile.rewardTitleIds = profile.rewardTitleIds or {}
	for _, milestone in ipairs(Discoveries.Milestones) do
		if found >= Discoveries.milestoneCount(milestone) and not profile.rewardTitleIds[milestone.titleId] then
			profile.rewardTitleIds[milestone.titleId] = true
			result.text = result.text .. ". Title: " .. milestone.label
		end
	end
	return true, result
end

-- Takes the merchant discount for the next normal run (once). Returns the Tips off.
function Discoveries.takeMerchantDiscount(profile)
	local n = math.max(0, math.floor(profile.merchantDiscount or 0))
	profile.merchantDiscount = 0
	return n
end

-- What the client draws.
function Discoveries.view(profile)
	local claimed, revealed = {}, {}
	for _, spot in ipairs(Discoveries.spots()) do
		if profile.discoveries and profile.discoveries[spot.id] then claimed[spot.id] = true end
		if Discoveries.isRevealed(profile, spot.region) then revealed[spot.region] = true end
	end
	return {
		found = Discoveries.foundCount(profile), total = Discoveries.total(), perRegion = Discoveries.SPOTS_PER_REGION,
		claimed = claimed, revealed = revealed,
		half = Discoveries.milestoneCount(Discoveries.Milestones[1]), all = Discoveries.milestoneCount(Discoveries.Milestones[2]),
	}
end

-- Cleans saved values: only real spots and real regions survive.
function Discoveries.cleanSaved(rawDiscoveries, rawRevealed, rawDiscount)
	local claimed, revealed = {}, {}
	if type(rawDiscoveries) == "table" then
		for id, flag in pairs(rawDiscoveries) do
			if flag == true and type(id) == "string" and Discoveries.getSpot(id) then claimed[id] = true end
		end
	end
	if type(rawRevealed) == "table" then
		for region, flag in pairs(rawRevealed) do
			if flag == true and type(region) == "string" and WorldMap.Regions[region] then revealed[region] = true end
		end
	end
	local discount = 0
	if type(rawDiscount) == "number" and rawDiscount == rawDiscount then
		discount = math.max(0, math.min(Discoveries.MAX_MERCHANT_DISCOUNT, math.floor(rawDiscount)))
	end
	return claimed, revealed, discount
end

return Discoveries
