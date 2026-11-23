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
MenuRoomLayout.SCENE_KEY = "menu_scene_a" -- in the menu_scene art category (MenuSceneArt), filled by record-image
MenuRoomLayout.pic = {
	play        = { l = 0.254, t = 0.576, r = 0.755, b = 0.977 },  -- the card table and chairs; the deck is the primary button
	tome        = { l = 0.007, t = 0.50,  r = 0.20,  b = 0.84 },   -- lectern and open book
	questscroll = { l = 0.342, t = 0.205, r = 0.404, b = 0.37 },   -- hanging scroll (top trimmed from 0.19 so the hit area clears the wordmark)
	maptable    = { l = 0.612, t = 0.24,  r = 0.723, b = 0.43 },   -- wall map
	coinjar     = { l = 0.279, t = 0.36,  r = 0.352, b = 0.49 },   -- jar on the counter
	rulebook    = { l = 0.55,  t = 0.478, r = 0.641, b = 0.523 },  -- small book on the counter (grown to a 44 px touch target)
	jukebox     = { l = 0.80,  t = 0.40,  r = 0.983, b = 0.80 },   -- top trimmed from 0.37 so it clears the board by 8 percent or less; bottom from 0.82 so the Daily strip clears it
	noticeboard = { l = 0.775, t = 0.137, r = 0.97,  b = 0.41 },   -- cork board on the right wall: opens the All actions list
}
-- The cork surface itself (inside the wooden frame of noticeboard): the Notice Board notes are laid out inside it.
MenuRoomLayout.cork = { l = 0.79, t = 0.155, r = 0.955, b = 0.41 }
MenuRoomLayout.NOTE_W, MenuRoomLayout.NOTE_GAP, MenuRoomLayout.NOTE_TOP, MenuRoomLayout.CORK_MARGIN, MenuRoomLayout.MAX_NOTES = 300, 12, 10, 10, 4
-- Notes read at least MIN_TEXT px on screen (the table plates use 22). Plate height floors: the daily and Rank plates 86, the goal plate 70.
MenuRoomLayout.MIN_TEXT = 18
function MenuRoomLayout.minNoteH(name)
	if name == "NextGoalBanner" then return 70 end
	return 86
end
-- When the notes do not all fit they first move closer together (noteSlots), before any note is taken off the board.
MenuRoomLayout.NOTE_GAP_TIGHT, MenuRoomLayout.NOTE_TOP_TIGHT = 8, 4
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
	"menu_room_map", "menu_room_rulebook", "menu_room_cardtable", "menu_room_lantern", "menu_room_sign",
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

-- The card table carries its own sign (Client/MenuHotspots): "Deal Me In" (210 x 38) over "New Run" (34 px) with a
-- 12 px gap, hung from the bottom of the hotspot, 24 px above the bottom of the screen. A strip plate is 44 px tall, so
-- as a strip plate the table had "Deal Me In" above its own click surface and "New Run" over the rest of it: a click on
-- the sign did nothing. That was every screen wider than 2.37 to 1 (a 21:9 monitor, a short window), where more than
-- 40 percent of the table is cropped off the bottom. The table stays a prop while the part on screen holds the sign.
MenuRoomLayout.PLAY_SIGN_W, MenuRoomLayout.PLAY_SIGN_H, MenuRoomLayout.PLAY_SIGN_MARGIN = 340, 130, 24

function MenuRoomLayout.holdsSign(l, t, r, b, W, H)
	local width = math.min(r, W) - math.max(l, 0)
	local height = math.min(b, H) - math.max(t, 0)
	return width >= MenuRoomLayout.PLAY_SIGN_W and height >= MenuRoomLayout.PLAY_SIGN_H + MenuRoomLayout.PLAY_SIGN_MARGIN
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
		if fractionInside(l, t, r, b, W, H) < 0.6 and not (id == "play" and MenuRoomLayout.holdsSign(l, t, r, b, W, H)) then
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

-- The cork rectangle in pixels on a W x H screen.
function MenuRoomLayout.corkRect(W, H)
	return MenuRoomLayout.toPixels(MenuRoomLayout.cork, W, H)
end

-- Notes on the cork. heights = the unscaled heights of the visible notes in order. The notes keep NOTE_W wide, shrink with one
-- scale (never above 1) to fit the cork minus a margin and a little extra for their tilt, and as many as fit are shown, at most
-- MAX_NOTES, with equal gaps. Returns { scale, shown, rects = { {x, y, w, h} }, show = { [i] = true }, gap, top } in pixels
-- inside the cork (0,0 = cork top left); gap and top are the unscaled spacing the rects were measured with.
--
-- Notes that do not all fit first move closer together (NOTE_GAP_TIGHT, NOTE_TOP_TIGHT). keep (optional) is the index of
-- the one note that must stay on the board, the Next goal: if it still has no room, the notes above it come off, the
-- nearest first, until it has. A goal line that wrapped onto a second row used to push its own note off the board.
function MenuRoomLayout.noteSlots(corkW, corkH, heights, keep, rank)
	local M, tilt = MenuRoomLayout.CORK_MARGIN, 10 -- 10 px of slack for a 2 degree tilt
	local w = MenuRoomLayout.NOTE_W
	local scale = math.max(0.1, math.min(1, (corkW - 2 * M - tilt) / w))
	local availH = corkH - 2 * M - tilt
	local function fill(gap, top, skip)
		local rects, show, y, shown = {}, {}, top * scale, 0
		for i, h in ipairs(heights) do
			if shown >= MenuRoomLayout.MAX_NOTES then break end
			if not (skip and skip[i]) then
				local bottom = y + h * scale
				if bottom > availH then break end
				rects[#rects + 1] = { x = (corkW - w * scale) / 2, y = M + tilt / 2 + y, w = w * scale, h = h * scale }
				show[i] = true
				shown = shown + 1
				y = bottom + gap * scale
			end
		end
		return { scale = scale, shown = shown, rects = rects, show = show, gap = gap, top = top }
	end
	local best = fill(MenuRoomLayout.NOTE_GAP, MenuRoomLayout.NOTE_TOP)
	if best.shown < math.min(#heights, MenuRoomLayout.MAX_NOTES) then
		local tight = fill(MenuRoomLayout.NOTE_GAP_TIGHT, MenuRoomLayout.NOTE_TOP_TIGHT)
		if tight.shown > best.shown then best = tight end
	end
	-- the Rank note outranks the notes above it (the news): when it has no room they come off first, never the Rank
	if rank and heights[rank] and not best.show[rank] then
		local skip = {}
		for i = rank - 1, 1, -1 do
			skip[i] = true
			local try = fill(MenuRoomLayout.NOTE_GAP_TIGHT, MenuRoomLayout.NOTE_TOP_TIGHT, skip)
			if try.show[rank] then best = try; break end
		end
	end
	if keep and heights[keep] and not best.show[keep] then
		-- notes above the goal come off nearest first, but the Rank note is the last of them to go (it outranks the news)
		local order = {}
		for i = keep - 1, 1, -1 do
			if i ~= rank then order[#order + 1] = i end
		end
		if rank and rank < keep then order[#order + 1] = rank end
		local skip = {}
		for _, i in ipairs(order) do
			skip[i] = true
			local try = fill(MenuRoomLayout.NOTE_GAP_TIGHT, MenuRoomLayout.NOTE_TOP_TIGHT, skip)
			if try.show[keep] then
				best = try
				break
			end
		end
	end
	return best
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
	MenuLayout.corkRect = MenuRoomLayout.corkRect
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
