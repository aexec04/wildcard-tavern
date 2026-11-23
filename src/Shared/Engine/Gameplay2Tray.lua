--[[
	Engine/Gameplay2Tray.lua
	Gameplay v2: the consumables tray. Recipes (House, Menu, Secret) are the run's consumables; up to two show in a small tray in the
	top left under Mute and Calm. Pure and tested; Client/Gameplay2Tray draws it with TavernKit on Gameplay2Layout rects.

	held(state)                 -> { slots = { slot1, slot2 }, more = n }   slot = { empty = true } or
	                               { category, id, name, label, tier, need = { min, max } or nil, needsSuit, sell, text }
	flow(slot, selectedCount, suit, picked) -> { phase, prompt, useText, canUse }
	    phase "empty" | "idle" (nothing picked) | "pick" (needs hand cards) | "ready" ; picked = this slot is the armed one
	useArgs(slot, indices, suit) -> category, id, indices or nil, suit or nil    what the UseRecipe remote takes
	nextSuit(suit)              -> the next suit in the cycle (used by the suit plate)
	lines(text, width)          -> number of lines a name needs at 14 px (7 px per character, greedy word wrap)
	Rule: a recipe is used from the shop or while playing a round (RunState.phaseAllowsRecipeUse); Calm mode draws no tween.
]]

local Recipes = require(script.Parent:WaitForChild("Recipes"))
local PackRoom = require(script.Parent:WaitForChild("PackRoom"))

local M = {}

M.SLOTS = 2
M.HEADING = "Recipes" -- the plate above the slots, so a new player knows what these are
M.EMPTY_TEXT = "Empty slot"
M.PICK_RECIPE = "Pick a Recipe" -- the Use plate until a Recipe is armed
M.FIRST_TIME = "Recipes are one use helpers: tap one, pick the cards it needs, then press Use" -- Hints first_recipe says it in 12 words
M.CHAR_W = 7 -- px per character at 14 px, a little generous
M.SUITS = { "Spades", "Hearts", "Clubs", "Diamonds" }
M.TIERS = { house = "Common", menu = "Uncommon", secret = "Rare" } -- the tier word on each card, never colour alone

local CATEGORIES = {
	{ key = "house", inventory = "houseRecipeInventory", find = Recipes.getHouseRecipeById },
	{ key = "menu", inventory = "menuRecipeInventory", find = Recipes.getMenuRecipeById },
	{ key = "secret", inventory = "secretRecipeInventory", find = Recipes.getSecretRecipeById },
}

-- the plate drops a trailing "Recipe" (every plate here is one), so "Double Trouble Recipe" reads "Double Trouble"
function M.label(name)
	local short = tostring(name):gsub("%s+Recipe$", "")
	return short ~= "" and short or tostring(name)
end

local function slotFor(category, id, def)
	return {
		category = category,
		id = id,
		name = def.name or id,
		icon = def.icon or "",
		label = M.label(def.name or id),
		tier = M.TIERS[category],
		need = def.cardCount and { min = def.cardCount.min, max = def.cardCount.max } or nil,
		needsSuit = def.needsSuit == true,
		sell = PackRoom.sellValue("recipe", id),
		text = def.description or "",
	}
end

function M.held(state)
	local all = {}
	for _, c in ipairs(CATEGORIES) do
		for _, id in ipairs((state and state[c.inventory]) or {}) do
			local def = c.find(id)
			if def then all[#all + 1] = slotFor(c.key, id, def) end
		end
	end
	local out = { slots = {}, more = math.max(0, #all - M.SLOTS) }
	for i = 1, M.SLOTS do out.slots[i] = all[i] or { empty = true } end
	return out
end

function M.nextSuit(suit)
	for i, s in ipairs(M.SUITS) do
		if s == suit then return M.SUITS[i % #M.SUITS + 1] end
	end
	return M.SUITS[1]
end

local function plural(n, word) return n == 1 and ("1 " .. word) or (n .. " " .. word .. "s") end

function M.flow(slot, selectedCount, suit, picked)
	if not slot or slot.empty then
		return { phase = "empty", prompt = "", info = "", useText = M.PICK_RECIPE, canUse = false }
	end
	if not picked then
		return { phase = "idle", prompt = "", info = "", useText = M.PICK_RECIPE, canUse = false }
	end
	local n = selectedCount or 0
	local need = slot.need
	if not need then
		return { phase = "ready", prompt = slot.name, info = slot.text, useText = "Use", canUse = true }
	end
	local want = need.min == need.max and plural(need.min, "card") or (need.min .. " to " .. plural(need.max, "card"))
	if n < need.min or n > need.max then
		return { phase = "pick", prompt = "Pick " .. want, info = slot.text, useText = "Pick " .. want, canUse = false }
	end
	if slot.needsSuit then
		return { phase = "ready", prompt = "Suit: " .. (suit or M.SUITS[1]) .. ". Tap to change", info = slot.text, useText = "Use " .. (suit or M.SUITS[1]), canUse = true }
	end
	return { phase = "ready", prompt = slot.name, info = slot.text, useText = "Use", canUse = true }
end

-- What the prompt plate says: the armed Recipe's own description (what it does) while the player is still picking, the suit
-- line when a suit is asked for, else the description again. Empty when nothing is armed.
function M.promptLine(flow, slot)
	if not slot or slot.empty or not flow then return "" end
	if slot.needsSuit and flow.phase == "ready" then return flow.prompt end
	return flow.info ~= "" and flow.info or flow.prompt
end

-- The slot plate: icon and name (the tier is the rim colour and the Tier attribute), or "Empty slot".
function M.slotText(slot)
	if not slot or slot.empty then return M.EMPTY_TEXT end
	return (slot.icon ~= "" and (slot.icon .. " ") or "") .. slot.label
end

function M.useArgs(slot, indices, suit)
	if not slot or slot.empty then return nil end
	local idx = slot.need and indices or nil
	return slot.category, slot.id, idx, slot.needsSuit and (suit or M.SUITS[1]) or nil
end

function M.lines(text, width)
	local per = math.max(1, math.floor(width / M.CHAR_W))
	local lines, cur = 1, 0
	for word in tostring(text):gmatch("%S+") do
		local len = #word
		if cur == 0 then
			cur = len
		elseif cur + 1 + len <= per then
			cur = cur + 1 + len
		else
			lines, cur = lines + 1, len
		end
		if len > per then lines = lines + math.ceil(len / per) - 1 end
	end
	return lines
end

return M
