--[[
	BossRounds.lua
	Every Night ends on a tougher, modified round -- our equivalent of a
	"boss" encounter, but expressed as data-driven modifiers rather than a
	literal fight. Original names/effects, not copied from any other game.

	A boss round applies for the LAST round of each Night (see
	isBossRound). Which modifier gets picked is randomized per Night.

	Modifier shape:
		{ id, name, description,
		  handSizeDelta = number|nil,       -- added to config.handSize for the deal
		  discardsDelta = number|nil,       -- added to config.discardsPerRound
		  targetScoreMultiplier = number|nil -- multiplies that round's target score }
]]

local BossRounds = {}

BossRounds.Definitions = {
	{
		id = "bouncer",
		name = "The Bouncer",
		description = "Deals you one fewer card this round.",
		handSizeDelta = -1,
	},
	{
		id = "last_orders",
		name = "Last Orders",
		description = "One fewer discard this round.",
		discardsDelta = -1,
	},
	{
		id = "house_rules",
		name = "House Rules",
		description = "The target score is 40% higher this round.",
		targetScoreMultiplier = 1.4,
	},
	{
		id = "dry_spell",
		name = "Dry Spell",
		description = "One fewer card dealt AND one fewer discard this round.",
		handSizeDelta = -1,
		discardsDelta = -1,
	},
}

function BossRounds.getById(id)
	for _, def in ipairs(BossRounds.Definitions) do
		if def.id == id then
			return def
		end
	end
	return nil
end

-- Boss rounds land on the last round of every Night.
function BossRounds.isBossRound(round, roundsPerNight)
	return round == roundsPerNight
end

-- rng follows the same convention as Deck.shuffle: rng(n) returns an
-- integer in [1, n]. Defaults to math.random so real games are randomized;
-- tests can pass a deterministic function instead.
function BossRounds.pick(rng)
	rng = rng or math.random
	local index = rng(#BossRounds.Definitions)
	return BossRounds.Definitions[index]
end

return BossRounds
