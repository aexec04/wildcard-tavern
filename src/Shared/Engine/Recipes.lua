--[[
	Recipes.lua
	Our equivalent of one-shot "consumable" cards. Split into three kitchen-
	themed categories (see the "Feature Expansion Plan" project doc for the
	full naming rationale):

		House Recipes  -- modify the actual cards in your hand (Garnishes/
		                  Specials/rank/suit changes, deck trims, etc.)
		Menu Recipes    -- permanently level up ONE poker hand type (raises
		                  its Scoring.HandBase numbers via Scoring.HandLevelGrowth)
		Secret Recipes  -- rarer, higher-risk/higher-reward effects

	ENGINE-ONLY IN THIS PASS: these are fully implemented and unit-tested,
	but nothing in the shop/UI grants or lets a player "use" one yet --
	that's the next pass (see the design doc's Phase 1b). RunState already
	exposes RunState.useHouseRecipe/useMenuRecipe/useSecretRecipe below so
	the wiring, once it exists client-side, is a thin UI layer on top of
	logic that's already written and tested.

	Every `apply` function takes (state, opts) and returns true/message on
	success or false/message on failure. opts fields vary by recipe (see
	each one's comment); cardIndices are 1-based indices into state.hand,
	same convention as RunState.playHand/discard.
]]

local Card = require(script.Parent.Card)
local Scoring = require(script.Parent.Scoring)

local Recipes = {}

local function cardsAt(state, indices)
	local cards = {}
	for _, i in ipairs(indices or {}) do
		local card = state.hand[i]
		if not card then
			return nil
		end
		table.insert(cards, card)
	end
	return cards
end

local function randomChoice(list, rng)
	rng = rng or math.random
	return list[rng(#list)]
end

-- ===== House Recipes (card-modifying) =====

Recipes.HouseRecipes = {
	{
		id = "sugar_rush", name = "Sugar Rush", icon = "🍬", price = 3,
		description = "Adds a Sweet Garnish (+30 Chips) to up to 2 selected cards.",
		apply = function(state, opts)
			local cards = cardsAt(state, opts and opts.cardIndices)
			if not cards or #cards < 1 or #cards > 2 then
				return false, "Select 1-2 cards"
			end
			for _, card in ipairs(cards) do
				card.garnish = "sweet"
			end
			return true, "Sweetened up!"
		end,
	},
	{
		id = "spice_rack", name = "Spice Rack", icon = "🌶️", price = 3,
		description = "Adds a Zesty Garnish (+4 Mult) to up to 2 selected cards.",
		apply = function(state, opts)
			local cards = cardsAt(state, opts and opts.cardIndices)
			if not cards or #cards < 1 or #cards > 2 then
				return false, "Select 1-2 cards"
			end
			for _, card in ipairs(cards) do
				card.garnish = "zesty"
			end
			return true, "Zested up!"
		end,
	},
	{
		id = "house_blend_order", name = "House Blend Order", icon = "🍹", price = 4,
		description = "Adds House Blend (counts as every suit) to 1 selected card.",
		apply = function(state, opts)
			local cards = cardsAt(state, opts and opts.cardIndices)
			if not cards or #cards ~= 1 then
				return false, "Select exactly 1 card"
			end
			cards[1].garnish = "houseBlend"
			return true, "Now counts as every suit."
		end,
	},
	{
		id = "cast_iron_order", name = "Cast Iron Order", icon = "🍳", price = 4,
		description = "Adds an Iron Garnish (x1.5 Mult while held) to 1 selected card.",
		apply = function(state, opts)
			local cards = cardsAt(state, opts and opts.cardIndices)
			if not cards or #cards ~= 1 then
				return false, "Select exactly 1 card"
			end
			cards[1].garnish = "iron"
			return true, "Cast in iron."
		end,
	},
	{
		id = "candy_order", name = "Candy Order", icon = "🍭", price = 4,
		description = "Adds a Brittle Garnish (x2 Mult, can shatter) to 1 selected card.",
		apply = function(state, opts)
			local cards = cardsAt(state, opts and opts.cardIndices)
			if not cards or #cards ~= 1 then
				return false, "Select exactly 1 card"
			end
			cards[1].garnish = "brittle"
			return true, "Sweet, but fragile."
		end,
	},
	{
		id = "golden_hour", name = "Golden Hour", icon = "🌟", price = 5,
		description = "Adds a Golden Garnish (earn 3 Tips if held at round end) to 1 selected card.",
		apply = function(state, opts)
			local cards = cardsAt(state, opts and opts.cardIndices)
			if not cards or #cards ~= 1 then
				return false, "Select exactly 1 card"
			end
			cards[1].garnish = "golden"
			return true, "Feeling lucky."
		end,
	},
	{
		id = "house_token_order", name = "House Token Order", icon = "🪙", price = 4,
		description = "Turns 1 selected card into a Bar Token (+50 Chips).",
		apply = function(state, opts)
			local cards = cardsAt(state, opts and opts.cardIndices)
			if not cards or #cards ~= 1 then
				return false, "Select exactly 1 card"
			end
			cards[1].garnish = "barToken"
			return true, "Traded in for a token."
		end,
	},
	{
		id = "upsell", name = "Upsell", icon = "⬆️", price = 3,
		description = "Raises the rank of up to 2 selected cards by 1 (caps at Ace).",
		apply = function(state, opts)
			local cards = cardsAt(state, opts and opts.cardIndices)
			if not cards or #cards < 1 or #cards > 2 then
				return false, "Select 1-2 cards"
			end
			for _, card in ipairs(cards) do
				card.rank = math.min(14, card.rank + 1)
			end
			return true, "Upgraded!"
		end,
	},
	{
		id = "eighty_six_it", name = "86 It", icon = "🗑️", price = 3,
		description = "Removes up to 2 selected cards from your deck for good.",
		apply = function(state, opts)
			local indices = (opts and opts.cardIndices) or {}
			if #indices < 1 or #indices > 2 then
				return false, "Select 1-2 cards"
			end
			-- Remove highest index first so earlier indices stay valid.
			local sorted = {}
			for _, i in ipairs(indices) do
				table.insert(sorted, i)
			end
			table.sort(sorted, function(a, b) return a > b end)
			for _, i in ipairs(sorted) do
				if not state.hand[i] then
					return false, "Invalid selection"
				end
				table.remove(state.hand, i)
			end
			return true, "86'd."
		end,
	},
	{
		id = "copy_the_order", name = "Copy the Order", icon = "📋", price = 6,
		description = "Select 2 cards -- the first becomes a copy of the second.",
		apply = function(state, opts)
			local indices = (opts and opts.cardIndices) or {}
			if #indices ~= 2 then
				return false, "Select exactly 2 cards"
			end
			local from = state.hand[indices[1]]
			local to = state.hand[indices[2]]
			if not from or not to then
				return false, "Invalid selection"
			end
			from.rank, from.suit, from.garnish, from.special, from.stamp =
				to.rank, to.suit, to.garnish, to.special, to.stamp
			return true, "Order copied."
		end,
	},
	{
		id = "suit_swap", name = "Suit Swap", icon = "🔄", price = 4,
		description = "Converts up to 3 selected cards to a suit of your choice.",
		apply = function(state, opts)
			local cards = cardsAt(state, opts and opts.cardIndices)
			local suit = opts and opts.suit
			if not cards or #cards < 1 or #cards > 3 then
				return false, "Select 1-3 cards"
			end
			if not table.find(Card.Suits, suit) then
				return false, "Pick a valid suit"
			end
			for _, card in ipairs(cards) do
				card.suit = suit
			end
			return true, "Suits swapped."
		end,
	},
	{
		id = "happy_hour", name = "Happy Hour", icon = "🎉", price = 5,
		description = "Doubles your current Tips (capped at +20).",
		apply = function(state)
			local gain = math.min(state.tips, 20)
			state.tips = state.tips + gain
			return true, string.format("+%d Tips!", gain)
		end,
	},
	{
		id = "tabs_on_the_house", name = "Tab's On the House", icon = "🧾", price = 5,
		description = "Earn Tips equal to the total sell value of your Patrons (capped at 50).",
		apply = function(state)
			local total = 0
			for _, patron in ipairs(state.ownedPatrons) do
				total = total + math.floor(patron.price / 2)
			end
			total = math.min(total, 50)
			state.tips = state.tips + total
			return true, string.format("+%d Tips!", total)
		end,
	},
	{
		id = "new_regular", name = "New Regular", icon = "🙋", price = 8,
		description = "A random Patron joins your table for free (ignores slot price).",
		apply = function(state, opts, deps)
			local Patrons = deps and deps.Patrons
			if not Patrons then
				return false, "Unavailable"
			end
			if deps.patronSlotLimit and #state.ownedPatrons >= deps.patronSlotLimit then
				return false, "Your table is full -- sell a Patron to make room"
			end
			local rng = (opts and opts.rng) or math.random
			local available = {}
			for _, patron in ipairs(Patrons.Definitions) do
				local owned = false
				for _, o in ipairs(state.ownedPatrons) do
					if o.id == patron.id then
						owned = true
						break
					end
				end
				if not owned then
					table.insert(available, patron)
				end
			end
			if #available == 0 then
				return false, "Every Patron is already at your table"
			end
			local picked = randomChoice(available, rng)
			table.insert(state.ownedPatrons, picked)
			return true, picked.name .. " joins your table."
		end,
	},
	{
		id = "second_helping", name = "Second Helping", icon = "🍽️", price = 4,
		description = "Creates a copy of the last House or Menu Recipe you used.",
		apply = function(state, opts, deps)
			if not state.lastRecipeUsedId then
				return false, "Nothing to repeat yet"
			end
			table.insert(state.houseRecipeInventory, state.lastRecipeUsedId)
			return true, "Made a second helping."
		end,
	},
}

-- ===== Menu Recipes (permanently level up a hand type) =====
-- One per Scoring.HandBase entry, generated so it can never drift out of
-- sync with the hand list.
do
	local flavorNames = {
		["High Card"]       = { name = "Bar Snack Recipe", icon = "🥨" },
		["Pair"]             = { name = "Two-for-One Recipe", icon = "🍢" },
		["Two Pair"]          = { name = "Double Trouble Recipe", icon = "🍡" },
		["Three of a Kind"]   = { name = "Triple Threat Recipe", icon = "🍕" },
		["Straight"]          = { name = "Full Spread Recipe", icon = "🍱" },
		["Flush"]             = { name = "Matching Set Recipe", icon = "🍣" },
		["Full House"]        = { name = "Full House Recipe", icon = "🍲" },
		["Four of a Kind"]    = { name = "Fourth Round Recipe", icon = "🍗" },
		["Straight Flush"]    = { name = "Grand Tasting Recipe", icon = "🎂" },
	}

	Recipes.MenuRecipes = {}
	for handName in pairs(Scoring.HandBase) do
		local flavor = flavorNames[handName] or { name = handName .. " Recipe", icon = "📖" }
		table.insert(Recipes.MenuRecipes, {
			id = "level_" .. handName:gsub("%s+", "_"):lower(),
			name = flavor.name,
			icon = flavor.icon,
			handName = handName,
			price = 3,
			description = "Levels up " .. handName .. " (+chips/+mult every time you play one).",
			apply = function(state)
				state.handLevels[handName] = (state.handLevels[handName] or 0) + 1
				return true, handName .. " leveled up!"
			end,
		})
	end
end

-- ===== Secret Recipes (rarer, higher risk/reward) =====

Recipes.SecretRecipes = {
	{
		id = "mystery_guest", name = "Mystery Guest", icon = "🎭", price = 6,
		description = "Destroys 1 random card in hand, adds 3 random Garnished face cards.",
		apply = function(state, opts)
			local rng = (opts and opts.rng) or math.random
			if #state.hand > 0 then
				table.remove(state.hand, rng(#state.hand))
			end
			local garnishIds = { "sweet", "zesty", "houseBlend", "iron", "golden", "lucky" }
			for _ = 1, 3 do
				local rank = ({ 11, 12, 13 })[rng(3)]
				local suit = randomChoice(Card.Suits, rng)
				local card = Card.new(rank, suit, { garnish = randomChoice(garnishIds, rng) })
				table.insert(state.hand, card)
			end
			return true, "A mystery guest arrives."
		end,
	},
	{
		id = "last_round", name = "Last Round", icon = "🥃", price = 6,
		description = "Destroys 1 random card in hand, adds 2 random Garnished Aces.",
		apply = function(state, opts)
			local rng = (opts and opts.rng) or math.random
			if #state.hand > 0 then
				table.remove(state.hand, rng(#state.hand))
			end
			local garnishIds = { "sweet", "zesty", "houseBlend", "iron", "golden", "lucky" }
			for _ = 1, 2 do
				local suit = randomChoice(Card.Suits, rng)
				local card = Card.new(14, suit, { garnish = randomChoice(garnishIds, rng) })
				table.insert(state.hand, card)
			end
			return true, "Last round, on the house."
		end,
	},
	{
		id = "loyalty_punch", name = "Loyalty Punch", icon = "🟨", price = 4,
		description = "Adds a Gold Stamp (earn 3 Tips when it scores) to 1 selected card.",
		apply = function(state, opts)
			local cards = cardsAt(state, opts and opts.cardIndices)
			if not cards or #cards ~= 1 then
				return false, "Select exactly 1 card"
			end
			cards[1].stamp = "gold"
			return true, "Card punched."
		end,
	},
	{
		id = "chefs_special", name = "Chef's Special", icon = "👨‍🍳", price = 5,
		description = "Adds a random Special (Silver/Gold/Rainbow) to 1 selected card.",
		apply = function(state, opts)
			local cards = cardsAt(state, opts and opts.cardIndices)
			if not cards or #cards ~= 1 then
				return false, "Select exactly 1 card"
			end
			local rng = (opts and opts.rng) or math.random
			cards[1].special = randomChoice({ "silver", "gold", "rainbow" }, rng)
			return true, "Today's special, applied."
		end,
	},
	{
		id = "house_rules_order", name = "House Rules Order", icon = "🎲", price = 6,
		description = "Converts every card in your hand to a single random suit.",
		apply = function(state, opts)
			local rng = (opts and opts.rng) or math.random
			local suit = randomChoice(Card.Suits, rng)
			for _, card in ipairs(state.hand) do
				card.suit = suit
			end
			return true, "Everyone matches now."
		end,
	},
	{
		id = "clean_sweep", name = "Clean Sweep", icon = "🧹", price = 8,
		description = "A random Patron gets a Rainbow Special; every other Patron leaves (normal refund).",
		apply = function(state, opts)
			local rng = (opts and opts.rng) or math.random
			if #state.ownedPatrons == 0 then
				return false, "No Patrons to sweep"
			end
			local keepIndex = rng(#state.ownedPatrons)
			local kept = state.ownedPatrons[keepIndex]
			local refund = 0
			for i, patron in ipairs(state.ownedPatrons) do
				if i ~= keepIndex then
					refund = refund + math.floor(patron.price / 2)
				end
			end
			state.ownedPatrons = { kept }
			state.ownedPatronSpecials = state.ownedPatronSpecials or {}
			state.ownedPatronSpecials[kept.id] = "rainbow"
			state.tips = state.tips + refund
			return true, kept.name .. " gets the Rainbow treatment."
		end,
	},
	{
		id = "whole_menu_upgrade", name = "Whole Menu Upgrade", icon = "📈", price = 10,
		description = "Levels up EVERY poker hand type by 1.",
		apply = function(state)
			for handName in pairs(Scoring.HandBase) do
				state.handLevels[handName] = (state.handLevels[handName] or 0) + 1
			end
			return true, "The whole menu got better."
		end,
	},
}

function Recipes.getHouseRecipeById(id)
	for _, r in ipairs(Recipes.HouseRecipes) do
		if r.id == id then return r end
	end
	return nil
end

function Recipes.getMenuRecipeById(id)
	for _, r in ipairs(Recipes.MenuRecipes) do
		if r.id == id then return r end
	end
	return nil
end

function Recipes.getSecretRecipeById(id)
	for _, r in ipairs(Recipes.SecretRecipes) do
		if r.id == id then return r end
	end
	return nil
end

function Recipes.randomHouseRecipeId(rng)
	return randomChoice(Recipes.HouseRecipes, rng).id
end

function Recipes.randomMenuRecipeForHand(handName)
	for _, r in ipairs(Recipes.MenuRecipes) do
		if r.handName == handName then return r end
	end
	return nil
end

return Recipes
