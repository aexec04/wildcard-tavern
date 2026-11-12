--[[
	Shared/Engine/PackRoom.lua
	"Make room": the pure rules for picking a Patron (or Recipe) from a pack when the table (or recipe box) is already full. The pick is never
	silently lost: the player chooses which owned items leave, they are sold at their normal sell value (half the price, rounded down, the
	same rule as Sell in My Patrons) and the picks join. Used by Engine/RunState.resolvePack (the server rule) and by Client/PackMakeRoom
	(the panel), so both read the same numbers. Tested in EngineTests ("PackRoom").

	A view is { ownedPatrons = { id, ... }, recipes = { id, ... }, patronLimit, recipeLimit } (RunState builds it from its state, the client
	from the serialized state). `items` are the picked reveal items, each with a `category` ("patron", "house", "menu", "secret", "standard").

	PackRoom.overflow(view, items)               { patrons = n, recipes = m } how many owned items must leave
	PackRoom.sellValue(kind, id)                 Tips back for selling that owned Patron ("patron") or Recipe ("recipe"), 0 when unknown
	PackRoom.check(view, items, replaceIds)      true, { patrons = { id }, recipes = { id } } or false, message
	PackRoom.isRecipeCategory(category)
	PackRoom.nameOf(kind, id)                    display name of an owned Patron or Recipe
	PackRoom.summary(view, items, replaceIds)    { need, ready, refund, lines } for the panel: "X leaves, Y joins your table." per pair and the Tips back
]]

local Patrons = require(script.Parent.Patrons)
local Recipes = require(script.Parent.Recipes)

local PackRoom = {}

local RECIPE = { house = true, menu = true, secret = true }

function PackRoom.isRecipeCategory(category)
	return RECIPE[category] == true
end

local function recipeDef(id)
	return Recipes.getHouseRecipeById(id) or Recipes.getMenuRecipeById(id) or Recipes.getSecretRecipeById(id)
end
PackRoom.recipeDef = recipeDef

function PackRoom.sellValue(kind, id)
	local def
	if kind == "patron" then def = Patrons.getById(id) else def = recipeDef(id) end
	return def and math.floor((def.price or 0) / 2) or 0
end

function PackRoom.overflow(view, items)
	local patronPicks, recipePicks = 0, 0
	for _, item in ipairs(items or {}) do
		if item.category == "patron" then
			patronPicks = patronPicks + 1
		elseif RECIPE[item.category] then
			recipePicks = recipePicks + 1
		end
	end
	local patrons = math.max(0, #view.ownedPatrons + patronPicks - (view.patronLimit or 0))
	local recipes = math.max(0, #view.recipes + recipePicks - (view.recipeLimit or 0))
	return { patrons = patrons, recipes = recipes }
end

function PackRoom.check(view, items, replaceIds)
	local need = PackRoom.overflow(view, items)
	if need.patrons + need.recipes == 0 then
		if replaceIds ~= nil and type(replaceIds) == "table" and #replaceIds > 0 then
			return false, "There is room, nothing needs to leave"
		end
		return true, { patrons = {}, recipes = {} }
	end
	if type(replaceIds) ~= "table" or #replaceIds == 0 then
		return false, "Make room first"
	end
	local ownedPatron, ownedRecipe = {}, {}
	for _, id in ipairs(view.ownedPatrons) do ownedPatron[id] = true end
	for _, id in ipairs(view.recipes) do ownedRecipe[id] = (ownedRecipe[id] or 0) + 1 end
	local seen, outP, outR, usedRecipe = {}, {}, {}, {}
	for _, id in ipairs(replaceIds) do
		if type(id) ~= "string" then return false, "Invalid selection" end
		if ownedPatron[id] then
			if seen[id] then return false, "Each Patron can leave only once" end
			seen[id] = true
			outP[#outP + 1] = id
		elseif ownedRecipe[id] then
			usedRecipe[id] = (usedRecipe[id] or 0) + 1
			if usedRecipe[id] > ownedRecipe[id] then return false, "You do not have that many of that recipe" end
			outR[#outR + 1] = id
		else
			return false, "You do not own that"
		end
	end
	if #outP ~= need.patrons or #outR ~= need.recipes then
		local parts = {}
		if need.patrons > 0 then parts[#parts + 1] = string.format("%d Patron%s", need.patrons, need.patrons == 1 and "" or "s") end
		if need.recipes > 0 then parts[#parts + 1] = string.format("%d recipe%s", need.recipes, need.recipes == 1 and "" or "s") end
		return false, "Choose " .. table.concat(parts, " and ") .. " to leave"
	end
	return true, { patrons = outP, recipes = outR }
end

function PackRoom.nameOf(kind, id)
	local def
	if kind == "patron" then def = Patrons.getById(id) else def = recipeDef(id) end
	return def and def.name or tostring(id)
end

-- The emoji fallback for an owned Patron or Recipe portrait.
function PackRoom.iconOf(kind, id)
	local def
	if kind == "patron" then def = Patrons.getById(id) else def = recipeDef(id) end
	return def and def.icon or "🃏"
end

-- The picks that do not fit (the LAST ones, as in summary): { { kind, id, name } }, shown as "Joins your table".
function PackRoom.joiners(view, items)
	local need = PackRoom.overflow(view, items)
	local patrons, recipes = {}, {}
	for _, item in ipairs(items or {}) do
		if item.category == "patron" then patrons[#patrons + 1] = item elseif RECIPE[item.category] then recipes[#recipes + 1] = item end
	end
	local out = {}
	for i = math.max(1, #patrons - need.patrons + 1), #patrons do
		if need.patrons > 0 then out[#out + 1] = { kind = "patron", id = patrons[i].id, name = patrons[i].name or PackRoom.nameOf("patron", patrons[i].id) } end
	end
	for i = math.max(1, #recipes - need.recipes + 1), #recipes do
		if need.recipes > 0 then out[#out + 1] = { kind = "recipe", id = recipes[i].id, name = recipes[i].name or PackRoom.nameOf("recipe", recipes[i].id) } end
	end
	return out
end

-- What the Make room panel shows for the current choice. `ready` is true when the choice is exactly the overflow (it can be confirmed).
function PackRoom.summary(view, items, replaceIds)
	local need = PackRoom.overflow(view, items)
	local ownedPatron = {}
	for _, id in ipairs(view.ownedPatrons) do ownedPatron[id] = true end
	local leavingP, leavingR = {}, {}
	for _, id in ipairs(replaceIds or {}) do
		if ownedPatron[id] then leavingP[#leavingP + 1] = id else leavingR[#leavingR + 1] = id end
	end
	local joiningP, joiningR = {}, {}
	for _, item in ipairs(items or {}) do
		if item.category == "patron" then joiningP[#joiningP + 1] = item elseif RECIPE[item.category] then joiningR[#joiningR + 1] = item end
	end
	-- the picks that do not fit are the LAST ones (earlier picks take the free seats), so the pairs line up with them
	local lines, refund = {}, 0
	local function pairUp(leaving, joining, over, kind, where)
		for i, id in ipairs(leaving) do
			local joinItem = joining[#joining - over + i] or joining[#joining]
			local joinName = joinItem and joinItem.name or PackRoom.nameOf(kind, joinItem and joinItem.id)
			lines[#lines + 1] = string.format("%s leaves, %s joins your %s.", PackRoom.nameOf(kind, id), joinName or "the new pick", where)
			refund = refund + PackRoom.sellValue(kind, id)
		end
	end
	pairUp(leavingP, joiningP, need.patrons, "patron", "table")
	pairUp(leavingR, joiningR, need.recipes, "recipe", "recipe box")
	local ok = PackRoom.check(view, items, replaceIds)
	return { need = need, ready = ok == true, refund = refund, lines = lines }
end

return PackRoom
