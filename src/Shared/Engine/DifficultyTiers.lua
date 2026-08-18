--[[
	DifficultyTiers.lua
	Difficulty picked before a run begins (alongside a Deck Variant --
	see DeckVariants.lua). Original names, not copied from any other game's
	difficulty-tier system.
]]

local DifficultyTiers = {}

DifficultyTiers.DefaultId = "standard"

DifficultyTiers.Definitions = {
	{
		id = "casual",
		name = "Casual",
		description = "Round targets are 20% lower and Boss Rounds are off. Good for learning the game.",
		targetScoreMultiplier = 0.8,
		bossRoundsEnabled = false,
	},
	{
		id = "standard",
		name = "Standard",
		description = "The intended balance -- a Boss Round caps off every Night.",
		targetScoreMultiplier = 1.0,
		bossRoundsEnabled = true,
	},
	{
		id = "high_stakes",
		name = "High Stakes",
		description = "Round targets are 20% higher, on top of every Night's Boss Round.",
		targetScoreMultiplier = 1.2,
		bossRoundsEnabled = true,
	},
}

function DifficultyTiers.getById(id)
	for _, def in ipairs(DifficultyTiers.Definitions) do
		if def.id == id then
			return def
		end
	end
	return nil
end

return DifficultyTiers
