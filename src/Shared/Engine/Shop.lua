--[[
	Shop.lua
	Pure shop-offer generation: what's on sale for one shop visit. No Roblox
	APIs, so the server and the headless simulator (tools/sim) roll offers
	through this exact same code.

	Layout: 2 Patron offers + 2 Pack offers every visit, plus an occasional
	single Voucher (House Pass) offer -- see Shop.VOUCHER_CHANCE. Reroll cost
	climbs by REROLL_COST_STEP each reroll within a single shop visit, then
	resets to REROLL_BASE_COST next visit. Purchases themselves live in
	RunState (buyPatron/openPack/buyHousePass).

	Every roll goes through `state.rng or math.random`, so a seeded run
	(Daily/Weekly/Seed Code -- see SeededRng.lua) gets seeded shop offers and
	a normal run stays random.
]]

local Patrons = require(script.Parent.Patrons)
local Packs = require(script.Parent.Packs)
local HousePasses = require(script.Parent.HousePasses)

local Shop = {}

Shop.OFFER_COUNT = 2
Shop.PACK_OFFER_COUNT = 2
Shop.VOUCHER_CHANCE = 0.35
Shop.REROLL_BASE_COST = 5
Shop.REROLL_COST_STEP = 2

local function rollPatronOffers(state)
	local rng = state.rng or math.random

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

	local offers = {}
	for _ = 1, math.min(Shop.OFFER_COUNT, #available) do
		local i = rng(#available)
		table.insert(offers, table.remove(available, i))
	end
	return offers
end

local function rollPackOffers(state)
	local rng = state.rng or math.random

	local pool = {}
	for _, pack in ipairs(Packs.Definitions) do
		table.insert(pool, pack)
	end
	local offers = {}
	for _ = 1, math.min(Shop.PACK_OFFER_COUNT, #pool) do
		local i = rng(#pool)
		table.insert(offers, table.remove(pool, i))
	end
	return offers
end

-- Only offers a House Pass the player doesn't already own, and only some of
-- the time. `rng(n)` only supports integer picks in [1, n], not a float roll
-- like `math.random()`'s no-arg form -- rolling a 1-in-10000 draw against a
-- scaled integer threshold gets the same probability out of the same
-- integer-only contract every other rng() call site uses.
local function rollVoucherOffer(state)
	local rng = state.rng or math.random
	local roll
	if state.rng then
		roll = rng(10000) <= math.floor(Shop.VOUCHER_CHANCE * 10000)
	else
		roll = math.random() <= Shop.VOUCHER_CHANCE
	end
	if not roll then
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
	return available[rng(#available)]
end

-- Rolls one full set of offers. Used for a fresh shop visit and for a reroll
-- alike; tracking the climbing reroll cost is the caller's job.
function Shop.rollOffers(state)
	local patrons = rollPatronOffers(state)
	local packs = rollPackOffers(state)
	local voucher = rollVoucherOffer(state)
	return { patrons = patrons, packs = packs, voucher = voucher }
end

return Shop
