--[[
	DeckVariants.lua
	Starting-deck flavors you pick before a run begins. Purely a different
	set of starting numbers (config deltas + starting Tips) -- no new cards,
	no gameplay complexity beyond tuning knobs. Original names.

	`configOverrides` fields are DELTAS added to RunState.DefaultConfig
	(not replacement values), so tweaking DefaultConfig later doesn't
	silently break a variant's balance.
]]

local DeckVariants = {}

DeckVariants.DefaultId = "standard"

DeckVariants.Definitions = {
	{
		id = "standard",
		name = "Standard Deck",
		description = "The full 52-card deck, no changes. A safe, balanced start.",
		configOverrides = {},
		startingTips = 0,
		targetScoreMultiplier = 1,
	},
	{
		id = "steady_hand",
		name = "Steady Hand",
		description = "+1 discard every round, but 1 fewer card dealt to your hand.",
		configOverrides = { handSize = -1, discardsPerRound = 1 },
		startingTips = 0,
		targetScoreMultiplier = 1,
	},
	{
		id = "high_roller",
		name = "High Roller",
		description = "Start with 6 extra Tips, but 1 fewer hand to play each round.",
		configOverrides = { handsPerRound = -1 },
		startingTips = 6,
		targetScoreMultiplier = 1,
	},
	{
		id = "marathon",
		name = "Marathon",
		description = "+1 hand to play each round, but round targets are 15% higher.",
		configOverrides = { handsPerRound = 1 },
		startingTips = 0,
		targetScoreMultiplier = 1.15,
	},
}

function DeckVariants.getById(id)
	for _, def in ipairs(DeckVariants.Definitions) do
		if def.id == id then
			return def
		end
	end
	return nil
end

return DeckVariants
