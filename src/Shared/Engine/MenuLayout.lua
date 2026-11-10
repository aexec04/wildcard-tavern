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
	far = 8,         -- wall backdrop, px of shift at the screen edge
	beams = 16,      -- mid layer: ceiling beams and hanging lanterns
	mid = 22,        -- the counter layer: counter, items and scrolls (items are meant to be 24, they share the layer)
	near = 28,       -- title
	lantern = 34,    -- the cutout foreground lantern, the only layer allowed past maxOffset
	wall = 8,        -- the Notice Board moves with the wall layer (same as far)
	maxOffset = 32,  -- nothing ever moves further than this, except the foreground lantern (lanternMax)
	lanternMax = 34,
	tiltDegrees = 1.5, -- the title tilts this much at the screen edge
	idleDrift = 6,   -- touch and phone: slow idle drift, px
	lerp = 0.08,     -- smoothing per frame at 60 fps
	backdropScale = 1.08, -- backdrop is drawn this much larger so edges never show
}

MenuLayout.PHONE_WIDTH = 700 -- narrower than this: no scene, just the action list
MenuLayout.MAX_ANIMATED = 16 -- cap on animated foreground objects

-- Painted scene art (category menu_scene) and the animated life drawn over it. Fractions of the screen. Animated budget:
-- 5 dust motes + 6 embers + fire glow + window light shaft + counter candle glow + steam wisp + swinging lantern = 16.
MenuLayout.SceneArt = {
	wall = "menu_wall_far", beams = "menu_mid_beams", counter = "menu_counter", board = "menu_noticeboard_wall",
	scrollTop = "menu_scroll_top", scrollBottom = "menu_scroll_bottom", parchment = "menu_parchment",
	sealGold = "menu_seal_gold", sealRed = "menu_seal_red", lantern = "menu_lantern_fg",
	-- counter slot -> object image
	items = { "menu_item_scroll", "menu_item_map", "menu_item_tome", "menu_item_coinjar", "menu_item_rulebook", "menu_item_jukebox" },
	-- the beams image is cropped to the band of beams (source pixels of the 1536x1024 picture) so its brown sky never covers the wall
	beamsRect = { x = 0, y = 270, w = 1536, h = 380 },
	fire = { x = 0.61, y = 0.60, w = 0.14, h = 0.14 },      -- fireplace glow centre
	window = { x = 0.04, y = 0.30, w = 0.14, h = 0.34 },     -- window light shaft start
	candle = { x = 0.10, y = 0.745, w = 0.05 },              -- candle on the counter's left end
	steam = { x = 0.575, y = 0.77 },                         -- above the counter mug spot
	lanternPos = { x = 0.92, y = 0.18, h = 0.22 },            -- foreground lantern, hangs from the top
	embers = 6,
	motes = 5,
}

-- The bayou backdrop (category menu_bayou, Client/MenuBayou.lua): a stilt tavern over misty water at golden hour. Layers back to
-- front with their parallax depth in px (deeper in front moves more, nothing past maxOffset). x, y, w, h are fractions of the
-- screen for the image box (anchor centre); `bleed` layers are drawn backdropScale larger so parallax never shows an edge.
-- Animated budget: water shimmer + drifting mist + tavern window glow + whole-scene drift + 6 fireflies = 10, plus the
-- swinging lantern from MenuScene = 11, under MAX_ANIMATED. The bayou replaces the painted wall only when its sky art is recorded.
MenuLayout.Bayou = {
	layers = {
		{ key = "sky",     id = "bayou_sky",           px = 0,   x = 0.5,  y = 0.5,  w = 1,    h = 1,    bleed = true },
		{ key = "trees",   id = "bayou_far_trees",     px = 0,   x = 0.5,  y = 0.5,  w = 1.08, h = 0.72 },
		{ key = "water",   id = "bayou_water",         px = 0,  x = 0.5,  y = 0.74, w = 1.08, h = 0.56 },
		{ key = "tavern",  id = "bayou_tavern_stilts", px = 0,  x = 0.70, y = 0.47, w = 0.46, h = 0.62 },
		{ key = "boat",    id = "bayou_boat_post",     px = 0,  x = 0.40, y = 0.64, w = 0.26, h = 0.26 },
		{ key = "mist",    id = "bayou_mist",          px = 0,  x = 0.5,  y = 0.60, w = 1.2,  h = 0.34 },
		{ key = "knees",   id = "bayou_cypress_knees", px = 0,  x = 0.5,  y = 0.86, w = 1.08, h = 0.36 },
		{ key = "willow",  id = "bayou_willow_fg",     px = 0,  x = 0.14, y = 0.5,  w = 0.40, h = 1.04 },
	},
	fireflies = 6,
	animated = 10,
	-- ONE rigid camera for the whole scene (every layer lives in one frame): a tiny pan and a 1 percent zoom breath over `period`
	-- seconds. No layer has its own parallax or bob, so nothing slides against anything else. baseZoom keeps the edges covered.
	drift = { panPx = 6, baseZoom = 1.03, zoomAmp = 0.01, period = 40 },
	windowGlow = { x = 0.5, y = 0.60, w = 0.50, h = 0.20 }, -- inside the tavern image, fractions of its box
	mistTint = { 255, 236, 205 },                           -- the mist ribbon has a pink tint from its cutout, warm it up
	scrim = 0.55,                                           -- dark translucent backing under the title and the counter, 0 to 1 transparency
}

-- The tavern composition (menu redesign 2). A long bar COUNTER runs along the bottom; six painted ITEMS sit on it in a fixed
-- row, evenly spaced and centred; a click UNROLLS a parchment scroll upward from the item that lists that group's actions.
-- The carved Deal Me In SIGN hangs from a ceiling beam in the centre. A NOTICE BOARD on the left wall holds the pinned notes.
-- Tutorial note: every action button lives inside its scroll (hidden while the scroll is closed). A tutorial step that points at
-- one must open that item's scroll first (MenuHotspots result.openScroll(itemId)); Play and New Run are always visible.
-- Boss Rush has no Menu action yet (it starts from Run Setup), Badges and Bonds are tabs inside Collection, Poker Hands has its
-- own corner button, so the scrolls list only real Menu actions.
MenuLayout.Counter = { top = 0.78, bottom = 1.0 }
MenuLayout.ITEM_Y = 0.855       -- centre of the item row, fraction of screen height
MenuLayout.ITEM_S = 0.115       -- item height as a fraction of screen height (square)
MenuLayout.ITEM_SPACING = 0.115 -- distance between item centres, fraction of screen width
MenuLayout.PLATE_H = 0.05       -- carved name plate under each item, fraction of screen height
MenuLayout.PLATE_W = 1.5        -- plate width as a multiple of the item width
MenuLayout.NoticeBoard = { x = 0.02, y = 0.28, w = 0.27, h = 0.30 } -- left wall, fractions of screen width and height
MenuLayout.SCROLL = { width = 270, rowH = 46, pad = 16, rod = 14, gap = 8, minTop = 8 }

-- x of counter item number i (1 to 6): evenly spaced, centred on the screen.
function MenuLayout.itemX(i)
	return 0.5 + (i - 3.5) * MenuLayout.ITEM_SPACING
end

-- Hotspots: the Play sign plus the six counter items (in counter order, left to right).
-- `lit` marks the one primary action (pulsing lantern). `item` is the counter slot.
MenuLayout.Hotspots = {
	{ id = "play", x = 0.50, y = 0.56, s = 0.24, asp = 1.5, label = "Deal Me In", desc = "Start a new run", glyph = "\240\159\143\174", art = "menu_sign_play", lit = true,
		actions = { "play", "newRun" } },
	{ id = "questscroll", item = 1, label = "Quest Scroll", desc = "Challenges, quests and boards", glyph = "\240\159\147\156",
		actions = { "daily", "weekly", "seed", "quests", "leaderboards" } },
	{ id = "maptable", item = 2, label = "Road Ahead", desc = "Study the Tavern Map", glyph = "\240\159\151\186", art = "menu_maptable",
		actions = { "road" } },
	{ id = "tome", item = 3, label = "The Tome", desc = "Collection, Card Sets, Flair, Legend and your Ledger", glyph = "\240\159\147\154", art = "menu_bookshelf",
		actions = { "collection", "cardSets", "flair", "legend", "stats" } },
	{ id = "coinjar", item = 4, label = "Coin Jar", desc = "Store, Season, Rewards and Invite", glyph = "\240\159\170\153", art = "menu_coinjar",
		actions = { "store", "season", "rewards", "invite" } },
	{ id = "rulebook", item = 5, label = "Rulebook", desc = "Learn how to play", glyph = "\240\159\147\150",
		actions = { "howToPlay", "tutorial" } },
	{ id = "jukebox", item = 6, label = "Jukebox", desc = "Settings and Volume", glyph = "\240\159\142\181", art = "menu_jukebox",
		actions = { "settings", "volume" } },
}
for _, hotspot in ipairs(MenuLayout.Hotspots) do
	if hotspot.item then
		hotspot.x = MenuLayout.itemX(hotspot.item)
		hotspot.y = MenuLayout.ITEM_Y
		hotspot.s = MenuLayout.ITEM_S
		hotspot.asp = 1.0
	end
end

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
	{ id = "cardSets", label = "Card Sets" },
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

-- Pixel rectangle of the name plate under a counter item.
function MenuLayout.plateRect(hotspot, screenW, screenH)
	local l, _, r, b = MenuLayout.rect(hotspot, screenW, screenH)
	local cx, half = (l + r) / 2, (r - l) / 2 * MenuLayout.PLATE_W
	return cx - half, b + 2, cx + half, b + 2 + MenuLayout.PLATE_H * screenH
end

-- Pixel rectangle of the Notice Board.
function MenuLayout.noticeRect(screenW, screenH)
	local n = MenuLayout.NoticeBoard
	return n.x * screenW, n.y * screenH, (n.x + n.w) * screenW, (n.y + n.h) * screenH
end

-- Pixel rectangle of an item's open scroll (left, top, right, bottom): centred over the item, its bottom edge just above the
-- item, kept on screen. `count` is the number of action rows.
function MenuLayout.scrollRect(hotspot, count, screenW, screenH)
	local S = MenuLayout.SCROLL
	local w = math.min(S.width, screenW - 16)
	local h = count * S.rowH + S.pad * 2 + S.rod * 2
	local il, it, ir = MenuLayout.rect(hotspot, screenW, screenH)
	local cx = (il + ir) / 2
	local left = math.max(8, math.min(cx - w / 2, screenW - w - 8))
	local bottom = it - S.gap
	local top = bottom - h
	if top < S.minTop then
		top = S.minTop
		bottom = top + h
	end
	return left, top, left + w, bottom
end

local function clamp(v, lo, hi)
	if v < lo then return lo end
	if v > hi then return hi end
	return v
end
MenuLayout.clamp = clamp

-- Parallax shift in pixels for a layer. nx, ny are the cursor from the screen centre, -1 to 1. The layer moves opposite to the
-- cursor. Calm mode and reduced motion return zero, and nothing ever exceeds maxOffset.
function MenuLayout.parallaxOffset(nx, ny, layerPx, calm, maxPx)
	if calm then return 0, 0 end
	local limit = maxPx or MenuLayout.Parallax.maxOffset
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
