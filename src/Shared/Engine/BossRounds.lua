--[[
	BossRounds.lua
	Every Night ends on a tougher, modified round -- our equivalent of a
	"boss" encounter, but expressed as data-driven modifiers rather than a
	literal fight. Original names/effects, not copied from any other game.

	A boss round applies for the LAST round of each Night (see
	isBossRound). Which modifier gets picked is randomized per Night, but
	gated by `minNight` (see BossRounds.pick) -- BUGFIX (Ahmed's playtest:
	"the first boss that appeared... had you play only 1 hand to win and
	it was just impossible since you didn't even have that many jokers to
	begin with"). Before this, selection was uniform across ALL 24
	modifiers regardless of what Night you were on, so a run-ending wall
	like Closing Time (1 hand only) was exactly as likely on Night 1 as
	Night 10. Now every modifier has a `minNight`, grouped into 3 rough
	tiers by how much they actually cripple a fresh, Patron-light run:
	tier 1 (Night 1+) is mild single-knob stuff (a card/discard down, a
	modest score bump); tier 2 (Night 3+) adds real strategic
	restrictions (suit/face debuffs, no-repeat hands, 0 discards); tier 3
	(Night 6+) is the genuinely brutal stuff (hard hand caps, halved
	Chips+Mult, a forced 1-card hand, tripled target) -- exactly the
	category Closing Time was in. By Night 6 a run has had 15 rounds
	(5 Nights x 3 rounds) to build up Patrons/Recipes/House Passes, so
	these read as a real challenge spike instead of an early-run wall.

	Modifier shape (every field optional except minNight -- RunState.
	startRound/playHand interpret whichever ones are present):
		{ id, name, description,
		  minNight = number,                   -- BossRounds.pick won't return
		                                        -- this before state.night reaches it
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
	-- ===== Tier 1 (Night 1+) -- mild, fair for a fresh run =====
	{
		id = "bouncer",
		name = "The Bouncer",
		description = "Deals you one fewer card this round.",
		minNight = 1,
		handSizeDelta = -1,
	},
	{
		id = "last_orders",
		name = "Last Orders",
		description = "One fewer discard this round.",
		minNight = 1,
		discardsDelta = -1,
	},
	{
		id = "house_rules",
		name = "House Rules",
		description = "The target score is 40% higher this round.",
		minNight = 1,
		targetScoreMultiplier = 1.4,
	},
	{
		id = "the_tab",
		name = "The Tab",
		description = "Lose 1 Tip for every card you play.",
		minNight = 1,
		tipsLostPerCardPlayed = 1,
	},

	-- ===== Tier 2 (Night 3+) -- real strategic restrictions =====
	{
		id = "rowdy_crowd",
		name = "Rowdy Crowd",
		description = "2 random cards are tossed out of your hand after every hand you play.",
		minNight = 3,
		forcedRandomDiscardsPerHand = 2,
	},
	{
		id = "no_repeats",
		name = "No Repeats",
		description = "You can't score the same poker hand type twice this round.",
		minNight = 3,
		noRepeatHandTypes = true,
	},
	{
		id = "hearts_are_out",
		name = "Hearts Are Out",
		description = "Heart cards score no Chips or Mult this round.",
		minNight = 3,
		debuff = "Hearts",
	},
	{
		id = "spades_are_out",
		name = "Spades Are Out",
		description = "Spade cards score no Chips or Mult this round.",
		minNight = 3,
		debuff = "Spades",
	},
	{
		id = "no_vips",
		name = "No VIPs",
		description = "Face cards (Jack, Queen, King) score no Chips or Mult this round.",
		minNight = 3,
		debuff = "FaceCards",
	},
	{
		id = "empty_pockets",
		name = "Empty Pockets",
		description = "Playing your most-used hand type this round wipes your Tips to 0.",
		minNight = 3,
		zeroTipsOnMostPlayedHand = true,
	},
	{
		id = "full_table",
		name = "Full Table",
		description = "You must play exactly 5 cards every hand this round.",
		minNight = 3,
		requiredCardsPerHand = 5,
	},
	{
		id = "last_call_only",
		name = "Last Call Only",
		description = "You start this round with 0 discards.",
		minNight = 3,
		discardsDelta = -99, -- clamped to 0 by RunState.startRound
	},
	{
		id = "dry_spell",
		name = "Dry Spell",
		description = "One fewer card dealt AND one fewer discard this round.",
		minNight = 3,
		handSizeDelta = -1,
		discardsDelta = -1,
	},
	{
		id = "diamonds_are_out",
		name = "Diamonds Are Out",
		description = "Diamond cards score no Chips or Mult this round.",
		minNight = 3,
		debuff = "Diamonds",
	},
	{
		id = "clubs_are_out",
		name = "Clubs Are Out",
		description = "Club cards score no Chips or Mult this round.",
		minNight = 3,
		debuff = "Clubs",
	},
	{
		id = "steep_tab",
		name = "Steep Tab",
		description = "Lose 2 Tips for every card you play this round.",
		minNight = 3,
		tipsLostPerCardPlayed = 2,
	},
	{
		id = "thin_chips",
		name = "Thin Chips",
		description = "Chips from played hands are halved this round (Mult is untouched).",
		minNight = 3,
		chipsMultiplier = 0.5,
	},
	{
		id = "flat_mult",
		name = "Flat Mult",
		description = "Mult from played hands is halved this round (Chips are untouched).",
		minNight = 3,
		multMultiplier = 0.5,
	},

	-- ===== Tier 3 (Night 6+) -- the genuinely brutal ones. By Night 6 a =====
	-- ===== run has had 15 rounds to build up Patrons/Recipes/House Passes =====
	{
		id = "closing_time",
		name = "Closing Time",
		description = "You may only play 1 hand this round.",
		minNight = 6,
		handsPerRoundOverride = 1,
	},
	{
		id = "quick_service",
		name = "Quick Service",
		description = "You may only play 2 hands this round.",
		minNight = 6,
		handsPerRoundOverride = 2,
	},
	{
		id = "watered_down",
		name = "Watered Down",
		description = "Chips and Mult from played hands are halved this round.",
		minNight = 6,
		chipsMultiplier = 0.5,
		multMultiplier = 0.5,
	},
	{
		id = "one_at_a_time",
		name = "One at a Time",
		description = "You must play exactly 1 card every hand this round.",
		minNight = 6,
		requiredCardsPerHand = 1,
	},
	{
		id = "big_tab",
		name = "Big Tab",
		description = "The target score is triple this round.",
		minNight = 6,
		targetScoreMultiplier = 3,
	},
	{
		id = "wild_crowd",
		name = "Wild Crowd",
		description = "3 random cards are tossed out of your hand after every hand you play.",
		minNight = 6,
		forcedRandomDiscardsPerHand = 3,
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
--
-- `night` gates which modifiers are even eligible (see each definition's
-- `minNight` and the file header comment for why) -- defaults to 1, i.e.
-- the most restrictive tier, if the caller doesn't have a Night number
-- handy for some reason. Still genuinely random WITHIN whatever tier(s)
-- are unlocked, not a fixed/deterministic-by-Night pick.
function BossRounds.pick(rng, night)
	rng = rng or math.random
	night = night or 1

	local eligible = {}
	for _, def in ipairs(BossRounds.Definitions) do
		if (def.minNight or 1) <= night then
			table.insert(eligible, def)
		end
	end
	if #eligible == 0 then
		-- Defensive only -- every tier-1 modifier has minNight = 1, so this
		-- can't actually happen for any night >= 1. Falls back to the full
		-- pool rather than erroring if it somehow ever did.
		eligible = BossRounds.Definitions
	end

	local index = rng(#eligible)
	return eligible[index]
end

return BossRounds
