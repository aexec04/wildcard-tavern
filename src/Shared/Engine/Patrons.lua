--[[
	Patrons.lua
	"Patrons" are our equivalent of a passive modifier card that sits in your
	party and boosts hands as you play them (own original names/effects --
	swap in your own art & flavor text freely).

	Each patron is data + a pure `effect(handResult, context)` function that
	returns an optional { chips = n, mult = n, multMultiplier = n, tips = n }
	bonus. Keeping effects as pure functions of (handResult, context) means
	they're trivially unit-testable in isolation. A patron can also define
	`onRoundWin(state)` for a once-per-round-won effect that isn't tied to
	any particular hand (e.g. flat Tip income) -- that one DOES touch state
	directly, called by RunState after a round is won.
]]

local Card = require(script.Parent.Card)

local Patrons = {}

-- Runs `target`'s ability on behalf of a copying Patron. Copiers can point at
-- each other (The Understudy seated leftmost with Second Opinion on its
-- right would otherwise copy each other forever), so a copy that would
-- revisit a Patron already in the current chain contributes nothing.
local function copyAbility(selfId, target, handResult, context)
	if not target then
		return nil
	end
	local chain = context.copyChain or {}
	context.copyChain = chain
	if target.id == selfId or chain[target.id] then
		return nil
	end
	local wasInChain = chain[selfId]
	chain[selfId] = true
	local bonus = target.effect(handResult, context)
	chain[selfId] = wasInChain
	return bonus
end

-- context fields you can use in an effect function:
--   allPlayedCards   -- every card in the hand that was played (not just scoring ones)
--   heldCards        -- cards left in hand, NOT played, at the moment of scoring
--   handsRemaining   -- hands left to play this round, before this one
--   discardsRemaining
--   isLastHand       -- true if this is the last hand of the round
--   night, round     -- current progress
--   tips             -- Tips held before this hand's reward is added
--   ownedPatrons, patronIndex -- this patron's own list/position, for
--                                "copy a neighbor's ability" patrons
--   roundsCleared, bossesCleared, handsPlayedTotal, discardsUsedTotal,
--   patronsSold, handStatsBefore -- run-long tallies as of before this hand,
--                                see RunState.runCounters. Definitions are
--                                shared between runs, so a scaling Patron
--                                must read these, never store its own count.

Patrons.Definitions = {
	{
		id = "the_regular",
		name = "The Regular",
		icon = "☕",
		description = "+4 Mult on every hand.",
		flavorText = "Same stool, same cocoa, same story about the big storm.",
		price = 4,
		effect = function(_handResult, _context)
			return { mult = 4 }
		end,
	},
	{
		id = "lucky_dice",
		name = "Lucky Dice",
		icon = "🎲",
		description = "+15 Chips if the hand contains a Pair (or better).",
		flavorText = "Rolls them for every decision, even soup or stew.",
		price = 5,
		effect = function(handResult, _context)
			local pairLike = {
				["Pair"] = true, ["Two Pair"] = true, ["Three of a Kind"] = true,
				["Full House"] = true, ["Four of a Kind"] = true,
			}
			if pairLike[handResult.name] then
				return { chips = 15 }
			end
			return nil
		end,
	},
	{
		id = "suit_yourself",
		name = "Suit Yourself",
		icon = "♥️",
		description = "+3 Mult for each Heart among the scoring cards.",
		flavorText = "Wears a heart on every sleeve. Literally.",
		price = 6,
		effect = function(handResult, _context)
			local hearts = 0
			for _, card in ipairs(handResult.scoringCards) do
				if Card.hasSuit(card, "Hearts") then
					hearts = hearts + 1
				end
			end
			if hearts > 0 then
				return { mult = 3 * hearts }
			end
			return nil
		end,
	},
	{
		id = "curtain_call",
		name = "Curtain Call",
		icon = "🌙",
		description = "Mult x1.5 when played as your last hand of the round.",
		flavorText = "Always saves the best bow for last.",
		price = 7,
		effect = function(_handResult, context)
			if context.isLastHand then
				return { multMultiplier = 1.5 }
			end
			return nil
		end,
	},
	{
		id = "the_bard",
		name = "The Bard",
		icon = "🎻",
		description = "+1 Mult for every card played (not just scoring cards).",
		flavorText = "Knows a song for every card, and sings all of them.",
		price = 7,
		effect = function(_handResult, context)
			local played = context.allPlayedCards or {}
			if #played > 0 then
				return { mult = #played }
			end
			return nil
		end,
	},

	-- ===== +MULT: rewards a specific hand type =====
	{
		id = "regulars_round", name = "Regulars' Round", icon = "🤝", price = 5,
		description = "+8 Mult if the hand contains a Pair (or better).",
		flavorText = "Two old friends who never sit apart.",
		effect = function(handResult, _context)
			local pairLike = {
				["Pair"] = true, ["Two Pair"] = true, ["Three of a Kind"] = true,
				["Full House"] = true, ["Four of a Kind"] = true,
			}
			if pairLike[handResult.name] then
				return { mult = 8 }
			end
			return nil
		end,
	},
	{
		id = "threes_company", name = "Three's Company", icon = "🎊", price = 5,
		description = "+18 Mult if the hand contains a Three of a Kind.",
		flavorText = "Arrive as a trio, leave as a trio, laugh as a trio.",
		effect = function(handResult, _context)
			if handResult.name == "Three of a Kind" or handResult.name == "Full House" then
				return { mult = 18 }
			end
			return nil
		end,
	},
	{
		id = "all_hands_in", name = "All Hands In", icon = "🙌", price = 7,
		description = "+25 Mult if the hand contains a Four of a Kind.",
		flavorText = "Four cousins, one table, zero quiet moments.",
		effect = function(handResult, _context)
			if handResult.name == "Four of a Kind" then
				return { mult = 25 }
			end
			return nil
		end,
	},
	{
		id = "straight_shooter", name = "Straight Shooter", icon = "🎯", price = 6,
		description = "+18 Mult if the hand contains a Straight.",
		flavorText = "Lines up the salt shakers by height. Every time.",
		effect = function(handResult, _context)
			if handResult.name == "Straight" or handResult.name == "Straight Flush" then
				return { mult = 18 }
			end
			return nil
		end,
	},
	{
		id = "all_matching", name = "All Matching", icon = "🃏", price = 6,
		description = "+18 Mult if the hand contains a Flush.",
		flavorText = "Their hat, scarf and mittens are all the same color.",
		effect = function(handResult, _context)
			if handResult.name == "Flush" or handResult.name == "Straight Flush" then
				return { mult = 18 }
			end
			return nil
		end,
	},
	{
		id = "small_plate", name = "Small Plate", icon = "🍽️", price = 6,
		description = "+8 Mult if you play 3 or fewer cards.",
		flavorText = "Orders the tiny pie and enjoys every crumb.",
		effect = function(_handResult, context)
			local played = context.allPlayedCards or {}
			if #played > 0 and #played <= 3 then
				return { mult = 8 }
			end
			return nil
		end,
	},

	-- ===== +CHIPS =====
	{
		id = "big_portions", name = "Big Portions", icon = "🍖", price = 7,
		description = "+25 Chips if the hand contains a Pair (or better).",
		flavorText = "Asks for seconds before the firsts arrive.",
		effect = function(handResult, _context)
			local pairLike = {
				["Pair"] = true, ["Two Pair"] = true, ["Three of a Kind"] = true,
				["Full House"] = true, ["Four of a Kind"] = true,
			}
			if pairLike[handResult.name] then
				return { chips = 25 }
			end
			return nil
		end,
	},
	{
		id = "tab_regulars", name = "Tab Regulars", icon = "💰", price = 5,
		description = "+1 Chip for every Tip you're currently holding.",
		flavorText = "Counts their coins out loud, slowly, with joy.",
		effect = function(_handResult, context)
			local tips = context.tips or 0
			if tips >= 1 then
				return { chips = tips }
			end
			return nil
		end,
	},

	-- ===== XMULT =====
	{
		id = "house_favorite", name = "House Favorite", icon = "👑", price = 8,
		description = "x1.5 Mult for each King held in your hand (not played).",
		flavorText = "The kings at the card table bow when they walk in.",
		effect = function(_handResult, context)
			local count = 0
			for _, card in ipairs(context.heldCards or {}) do
				if card.rank == 13 then
					count = count + 1
				end
			end
			if count > 0 then
				return { multMultiplier = 1.5 ^ count }
			end
			return nil
		end,
	},
	{
		id = "repeat_customer", name = "Repeat Customer", icon = "🔁", price = 7,
		description = "x3 Mult if you've already played this poker hand type this round.",
		flavorText = "Found a favorite and is never changing it.",
		effect = function(_handResult, context)
			if context.alreadyPlayedThisHandTypeThisRound then
				return { multMultiplier = 3 }
			end
			return nil
		end,
	},

	-- ===== UTILITY =====
	{
		id = "the_understudy", name = "The Understudy", icon = "🎭", price = 6,
		description = "Copies the ability of the Patron to its right.",
		flavorText = "Has memorized every line of the guest to their right.",
		effect = function(handResult, context)
			local patrons = context.ownedPatrons or {}
			local i = context.patronIndex or 0
			return copyAbility("the_understudy", patrons[i + 1], handResult, context)
		end,
	},
	{
		id = "second_opinion", name = "Second Opinion", icon = "💡", price = 6,
		description = "Copies the ability of your leftmost Patron.",
		flavorText = "Watches the first guest closely, then does it again.",
		effect = function(handResult, context)
			local patrons = context.ownedPatrons or {}
			return copyAbility("second_opinion", patrons[1], handResult, context)
		end,
	},

	-- ===== ECONOMY =====
	{
		id = "tip_jar", name = "Tip Jar", icon = "🫙", price = 6,
		description = "Earn 4 Tips at the end of each round you win.",
		flavorText = "Rattles a little happier after every good night.",
		effect = function() return nil end,
		onRoundWin = function(state)
			state.tips = state.tips + 4
		end,
	},
	{
		id = "penny_pincher", name = "Penny Pincher", icon = "🪙", price = 7,
		description = "+1 Mult for every 3 Tips you're currently holding.",
		flavorText = "Every coin is saved, polished and named.",
		effect = function(_handResult, context)
			local tips = context.tips or 0
			if tips >= 3 then
				return { mult = math.floor(tips / 3) }
			end
			return nil
		end,
	},

	-- ===== More suit specialists (mirrors Suit Yourself, one per remaining suit) =====
	{
		id = "sparkling_service", name = "Sparkling Service", icon = "💎", price = 6,
		description = "+3 Mult for each Diamond among the scoring cards.",
		flavorText = "Their boots shine brighter than the lanterns.",
		effect = function(handResult, _context)
			local count = 0
			for _, card in ipairs(handResult.scoringCards) do
				if Card.hasSuit(card, "Diamonds") then
					count = count + 1
				end
			end
			if count > 0 then
				return { mult = 3 * count }
			end
			return nil
		end,
	},
	{
		id = "rowdy_bunch", name = "Rowdy Bunch", icon = "♣️", price = 6,
		description = "+3 Mult for each Club among the scoring cards.",
		flavorText = "Cheers so loud the spoons jump off the table.",
		effect = function(handResult, _context)
			local count = 0
			for _, card in ipairs(handResult.scoringCards) do
				if Card.hasSuit(card, "Clubs") then
					count = count + 1
				end
			end
			if count > 0 then
				return { mult = 3 * count }
			end
			return nil
		end,
	},
	{
		id = "sharp_dressed", name = "Sharp Dressed", icon = "♠️", price = 6,
		description = "+3 Mult for each Spade among the scoring cards.",
		flavorText = "Ironed their cape twice before coming in.",
		effect = function(handResult, _context)
			local count = 0
			for _, card in ipairs(handResult.scoringCards) do
				if Card.hasSuit(card, "Spades") then
					count = count + 1
				end
			end
			if count > 0 then
				return { mult = 3 * count }
			end
			return nil
		end,
	},

	-- ===== More hand-type specialists (Two Pair / Full House were the two =====
	-- ===== gaps left in the "+Mult for hand type" family) =====
	{
		id = "double_down", name = "Double Down", icon = "👯", price = 6,
		description = "+10 Mult if the hand is exactly a Two Pair.",
		flavorText = "Two pairs of socks, two pairs of gloves, two of everything.",
		effect = function(handResult, _context)
			if handResult.name == "Two Pair" then
				return { mult = 10 }
			end
			return nil
		end,
	},
	{
		id = "house_special", name = "House Special", icon = "🍱", price = 8,
		description = "+22 Mult if the hand is a Full House.",
		flavorText = "Ordered one of everything on the menu, all at once.",
		effect = function(handResult, _context)
			if handResult.name == "Full House" then
				return { mult = 22 }
			end
			return nil
		end,
	},

	-- ===== Rank-based (new dimension -- everything above rewarded suits or =====
	-- ===== hand shapes, nothing rewarded specific ranks among scoring cards) =====
	{
		id = "ace_of_the_house", name = "Ace of the House", icon = "🅰️", price = 6,
		description = "+8 Mult for each Ace among the scoring cards.",
		flavorText = "Wins every game of checkers in the back room.",
		effect = function(handResult, _context)
			local count = 0
			for _, card in ipairs(handResult.scoringCards) do
				if card.rank == 14 then
					count = count + 1
				end
			end
			if count > 0 then
				return { mult = 8 * count }
			end
			return nil
		end,
	},
	{
		id = "vip_table", name = "VIP Table", icon = "🎩", price = 6,
		description = "+8 Mult if the hand contains a face card (Jack, Queen, or King) among the scoring cards.",
		flavorText = "Has a reserved seat, a reserved cushion and a reserved spoon.",
		effect = function(handResult, _context)
			for _, card in ipairs(handResult.scoringCards) do
				if Card.isFaceCard(card) then
					return { mult = 8 }
				end
			end
			return nil
		end,
	},

	-- ===== More XMULT (only House Favorite/Repeat Customer existed before) =====
	{
		id = "early_bird", name = "Early Bird", icon = "🌅", price = 8,
		description = "x1.1 Mult for each Hand you have remaining this round after this one.",
		flavorText = "Arrives before the doors open and waits politely.",
		effect = function(_handResult, context)
			local remaining = context.handsRemaining or 0
			if remaining > 0 then
				return { multMultiplier = 1.1 ^ remaining }
			end
			return nil
		end,
	},
	{
		id = "discard_special", name = "Discard Special", icon = "🧾", price = 6,
		description = "+1 Mult for each Discard you have remaining this round.",
		flavorText = "Keeps a neat pile of things they didn't need.",
		effect = function(_handResult, context)
			local remaining = context.discardsRemaining or 0
			if remaining > 0 then
				return { mult = remaining }
			end
			return nil
		end,
	},

	-- ===== More UTILITY (mirrors The Understudy, but copies the other =====
	-- ===== direction -- Second Opinion always copies leftmost regardless =====
	-- ===== of position, this one copies whichever Patron sits immediately =====
	-- ===== to its own left) =====
	{
		id = "the_apprentice", name = "The Apprentice", icon = "🧑‍🍳", price = 6,
		description = "Copies the ability of the Patron to its left.",
		flavorText = "Learns every trick from the guest on their left.",
		effect = function(handResult, context)
			local patrons = context.ownedPatrons or {}
			local i = context.patronIndex or 0
			return copyAbility("the_apprentice", patrons[i - 1], handResult, context)
		end,
	},

	-- ===== More ECONOMY (only Tip Jar/Penny Pincher existed before) =====
	{
		id = "big_spender", name = "Big Spender", icon = "🤵", price = 7,
		description = "Earn 1 Tip for each Patron at your table, at the end of each round you win.",
		flavorText = "Buys a round of muffins for the whole table.",
		effect = function() return nil end,
		onRoundWin = function(state)
			state.tips = state.tips + #state.ownedPatrons
		end,
	},
	{
		id = "nest_egg", name = "Nest Egg", icon = "🥚", price = 7,
		description = "Doubles your round-win interest cap: +10 Tips instead of +5.",
		flavorText = "Saving up for a cottage with a very big garden.",
		effect = function() return nil end,
		-- GENRE PARITY REWORK: end-of-round interest (1 Tip per 5 held,
		-- capped) is now a universal base rule for EVERY run (see
		-- RunState.playHand's roundWon branch) -- this Patron used to BE
		-- that rule, via its own onRoundWin doing the exact same math. Kept
		-- as-is, it would have silently double-dipped the moment the base
		-- rule shipped (both reading/adding off the same state.tips with
		-- the same formula, back to back). Reworked to just raise the base
		-- rule's cap instead -- RunState.playHand checks
		-- `patron.id == "nest_egg"` directly rather than calling an
		-- onRoundWin hook here, so owning this is still a real, distinct
		-- upgrade instead of a redundant purchase.
	},

	-- ===== More rank-based (Ace of the House/House Favorite covered Ace =====
	-- ===== (scoring) and King (held) -- Jack and Queen were the two ranks =====
	-- ===== with no rank-specific Patron at all yet) =====
	{
		id = "jack_of_all_trades", name = "Jack of All Trades", icon = "🎫", price = 5,
		description = "+9 Mult for each Jack among the scoring cards.",
		flavorText = "Can fix a chair, tune a fiddle and bake a pie.",
		effect = function(handResult, _context)
			local count = 0
			for _, card in ipairs(handResult.scoringCards) do
				if card.rank == 11 then
					count = count + 1
				end
			end
			if count > 0 then
				return { mult = 9 * count }
			end
			return nil
		end,
	},
	{
		id = "queens_gambit", name = "Queen's Gambit", icon = "♟️", price = 5,
		description = "+9 Mult for each Queen among the scoring cards.",
		flavorText = "Thinks three moves ahead, even when ordering lunch.",
		effect = function(handResult, _context)
			local count = 0
			for _, card in ipairs(handResult.scoringCards) do
				if card.rank == 12 then
					count = count + 1
				end
			end
			if count > 0 then
				return { mult = 9 * count }
			end
			return nil
		end,
	},

	-- ===== More ECONOMY (reads discardsRemaining at round-win time, same =====
	-- ===== timing Nest Egg/the base interest rule already rely on -- =====
	-- ===== discardsRemaining isn't reset to the next round's value until =====
	-- ===== RunState.startRound, so it's still THIS round's leftover count =====
	-- ===== here) =====
	{
		id = "spare_change", name = "Spare Change", icon = "🧻", price = 6,
		description = "Earn 1 Tip for every Discard you have remaining at the end of a round you win.",
		flavorText = "Finds coins under every cushion in the place.",
		effect = function() return nil end,
		onRoundWin = function(state)
			state.tips = state.tips + (state.discardsRemaining or 0)
		end,
	},

	-- ===== More XMULT (scales with table size instead of a hand/held-card =====
	-- ===== property -- rewards actually filling out your Patron slots, =====
	-- ===== which nothing so far did directly) =====
	{
		id = "full_house_crowd", name = "Full House Crowd", icon = "🥳", price = 8,
		description = "x1.15 Mult for every OTHER Patron at your table.",
		flavorText = "The more friends at the table, the bigger the smiles.",
		effect = function(_handResult, context)
			local patrons = context.ownedPatrons or {}
			local others = math.max(0, #patrons - 1)
			if others > 0 then
				return { multMultiplier = 1.15 ^ others }
			end
			return nil
		end,
	},

	-- ===== More +CHIPS (per-scoring-card, the Chips-side counterpart to =====
	-- ===== The Bard's per-ALL-played-card Mult -- deliberately counts only =====
	-- ===== handResult.scoringCards, not context.allPlayedCards, so it =====
	-- ===== rewards cards that actually scored rather than every card =====
	-- ===== thrown into the hand) =====
	{
		id = "fair_share", name = "Fair Share", icon = "🥧", price = 6,
		description = "+4 Chips for each scoring card in the hand.",
		flavorText = "Cuts every pie into perfectly equal slices.",
		effect = function(handResult, _context)
			local count = #handResult.scoringCards
			if count > 0 then
				return { chips = 4 * count }
			end
			return nil
		end,
	},
	{
		id = "efficient_service", name = "Efficient Service", icon = "🧑‍💼", price = 6,
		description = "+3 Chips for every Hand or Discard you have remaining this round (combined).",
		flavorText = "Clears the table before you finish saying thank you.",
		effect = function(_handResult, context)
			local total = (context.handsRemaining or 0) + (context.discardsRemaining or 0)
			if total > 0 then
				return { chips = 3 * total }
			end
			return nil
		end,
	},

	-- ===== Phase 15 batch -- more content, same low-risk "reuse an =====
	-- ===== existing knob" pattern as Phases 2/3/12. =====

	-- ===== More rank-based (Ace/King/Jack/Queen all had a dedicated Patron =====
	-- ===== -- Ten was the last rank worth a specific callout below that) =====
	{
		id = "perfect_ten", name = "Perfect Ten", icon = "🔟", price = 6,
		description = "+8 Mult for each Ten among the scoring cards.",
		flavorText = "Rates every meal a ten. Means it every time.",
		effect = function(handResult, _context)
			local count = 0
			for _, card in ipairs(handResult.scoringCards) do
				if card.rank == 10 then
					count = count + 1
				end
			end
			if count > 0 then
				return { mult = 8 * count }
			end
			return nil
		end,
	},

	-- ===== More XMULT (scales with run progress instead of a hand/held- =====
	-- ===== card/table-size property -- nothing so far rewarded just being =====
	-- ===== deep into a run) =====
	{
		id = "night_owl", name = "Night Owl", icon = "🦉", price = 8,
		description = "+1 Mult for each Night you've reached so far this run.",
		flavorText = "Wide awake when the candles burn low.",
		effect = function(_handResult, context)
			local night = context.night or 0
			if night > 0 then
				return { mult = night }
			end
			return nil
		end,
	},

	-- ===== More +MULT (rewards playing exactly a full 5-card hand -- the =====
	-- ===== "opposite" of Small Plate's <=3-card reward, and the one card- =====
	-- ===== count Patrons hadn't covered yet) =====
	{
		id = "steady_hand", name = "Steady Hand", icon = "✋", price = 7,
		description = "+5 Mult if you play exactly 5 cards.",
		flavorText = "Can carry five full bowls without spilling a drop.",
		effect = function(_handResult, context)
			local played = context.allPlayedCards or {}
			if #played == 5 then
				return { mult = 5 }
			end
			return nil
		end,
	},

	-- ===== More ECONOMY (reads handsRemaining at round-win time -- the =====
	-- ===== Hands-side counterpart to Spare Change's Discards-side payout) =====
	{
		id = "rainy_day_fund", name = "Rainy Day Fund", icon = "☔", price = 6,
		description = "Earn 1 Tip for every Hand you have remaining at the end of a round you win.",
		flavorText = "Keeps an umbrella and a few coins for stormy nights.",
		effect = function() return nil end,
		onRoundWin = function(state)
			state.tips = state.tips + (state.handsRemaining or 0)
		end,
	},

	-- ===== More ECONOMY (rewards clearing a Boss Round specifically -- =====
	-- ===== state.bossModifier is still set to the round just won at the =====
	-- ===== moment onRoundWin fires, since it isn't cleared until the next =====
	-- ===== RunState.startRound -- same timing the reward-doubling code right =====
	-- ===== below this loop in RunState.playHand already relies on) =====
	{
		id = "boss_bane", name = "Boss's Bane", icon = "🥊", price = 7,
		description = "Earn 10 Tips whenever you clear a Boss Round.",
		flavorText = "Not scared of any troublemaker who walks through the door.",
		effect = function() return nil end,
		onRoundWin = function(state)
			-- isBossRound covers Casual too (no modifier, still a boss
			-- round). Can't call RunState.isBossRound -- require cycle.
			if state.bossModifier or state.isBossRound then
				state.tips = state.tips + 10
			end
		end,
	},

	-- ===== SCALING (grow over a run; every count lives on the run's state) =====
	{
		id = "slow_cooker", name = "Slow Cooker", icon = "🍲", price = 7,
		description = "x0.025 more Mult for every round cleared this run (up to x2).",
		flavorText = "Good things take time, and this stew takes all night.",
		effect = function(_handResult, context)
			local rounds = context.roundsCleared or 0
			if rounds > 0 then
				return { multMultiplier = math.min(2, 1 + 0.025 * rounds) }
			end
			return nil
		end,
	},
	{
		id = "house_tab", name = "House Tab", icon = "📒", price = 8,
		description = "x0.08 more Mult for every Boss Round cleared this run.",
		flavorText = "Keeps a tidy list of every tough night survived.",
		effect = function(_handResult, context)
			local bosses = context.bossesCleared or 0
			if bosses > 0 then
				return { multMultiplier = 1 + 0.08 * bosses }
			end
			return nil
		end,
	},
	{
		id = "regulars_chair", name = "Regular's Chair", icon = "🪑", price = 6,
		description = "+1 Mult for every 6 hands played this run (up to +15).",
		flavorText = "The cushion has their exact shape by now.",
		effect = function(_handResult, context)
			local bonus = math.min(15, math.floor((context.handsPlayedTotal or 0) / 6))
			if bonus > 0 then
				return { mult = bonus }
			end
			return nil
		end,
	},
	{
		id = "cobweb_shelf", name = "Cobweb Shelf", icon = "🕸️", price = 5,
		description = "+1 Mult for every 3 Discards used this run (up to +15).",
		flavorText = "Nobody dusts it. Somehow it keeps getting better.",
		effect = function(_handResult, context)
			local bonus = math.min(15, math.floor((context.discardsUsedTotal or 0) / 3))
			if bonus > 0 then
				return { mult = bonus }
			end
			return nil
		end,
	},
	{
		id = "tasting_menu", name = "Tasting Menu", icon = "📜", price = 7,
		description = "+1 Mult for every different poker hand type played this run (up to +9).",
		flavorText = "Wants to try a little bit of everything.",
		effect = function(_handResult, context)
			local types = 0
			for _ in pairs(context.handStatsBefore or {}) do
				types = types + 1
			end
			if types > 0 then
				return { mult = types }
			end
			return nil
		end,
	},
	{
		id = "estate_sale", name = "Estate Sale", icon = "🏷️", price = 6,
		description = "+2 Mult for every Patron you've sold this run (up to +20).",
		flavorText = "Always knows someone who wants your old things.",
		effect = function(_handResult, context)
			local sold = context.patronsSold or 0
			if sold > 0 then
				return { mult = math.min(20, 2 * sold) }
			end
			return nil
		end,
	},
	{
		id = "pair_bonds", name = "Pair Bonds", icon = "💞", price = 6,
		description = "+1 Mult for every 4 Pairs or Two Pairs played this run (up to +15).",
		flavorText = "Introduces everyone to everyone else.",
		effect = function(_handResult, context)
			local stats = context.handStatsBefore or {}
			local bonus = math.min(15, math.floor(((stats["Pair"] or 0) + (stats["Two Pair"] or 0)) / 4))
			if bonus > 0 then
				return { mult = bonus }
			end
			return nil
		end,
	},
	{
		id = "veterans_table", name = "Veteran's Table", icon = "🎖️", price = 8,
		description = "+8 Chips for each Night you've reached after Night 1.",
		flavorText = "Has a story from every night the tavern stayed open.",
		effect = function(_handResult, context)
			local nights = (context.night or 1) - 1
			if nights > 0 then
				return { chips = 8 * nights }
			end
			return nil
		end,
	},
}

-- ===== Biome Patrons (WorldMap branch-end rewards, Engine/BiomeRewards.lua) =====
-- One per biome. Deliberately mild or situational (price 5, no scaling) so no road is stronger: they sit in
-- the shop pool like every other Patron, and the biome reward adds them to the Collection.
local function countScoring(handResult, test)
	local n = 0
	for _, card in ipairs(handResult.scoringCards) do
		if test(card) then
			n = n + 1
		end
	end
	return n
end

local biomePatrons = {
	{
		id = "meadow_bee", name = "Meadow Bee", icon = "🐝", price = 5, rarity = "uncommon", biome = "meadow",
		description = "+6 Chips for each scoring card ranked 6 or lower.",
		flavorText = "Hums over the small cards and never forgets a flower.",
		effect = function(handResult, _context)
			local n = countScoring(handResult, function(card) return card.rank <= 6 end)
			if n > 0 then
				return { chips = 6 * n }
			end
			return nil
		end,
	},
	{
		id = "ferry_captain", name = "Ferry Captain", icon = "⛴️", price = 5, rarity = "uncommon", biome = "river",
		description = "+10 Chips when you play exactly 3 cards.",
		flavorText = "Three passengers per trip, and not one more.",
		effect = function(_handResult, context)
			if #(context.allPlayedCards or {}) == 3 then
				return { chips = 10 }
			end
			return nil
		end,
	},
	{
		id = "summit_guide", name = "Summit Guide", icon = "🧗", price = 5, rarity = "uncommon", biome = "peaks",
		description = "+2 Mult for each King or Ace among the scoring cards.",
		flavorText = "Only counts the tallest peaks on the trail.",
		effect = function(handResult, _context)
			local n = countScoring(handResult, function(card) return card.rank == 13 or card.rank == 14 end)
			if n > 0 then
				return { mult = 2 * n }
			end
			return nil
		end,
	},
	{
		id = "sand_merchant", name = "Sand Merchant", icon = "🐪", price = 5, rarity = "uncommon", biome = "desert",
		description = "Earn 1 Tip when your hand is a Flush.",
		flavorText = "Trades in warm spices and one very patient camel.",
		effect = function(handResult, _context)
			if handResult.name == "Flush" then
				return { tips = 1 }
			end
			return nil
		end,
	},
	{
		id = "marsh_gardener", name = "Marsh Gardener", icon = "🍄", price = 5, rarity = "uncommon", biome = "swamp",
		description = "+3 Mult if none of the scoring cards is a Heart or a Diamond.",
		flavorText = "Grows mushrooms only in the shadiest corners.",
		effect = function(handResult, _context)
			local red = countScoring(handResult, function(card)
				return Card.hasSuit(card, "Hearts") or Card.hasSuit(card, "Diamonds")
			end)
			if red == 0 and #handResult.scoringCards > 0 then
				return { mult = 3 }
			end
			return nil
		end,
	},
	{
		id = "lantern_lighter", name = "Lantern Lighter", icon = "🏮", price = 5, rarity = "uncommon", biome = "snow",
		description = "+4 Chips for each card still in your hand when you play.",
		flavorText = "Keeps a lantern lit for every card left in the cold.",
		effect = function(_handResult, context)
			local held = #(context.heldCards or {})
			if held > 0 then
				return { chips = 4 * held }
			end
			return nil
		end,
	},
	{
		id = "lighthouse_keeper", name = "Lighthouse Keeper", icon = "🗼", price = 5, rarity = "uncommon", biome = "coast",
		description = "+2 Mult for each Discard you still have.",
		flavorText = "Saves a little light for later, just in case.",
		effect = function(_handResult, context)
			local d = context.discardsRemaining or 0
			if d > 0 then
				return { mult = 2 * d }
			end
			return nil
		end,
	},
}
for _, patron in ipairs(biomePatrons) do
	table.insert(Patrons.Definitions, patron)
end

-- ===== More Patrons: suit, pair, straight, economy, scaling and rule benders (24). Gated in Engine/Unlocks.lua. =====
-- Rule benders use data fields read by RunState: handSizeDelta, discardsDelta, handsDelta, rerollDelta (see Patrons.sum).
local depthPatrons = {
	{
		id = "flush_fan", name = "Flush Fan", icon = "🪭", price = 6,
		description = "+30 Chips if the hand is a Flush or Straight Flush.",
		flavorText = "Fans the whole table in one color.",
		effect = function(handResult, context)
			return (handResult.name == "Flush" or handResult.name == "Straight Flush") and { chips = 30 } or nil
		end,
	},
	{
		id = "suit_sampler", name = "Suit Sampler", icon = "🍬", price = 6,
		description = "+2 Mult for each different suit among the scoring cards.",
		flavorText = "Tries one of every flavor.",
		effect = function(handResult, context)
			local seen, n = {}, 0
			for _, card in ipairs(handResult.scoringCards) do
				if not seen[card.suit] then seen[card.suit] = true; n = n + 1 end
			end
			return n > 0 and { mult = 2 * n } or nil
		end,
	},
	{
		id = "warm_hearth", name = "Warm Hearth", icon = "🔥", price = 6,
		description = "+2 Mult for each Heart held in your hand, not played.",
		flavorText = "Keeps the best seats by the fire.",
		effect = function(handResult, context)
			local n = 0
			for _, card in ipairs(context.heldCards or {}) do
				if Card.hasSuit(card, "Hearts") then n = n + 1 end
			end
			return n > 0 and { mult = 2 * n } or nil
		end,
	},
	{
		id = "color_matcher", name = "Color Matcher", icon = "🎨", price = 5,
		description = "+20 Chips if all scoring cards are red or all are black.",
		flavorText = "Never mixes the red paint with the black.",
		effect = function(handResult, context)
			local red, black = 0, 0
			for _, card in ipairs(handResult.scoringCards) do
				if card.suit == "Hearts" or card.suit == "Diamonds" then red = red + 1 else black = black + 1 end
			end
			return ((red > 0) ~= (black > 0)) and { chips = 20 } or nil
		end,
	},
	{
		id = "full_suit_feast", name = "Full Suit Feast", icon = "🍛", price = 8,
		description = "x1.5 Mult if 4 or more scoring cards share one suit.",
		flavorText = "Orders everything in a single color.",
		effect = function(handResult, context)
			local counts, best = {}, 0
			for _, card in ipairs(handResult.scoringCards) do
				counts[card.suit] = (counts[card.suit] or 0) + 1
				best = math.max(best, counts[card.suit])
			end
			return best >= 4 and { multMultiplier = 1.5 } or nil
		end,
	},
	{
		id = "twin_spoons", name = "Twin Spoons", icon = "🥄", price = 5,
		description = "+6 Mult if the hand is a Two Pair.",
		flavorText = "Two of everything, always.",
		effect = function(handResult, context)
			return handResult.name == "Two Pair" and { mult = 6 } or nil
		end,
	},
	{
		id = "triple_treat", name = "Triple Treat", icon = "🍰", price = 6,
		description = "+12 Mult if the hand is a Three of a Kind.",
		flavorText = "Three slices, one happy guest.",
		effect = function(handResult, context)
			return handResult.name == "Three of a Kind" and { mult = 12 } or nil
		end,
	},
	{
		id = "foursome_table", name = "Foursome Table", icon = "🎴", price = 8,
		description = "x2 Mult if the hand is a Four of a Kind.",
		flavorText = "The corner table seats four, always.",
		effect = function(handResult, context)
			return handResult.name == "Four of a Kind" and { multMultiplier = 2 } or nil
		end,
	},
	{
		id = "kitchen_duo", name = "Kitchen Duo", icon = "👩‍🍳", price = 6,
		description = "+40 Chips if the hand is a Full House.",
		flavorText = "One chops, one stirs, nobody argues.",
		effect = function(handResult, context)
			return handResult.name == "Full House" and { chips = 40 } or nil
		end,
	},
	{
		id = "pair_parade", name = "Pair Parade", icon = "🎺", price = 6,
		description = "+2 Mult for each scoring card in a Pair or better.",
		flavorText = "Marches in twos, trumpets and all.",
		effect = function(handResult, context)
			if (handResult.name == "High Card" or handResult.name == "Straight" or handResult.name == "Flush" or handResult.name == "Straight Flush") then return nil end
			return { mult = 2 * #handResult.scoringCards }
		end,
	},
	{
		id = "stair_climber", name = "Stair Climber", icon = "🪜", price = 6,
		description = "+30 Chips if the hand is a Straight or Straight Flush.",
		flavorText = "Takes the stairs, one rank at a time.",
		effect = function(handResult, context)
			return (handResult.name == "Straight" or handResult.name == "Straight Flush") and { chips = 30 } or nil
		end,
	},
	{
		id = "long_road", name = "Long Road", icon = "🛤️", price = 6,
		description = "+8 Mult if the hand is a Straight.",
		flavorText = "Has walked every road in order.",
		effect = function(handResult, context)
			return handResult.name == "Straight" and { mult = 8 } or nil
		end,
	},
	{
		id = "ladder_builder", name = "Ladder Builder", icon = "🏗️", price = 6,
		description = "+2 Mult for each scoring card in a Straight.",
		flavorText = "Adds one more rung every night.",
		effect = function(handResult, context)
			if handResult.name ~= "Straight" and handResult.name ~= "Straight Flush" then return nil end
			return { mult = 2 * #handResult.scoringCards }
		end,
	},
	{
		id = "royal_road", name = "Royal Road", icon = "🏰", price = 8,
		description = "x1.5 Mult if a Straight has an Ace.",
		flavorText = "Rolls out the red carpet for the high card.",
		effect = function(handResult, context)
			if handResult.name ~= "Straight" and handResult.name ~= "Straight Flush" then return nil end
			for _, card in ipairs(handResult.scoringCards) do
				if card.rank == 14 then return { multMultiplier = 1.5 } end
			end
			return nil
		end,
	},
	{
		id = "savings_club", name = "Savings Club", icon = "🏦", price = 7,
		description = "After a round win, earn 1 Tip per 4 held (up to 4).",
		flavorText = "Everyone chips in a little.",
		effect = function() return nil end,
		onRoundWin = function(state)
			state.tips = state.tips + math.min(4, math.floor(state.tips / 4))
		end,
	},
	{
		id = "bargain_hunter", name = "Bargain Hunter", icon = "🔍", price = 6,
		description = "Shop rerolls cost 1 less (minimum 1).",
		flavorText = "Can smell a good deal from the doorway.",
		rerollDelta = -1,
		effect = function() return nil end,
	},
	{
		id = "quick_service", name = "Quick Service", icon = "⚡", price = 6,
		description = "Earn 5 Tips when you win a round using only 1 Hand.",
		flavorText = "Plates are out before you finish asking.",
		effect = function() return nil end,
		onRoundWin = function(state)
			if (state.roundStartHands or 0) - (state.handsRemaining or 0) == 1 then state.tips = state.tips + 5 end
		end,
	},
	{
		id = "lucky_penny_jar", name = "Lucky Penny Jar", icon = "🍯", price = 6,
		description = "Earn 1 Tip each time you play a Pair or better.",
		flavorText = "Every pair earns a clink.",
		effect = function(handResult, context)
			if (handResult.name == "High Card" or handResult.name == "Straight" or handResult.name == "Flush" or handResult.name == "Straight Flush") then return nil end
			return { tips = 1 }
		end,
	},
	{
		id = "rising_dough", name = "Rising Dough", icon = "🥖", price = 6,
		description = "+1 Mult for every round cleared this run (up to +12).",
		flavorText = "Gets bigger the longer you wait.",
		effect = function(handResult, context)
			local bonus = math.min(12, context.roundsCleared or 0)
			return bonus > 0 and { mult = bonus } or nil
		end,
	},
	{
		id = "stack_of_plates", name = "Stack of Plates", icon = "🥞", price = 6,
		description = "+2 Chips for every hand played this run (up to +100).",
		flavorText = "One more plate on the pile each time.",
		effect = function(handResult, context)
			local bonus = math.min(100, 2 * (context.handsPlayedTotal or 0))
			return bonus > 0 and { chips = bonus } or nil
		end,
	},
	{
		id = "bread_starter", name = "Bread Starter", icon = "🫓", price = 8,
		description = "x0.02 more Mult for every hand played this run (up to x2).",
		flavorText = "Fed every night since the first.",
		effect = function(handResult, context)
			local hands = context.handsPlayedTotal or 0
			return hands > 0 and { multMultiplier = 1 + math.min(1, 0.02 * hands) } or nil
		end,
	},
	{
		id = "extra_chair", name = "Extra Chair", icon = "💺", price = 7,
		description = "Draw 1 more card at the start of each round.",
		flavorText = "Always pulls up one more seat.",
		handSizeDelta = 1,
		effect = function() return nil end,
	},
	{
		id = "second_helpings", name = "Second Helpings", icon = "🥣", price = 7,
		description = "+1 Discard each round.",
		flavorText = "Never says no to a refill.",
		discardsDelta = 1,
		effect = function() return nil end,
	},
	{
		id = "overtime", name = "Overtime", icon = "🕰️", price = 8,
		description = "+1 Hand each round, but draw 1 fewer card.",
		flavorText = "Works late, travels light.",
		handsDelta = 1, handSizeDelta = -1,
		effect = function() return nil end,
	},
}
for _, patron in ipairs(depthPatrons) do
	table.insert(Patrons.Definitions, patron)
end

-- SYNERGY TAGS (Engine/Synergy.lua): 1 to 3 build tags per Patron, shown as small glowing tags in the Counter and pack
-- picks when a Patron fits what the player owns. EDIT ME: this table is the one place to retag a Patron.
-- flush (suits), pairs (pairs, trips, quads, full house), straight, economy (Tips, rerolls), scaling (grows over the run),
-- rulebender (changes discards, hands or hand size), ranks (specific ranks or face cards), flat (steady bonuses).
local PATRON_TAGS = {
	the_regular = { "flat" }, lucky_dice = { "pairs" }, suit_yourself = { "flush" }, curtain_call = { "flat" }, the_bard = { "flat" },
	regulars_round = { "pairs" }, threes_company = { "pairs" }, all_hands_in = { "pairs" }, straight_shooter = { "straight" },
	all_matching = { "flush" }, small_plate = { "flat" }, big_portions = { "pairs" }, tab_regulars = { "economy" },
	house_favorite = { "ranks" }, repeat_customer = { "flat" }, the_understudy = { "flat" }, second_opinion = { "flat" },
	tip_jar = { "economy" }, penny_pincher = { "economy" }, sparkling_service = { "flush" }, rowdy_bunch = { "flush" },
	sharp_dressed = { "flush" }, double_down = { "pairs" }, house_special = { "pairs" }, ace_of_the_house = { "ranks" },
	vip_table = { "ranks" }, early_bird = { "flat" }, discard_special = { "flat" }, the_apprentice = { "flat" },
	big_spender = { "economy" }, nest_egg = { "economy" }, jack_of_all_trades = { "ranks" }, queens_gambit = { "ranks" },
	spare_change = { "economy" }, full_house_crowd = { "scaling" }, fair_share = { "flat" }, efficient_service = { "flat" },
	perfect_ten = { "ranks" }, night_owl = { "scaling" }, steady_hand = { "flat" }, rainy_day_fund = { "economy" },
	boss_bane = { "economy" }, slow_cooker = { "scaling" }, house_tab = { "scaling" }, regulars_chair = { "scaling" },
	cobweb_shelf = { "scaling" }, tasting_menu = { "scaling" }, estate_sale = { "scaling" }, pair_bonds = { "scaling", "pairs" },
	veterans_table = { "scaling" }, meadow_bee = { "ranks" }, ferry_captain = { "flat" }, summit_guide = { "ranks" },
	sand_merchant = { "economy", "flush" }, marsh_gardener = { "flush" }, lantern_lighter = { "flat" }, lighthouse_keeper = { "flat" },
	flush_fan = { "flush" }, suit_sampler = { "flush" }, warm_hearth = { "flush" }, color_matcher = { "flush" },
	full_suit_feast = { "flush" }, twin_spoons = { "pairs" }, triple_treat = { "pairs" }, foursome_table = { "pairs" },
	kitchen_duo = { "pairs" }, pair_parade = { "pairs" }, stair_climber = { "straight" }, long_road = { "straight" },
	ladder_builder = { "straight" }, royal_road = { "straight" }, savings_club = { "economy" }, bargain_hunter = { "economy" },
	quick_service = { "economy" }, lucky_penny_jar = { "economy", "pairs" }, rising_dough = { "scaling" }, stack_of_plates = { "scaling" },
	bread_starter = { "scaling" }, extra_chair = { "rulebender" }, second_helpings = { "rulebender" }, overtime = { "rulebender" },
}
-- BOSS COUNTERPLAY: which boss rule tags this Patron truly helps against (Engine/BossCounters.lua). EDIT ME.
local PATRON_COUNTERS = {
	ace_of_the_house = { "faceDebuff" }, big_portions = { "weakenMult", "handBan" }, color_matcher = { "suitDebuff" },
	curtain_call = { "fewerHands", "slowStart" }, early_bird = { "slowStart" }, extra_chair = { "lowHandSize", "cardToss" },
	fair_share = { "weakenMult" }, ferry_captain = { "cardCount" }, flush_fan = { "weakenMult" },
	foursome_table = { "fewerHands", "targetBoost" }, full_suit_feast = { "targetBoost" }, house_special = { "targetBoost" },
	kitchen_duo = { "weakenMult" }, ladder_builder = { "cardCount" }, lantern_lighter = { "cardToss" },
	lucky_dice = { "weakenMult", "handBan" }, marsh_gardener = { "suitDebuff" }, meadow_bee = { "faceDebuff" },
	overtime = { "fewerHands", "slowStart", "cardToss" }, pair_parade = { "handBan" }, perfect_ten = { "faceDebuff", "oddRank" },
	quick_service = { "tipsDrain" }, regulars_round = { "weakenChips", "handBan", "patronLimit" }, royal_road = { "targetBoost" },
	savings_club = { "tipsDrain" }, second_helpings = { "lowHandSize", "fewerDiscards" }, second_opinion = { "patronLimit" },
	small_plate = { "cardCount" }, steady_hand = { "cardCount" }, suit_sampler = { "suitDebuff" },
	tab_regulars = { "tipsDrain" }, tasting_menu = { "noRepeat" }, the_regular = { "weakenChips", "patronLimit" },
	the_understudy = { "patronLimit" }, threes_company = { "weakenChips" }, tip_jar = { "tipsDrain" },
	twin_spoons = { "handBan" },
}
for _, patron in ipairs(Patrons.Definitions) do
	patron.counters = PATRON_COUNTERS[patron.id]
end
Patrons.TagIds = { "flush", "pairs", "straight", "economy", "scaling", "rulebender", "ranks", "flat" }
for _, patron in ipairs(Patrons.Definitions) do
	patron.tags = PATRON_TAGS[patron.id]
end

-- Sum of a numeric rule field (handSizeDelta, discardsDelta, handsDelta, rerollDelta) over the owned Patrons.
function Patrons.sum(owned, field)
	local total = 0
	for _, patron in ipairs(owned or {}) do
		total = total + (patron[field] or 0)
	end
	return total
end

function Patrons.getById(id)
	for _, patron in ipairs(Patrons.Definitions) do
		if patron.id == id then
			return patron
		end
	end
	return nil
end

return Patrons
