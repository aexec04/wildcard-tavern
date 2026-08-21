--[[
	Tags.lua
	Our "skip a round" reward catalog. Where RunState.nightBossModifier
	(see BossRounds.lua) reveals what you're walking toward if you PLAY
	through the Night, this reveals what you'd get for SKIPPING the round
	you're currently on instead -- distinct, previewed-in-advance effects
	(some Tips, a free Patron, a shop discount), not just a flat number.

	A fresh Tag is picked for whichever round is currently skippable every
	time RunState.startRound runs a non-Boss round (see
	state.currentRoundSkipTag) -- so it's always visible on the Round
	Select screen (Client/RoundSelect.lua) before you decide.

	Tag shape:
		{ id, name, icon, description,
		  apply = function(state, ctx) -> result }
	`apply` mutates `state` directly (granting the actual reward) and
	returns a small result table describing what happened, so the server/
	client can show a confirmation that says the RIGHT thing (a Tips
	number, a new Patron's name, a discount amount) instead of always
	assuming "+X Tips":
		{ kind = "tips", amount = number, fallback = boolean? }
		{ kind = "patron", patron = <Patrons.Definitions entry> }
		{ kind = "discount", amount = number }

	`ctx` (all optional, RunState.skipRound fills these in):
		rng             -- same convention as Deck.shuffle: rng(n) -> [1, n]
		patronSlotLimit -- RunState.patronSlotLimit(state) at the moment of
		                   skipping -- passed in rather than computed here
		                   so this file never needs to require RunState
		                   (which itself will require this file -- a cycle).

	Deliberately NOT required by/requiring RunState.lua for that reason;
	only requires Patrons.lua (a leaf module, no cycle risk).
]]

local Patrons = require(script.Parent.Patrons)

local Tags = {}

-- Deliberately less than a normal round win (config.tipsPerRoundWin,
-- doubled for a Boss Round -- see RunState.playHand): skipping also means
-- missing that round's shop visit, so it has to stay worse than actually
-- playing for the choice to be a real tradeoff, not a strictly-better
-- shortcut. Scales gently by Night, capped below tipsPerRoundWin so it can
-- never catch up to a real win no matter how long the run goes.
local function tipJarAmount(state)
	local uncapped = math.ceil(state.config.tipsPerRoundWin / 2) + (state.night - 1)
	return math.min(uncapped, state.config.tipsPerRoundWin - 1)
end

local function unownedPatrons(state)
	local owned = {}
	for _, patron in ipairs(state.ownedPatrons) do
		owned[patron.id] = true
	end
	local available = {}
	for _, patron in ipairs(Patrons.Definitions) do
		if not owned[patron.id] then
			table.insert(available, patron)
		end
	end
	return available
end

Tags.Definitions = {
	{
		id = "tip_jar",
		name = "Tip Jar Tag",
		icon = "💰",
		description = "Instant Tips, right now.",
		apply = function(state)
			local amount = tipJarAmount(state)
			state.tips = state.tips + amount
			return { kind = "tips", amount = amount }
		end,
	},
	{
		id = "on_the_house",
		name = "On the House Tag",
		icon = "🎁",
		description = "A random Patron joins your table for free -- if there's room and one's still available.",
		apply = function(state, ctx)
			ctx = ctx or {}
			local rng = ctx.rng or state.rng or math.random
			-- Conservative fallback if the caller didn't pass a slot limit:
			-- treat the table as already full rather than risk granting a
			-- Patron past the real cap (see the file header for why this
			-- can't just call RunState.patronSlotLimit directly).
			local slotLimit = ctx.patronSlotLimit or #state.ownedPatrons
			local available = unownedPatrons(state)
			if #state.ownedPatrons < slotLimit and #available > 0 then
				local patron = table.remove(available, rng(#available))
				table.insert(state.ownedPatrons, patron)
				return { kind = "patron", patron = patron }
			end
			-- No room, or every Patron already owned -- a Tag should never
			-- feel like a dead draw, so fall back to the Tip Jar amount.
			local amount = tipJarAmount(state)
			state.tips = state.tips + amount
			return { kind = "tips", amount = amount, fallback = true }
		end,
	},
	{
		id = "happy_hour",
		name = "Happy Hour Tag",
		icon = "🥤",
		description = "Your NEXT shop visit: Patron and Pack prices are 3 Tips cheaper (minimum 1).",
		apply = function(state)
			local amount = 3
			state.nextShopDiscount = (state.nextShopDiscount or 0) + amount
			return { kind = "discount", amount = amount }
		end,
	},
}

function Tags.getById(id)
	for _, tag in ipairs(Tags.Definitions) do
		if tag.id == id then
			return tag
		end
	end
	return nil
end

-- rng follows the same convention as Deck.shuffle: rng(n) returns an
-- integer in [1, n]. Defaults to math.random so real games are randomized;
-- tests can pass a deterministic function instead.
function Tags.pick(rng)
	rng = rng or math.random
	local index = rng(#Tags.Definitions)
	return Tags.Definitions[index]
end

return Tags
