--[[
	Shared/Engine/AdminJumpKeys.lua
	One table of every jump the Studio-only admin panel (Client/AdminJumpPanel) shows as a button. Add a key here and a button
	appears. Each value is a DebugGoto value: it must parse through DebugGotoRules (tested), so a key that does not exist yet
	cannot be listed. shouldBuild(isStudio) is the guard the panel uses: it never builds outside Studio.
]]

local AdminJumpKeys = {}

AdminJumpKeys.ROW_HEIGHT = 44 -- touch size
AdminJumpKeys.REPEAT_GAP = 0.3 -- seconds between clearing the attribute and setting it again, so the same key can run twice
AdminJumpKeys.RUN_WAIT = 12 -- seconds to wait for a started run before the key is sent anyway

-- true only in Studio (the caller passes RunService:IsStudio())
function AdminJumpKeys.shouldBuild(isStudio)
	return isStudio == true
end

-- keys that work without a live run
AdminJumpKeys.NO_RUN = { menu = true, round1 = true, store = true, map = true }

-- Rows for the panel, most used first. ids (real registry ids, passed by the panel):
--   bosses = { { id, name } ... } (BossRounds.Definitions), recipes = { id ... }, tags = { id ... }
-- Each row is { label, value, needsRun } for a button, or { label, heading = true } for a 24 px group heading (not a button).
AdminJumpKeys.HEADING_HEIGHT = 24
function AdminJumpKeys.list(ids)
	ids = ids or {}
	local bosses = ids.bosses or {}
	local recipes = ids.recipes or {}
	local tags = ids.tags or {}
	local out, seen = {}, {}
	local function add(label, value)
		if seen[value] then return end -- a key is listed once, the first time
		seen[value] = true
		out[#out + 1] = { label = label, value = value, needsRun = not AdminJumpKeys.NO_RUN[value] }
	end
	local function heading(label) out[#out + 1] = { label = label, heading = true } end
	-- the keys used most
	add("Start run", "round1")
	add("Night 2", "night:2")
	add("Boon", "boon")
	add("Reward", "reward")
	add("Victory", "victory")
	if recipes[1] then add("Recipes", "recipes:" .. recipes[1]) end
	if bosses[1] then add("Boss", "boss2:" .. bosses[1].id) end
	heading("Screens")
	add("Menu", "menu")
	add("Store", "store")
	add("Map", "map")
	add("Boss table", "boss1")
	heading("Nights")
	for n = 1, 12 do add("Night " .. n, "night:" .. n) end
	heading("Run")
	add("Sell a Patron", "sellpatron")
	add("Counter, 20 Tips", "shop:20")
	add("End run", "endrun")
	add("End run, win", "endrun:win")
	heading("Recipes")
	for i = 1, math.min(3, #recipes) do add("Recipe " .. i, "recipes:" .. recipes[i]) end
	heading("Patrons")
	add("One Patron", "patrons:1")
	add("Full table (5)", "patrons:5")
	if #tags > 0 then
		heading("Tags")
		for _, id in ipairs(tags) do add("Tag " .. id:gsub("_", " "), "tag:" .. id) end
	end
	if #bosses > 0 then
		heading("Bosses")
		for _, b in ipairs(bosses) do add(b.name or b.id, "boss3:" .. b.id) end
	end
	return out
end

return AdminJumpKeys
