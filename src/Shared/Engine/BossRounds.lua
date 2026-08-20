--[[
	BossRounds.lua
	Every Night ends on a tougher, modified round -- our equivalent of a
	"boss" encounter, but expressed as data-driven modifiers rather than a
	literal fight. Original names/effects, not copied from any other game.

	A boss round applies for the LAST round of each Night (see
	isBossRound). Which modifier gets picked is randomized per Night.

	Modifier shape (every field optional -- RunState.startRound/playHand
	interpret whichever ones are present):
		{ id, name, description,
		  handSizeDelta = number|nil,          -- added to config.handSize for the deal
		  discardsDelta = number|nil,          -- added to config.discardsPerRound
		  handsPerRoundOverride = number|nil,  -- hard-sets hands allowed this round
		  targetScoreMultiplier = number|nil,  -- multiplies that round's target score
		  chipsMultiplier = number|nil,        -- multiplies every played hand's Chips
		  multMultiplier = number|nil,         -- multiplies every played hand's Mult
		  tipsLostPerCardPlayed = number|nil,  -- Tips lost per card played, per hand
		  forcedRandomDiscardsPerHand = number|nil, -- random cards tossed after each hand played
		  requiredCardsPerHand = number|nil,   -- must play EXACTLY this many cards
		  noRepeatHandTypes = true|nil,        -- 2nd play of a hand type scores 0
		  zeroTipsOnMostPlayedHand = true|nil, -- playing your most-used hand wipes Tips
		  debuff = "FaceCards"|"Hearts"|"Diamonds"|"Clubs"|"Spades"|nil, -- matching
		    scoring cards contribute 0 Chips/Mult/Garnish/Special/Stamp this round }
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
		id = "the_tab",
		name = "The Tab",
		description = "Lose 1 Tip for every card you play.",
		tipsLostPerCardPlayed = 1,
	},
	{
		id = "closing_time",
		name = "Closing Time",
		description = "You may only play 1 hand this round.",
		handsPerRoundOverride = 1,
	},
	{
		id = "rowdy_crowd",
		name = "Rowdy Crowd",
		description = "2 random cards are tossed out of your hand after every hand you play.",
		forcedRandomDiscardsPerHand = 2,
	},
	{
		id = "big_tab",
		name = "Big Tab",
		description = "The target score is triple this round.",
		targetScoreMultiplier = 3,
	},
	{
		id = "watered_down",
		name = "Watered Down",
		description = "Chips and Mult from played hands are halved this round.",
		chipsMultiplier = 0.5,
		multMultiplier = 0.5,
	},
	{
		id = "no_repeats",
		name = "No Repeats",
		description = "You can't score the same poker hand type twice this round.",
		noRepeatHandTypes = true,
	},
	{
		id = "hearts_are_out",
		name = "Hearts Are Out",
		description = "Heart cards score no Chips or Mult this round.",
		debuff = "Hearts",
	},
	{
		id = "spades_are_out",
		name = "Spades Are Out",
		description = "Spade cards score no Chips or Mult this round.",
		debuff = "Spades",
	},
	{
		id = "no_vips",
		name = "No VIPs",
		description = "Face cards (Jack, Queen, King) score no Chips or Mult this round.",
		debuff = "FaceCards",
	},
	{
		id = "empty_pockets",
		name = "Empty Pockets",
		description = "Playing your most-used hand type this round wipes your Tips to 0.",
		zeroTipsOnMostPlayedHand = true,
	},
	{
		id = "full_table",
		name = "Full Table",
		description = "You must play exactly 5 cards every hand this round.",
		requiredCardsPerHand = 5,
	},
	{
		id = "last_call_only",
		name = "Last Call Only",
		description = "You start this round with 0 discards.",
		discardsDelta = -99, -- clamped to 0 by RunState.startRound
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
