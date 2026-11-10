--[[
	Engine/MenuRoomLayout.lua
	Numbers for the Tavern Room Menu (Client/MenuRoom.lua): ONE painted tavern interior (menu_room_scene) is the whole Menu and
	the props in it ARE the buttons. Hotspots are rectangles of the picture mapped through the cover crop (pure, unit tested).

	apply(MenuLayout) gives the Menu hotspots their picture rectangles (MenuLayout.rect maps them to pixels).
	Called once by Client/Menu.lua. Presentation only: every action keeps its handler, route and scroll.
]]

local MenuRoomLayout = {}

-- ONE painted tavern interior (art key menu_room_scene, 1536x1024) fills the Menu. Hotspots are rectangles of that PICTURE
-- (fractions l, t, r, b) mapped through the cover crop, so they stay on their props at any screen aspect.
MenuRoomLayout.ASPECT = 1.5
MenuRoomLayout.SCENE_KEY = "menu_room_scene"
MenuRoomLayout.pic = {
	play        = { l = 0.254, t = 0.576, r = 0.755, b = 0.977 },  -- the card table and chairs; the deck is the primary button
	tome        = { l = 0.007, t = 0.50,  r = 0.20,  b = 0.84 },   -- lectern and open book
	questscroll = { l = 0.342, t = 0.19,  r = 0.404, b = 0.37 },   -- hanging scroll
	maptable    = { l = 0.612, t = 0.24,  r = 0.723, b = 0.43 },   -- wall map
	coinjar     = { l = 0.279, t = 0.36,  r = 0.352, b = 0.49 },   -- jar on the counter
	rulebook    = { l = 0.55,  t = 0.478, r = 0.641, b = 0.523 },  -- small book on the counter (grown to a 44 px touch target)
	jukebox     = { l = 0.80,  t = 0.40,  r = 0.983, b = 0.82 },   -- top trimmed from 0.37 so it clears the board by 8 percent or less
	noticeboard = { l = 0.775, t = 0.137, r = 0.97,  b = 0.41 },   -- cork board on the right wall: opens the All actions list
}
MenuRoomLayout.deck = { l = 0.49, t = 0.67, r = 0.56, b = 0.73 }   -- gentle pulse ring on the primary
MenuRoomLayout.stripOrder = { "play", "questscroll", "maptable", "tome", "coinjar", "rulebook", "jukebox", "noticeboard" }
MenuRoomLayout.STRIP_H = 44
MenuRoomLayout.minTouch = 44                                             -- smallest button side in pixels

-- Ambient rectangles in picture fractions (all off in calm mode). Eight kinds, one 30 Hz update.
MenuRoomLayout.fireRect = { l = 0.062, t = 0.37, r = 0.15, b = 0.50 }
MenuRoomLayout.lanternRects = { { l = 0.24, t = 0.06, r = 0.30, b = 0.25 }, { l = 0.70, t = 0.06, r = 0.77, b = 0.25 } }
MenuRoomLayout.candles = { { x = 0.43, y = 0.70 }, { x = 0.61, y = 0.665 } }
MenuRoomLayout.windowRect = { l = 0.43, t = 0.16, r = 0.57, b = 0.37 }
MenuRoomLayout.stars = { { 0.46, 0.22 }, { 0.51, 0.29 }, { 0.54, 0.19 } }
MenuRoomLayout.jukeTop = { x = 0.89, y = 0.40 }
MenuRoomLayout.jarGlint = { x = 0.31, y = 0.39 }
MenuRoomLayout.motes = 3
MenuRoomLayout.glint = { every = 7, length = 0.5 }                       -- one glint on the coin jar every `every` s, `length` s long
MenuRoomLayout.flicker = 0.03                                            -- glow flicker amplitude (transparency)
MenuRoomLayout.ambientKinds = 8                                          -- fire, lanterns, motes, candles, stars, notes, glint, deck ring
MenuRoomLayout.MAX_AMBIENT = 8

-- Every key MenuRoomArt may hold (the generated map only ever contains these). The old per-prop pieces stay uploaded but are not drawn.
MenuRoomLayout.artKeys = {
	"menu_room_wall", "menu_room_jukebox", "menu_room_coinjar", "menu_room_tome", "menu_room_scroll", "menu_room_noticeboard",
	"menu_room_map", "menu_room_rulebook", "menu_room_cardtable", "menu_room_lantern", "menu_room_sign", "menu_room_scene",
}

-- Cover crop of the picture on a screen: drawn width, height and top-left offset (the picture is centred, never stretched).
function MenuRoomLayout.cover(W, H)
	local s = math.max(W / MenuRoomLayout.ASPECT, H)
	local pw, ph = MenuRoomLayout.ASPECT * s, s
	return pw, ph, (W - pw) / 2, (H - ph) / 2
end

-- Picture-fraction rectangle to unclamped pixels through the crop.
function MenuRoomLayout.toPixels(r, W, H)
	local pw, ph, ox, oy = MenuRoomLayout.cover(W, H)
	return ox + r.l * pw, oy + r.t * ph, ox + r.r * pw, oy + r.b * ph
end

local function fractionInside(l, t, r, b, W, H)
	local il, it, ir, ib = math.max(l, 0), math.max(t, 0), math.min(r, W), math.min(b, H)
	if ir <= il or ib <= it then return 0 end
	return (ir - il) * (ib - it) / ((r - l) * (b - t))
end

-- Pixel rects { id -> { l, t, r, b, strip } } for every hotspot on a W x H screen: mapped through the crop, grown to the touch size,
-- clamped inside the screen; a hotspot that is mostly cropped away becomes a plain plate in a bottom strip so nothing is unreachable.
function MenuRoomLayout.layout(W, H)
	local out, stripIds = {}, {}
	local T = MenuRoomLayout.minTouch
	for _, id in ipairs(MenuRoomLayout.stripOrder) do
		local l, t, r, b = MenuRoomLayout.toPixels(MenuRoomLayout.pic[id], W, H)
		if fractionInside(l, t, r, b, W, H) < 0.6 then
			stripIds[#stripIds + 1] = id
		else
			if r - l < T then local c = (l + r) / 2; l, r = c - T / 2, c + T / 2 end
			if b - t < T then local c = (t + b) / 2; t, b = c - T / 2, c + T / 2 end
			-- cut to the visible part of the screen (a rect past the edge is cropped, not slid back onto the props above it)
			l, r, t, b = math.max(l, 0), math.min(r, W), math.max(t, 0), math.min(b, H)
			if r - l < T then l = math.max(0, math.min(l, W - T)); r = l + T end
			if b - t < T then t = math.max(0, math.min(t, H - T)); b = t + T end
			out[id] = { l = l, t = t, r = r, b = b, strip = false }
		end
	end
	local n = #stripIds
	if n > 0 then
		local gap = 6
		local w = math.max(T, math.min(150, (W - 16 - gap * (n - 1)) / n))
		local total = n * w + (n - 1) * gap
		local x0 = (W - total) / 2
		for i, id in ipairs(stripIds) do
			local l = x0 + (i - 1) * (w + gap)
			out[id] = { l = l, t = H - MenuRoomLayout.STRIP_H - 8, r = l + w, b = H - 8, strip = true }
		end
	end
	return out
end

-- Rectangles (pixels) the layout test checks: { id, kind, l, t, r, b }.
function MenuRoomLayout.rects(W, H)
	local out = {}
	for _, id in ipairs(MenuRoomLayout.stripOrder) do
		local r = MenuRoomLayout.layout(W, H)[id]
		out[#out + 1] = { id = id, kind = r.strip and "strip" or "prop", r.l, r.t, r.r, r.b }
	end
	return out
end

-- Point the Menu hotspots at the picture: each gets its rectangle, and MenuLayout.rect maps it through the crop. Returns the count set.
function MenuRoomLayout.apply(MenuLayout)
	local moved = 0
	for _, hotspot in ipairs(MenuLayout.Hotspots) do
		local pic = MenuRoomLayout.pic[hotspot.id]
		if pic then
			hotspot.pic = pic
			moved = moved + 1
		end
	end
	MenuLayout.picRect = function(hotspot, W, H)
		local r = MenuRoomLayout.layout(W, H)[hotspot.id]
		return r.l, r.t, r.r, r.b
	end
	MenuLayout.isStrip = function(id, W, H)
		local r = MenuRoomLayout.layout(W, H)[id]
		return r ~= nil and r.strip
	end
	MenuLayout.noticeSpot = { id = "noticeboard", pic = MenuRoomLayout.pic.noticeboard }
	MenuLayout.world = true
	MenuLayout.WorldArt = {} -- the old per-prop pieces are not drawn: the props are part of the one picture
	MenuLayout.WorldArtCategory = "menu_room"
	MenuLayout.room = true
	return moved
end

-- Coin glint phase: 0 when idle, then 0 to 1 over the glint length once every `every` seconds.
function MenuRoomLayout.glintAt(t)
	local G = MenuRoomLayout.glint
	local local_t = t % G.every
	if local_t > G.length then return 0 end
	return local_t / G.length
end

-- Flicker value (-flicker .. +flicker) at time t from two slow sines, never past the amplitude.
function MenuRoomLayout.flickerAt(t)
	local A = MenuRoomLayout.flicker
	return (math.sin(t * 1.7) * 0.65 + math.sin(t * 4.3) * 0.35) * A
end

-- Mote position (picture fractions) above the fire at time t for mote i (1 to motes): a slow rise that loops.
function MenuRoomLayout.moteAt(i, t)
	local F = MenuRoomLayout.fireRect
	local cx, top = (F.l + F.r) / 2, F.t
	local k = (t / (9 + i) + (i - 1) / MenuRoomLayout.motes) % 1
	return cx + math.sin(t * 0.6 + i * 2.1) * 0.02, top - k * 0.16, 1 - math.abs(k * 2 - 1)
end

return MenuRoomLayout
