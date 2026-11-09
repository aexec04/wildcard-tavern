--[[
	Engine/MenuLayout.lua
	Pure data and math for the tavern Menu (Client/Menu.lua, MenuHotspots.lua, MenuParallax.lua, MenuScene.lua).
	The tavern is the menu: each painted object in the backdrop is a hotspot that opens one action or a small fan of
	them. Positions are fractions so they can be tuned here without touching code:
	  x, y   centre of the hotspot as a fraction of the screen width and height
	  s      height of the hotspot as a fraction of the screen HEIGHT; width is s * asp (so objects keep their shape)
	  art    optional painted slot in the menu_icons category (emoji `glyph` is the fallback)
	Every old Menu action id is listed in Actions and owned by exactly one hotspot, and the "All actions" list shows all of
	them, so nothing is ever unreachable (phones skip the scene and show only that list).
	No Roblox APIs here, so tests/test_menu_layout cases run under plain Lua.
]]

local MenuLayout = {}

MenuLayout.Parallax = {
	far = 10,        -- backdrop, px of shift at the screen edge
	mid = 18,        -- hotspots
	near = 28,       -- title and foreground
	maxOffset = 32,  -- nothing ever moves further than this
	tiltDegrees = 1.5, -- the title tilts this much at the screen edge
	idleDrift = 6,   -- touch and phone: slow idle drift, px
	lerp = 0.08,     -- smoothing per frame at 60 fps
	backdropScale = 1.08, -- backdrop is drawn this much larger so edges never show
}

MenuLayout.PHONE_WIDTH = 700 -- narrower than this: no scene, just the action list
MenuLayout.MAX_ANIMATED = 16 -- cap on animated foreground objects

-- Hotspots. `lit` marks the one primary action (pulsing lantern).
MenuLayout.Hotspots = {
	{ id = "play", x = 0.50, y = 0.64, s = 0.24, asp = 1.5, label = "Deal Me In", desc = "Start a new run", glyph = "🏮", art = "menu_sign_play", lit = true,
		actions = { "play", "newRun" } },
	{ id = "noticeboard", x = 0.15, y = 0.50, s = 0.22, asp = 0.9, label = "Notice Board", desc = "Daily and weekly challenges and quests", glyph = "📌", art = "menu_noticeboard",
		actions = { "daily", "weekly", "quests" } },
	{ id = "maptable", x = 0.32, y = 0.72, s = 0.16, asp = 1.4, label = "Road Ahead", desc = "Study the Tavern Map", glyph = "🗺", art = "menu_maptable",
		actions = { "road" } },
	{ id = "bookshelf", x = 0.86, y = 0.55, s = 0.26, asp = 0.8, label = "Bookshelf", desc = "Collection, Flair, Legend and your Ledger", glyph = "📚", art = "menu_bookshelf",
		actions = { "collection", "flair", "legend", "stats" } },
	{ id = "book", x = 0.71, y = 0.72, s = 0.14, asp = 1.0, label = "Open Book", desc = "Learn how to play", glyph = "📖",
		actions = { "howToPlay", "tutorial" } },
	{ id = "coinjar", x = 0.86, y = 0.83, s = 0.14, asp = 1.0, label = "Bar Counter", desc = "The Store and the Tavern Season", glyph = "🪙", art = "menu_coinjar",
		actions = { "store", "season" } },
	{ id = "scroll", x = 0.07, y = 0.62, s = 0.12, asp = 1.0, label = "Daily Rewards", desc = "Your seven day reward ladder", glyph = "📜",
		actions = { "rewards" } },
	{ id = "chalkboard", x = 0.93, y = 0.32, s = 0.16, asp = 1.0, label = "Chalkboard", desc = "Leaderboards", glyph = "🏆", art = "menu_chalkboard",
		actions = { "leaderboards" } },
	{ id = "jukebox", x = 0.07, y = 0.32, s = 0.16, asp = 0.8, label = "Jukebox", desc = "Settings and Volume", glyph = "🎵", art = "menu_jukebox",
		actions = { "settings", "volume" } },
	{ id = "dicecup", x = 0.50, y = 0.90, s = 0.09, asp = 1.0, label = "Dice Cup", desc = "Play a Seed Run", glyph = "🎲", art = "menu_dicecup",
		actions = { "seed" } },
}

-- Actions in the order the "All actions" list shows them (and the phone list). Each is owned by exactly one hotspot.
MenuLayout.Actions = {
	{ id = "play", label = "Play" },
	{ id = "newRun", label = "New Run..." },
	{ id = "daily", label = "Daily Challenge" },
	{ id = "weekly", label = "Weekly Challenge" },
	{ id = "quests", label = "Daily Quests" },
	{ id = "seed", label = "Seed Run..." },
	{ id = "road", label = "Road Ahead" },
	{ id = "howToPlay", label = "How to Play" },
	{ id = "tutorial", label = "Tutorial" },
	{ id = "collection", label = "Collection" },
	{ id = "flair", label = "Flair" },
	{ id = "legend", label = "Legend" },
	{ id = "stats", label = "Tavern Ledger" },
	{ id = "store", label = "Store" },
	{ id = "season", label = "Season" },
	{ id = "invite", label = "Invite" },
	{ id = "rewards", label = "Rewards" },
	{ id = "leaderboards", label = "Leaderboards" },
	{ id = "settings", label = "Settings" },
	{ id = "volume", label = "Volume" },
}

-- Invite joins the bar counter fan (it is a social action, next to Store and Season).
for _, hotspot in ipairs(MenuLayout.Hotspots) do
	if hotspot.id == "coinjar" then
		table.insert(hotspot.actions, "invite")
	end
end

function MenuLayout.getHotspot(id)
	for _, hotspot in ipairs(MenuLayout.Hotspots) do
		if hotspot.id == id then return hotspot end
	end
	return nil
end

function MenuLayout.hotspotOf(actionId)
	for _, hotspot in ipairs(MenuLayout.Hotspots) do
		for _, id in ipairs(hotspot.actions) do
			if id == actionId then return hotspot end
		end
	end
	return nil
end

function MenuLayout.getAction(id)
	for _, action in ipairs(MenuLayout.Actions) do
		if action.id == id then return action end
	end
	return nil
end

-- True when the screen is too narrow for the scene (phones): only Play and the list are shown.
function MenuLayout.isPhone(screenW)
	return screenW < MenuLayout.PHONE_WIDTH
end

-- Pixel rectangle of a hotspot on a screen: left, top, right, bottom. Width is s * asp of the HEIGHT.
function MenuLayout.rect(hotspot, screenW, screenH)
	local h = hotspot.s * screenH
	local w = h * hotspot.asp
	if w > screenW then
		w = screenW
		h = w / hotspot.asp
	end
	local cx, cy = hotspot.x * screenW, hotspot.y * screenH
	return cx - w / 2, cy - h / 2, cx + w / 2, cy + h / 2
end

-- Overlap area divided by the smaller rectangle's area (0 to 1).
function MenuLayout.overlapFraction(a, b)
	local l, t = math.max(a[1], b[1]), math.max(a[2], b[2])
	local r, bt = math.min(a[3], b[3]), math.min(a[4], b[4])
	if r <= l or bt <= t then return 0 end
	local inter = (r - l) * (bt - t)
	local areaA = (a[3] - a[1]) * (a[4] - a[2])
	local areaB = (b[3] - b[1]) * (b[4] - b[2])
	return inter / math.min(areaA, areaB)
end

local function clamp(v, lo, hi)
	if v < lo then return lo end
	if v > hi then return hi end
	return v
end
MenuLayout.clamp = clamp

-- Parallax shift in pixels for a layer. nx, ny are the cursor from the screen centre, -1 to 1. The layer moves opposite to the
-- cursor. Calm mode and reduced motion return zero, and nothing ever exceeds maxOffset.
function MenuLayout.parallaxOffset(nx, ny, layerPx, calm)
	if calm then return 0, 0 end
	local limit = MenuLayout.Parallax.maxOffset
	local dx = clamp(-clamp(nx or 0, -1, 1) * layerPx, -limit, limit)
	local dy = clamp(-clamp(ny or 0, -1, 1) * layerPx, -limit, limit)
	return dx, dy
end

-- Title tilt in degrees (zero in calm mode).
function MenuLayout.tilt(nx, calm)
	if calm then return 0 end
	return clamp(nx or 0, -1, 1) * MenuLayout.Parallax.tiltDegrees
end

-- Touch and phone: a slow sine drift instead of a cursor. Returns a normalised cursor so it feeds parallaxOffset unchanged,
-- scaled so the mid layer moves about idleDrift px.
function MenuLayout.idleCursor(t)
	local p = MenuLayout.Parallax
	return math.sin(t * 0.4) * (p.idleDrift / p.mid), math.cos(t * 0.3) * (p.idleDrift / p.mid) * 0.6
end

return MenuLayout
