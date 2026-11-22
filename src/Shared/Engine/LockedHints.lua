--[[
	LockedHints.lua
	One friendly line (under 60 characters) for how to unlock a Card Set, Card Back, Patron, Recipe or House Pass.
	Pure Lua; reads the real unlock data (CosmeticSets, JourneyMap, BiomeRewards, CollectionBook, Unlocks).
]]

local CosmeticSets = require(script.Parent.CosmeticSets)
local JourneyMap = require(script.Parent.JourneyMap)
local BiomeRewards = require(script.Parent.BiomeRewards)
local CollectionBook = require(script.Parent.CollectionBook)
local Unlocks = require(script.Parent.Unlocks)

local LockedHints = {}

LockedHints.MAX_LENGTH = 60

function LockedHints.forSet(set)
	return CosmeticSets.unlockText(set)
end

-- Never nil for a real back: falls back to the back's own description line.
function LockedHints.forBack(back)
	for _, set in ipairs(CosmeticSets.Definitions) do
		if set.cardBackId == back.id then
			return "Comes with " .. set.name .. "."
		end
	end
	for _, entry in ipairs(JourneyMap.Nights) do
		if entry.reward and entry.reward.kind == "cardBack" and entry.reward.id == back.id then
			return "Journey reward: clear Night " .. entry.night .. "."
		end
	end
	for region, row in pairs(BiomeRewards.Rows or {}) do
		for _, reward in ipairs(row.reward or {}) do
			if reward.kind == "cardBack" and reward.id == back.id then
				return "Clear " .. (CosmeticSets.RegionNames[region] or "the road") .. " on the Map."
			end
		end
	end
	for _, milestone in ipairs(CollectionBook.Milestones) do
		for _, reward in ipairs(milestone.rewards) do
			if reward.kind == "cardBack" and reward.id == back.id then
				return "Fill " .. milestone.percent .. " percent of the Collection."
			end
		end
	end
	return LockedHints.BackHints[back.id] or "Keep playing to unlock."
end

-- Backs earned by seasons, Legend levels and the Map end (no other data table says how in under 60 characters).
LockedHints.BackHints = {
	gala = "Reach the Keeper's Table on the Map.",
	winter_lanterns = "Clear 3 Nights in a run in Winter Lanterns.",
	harvest_premium = "Season premium reward: Harvest Moon tier 30.",
	winter_premium = "Season premium reward: Winter Welcome tier 30.",
	legend_gold = "Reach Legend level 3.",
	legend_crown = "Reach Legend level 7.",
	legend_eternal = "Reach Legend level 10.",
	harvest_moon = "Reach tier 30 of the Harvest Moon season.",
	winter_welcome = "Reach tier 30 of the Winter Welcome season.",
}

-- Hint for a gated Patron, Recipe or House Pass (kind = "patron" | "recipe" | "housePass").
function LockedHints.forContent(kind, id)
	local rule = Unlocks.ruleOf(kind, id)
	return rule and rule.hint or nil
end

return LockedHints
