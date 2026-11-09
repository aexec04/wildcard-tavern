--[[
	RunEvents.lua
	Random event cards between Nights (after a Boss Round, before Round Select), about half the time. Pure Lua,
	no Roblox APIs. Each event is data: a short story, and two or three options. EVERY event has a safe "Decline"
	that changes nothing. Events use the run's own rng (`state.rng`, or math.random), so they only ever run on
	normal runs; Daily, Weekly and Seed runs never roll one (boards stay fair).

	Fields per event: id, name, icon, text (one or two short lines), minNight, available(state) -> bool,
	options = { { id, label, detail, resolve(state, rng) -> ok, message } ... } with the last one the Decline.
	A resolve that returns false leaves the event open (for example "Not enough Tips").
	Art: painted cards come later (prompts.json `event_subjects`, ContentArt category `events`); the icon is the
	emoji fallback.
]]

local Patrons = require(script.Parent.Patrons)
local Recipes = require(script.Parent.Recipes)
local Unlocks = require(script.Parent.Unlocks)

local RunEvents = {}

RunEvents.CHANCE_PERCENT = 50

local function decline(message)
	return { id = "decline", label = "No, thanks", detail = "Nothing changes.", resolve = function()
		return true, message or "You wave them off politely."
	end }
end

local function recipeRoom(state)
	local held = #state.houseRecipeInventory + #state.menuRecipeInventory + #state.secretRecipeInventory
	return held < state.config.recipeSlotLimit
end

local function ownsPatron(state, id)
	for _, p in ipairs(state.ownedPatrons) do
		if p.id == id then return true end
	end
	return false
end

RunEvents.Definitions = {
	{
		id = "stranger_wager", name = "A Stranger's Wager", icon = "🎲", minNight = 2,
		text = "A cheerful stranger rolls a die across the table. \"Double or nothing?\"",
		available = function(state) return state.tips >= 4 end,
		options = {
			{ id = "bet", label = "Take the bet", detail = "Half the time win 8 Tips, otherwise lose 4.", resolve = function(state, rng)
				if rng(2) == 1 then
					state.tips = state.tips + 8
					return true, "You won the roll! +8 Tips."
				end
				local lost = math.min(4, state.tips)
				state.tips = state.tips - lost
				return true, "The die fell the other way. -" .. lost .. " Tips."
			end },
			decline("The stranger shrugs and rolls on."),
		},
	},
	{
		id = "hungry_cook", name = "The Hungry Cook", icon = "👨‍🍳", minNight = 2,
		text = "A traveling cook offers a spare recipe for a few Tips.",
		available = function(state) return recipeRoom(state) and state.tips >= 3 end,
		options = {
			{ id = "trade", label = "Pay 3 Tips", detail = "Get a random House Recipe.", resolve = function(state, rng)
				if state.tips < 3 then return false, "Not enough Tips." end
				if not recipeRoom(state) then return false, "Your recipe box is full." end
				local pool = Unlocks.filter(state, "recipe", Recipes.HouseRecipes)
				if #pool == 0 then pool = Recipes.HouseRecipes end
				local recipe = pool[rng(#pool)]
				state.tips = state.tips - 3
				table.insert(state.houseRecipeInventory, recipe.id)
				return true, recipe.name .. " goes into your recipe box. -3 Tips."
			end },
			decline("The cook tips their hat and walks on."),
		},
	},
	{
		id = "traveling_patron", name = "A Traveling Patron", icon = "🧳", minNight = 2,
		text = "A traveler offers to take one of your Patrons' seats and bring a friend.",
		available = function(state)
			for _, p in ipairs(state.ownedPatrons) do
				if state.ownedPatronSpecials[p.id] ~= "reserved" then return true end
			end
			return false
		end,
		options = {
			{ id = "swap", label = "Swap a Patron", detail = "One random Patron leaves, a random new one joins.", resolve = function(state, rng)
				-- a Patron carrying a Reserved Special holds an extra seat; it never leaves in a swap
				local candidates = {}
				for i, p in ipairs(state.ownedPatrons) do
					if state.ownedPatronSpecials[p.id] ~= "reserved" then candidates[#candidates + 1] = i end
				end
				if #candidates < 1 then return false, "You have no Patrons to swap." end
				local pool = {}
				for _, p in ipairs(Unlocks.filter(state, "patron", Patrons.Definitions)) do
					if not ownsPatron(state, p.id) then pool[#pool + 1] = p end
				end
				if #pool == 0 then return false, "No new Patron is around tonight." end
				local leaving = table.remove(state.ownedPatrons, candidates[rng(#candidates)])
				state.ownedPatronSpecials[leaving.id] = nil
				local joining = pool[rng(#pool)]
				table.insert(state.ownedPatrons, joining)
				return true, leaving.name .. " leaves. " .. joining.name .. " takes the seat."
			end },
			decline("The traveler tips their hat and moves on."),
		},
	},
	{
		id = "kind_donation", name = "A Kind Donation", icon = "💝", minNight = 2,
		text = "The village sends a basket of thanks for hosting such lively Nights.",
		available = function() return true end,
		options = {
			{ id = "accept", label = "Accept the basket", detail = "Gain 5 Tips.", resolve = function(state)
				state.tips = state.tips + 5
				return true, "The basket holds a pouch of Tips. +5 Tips."
			end },
			decline("You ask them to keep it for the next guest."),
		},
	},
	{
		id = "lantern_stall", name = "The Lantern Stall", icon = "🏮", minNight = 2,
		text = "A stall sells bright lanterns so you can see your cards better tonight.",
		available = function(state) return state.tips >= 4 end,
		options = {
			{ id = "buy", label = "Pay 4 Tips", detail = "+1 Hand in every round of this Night.", resolve = function(state)
				if state.tips < 4 then return false, "Not enough Tips." end
				state.tips = state.tips - 4
				state.bonusHandsNight = state.night
				state.handsRemaining = state.handsRemaining + 1 -- the round already dealt
				state.roundStartHands = (state.roundStartHands or state.handsRemaining - 1) + 1
				return true, "Bright light all Night. +1 Hand each round. -4 Tips."
			end },
			decline("You nod to the seller and walk on."),
		},
	},
}

function RunEvents.getById(id)
	for _, e in ipairs(RunEvents.Definitions) do
		if e.id == id then return e end
	end
	return nil
end

-- Which events could show for this run right now.
function RunEvents.availableFor(state)
	local list = {}
	for _, e in ipairs(RunEvents.Definitions) do
		if state.night >= (e.minNight or 1) and e.available(state) then
			list[#list + 1] = e
		end
	end
	return list
end

-- Resolves an option. Returns ok, message. A failed resolve leaves everything as it was.
function RunEvents.resolve(state, eventId, optionId, rng)
	local event = RunEvents.getById(eventId)
	if not event then return false, "Unknown event." end
	for _, option in ipairs(event.options) do
		if option.id == optionId then
			return option.resolve(state, rng or state.rng or math.random)
		end
	end
	return false, "Unknown option."
end

return RunEvents
