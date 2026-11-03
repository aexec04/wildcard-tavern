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
	like Lights Out (1 hand only) was exactly as likely on Night 1 as
	Night 10. Now every modifier has a `minNight`, grouped into 3 rough
	tiers by how much they actually cripple a fresh, Patron-light run:
	tier 1 (Night 1+) is mild single-knob stuff (a card/discard down, a
	modest score bump); tier 2 (Night 3+) adds real strategic
	restrictions (suit/face debuffs, no-repeat hands, 0 discards); tier 3
	(Night 6+) is the genuinely brutal stuff (hard hand caps, reduced
	Chips+Mult, a forced 1-card hand, doubled target) -- exactly the
	category Lights Out was in. By Night 6 a run has had 15 rounds
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
		flavorText = "Big arms, small smile, and a very short guest list.",
		minNight = 1,
		handSizeDelta = -1,
	},
	{
		id = "short_notice",
		name = "Short Notice",
		description = "One fewer discard this round.",
		flavorText = "The inspector is coming. No time to tidy up!",
		minNight = 1,
		discardsDelta = -1,
	},
	{
		id = "house_rules",
		name = "House Rules",
		description = "The target score is 40% higher this round.",
		flavorText = "Someone pinned a new rule to the door. It's a hard one.",
		minNight = 1,
		targetScoreMultiplier = 1.4,
	},
	{
		id = "the_tab",
		name = "The Tab",
		description = "Lose 1 Tip for every card you play.",
		flavorText = "Every card you play costs a coin. Ouch.",
		minNight = 1,
		tipsLostPerCardPlayed = 1,
	},
	{
		id = "thin_soup",
		name = "Thin Soup",
		description = "Chips from played hands are reduced by 20% this round.",
		flavorText = "The pot was watered down. The chips feel it.",
		minNight = 1,
		chipsMultiplier = 0.8,
	},
	{
		id = "slow_simmer",
		name = "Slow Simmer",
		description = "Mult from played hands is reduced by 20% this round.",
		flavorText = "The fire is low and the mult is lukewarm.",
		minNight = 1,
		multMultiplier = 0.8,
	},

	-- ===== Tier 2 (Night 3+) -- real strategic restrictions =====
	{
		id = "rowdy_crowd",
		name = "Rowdy Crowd",
		description = "2 random cards are tossed out of your hand after every hand you play.",
		flavorText = "A crowd bumps your elbow and cards go flying.",
		minNight = 3,
		forcedRandomDiscardsPerHand = 2,
	},
	{
		id = "no_repeats",
		name = "No Repeats",
		description = "You can't score the same poker hand type twice this round.",
		flavorText = "The critic yawns at anything played twice.",
		minNight = 3,
		noRepeatHandTypes = true,
	},
	{
		id = "hearts_are_out",
		name = "Hearts Are Out",
		description = "Heart cards score no Chips or Mult this round.",
		flavorText = "The hearts went home early with a sniffle.",
		minNight = 3,
		debuff = "Hearts",
	},
	{
		id = "spades_are_out",
		name = "Spades Are Out",
		description = "Spade cards score no Chips or Mult this round.",
		flavorText = "The spades are busy digging in the garden.",
		minNight = 3,
		debuff = "Spades",
	},
	{
		id = "no_vips",
		name = "No VIPs",
		description = "Face cards (Jack, Queen, King) score no Chips or Mult this round.",
		flavorText = "The royals are on holiday. No crowns tonight.",
		minNight = 3,
		debuff = "FaceCards",
	},
	{
		id = "empty_pockets",
		name = "Empty Pockets",
		description = "Playing your most-used hand type this round wipes your Tips to 0.",
		flavorText = "Play your favorite trick and the coins roll away.",
		minNight = 3,
		zeroTipsOnMostPlayedHand = true,
	},
	{
		id = "full_table",
		name = "Full Table",
		description = "You must play exactly 5 cards every hand this round.",
		flavorText = "Every seat must be filled. Five cards, no less.",
		minNight = 3,
		requiredCardsPerHand = 5,
	},
	{
		id = "last_chance",
		name = "Last Chance",
		description = "You get only 1 discard this round.",
		flavorText = "One toss in the bin and that's it.",
		minNight = 3,
		discardsDelta = -2,
	},
	{
		id = "short_staffed",
		name = "Short Staffed",
		description = "One fewer card dealt AND one fewer discard this round.",
		flavorText = "Half the helpers caught the same cold.",
		minNight = 3,
		handSizeDelta = -1,
		discardsDelta = -1,
	},
	{
		id = "diamonds_are_out",
		name = "Diamonds Are Out",
		description = "Diamond cards score no Chips or Mult this round.",
		flavorText = "The diamonds are being polished in the back room.",
		minNight = 3,
		debuff = "Diamonds",
	},
	{
		id = "clubs_are_out",
		name = "Clubs Are Out",
		description = "Club cards score no Chips or Mult this round.",
		flavorText = "The clubs went to march in the town parade.",
		minNight = 3,
		debuff = "Clubs",
	},
	{
		id = "steep_tab",
		name = "Steep Tab",
		description = "Lose 2 Tips for every card you play this round.",
		flavorText = "Prices doubled the minute you walked in.",
		minNight = 3,
		tipsLostPerCardPlayed = 2,
	},
	{
		id = "thin_chips",
		name = "Thin Chips",
		description = "Chips from played hands are reduced by 40% this round (Mult is untouched).",
		flavorText = "Someone ate half the chips before they got to you.",
		minNight = 3,
		chipsMultiplier = 0.6,
	},
	{
		id = "flat_mult",
		name = "Flat Mult",
		description = "Mult from played hands is reduced by 40% this round (Chips are untouched).",
		flavorText = "The fizz went flat on your mult tonight.",
		minNight = 3,
		multMultiplier = 0.6,
	},
	{
		id = "double_tab",
		name = "Double Tab",
		description = "Lose 1 Tip for every card you play, and the target score is 20% higher this round.",
		flavorText = "Paying for every card and aiming higher too.",
		minNight = 3,
		tipsLostPerCardPlayed = 1,
		targetScoreMultiplier = 1.2,
	},
	-- ===== Tier 3 (Night 6+) -- the genuinely brutal ones. By Night 6 a =====
	-- ===== run has had 15 rounds to build up Patrons/Recipes/House Passes =====
	{
		id = "lights_out",
		name = "Lights Out",
		description = "You may only play 1 hand this round, but the target score is halved.",
		flavorText = "The candles blew out. One shot in the dark.",
		minNight = 6,
		handsPerRoundOverride = 1,
		targetScoreMultiplier = 0.5,
	},
	{
		id = "quick_service",
		name = "Quick Service",
		description = "You may only play 2 hands this round, but the target score is 25% lower.",
		flavorText = "The cook wants to close early. Two tries, quick!",
		minNight = 6,
		handsPerRoundOverride = 2,
		targetScoreMultiplier = 0.75,
	},
	{
		id = "stale_bread",
		name = "Stale Bread",
		description = "Chips and Mult from played hands are reduced by 25% this round.",
		flavorText = "Yesterday's loaf, and it tastes like it.",
		minNight = 6,
		chipsMultiplier = 0.75,
		multMultiplier = 0.75,
	},
	{
		id = "one_at_a_time",
		name = "One at a Time",
		description = "You must play exactly 1 card every hand this round, but the target score is 65% lower.",
		flavorText = "Single file, please. One card per trip.",
		minNight = 6,
		requiredCardsPerHand = 1,
		targetScoreMultiplier = 0.35,
	},
	{
		id = "big_tab",
		name = "Big Tab",
		description = "The target score is double this round.",
		flavorText = "The bill came back twice as long as expected.",
		minNight = 6,
		targetScoreMultiplier = 2,
	},
	{
		id = "wild_crowd",
		name = "Wild Crowd",
		description = "3 random cards are tossed out of your hand after every hand you play.",
		flavorText = "Chaos at every table. Hold on to your cards!",
		minNight = 6,
		forcedRandomDiscardsPerHand = 3,
	},
	{
		id = "empty_handed",
		name = "Empty-Handed",
		description = "You get only 1 discard and may only play 3 hands this round.",
		flavorText = "Short on tries, short on tosses, long on nerves.",
		minNight = 6,
		discardsDelta = -2,
		handsPerRoundOverride = 3,
	},
	{
		id = "everythings_out",
		name = "Everything's Out",
		description = "Chips and Mult from played hands are reduced by 32% this round.",
		flavorText = "The pantry is almost bare tonight.",
		minNight = 6,
		chipsMultiplier = 0.68,
		multMultiplier = 0.68,
	},
	{
		id = "four_top",
		name = "Four Top",
		description = "You must play exactly 4 cards every hand this round.",
		flavorText = "Tables for four only. Exactly four.",
		-- RETUNED (independent review, before deploy): originally tier 2
		-- (minNight = 3) as "six_max" -- moved to tier 3 and renamed once
		-- the review pointed out exactly-4-cards is actually MORE
		-- restrictive than tier-2 sibling Full Table's exactly-5 (Straight/
		-- Flush/Full House/Straight Flush all hard-require 5 cards --
		-- see HandEvaluator.lua -- so exactly 4 forecloses all 4 of those
		-- hand types outright, while exactly 5 forecloses nothing). That's
		-- closer to One at a Time's severity (tier 3's exactly-1-card) than
		-- to Full Table's, so it belongs in tier 3 -- exactly the kind of
		-- early-run difficulty wall this file's own tier system exists to
		-- prevent (see the file header comment).
		minNight = 6,
		requiredCardsPerHand = 4,
	},

	-- ===== Phase 15 batch -- more content, same reuse-an-existing-field =====
	-- ===== pattern every prior batch used. Tiered carefully against the =====
	-- ===== closest existing sibling rather than guessed, after the Four =====
	-- ===== Top mistuning in Phase 12 -- see that entry's comment for why =====
	-- ===== requiredCardsPerHand specifically needs this care (a SMALLER =====
	-- ===== exact-count forecloses MORE hand types, so it's more brutal, =====
	-- ===== not less -- none of these new ones touch that field at all). =====
	{
		id = "slow_night",
		name = "Slow Night",
		description = "1 random card is tossed out of your hand after every hand you play.",
		flavorText = "Quiet tables, wandering cards.",
		-- Milder sibling of tier-2 Rowdy Crowd (2 cards) and tier-3 Wild
		-- Crowd (3 cards) -- 1 card is the gentlest step on this knob, so it
		-- belongs a tier below both.
		minNight = 1,
		forcedRandomDiscardsPerHand = 1,
	},
	{
		id = "house_minimum",
		name = "House Minimum",
		description = "The target score is 20% higher this round.",
		flavorText = "The house wants a little more effort tonight.",
		-- Milder sibling of tier-1 House Rules (1.4x) -- same knob, lower
		-- number, same tier (a numeric variant within a tier is the exact
		-- pattern Thin Soup/Slow Simmer already established for
		-- Chips/Mult at tier 1).
		minNight = 1,
		targetScoreMultiplier = 1.2,
	},
	{
		id = "picked_over",
		name = "Picked Over",
		description = "Heart cards score no Chips or Mult, and you're dealt one fewer card, this round.",
		flavorText = "The hearts are gone and the deck feels light.",
		-- New COMBO (a suit debuff + a hand-size cut together) -- not just a
		-- numeric variant, so tiered by comparing severity to existing tier-2
		-- combos: Short Staffed (handSizeDelta -1 + discardsDelta -1) and Double
		-- Tab (tipsLost + targetMult +20%) are both 2-knob tier-2 modifiers;
		-- a single-suit debuff (already tier 2 alone, e.g. Hearts Are Out)
		-- plus a 1-card hand cut (tier 1 alone, The Bouncer) reads as
		-- comparable combined severity to those, so tier 2.
		minNight = 3,
		debuff = "Hearts",
		handSizeDelta = -1,
	},
	{
		id = "rushed_order",
		name = "Rushed Order",
		description = "You may only play 3 hands this round.",
		flavorText = "Three tries before the kitchen closes.",
		-- Milder sibling of tier-3 Lights Out (1 hand) and Quick Service
		-- (2 hands) -- 3 hands is a genuine restriction (below the default
		-- handsPerRound) but nowhere near as crippling as capping at 1-2,
		-- so it sits a tier below both rather than joining them at tier 3.
		minNight = 3,
		handsPerRoundOverride = 3,
	},
	{
		id = "bare_bones",
		name = "Bare Bones",
		description = "Chips and Mult from played hands are reduced by 30% this round.",
		flavorText = "Just the basics tonight. No frills at all.",
		-- Sits between tier-3 siblings Stale Bread (-25%) and
		-- Everything's Out (-32%) -- a genuine tier-3-only
		-- escalation step, not a new knob.
		minNight = 6,
		chipsMultiplier = 0.7,
		multMultiplier = 0.7,
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

-- JOURNEY MAP (distinct boss gates): a coarse "what kind of boss is
-- this" bucket, derived from whichever effect fields a definition sets
-- rather than hand-tagged on all 35 entries -- so a new modifier gets a
-- category for free, and can't be mis-tagged. The client (Journey.lua)
-- maps each id to a gate color/glyph; this file stays presentation-free.
-- Combos (e.g. Picked Over's debuff + hand cut) take the FIRST match in
-- this order, which runs roughly most-to-least strategically disruptive.
BossRounds.Categories = {
	{ id = "debuff", name = "Debuff" },           -- suit/face cards score nothing
	{ id = "restriction", name = "Play Limit" },  -- hand caps, exact card counts, no repeats
	{ id = "weaken", name = "Chip/Mult Penalty" },
	{ id = "squeeze", name = "Hand Cut" },        -- fewer cards/discards, random tosses
	{ id = "tips", name = "Tips Penalty" },
	{ id = "target", name = "Higher Target" },
}

function BossRounds.categoryOf(def)
	if not def then
		return nil
	end
	if def.debuff then
		return "debuff"
	elseif def.handsPerRoundOverride or def.requiredCardsPerHand or def.noRepeatHandTypes then
		return "restriction"
	elseif def.chipsMultiplier or def.multMultiplier then
		return "weaken"
	elseif def.handSizeDelta or def.discardsDelta or def.forcedRandomDiscardsPerHand then
		return "squeeze"
	elseif def.tipsLostPerCardPlayed or def.zeroTipsOnMostPlayedHand then
		return "tips"
	elseif def.targetScoreMultiplier then
		return "target"
	end
	return nil
end

function BossRounds.getCategoryById(id)
	for _, category in ipairs(BossRounds.Categories) do
		if category.id == id then
			return category
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
