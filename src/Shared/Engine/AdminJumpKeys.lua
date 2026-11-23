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
AdminJumpKeys.NO_RUN = { menu = true, round1 = true, store = true, map = true, news = true, season = true, collection = true,
	["tome:cardsets"] = true, ["tome:badges"] = true, ["tome:legend"] = true, ["tome:flair"] = true, ["tome:stats"] = true,
	loading = true, perf = true, ["map:night=1"] = true, ["map:night=4"] = true, ["map:night=8"] = true,
	["scale:800x450"] = true, ["scale:1024x768"] = true, ["scale:off"] = true, ["sfx:ladder"] = true }

-- Rows for the panel, most used first. ids (real registry ids, passed by the panel):
--   bosses = { { id, name } ... } (BossRounds.Definitions), recipes = { id ... }, tags = { id ... }
-- Each row is { label, value, needsRun } for a button, or { label, heading = true } for a 24 px group heading (not a button).
AdminJumpKeys.HEADING_HEIGHT = 24
function AdminJumpKeys.list(ids)
	ids = ids or {}
	local bosses = ids.bosses or {}
	local recipes = ids.recipes or {}
	local tags = ids.tags or {}
	local sets = ids.sets or {} -- { { id, name } ... } from CosmeticSets.Definitions
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
	heading("Menu screens")
	add("News", "news")
	add("Collection", "collection")
	add("Card Sets page", "tome:cardsets")
	add("Loading screen", "loading")
	add("Tavern Map, Night 1", "map:night=1")
	add("Tavern Map, Night 4", "map:night=4")
	add("Tavern Map, Night 8", "map:night=8")
	add("Draft by rarity", "rarity")
	heading("Daily and meta")
	add("Season track", "season")
	add("Badges", "tome:badges")
	add("Legends", "tome:legend")
	add("Flair", "tome:flair")
	add("Stats", "tome:stats")
	add("Performance", "perf")
	add("Phone size", "scale:800x450")
	add("Tablet size", "scale:1024x768")
	add("Full size", "scale:off")
	add("Sound ladder", "sfx:ladder")
	if #sets > 0 then
		heading("Card Sets")
		for _, s in ipairs(sets) do add(s.name or s.id, "menu:" .. s.id) end
	end
	heading("Run screens")
	add("Haggle", "haggle")
	add("Haggle, good", "haggle:good")
	add("Haggle, bad", "haggle:bad")
	add("Choose a road", "road")
	add("Run Over", "runover")
	add("Run Over, win", "runover:win")
	add("Pack, make room", "packroom")
	add("Wildcard effect", "wildcard")
	add("Legendary effect", "legendary")
	add("Play a hand", "playhand")
	add("Play, keep round", "playhand:keep")
	add("Slow beats on", "beatslow:on")
	add("Freeze a beat", "beatslow:freeze")
	add("Slow beats off", "beatslow:off")
	add("Round win sounds", "sfx:roundwin")
	add("Counter screen", "shop")
	add("Round won", "roundwin")
	add("Game over", "gameover")
	return out
end

return AdminJumpKeys
