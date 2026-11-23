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

-- list of { label, value, needsRun }. ids: { recipe = id, boss = id } (real registry ids, passed by the panel).
function AdminJumpKeys.list(ids)
	ids = ids or {}
	local out = {}
	local function add(label, value)
		out[#out + 1] = { label = label, value = value, needsRun = not AdminJumpKeys.NO_RUN[value] }
	end
	add("Menu", "menu")
	add("Start run", "round1")
	for n = 1, 12 do add("Night " .. n, "night:" .. n) end
	add("Night boon", "boon")
	add("Reward", "reward")
	add("Victory", "victory")
	add("Sell a Patron", "sellpatron")
	if ids.recipe then add("Recipes", "recipes:" .. ids.recipe) end
	add("Full table (5)", "patrons:5")
	add("Counter, 20 Tips", "shop:20")
	add("End run", "endrun")
	add("End run, win", "endrun:win")
	if ids.boss then
		for n = 2, 12 do add("Boss, Night " .. n, "boss" .. n .. ":" .. ids.boss) end
	end
	add("Store", "store")
	add("Map", "map")
	return out
end

return AdminJumpKeys
