--[[
	Shared/Engine/ShopSceneLayout.lua
	Pure layout maths for the Counter v2 scene (the Shop overlay as a tavern counter with Marlo behind it). No Roblox
	calls, so it is unit tested. Rects are { x, y, w, h } in the play area's local pixels (the shop frame, right of the
	sidebar). Look only: nothing here knows about prices, offers or remotes.

	rects(W, H, counts) -> {
	  phone, area, wall, counter, surfaceY,          surfaceY = the counter's worn top surface line (items rest on it)
	  marlo,                                         painted Marlo (3:4), feet hidden behind the counter
	  offers = { rect... },                          Patron cards lying on the table in one row (a card is turned by cardTilt)
	  shadows = { rect... },                         soft oval contact shadow per offer, under its lower edge
	  packs = { rect... },                           smaller packs lying on the table under the Patrons
	  props = { bell, ledger, mug, candle },         bell = Reroll, ledger = Haggle; mug and candle are decor (nil on phones)
	  table, felt, fitted,                           the oval card table (its wood rim) and the felt inside it; every card, turned by its
	                                                 tilt, is inside the felt with TABLE_MARGIN to spare, which `fitted` says (false only
	                                                 when many cards crowd a small window). All nil on phones.
	  light,                                         warm light pool on the counter
	  tabs, nextBoss, leave, bubble                  controls and Marlo's speech plate
	}
	counts = { offers = n, packs = m } (defaults 3 and 2).
]]

local ShopSceneLayout = {}

ShopSceneLayout.HOVER_PX = 14        -- offers float this far above the counter surface
ShopSceneLayout.LIFT_PX = 6          -- extra lift on hover
ShopSceneLayout.BOB_PX = 5           -- gentle bob amplitude
ShopSceneLayout.BOB_PERIOD = 3.5     -- seconds
ShopSceneLayout.MARLO_RATIO = 0.75   -- width / height of shop_marlo_behind (3:4)
ShopSceneLayout.ROW_GAP, ShopSceneLayout.ROW_PAD = 16, 14 -- Client/ShopCards row: gap between cards, padding at each end
ShopSceneLayout.CARD_RATIO = 0.72    -- width / height of an offer card
ShopSceneLayout.MAX_AMBIENT = 14     -- cap on ambient objects (motes, glow, sway)
ShopSceneLayout.HOVER_OVERLAP = 0.15 -- offers may overlap Marlo by this share of his width
ShopSceneLayout.MIN_W, ShopSceneLayout.MIN_H = 320, 400
ShopSceneLayout.FACE_X0, ShopSceneLayout.FACE_X1, ShopSceneLayout.FACE_H = 0.25, 0.75, 0.35 -- Marlo's face: middle half of his rect, top 35 percent
ShopSceneLayout.BOSS_MAX_W = 620
ShopSceneLayout.BOSS_PAD = 28 -- text keeps this far inside the ornate gold ends
ShopSceneLayout.BOSS_H = 44 -- the Next boss plate: tall enough for 18 px text inside the painted gold frame
ShopSceneLayout.BUBBLE_H = 58 -- Marlo's parchment speech plate: two lines of 16 px
ShopSceneLayout.TAB_GAP = 12 -- clear space between the tab row and the Next boss line
ShopSceneLayout.MIN_TOUCH = 44 -- smallest height of a tappable control (tabs, Next Round)

-- The round card table: a wide oval (a rounded rectangle with half-circle ends, the same shape as the Menu room's felt table) with a
-- wood rim; every card lies on the felt, TABLE_MARGIN clear of the rim.
ShopSceneLayout.TABLE_RIM = 14       -- width of the wood rim around the felt (px; 12 to 16)
ShopSceneLayout.TABLE_MARGIN = 18    -- clear felt between a card and the rim (px)
ShopSceneLayout.TABLE_ASPECT = 1.5   -- table width over height: wide, never a square
ShopSceneLayout.TABLE_EDGE = 8       -- gap between the table and the foot of the screen
ShopSceneLayout.TABLE_FOOT = 30      -- the table's lower edge stays at least this far above the Next Round sign
ShopSceneLayout.TABLE_WIDTH = 0.88   -- the table takes this share of the room between Marlo and the bell (it was too big, over the shelves)
ShopSceneLayout.PACK_RATIO = 0.8     -- width / height of a pack's rect
ShopSceneLayout.PACK_SHARE_MIN = 0.4 -- the smallest share a pack may lie at to keep Patron cards at OFFER_GOAL_W
ShopSceneLayout.PACK_SHARE = 0.75    -- a pack is this share of a Patron card's width: packs lie smaller
ShopSceneLayout.DEAL_GAP = 8         -- between the Patron row and the pack row
ShopSceneLayout.OFFER_GOAL_W = 190  -- a normal offer card is at least this wide (230 tall) when the room can hold it: packs go beside the Patrons before the Patrons shrink
ShopSceneLayout.OFFER_MAX_W = 250    -- a lone offer never grows past this wide (about 250 x 320 at 1920 x 957)
ShopSceneLayout.READABLE_SCALE = 0.5-- the table grows taller on a small window until its Patron cards reach this card scale

-- A hand-dealt look: every card lies at its own visible, fixed angle (degrees), the same every visit: -5, +4, -3, +4 by slot. Offers
-- use slot 1 to n, packs go on from n + 1, so neighbours never lean the same way.
local TILTS = { -1.5, 1, -1, 1.5 } -- at most 1.5 degrees: names stay readable
function ShopSceneLayout.cardTilt(index)
	return TILTS[((math.max(1, math.floor(index)) - 1) % #TILTS) + 1]
end

-- Crop rects (fractions of the generated 3:2 picture) for the pieces the model drew with empty margin.
-- shop_counter_props is one image with four props in a row; ImageRectOffset/Size are in the picture's pixels.
ShopSceneLayout.PROP_CROP = {
	bell = { 0.02, 0.36, 0.20, 0.38 },
	ledger = { 0.24, 0.35, 0.25, 0.37 },
	mug = { 0.55, 0.36, 0.21, 0.37 },
	candle = { 0.79, 0.29, 0.19, 0.45 },
}
-- shop_counter_top: the counter sits in the lower part of its picture.
ShopSceneLayout.COUNTER_CROP = { 0.0, 0.36, 1.0, 0.50 }

local function clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end
local function rect(x, y, w, h) return { x = math.floor(x + 0.5), y = math.floor(y + 0.5), w = math.floor(w + 0.5), h = math.floor(h + 0.5) } end

function ShopSceneLayout.intersects(a, b)
	return a.x < b.x + b.w and b.x < a.x + a.w and a.y < b.y + b.h and b.y < a.y + a.h
end

function ShopSceneLayout.overlapArea(a, b)
	local w = math.min(a.x + a.w, b.x + b.w) - math.max(a.x, b.x)
	local h = math.min(a.y + a.h, b.y + b.h) - math.max(a.y, b.y)
	if w <= 0 or h <= 0 then return 0 end
	return w * h
end

function ShopSceneLayout.inside(r, area)
	return r.x >= area.x and r.y >= area.y and r.x + r.w <= area.x + area.w and r.y + r.h <= area.y + area.h
end

-- Phones: portrait or very narrow play areas.
function ShopSceneLayout.isPhone(W, H)
	return W < 600 or W < H
end

-- The four corners of rect r turned by deg degrees about its centre (how a tilted card sits).
function ShopSceneLayout.corners(r, deg)
	local cx, cy = r.x + r.w / 2, r.y + r.h / 2
	local t = math.rad(deg or 0)
	local c, s = math.cos(t), math.sin(t)
	local out = {}
	for i, d in ipairs({ { -1, -1 }, { 1, -1 }, { 1, 1 }, { -1, 1 } }) do
		local dx, dy = d[1] * r.w / 2, d[2] * r.h / 2
		out[i] = { x = cx + dx * c - dy * s, y = cy + dx * s + dy * c }
	end
	return out
end

-- Is the point inside the table (a rounded rectangle whose ends are half circles of radius h / 2), shrunk by `inset` px all round?
-- inset = TABLE_RIM gives the felt, TABLE_RIM + TABLE_MARGIN the area a card may use.
function ShopSceneLayout.insideTable(t, inset, x, y)
	local w, h = t.w - 2 * inset, t.h - 2 * inset
	if w <= 0 or h <= 0 then return false end
	local r = math.min(w, h) / 2
	local cx, cy = t.x + t.w / 2, t.y + t.h / 2
	local dx = math.max(math.abs(x - cx) - (w / 2 - r), 0)
	local dy = math.max(math.abs(y - cy) - (h / 2 - r), 0)
	return dx * dx + dy * dy <= r * r + 1e-6
end

-- True when all four corners of rect r, turned by deg, lie inside the table shrunk by `inset`.
function ShopSceneLayout.cardOnTable(t, r, deg, inset)
	for _, pt in ipairs(ShopSceneLayout.corners(r, deg)) do
		if not ShopSceneLayout.insideTable(t, inset, pt.x, pt.y) then return false end
	end
	return true
end

-- Deals the spread onto the table: one row of Patron cards and, under it, a row of smaller packs, both centred on the table. It takes
-- the biggest cards (width up to wMax) for which every corner of every card, turned by its own tilt, lies on the felt with
-- TABLE_MARGIN to spare, then the vertical spot that keeps the wide Patron row nearest the middle of the table. Returns two lists of
-- rounded rects (offers, packs).
local function dealOnTable(tbl, nOffers, nPacks, wMax)
	local gap, gapV = ShopSceneLayout.ROW_GAP, ShopSceneLayout.DEAL_GAP
	local inset = ShopSceneLayout.TABLE_RIM + ShopSceneLayout.TABLE_MARGIN + 1 -- one spare pixel for the rounding below
	local cx, cy = tbl.x + tbl.w / 2, tbl.y + tbl.h / 2
	-- The rects are the real cards (Engine/CardShape: 220 wide, the art 250 or 210 tall at scale 1, plus a 36 px name ribbon that does not
	-- scale). Client/ShopCards never draws a card below SCALE_MIN (see cardScales), so the layout never plans one smaller than that.
	local minW = ShopSceneLayout.SCALE_MIN * 220
	local function offerH(w) return 250 * w / 220 + 36 end
	local function packH(w) return 210 * w / 220 + 36 end
	local function build(w, yTop)
		local ho = offerH(w)
		local wp = math.max(w * ShopSceneLayout.PACK_SHARE, minW)
		local hp = packH(wp)
		local offers, packs = {}, {}
		local rowW = w * nOffers + gap * math.max(nOffers - 1, 0)
		for i = 1, nOffers do
			offers[i] = { x = cx - rowW / 2 + (i - 1) * (w + gap), y = yTop, w = w, h = ho }
		end
		local py = yTop + (nOffers > 0 and ho + gapV or 0)
		local packW = wp * nPacks + gap * math.max(nPacks - 1, 0)
		for i = 1, nPacks do
			packs[i] = { x = cx - packW / 2 + (i - 1) * (wp + gap), y = py, w = wp, h = hp }
		end
		local total = (nOffers > 0 and ho or 0) + ((nOffers > 0 and nPacks > 0) and gapV or 0) + (nPacks > 0 and hp or 0)
		return offers, packs, total, (nOffers > 0 and ho or 0)
	end
	local function fits(offers, packs)
		local index = 0
		for _, list in ipairs({ offers, packs }) do
			for _, r in ipairs(list) do
				index = index + 1
				if not ShopSceneLayout.cardOnTable(tbl, r, ShopSceneLayout.cardTilt(index), inset) then return false end
			end
		end
		return true
	end
	local function attempt(w)
		local _, _, total, ho = build(w, 0)
		local free = tbl.h - 2 * inset - total
		if free < 0 then return nil end
		local best, bestScore
		for k = 0, 12 do
			local yTop = tbl.y + inset + free * (k / 12)
			local offers, packs = build(w, yTop)
			if fits(offers, packs) then
				local score = math.abs(yTop + ho / 2 - cy)
				if not bestScore or score < bestScore then best, bestScore = { offers, packs }, score end
			end
		end
		return best
	end
	local top = math.floor(wMax)
	local w, found = top, nil
	while w >= minW and not found do
		found = attempt(w)
		if not found then w = w - 8 end
	end
	if found and w < top then -- the coarse step went past the best fit: climb back in 2 px steps
		for up = math.min(w + 6, top), w + 2, -2 do
			local better = attempt(up)
			if better then
				found = better
				break
			end
		end
	end
	local fitted = found ~= nil
	if not found then -- nothing fits even at the smallest size (a tiny window): centre the smallest spread anyway
		local _, _, total = build(minW, 0)
		found = { build(minW, math.max(cy - total / 2, tbl.y + ShopSceneLayout.TABLE_RIM)) } -- never above the felt (Marlo's speech plate is there)
	end
	local function rounded(list)
		local out = {}
		for i, r in ipairs(list) do out[i] = rect(r.x, r.y, r.w, r.h) end
		return out
	end
	return rounded(found[1]), rounded(found[2]), fitted
end


-- ONE painted room (shop_room_a, 1536 x 1024): the room image is cover-cropped (Roblox ScaleType Crop, centred) over the play area and
-- every rect below is a fraction of that picture, mapped through the crop. Fractions are x from the left, y from the top.
ShopSceneLayout.ROOM = {
	w = 1536, h = 1024,
	felt = { 0.38, 0.61, 0.85, 0.77 },        -- the green felt of the round table
	rim = { 0.35, 0.585, 0.875, 0.83 },       -- the wood rim around the felt
	counterTop = 0.47,                        -- the counter's back edge (where its top surface starts)
	surface = 0.53,                           -- the front edge of the counter top: Patron cards may rise to here, no higher
	counterFront = 716 / 1024,                -- foot of the counter's front panel (measured: the floor's dark line is row 716)
	counterBack = 486 / 1024,                 -- the counter's back edge: row 485 is the dark shadow line, row 486 the first bright top row
	waist = 0.04,                             -- Marlo's waist stands this share of the picture height BELOW the back edge (about 40 px)
	counterX = { 0.03, 0.85 },
	rail = 0.56,                              -- the brass rail
	ledger = { 0.14, 0.462, 0.18, 0.1125 },   -- centre x, centre y, width, height (the open book with the quill; 1.5x, same base on the counter)
	bell = { 0.73, 0.47, 0.05, 0.065 },       -- the brass service bell
	arch = { 0.84, 0.10, 1.0, 0.64 },         -- the stone archway: the way out
	shopkeeper = { 0.20, 0.10, 0.45, 0.50 },  -- the clear wall behind the counter where Marlo stands
	clipY = 0.49,                             -- Marlo's feet are hidden at this line (the counter top)
	marloH = 0.42, marloX = 0.325,            -- Marlo's height (share of the picture's height) and centre x
	deal = { 0.395, 0.455, 0.835, 0.82 },     -- the region the dealt cards lie in: x0, top, x1, bottom
}

-- The picture's cover-crop mapping: scale, offset and size of the 1536 x 1024 picture over a W x H play area (centred, may overflow).
function ShopSceneLayout.pic(W, H)
	local R = ShopSceneLayout.ROOM
	local s = math.max(W / R.w, H / R.h)
	local pw, ph = R.w * s, R.h * s
	return { x = (W - pw) / 2, y = (H - ph) / 2, w = pw, h = ph, scale = s }
end

-- A fraction rect (x0, y0, x1, y1 of the picture) in the play area's local pixels.
function ShopSceneLayout.picRect(W, H, x0, y0, x1, y1)
	local p = ShopSceneLayout.pic(W, H)
	return rect(p.x + x0 * p.w, p.y + y0 * p.h, (x1 - x0) * p.w, (y1 - y0) * p.h)
end

-- Rect around a centre point: cx, cy, w, h are fractions of the picture's width and height.
local function picCentred(W, H, c)
	local p = ShopSceneLayout.pic(W, H)
	local w, h = c[3] * p.w, c[4] * p.h
	return rect(p.x + c[1] * p.w - w / 2, p.y + c[2] * p.h - h / 2, w, h)
end

local function boundsOf(r, deg)
	local lo, hi = { x = math.huge, y = math.huge }, { x = -math.huge, y = -math.huge }
	for _, pt in ipairs(ShopSceneLayout.corners(r, deg)) do
		lo.x, lo.y = math.min(lo.x, pt.x), math.min(lo.y, pt.y)
		hi.x, hi.y = math.max(hi.x, pt.x), math.max(hi.y, pt.y)
	end
	return { x = lo.x, y = lo.y, w = hi.x - lo.x, h = hi.y - lo.y }
end

-- Deals the spread on the painted felt: the Patron row, then the smaller pack row under it, both centred on the region's middle, the
-- block resting on the region's bottom so the lower parts of the cards lie on the felt and the tops rise over the counter front. The
-- biggest cards (width up to wMax) for which every card, turned by its tilt, stays inside the region and clear of every keep-out rect.
local function dealInRoom(region, keep, nOffers, nPacks, wMax, felt, minClear, rim)
	local gapV = ShopSceneLayout.DEAL_GAP
	-- Neighbours in a row keep minClear px between their turned outlines: the row gap grows with the card height (a tilt of up to 4
	-- degrees swings a card's corners about 7 percent of its height sideways). Client/ShopCards lays the row out with this gap.
	local function gapFor(h) return math.max(ShopSceneLayout.ROW_GAP, math.ceil(minClear + 0.07 * h + 2)) end
	local cx = region.x + region.w / 2
	local minW = ShopSceneLayout.SCALE_MIN * 220
	local share = ShopSceneLayout.PACK_SHARE -- packs may shrink (down to PACK_SHARE_MIN) before the Patron cards fall under OFFER_GOAL_W
	local function build(w)
		local ho = nOffers > 0 and (250 * w / 220 + 36) or 0
		local wp = math.max(w * share, minW)
		local hp = nPacks > 0 and (210 * wp / 220 + 36) or 0
		local gap = gapFor(math.max(ho, hp))
		local total = ho + hp + ((nOffers > 0 and nPacks > 0) and gapV or 0)
		local yTop = region.y + region.h - total - (0.06 * w + 2) -- a turned card reaches a little below its rect
		local offers, packs = {}, {}
		local rowW = w * nOffers + gap * math.max(nOffers - 1, 0)
		for i = 1, nOffers do offers[i] = { x = cx - rowW / 2 + (i - 1) * (w + gap), y = yTop, w = w, h = ho } end
		local py = yTop + (nOffers > 0 and ho + gapV or 0)
		local packW = wp * nPacks + gap * math.max(nPacks - 1, 0)
		for i = 1, nPacks do packs[i] = { x = cx - packW / 2 + (i - 1) * (wp + gap), y = py, w = wp, h = hp } end
		return offers, packs
	end
	local function fits(offers, packs)
		local index, boxes = 0, {}
		for li, list in ipairs({ offers, packs }) do
			for _, r in ipairs(list) do
				index = index + 1
				local deg = ShopSceneLayout.cardTilt(index)
				local b = boundsOf(r, deg)
				if b.x < region.x or b.y < region.y or b.x + b.w > region.x + region.w or b.y + b.h > region.y + region.h then return false end
				for _, k in ipairs(keep) do -- (3 px of slack: the rects are rounded after this check)
					if ShopSceneLayout.intersects(b, { x = k.x - 3, y = k.y - 3, w = k.w + 6, h = k.h + 6 }) then return false end
				end
				-- on the felt: the whole card between its left and right rims, and its lower corners inside the oval
				if felt then
					if b.x < felt.x + minClear or b.x + b.w > felt.x + felt.w - minClear then return false end
					local cs = ShopSceneLayout.corners(r, deg)
					for c = 3, 4 do -- (the cards rest low on the felt, so their feet may reach the wood rim but not leave the table)
						if not ShopSceneLayout.insideTable(rim, 0, cs[c].x, cs[c].y) then return false end
					end
				end
				for _, o in ipairs(boxes) do
					local pad = (o.list == li) and minClear or 0
					if ShopSceneLayout.intersects({ x = b.x - pad, y = b.y, w = b.w + 2 * pad, h = b.h }, o) then return false end
				end
				boxes[#boxes + 1] = { x = b.x, y = b.y, w = b.w, h = b.h, list = li }
			end
		end
		return true
	end
	local function done(offers, packs, fitted, sideBySide)
		local function rounded(list)
			local out = {}
			for i, r in ipairs(list) do out[i] = rect(r.x, r.y, r.w, r.h) end
			return out
		end
		local hMax = math.max(offers[1] and offers[1].h or 0, packs[1] and packs[1].h or 0)
		return rounded(offers), rounded(packs), fitted, sideBySide, gapFor(hMax)
	end
	-- Stacked (Patrons, the smaller packs in a front row under them) is the look; on a small window its cards would be tiny, so the
	-- packs then stand beside the Patrons in one row (bottom aligned, a gap between the groups) and the cards get bigger.
	local function buildSide(w)
		local wp = math.max(w * share, minW)
		local ho = nOffers > 0 and (250 * w / 220 + 36) or 0
		local hp = nPacks > 0 and (210 * wp / 220 + 36) or 0
		local gap = gapFor(math.max(ho, hp))
		local offW = w * nOffers + gap * math.max(nOffers - 1, 0)
		local pkW = wp * nPacks + gap * math.max(nPacks - 1, 0)
		local between = (nOffers > 0 and nPacks > 0) and 28 or 0
		local x0 = cx - (offW + pkW + between) / 2
		local bottom = region.y + region.h - (0.06 * w + 2)
		local offers, packs = {}, {}
		for i = 1, nOffers do offers[i] = { x = x0 + (i - 1) * (w + gap), y = bottom - ho, w = w, h = ho } end
		for i = 1, nPacks do packs[i] = { x = x0 + offW + between + (i - 1) * (wp + gap), y = bottom - hp, w = wp, h = hp } end
		return offers, packs
	end
	local stackW, stackShare
	local goal = math.min(ShopSceneLayout.OFFER_GOAL_W, math.floor(wMax))
	for _, sh in ipairs({ ShopSceneLayout.PACK_SHARE, 0.62, 0.5, ShopSceneLayout.PACK_SHARE_MIN }) do
		share = sh
		for w = math.floor(wMax), minW, -2 do
			local offers, packs = build(w)
			if fits(offers, packs) then
				if not stackW or w > stackW then stackW, stackShare = w, sh end
				if w >= goal then return done(offers, packs, true, false) end
				break
			end
		end
		if nPacks == 0 then break end
	end
	share = ShopSceneLayout.PACK_SHARE
	for w = math.floor(wMax), minW, -2 do
		if stackW and w <= stackW then break end
		local offers, packs = buildSide(w)
		if fits(offers, packs) then return done(offers, packs, true, true) end
	end
	if stackW then
		share = stackShare
		local offers, packs = build(stackW)
		return done(offers, packs, true, false)
	end
	local offers, packs = build(minW) -- nothing fits (a tiny window): the smallest spread, resting on the felt anyway
	return done(offers, packs, false, false)
end

local function roomRects(W, H, out, nOffers, nPacks)
	local R = ShopSceneLayout.ROOM
	local p = ShopSceneLayout.pic(W, H)
	out.room = true
	out.pic = rect(p.x, p.y, p.w, p.h)
	out.table = ShopSceneLayout.picRect(W, H, R.rim[1], R.rim[2], R.rim[3], R.rim[4])
	out.felt = ShopSceneLayout.picRect(W, H, R.felt[1], R.felt[2], R.felt[3], R.felt[4])
	out.counter = ShopSceneLayout.picRect(W, H, R.counterX[1], R.counterTop, R.counterX[2], R.counterFront)
	out.surfaceY = math.floor(p.y + R.surface * p.h + 0.5)
	out.clipY = math.floor(p.y + R.clipY * p.h + 0.5)
	out.arch = ShopSceneLayout.picRect(W, H, R.arch[1], R.arch[2], R.arch[3], R.arch[4])
	out.shopkeeper = ShopSceneLayout.picRect(W, H, R.shopkeeper[1], R.shopkeeper[2], R.shopkeeper[3], R.shopkeeper[4])
	out.light = rect(0, 0, 0, 0)
	out.props = { ledger = picCentred(W, H, R.ledger), bell = picCentred(W, H, R.bell) }
	-- the picture is cover-cropped, so on a 4:3 window the bigger ledger's edge can fall off screen: keep its hit area on screen
	do
		local l = out.props.ledger
		out.props.ledger = rect(clamp(l.x, 4, math.max(4, W - l.w - 4)), l.y, l.w, l.h)
	end

	-- Marlo stands behind the counter: his height follows the picture (so the counter), his feet go below clipY and are clipped there
	local marloH = R.marloH * p.h
	local marloW = marloH * ShopSceneLayout.MARLO_RATIO
	-- his waist is R.waist of the picture below the counter's back edge, with no clipping: the counter band drawn over him hides his lower body
	local waistY = p.y + (R.counterBack + R.waist) * p.h
	out.marlo = rect(p.x + R.marloX * p.w - marloW / 2, waistY - marloH, marloW, marloH)
	-- the counter band: the same picture cropped from the back edge to the foot of the front, at the same scale and place as the room
	out.counterBand = ShopSceneLayout.picRect(W, H, R.counterX[1], R.counterBack, R.counterX[2], R.counterFront)

	-- Next Round: the plate sits on the stone doorway itself, bottom centre of the arch opening, clamped on screen
	local leaveW, leaveH = clamp(W * 0.11, 104, 220), 64
	local archMid = out.arch.x + out.arch.w / 2
	local leaveY = out.arch.y + out.arch.h - leaveH - 10
	out.leave = rect(clamp(archMid - leaveW / 2, 8, W - leaveW - 8), clamp(leaveY, 8, H - leaveH - 12), leaveW, leaveH)

	-- Marlo's face is the top of his middle half (FACE_*): the Next boss strip slides right of it when the centred strip would cover
	-- it, and his speech plate starts right of the face, never over it
	local faceRight = out.marlo.x + out.marlo.w * ShopSceneLayout.FACE_X1
	local faceBottom = out.marlo.y + out.marlo.h * ShopSceneLayout.FACE_H
	local nb = out.nextBoss
	if nb.y < faceBottom and nb.x < faceRight and nb.x + nb.w > out.marlo.x + out.marlo.w * ShopSceneLayout.FACE_X0 then
		nb.x = clamp(faceRight + 8, 8, math.max(8, W - nb.w - 8))
	end
	local bubbleW, bubbleH = clamp(W * 0.22, 180, 320), ShopSceneLayout.BUBBLE_H
	local tabsBottom = nb.y + nb.h
	out.bubble = rect(clamp(faceRight + 8, 8, W - bubbleW - 8), tabsBottom + 10, bubbleW, bubbleH)

	-- the dealt cards: inside the region, clear of the bell and ledger (with their name plates), the arch, Marlo's wall and Next Round
	local tagH = 28 + 12 + 4 -- the plate under a prop: ShopStage TAG_H + TAG_GAP + 4
	local function withTag(r, padX) return { x = r.x - padX, y = r.y, w = r.w + 2 * padX, h = r.h + tagH } end
	out.keepOut = {
		-- (the Reroll plate stands under the offers now, so the bell carries no name plate: only the bell itself is kept clear)
		{ x = out.props.bell.x - 30, y = out.props.bell.y, w = out.props.bell.w + 60, h = out.props.bell.h },
		withTag(out.props.ledger, 0), out.arch, out.shopkeeper,
		out.leave, out.tabs, out.nextBoss,
	}
	local region = ShopSceneLayout.picRect(W, H, R.deal[1], R.deal[2], R.deal[3], R.deal[4])
	local gap, pad = ShopSceneLayout.ROW_GAP + 0.02 * p.w, ShopSceneLayout.ROW_PAD
	local n = math.max(nOffers, 1)
	local wMax = math.min((region.w - 2 * pad - gap * (n - 1)) / n, H * 0.42 * ShopSceneLayout.CARD_RATIO, ShopSceneLayout.OFFER_MAX_W)
	local minClear = math.max(0.02 * p.w, 8)
	out.offers, out.packs, out.fitted, out.sideBySide, out.cardGap = dealInRoom(region, out.keepOut, nOffers, nPacks, wMax, out.felt, minClear, out.table)
	out.deal = region
	-- on a small screen an unfitted row can graze the Next Round plate: slide the plate down just clear of the cards it touches
	for _, o in ipairs(out.offers) do
		if ShopSceneLayout.intersects(o, out.leave) then
			out.leave = rect(out.leave.x, math.min(o.y + o.h + 4, H - leaveH - 8), out.leave.w, leaveH)
		end
	end
	out.bandX0, out.bandX1 = region.x, region.x + region.w
	if out.sideBySide then -- each row is only as wide as its own cards, so it centres them where they were dealt
		local function band(list)
			if not list[1] then return nil end
			local last = list[#list]
			return { x0 = list[1].x - pad, x1 = last.x + last.w + pad }
		end
		out.patronBand, out.packBand = band(out.offers), band(out.packs)
	end
	for i, r in ipairs(out.offers) do
		out.shadows[i] = rect(r.x + r.w * 0.1, r.y + r.h - 6, r.w * 0.8, 12)
	end
	return out
end

function ShopSceneLayout.rects(W, H, counts)
	W, H = math.max(W, 1), math.max(H, 1)
	local nOffers = (counts and counts.offers) or 3
	local nPacks = (counts and counts.packs) or 2
	local phone = ShopSceneLayout.isPhone(W, H)
	local out = { phone = phone, area = rect(0, 0, W, H), wall = rect(0, 0, W, H) }

	-- controls along the top
	local tabsW = phone and (W - 16) or clamp(W * 0.5, 300, 560)
	out.tabs = rect((W - tabsW) / 2, 2, tabsW, ShopSceneLayout.MIN_TOUCH) -- a touch target: at least 44 px tall
	local bossW = clamp(W * 0.32, 240, ShopSceneLayout.BOSS_MAX_W) -- 614 at 1920, narrower on small screens so it stays clear of the corner toast stack
	out.nextBoss = rect((W - bossW) / 2, 2 +ShopSceneLayout.MIN_TOUCH + ShopSceneLayout.TAB_GAP, bossW, ShopSceneLayout.BOSS_H) -- BOSS_H is the painted plate's height (ShopStage draws it at this rect, so nothing sticks out into the offers)
	local tabsBottom = out.nextBoss.y + out.nextBoss.h

	local leaveW, leaveH = clamp(W * 0.14, 110, 220), 64
	out.leave = rect(W - leaveW - 12, H - leaveH - 12, leaveW, leaveH)

	local counterH = H * (phone and 0.50 or 0.34)
	local counterY = H - counterH
	out.counter = rect(0, counterY, W, counterH)
	out.surfaceY = math.floor(counterY + counterH * (phone and 0.12 or 0.32) + 0.5)

	local p = clamp(H * 0.08, 40, 100) -- prop size
	out.offers, out.shadows, out.packs = {}, {}, {}

	if counts and counts.room and not phone then return roomRects(W, H, out, nOffers, nPacks) end

	if not phone then
		local marloH = H * 0.62
		local marloW = marloH * ShopSceneLayout.MARLO_RATIO
		-- Marlo stands BEHIND the counter: his frame is clipped at the counter's back lip, so his waist and legs are hidden
		out.clipY = math.floor(counterY + counterH * 0.02 + 0.5)
		out.marlo = rect(W * 0.03, out.clipY + marloH * 0.30 - marloH, marloW, marloH)

		-- props: ledger and mug at the left end, bell and candle at the far right, resting on the surface
		local propY = out.surfaceY + counterH * 0.08
		local lw = p * 1.25
		out.props = {
			ledger = rect(W * 0.02, propY - p * 0.7, lw, p * 0.8),
			mug = rect(W * 0.02 + lw + 8, propY - p * 0.85, p * 0.9, p * 0.95),
			bell = rect(W * 0.875, propY - p * 0.8, p, p * 0.85),
			candle = rect(W * 0.875 + p + 6, propY - p * 1.05, p * 0.7, p * 1.1),
		}

		-- The round card table: a wide oval lying on the counter, right of Marlo (his hand reaches the edge of his rect, never over him)
		-- and left of the bell, under the tabs and the Next boss strip, down to just above the foot of the screen, so its upper part
		-- overlaps the counter's back edge. The brass rail, the bell and the ledger stay clear of it.
		local noMarlo = counts and counts.noMarlo
		local leftLimit = noMarlo and 4 or (out.marlo.x + out.marlo.w + 2)
		local rightLimit = out.props.bell.x - 6
		-- the foot of the table stays at least TABLE_FOOT above the Next Round sign (and always above the bottom of the screen)
		local bottomLimit = math.min(H - ShopSceneLayout.TABLE_EDGE, out.leave.y - ShopSceneLayout.TABLE_FOOT)
		-- Marlo's speech plate sits near his shoulder under the tabs, above the offers: the table starts below it
		local bubbleW, bubbleH = clamp(W * 0.22, 180, 320), ShopSceneLayout.BUBBLE_H
		out.bubble = rect(out.marlo.x + out.marlo.w * 0.7, tabsBottom + 10, bubbleW, bubbleH)
		local topLimit = out.bubble.y + out.bubble.h + 6
		local avail = math.max(rightLimit - leftLimit, 80)
		local tw = math.min(avail, W * 0.62) * ShopSceneLayout.TABLE_WIDTH
		local tx = leftLimit + (avail - tw) / 2
		if noMarlo then tx = clamp(W / 2 - tw / 2, leftLimit, math.max(leftLimit, rightLimit - tw)) end -- no painted Marlo: centred on the stage
		-- Client/ShopCards lists cards with 16 px between them and 14 px padding at each end of the row
		local gap, pad = ShopSceneLayout.ROW_GAP, ShopSceneLayout.ROW_PAD
		local n = math.max(nOffers, 1)
		local wMax = math.min((tw - 2 * pad - gap * (n - 1)) / n, H * 0.42 * ShopSceneLayout.CARD_RATIO)
		-- A wide oval. On a small window the cards would be tiny inside it, so it grows a little taller (never rounder than 1.25 wide to
		-- 1 tall): the most oval shape whose cards reach READABLE_SCALE wins, else the shape that gives the biggest cards.
		local best
		for _, aspect in ipairs({ ShopSceneLayout.TABLE_ASPECT, 1.4, 1.3, 1.25 }) do
			local th = math.min(tw / aspect, bottomLimit - topLimit)
			local t = rect(tx, bottomLimit - th, tw, th)
			local offers, packs, fitted = dealOnTable(t, nOffers, nPacks, wMax)
			local w = (offers[1] or packs[1] or { w = 0 }).w
			if not best or (fitted and (not best.fitted or w > best.w)) then
				best = { table = t, offers = offers, packs = packs, fitted = fitted, w = w }
			end
			if fitted and w >= ShopSceneLayout.READABLE_SCALE * 220 then break end
		end
		out.table, out.offers, out.packs = best.table, best.offers, best.packs
		out.fitted = best.fitted -- false only when too many cards crowd a small window (they still lie on the table, centred, over the margin)
		local rim = ShopSceneLayout.TABLE_RIM
		out.felt = rect(out.table.x + rim, out.table.y + rim, out.table.w - 2 * rim, out.table.h - 2 * rim)
		-- the card rows are centred on the table (Client/ShopCards centres its cards in the row), so the band IS the table's width
		out.bandX0, out.bandX1 = out.table.x, out.table.x + out.table.w
		out.light = rect(out.table.x, out.surfaceY - counterH * 0.1, out.table.w, counterH * 0.55)
		for i, r in ipairs(out.offers) do
			out.shadows[i] = rect(r.x + r.w * 0.1, r.y + r.h - 6, r.w * 0.8, 12) -- a soft oval under each Patron card
		end
	else
		local marloH = H * 0.24
		local marloW = marloH * ShopSceneLayout.MARLO_RATIO
		out.marlo = rect(8, counterY + counterH * 0.04 - marloH, marloW, marloH)
		-- two wrapped rows of items on the counter (Patrons first, then packs)
		out.bandX0, out.bandX1 = 8, math.floor(W - 8)
		local total = nOffers + nPacks
		local perRow = 3
		local rows = math.max(1, math.ceil(total / perRow))
		local top = out.surfaceY + 4
		local bottom = out.leave.y - 8
		local gap = 8
		local rowH = (bottom - top - gap * (rows - 1)) / rows
		local cardH = math.min(rowH, ((W - 16 - gap * (perRow - 1)) / perRow) / ShopSceneLayout.CARD_RATIO)
		local cardW = cardH * ShopSceneLayout.CARD_RATIO
		for k = 1, total do
			local row = math.ceil(k / perRow)
			local inRow = math.min(perRow, total - (row - 1) * perRow)
			local col = k - (row - 1) * perRow
			local rowW = cardW * inRow + gap * (inRow - 1)
			local x = (W - rowW) / 2 + (col - 1) * (cardW + gap)
			local y = top + (row - 1) * (cardH + gap)
			local r = rect(x, y, cardW, cardH)
			if k <= nOffers then
				out.offers[k] = r
				out.shadows[k] = rect(x + cardW * 0.1, y + cardH - 6, cardW * 0.8, 8)
			else
				out.packs[k - nOffers] = r
			end
		end
		-- bell and ledger sit on the counter's back edge, right of Marlo
		local by = counterY - p * 0.9
		out.props = {
			bell = rect(W - 8 - p, by, p, p * 0.85),
			ledger = rect(W - 8 - p - 8 - p * 1.25, by, p * 1.25, p * 0.8),
		}
		out.light = rect(8, out.surfaceY, W - 16, counterH * 0.4)
		local bx = out.marlo.x + out.marlo.w + 8
		out.bubble = rect(bx, out.marlo.y, W - bx - 8, ShopSceneLayout.BUBBLE_H)
	end
	return out
end

-- Overlays on an offer card, in the card body's local pixels (Client/ShopCards uses these). The badge (MEGA, JUMBO) sits
-- top left of the art, synergy chips stack under it, and the price tag sits at the lower right of the art just above the
-- name ribbon, so no tag covers a ribbon or chip. chipWidths = pixel width of each synergy chip.
ShopSceneLayout.TAG_W, ShopSceneLayout.TAG_H = 64, 28
function ShopSceneLayout.cardOverlays(W, artTop, artH, bannerTop, badgeW, chipWidths)
	local out = { chips = {} }
	local y = artTop + 6
	-- a tag never runs past the card: at most the art width less a 12 px margin each side (its text is scaled to fit, 12 px at least)
	local maxW = math.max(W - 24, 40)
	if badgeW and badgeW > 0 then
		out.badge = { x = 12, y = y, w = math.min(badgeW, maxW), h = 22 }
		y = y + 28
	end
	for i, cw in ipairs(chipWidths or {}) do
		out.chips[i] = { x = 12, y = y, w = math.min(cw, maxW), h = 24 }
		y = y + 28
	end
	-- the price plate hangs from the card under the name ribbon, never over the art (inside the body's price strip, 4 px margin)
	out.price = { x = math.floor((W - ShopSceneLayout.TAG_W) / 2), y = bannerTop + require(script.Parent.CardShape).BANNER_H + require(script.Parent.CardShape).PRICE_GAP,
		w = ShopSceneLayout.TAG_W, h = ShopSceneLayout.TAG_H }
	return out
end

-- Width of a chip or badge pill for a word at 15 px (a safe upper bound; the real text is never wider).
function ShopSceneLayout.pillWidth(word)
	return #word * 9 + 28
end

-- Fallback scene colours used when the painted wall art is missing: warm wall gradient above a wood counter band.
ShopSceneLayout.FALLBACK = {
	wallTop = { 70, 44, 28 }, wallBottom = { 150, 98, 52 }, counter = { 168, 118, 66 }, counterEdge = { 226, 184, 110 },
}

-- Card sizes (Engine/CardShape numbers at scale 1: patron 220 x (250 + 36), pack 220 x (210 + 36)) that fit the
-- offer and pack rects. Patrons and packs get their own scale because packs rest smaller on the counter.
ShopSceneLayout.SCALE_MIN, ShopSceneLayout.SCALE_MAX = 0.35, 1.35
function ShopSceneLayout.cardScales(r)
	local function fit(rc, baseW, baseArt)
		if not rc then return nil end
		local s = math.min(rc.w / baseW, (rc.h - 64) / baseArt) -- card h = art + 64 (ribbon 40 + price strip 36 - 12)
		return clamp(s, ShopSceneLayout.SCALE_MIN, ShopSceneLayout.SCALE_MAX)
	end
	local patron = fit(r.offers[1], 220, 250) or 1
	local pack = fit(r.packs[1], 220, 210) or patron
	return { patron = patron, pack = pack, gap = r.cardGap }
end

-- The Reroll plate (44 px tall, cream text): left aligned with the Patron row, directly under it. When the pack row under the Patrons
-- starts far enough to the right it stands in that row's left margin (so it never sits under a pack), else under the last row. Rects
-- are the dealt (untilted) card rects plus a 10 px allowance for the tilt.
ShopSceneLayout.REROLL_W, ShopSceneLayout.REROLL_H, ShopSceneLayout.REROLL_AIR = 190, 44, 24
function ShopSceneLayout.rerollPlate(r)
	local o, k = r.offers and r.offers[1], r.packs and r.packs[1]
	if not o then return nil end
	local w, h, air = ShopSceneLayout.REROLL_W, ShopSceneLayout.REROLL_H, ShopSceneLayout.REROLL_AIR
	local y = o.y + o.h + air
	if k then
		if k.y < o.y + o.h then y = math.max(o.y + o.h, k.y + k.h) + air -- packs beside the Patrons (one row): under the whole row
		elseif k.x - o.x - 8 >= w then y = k.y else y = k.y + k.h + air end
	end
	local limit = r.area and r.area.h
	if limit then y = math.min(y, limit - h - 12) end
	-- centred under the Patron row, so the plate and its dice never touch a card name
	local last = r.offers[#r.offers]
	local x = o.x
	if not k then x = math.floor(o.x + (last.x + last.w - o.x - w) / 2) end
	return rect(math.max(x, o.x), y, w, h)
end

-- Rects of the two scrolling card rows (transparent containers; the cards inside are centred). A row is the cards
-- plus 16 px headroom above and 12 below (Client/ShopCards). Patron cards float HOVER_PX above the surface.
-- hP and hK are the row heights ShopCards.rowHeight reports.
function ShopSceneLayout.rows(r, hP, hK)
	local out = {}
	local x0, x1 = r.bandX0 or 8, r.bandX1 or (r.area.w - 8)
	if r.offers[1] then
		local y = r.offers[1].y - 16 -- the row's 16 px of headroom sits above the card
		local b = r.patronBand or { x0 = x0, x1 = x1 }
		out.patron = rect(b.x0, y, b.x1 - b.x0, hP)
	end
	if r.packs[1] then
		local b = r.packBand or { x0 = x0, x1 = x1 }
		out.pack = rect(b.x0, r.packs[1].y - 16, b.x1 - b.x0, hK)
	end
	return out
end

-- Free zone for the My Patrons / My Recipes tabs: right of Marlo, below the tab bar, above Next Round.
-- Coordinates are in shopFrame space; the lists live in a content area at (10, 84).
ShopSceneLayout.TAB_TOP, ShopSceneLayout.TAB_BOTTOM_RESERVE = 102, 80 -- 102: under the 40 px Next boss strip (ends at 94)
function ShopSceneLayout.tabZone(W, H, noMarlo, room)
	local r = ShopSceneLayout.rects(W, H, { offers = 1, packs = 0, noMarlo = noMarlo, room = room })
	local x0 = 10
	if r.marlo and not noMarlo then x0 = r.marlo.x + r.marlo.w + 32 end
	local x1 = W - 10
	local y0 = ShopSceneLayout.TAB_TOP
	return rect(x0, y0, math.max(x1 - x0, 1), math.max(H - ShopSceneLayout.TAB_BOTTOM_RESERVE - y0, 1)), r
end

-- Stacks rows (heights) top down inside the zone with a gap; returns one rect per row.
function ShopSceneLayout.stackRows(zone, heights, gap)
	local out, y = {}, zone.y
	for i, h in ipairs(heights) do
		out[i] = rect(zone.x, y, zone.w, h)
		y = y + h + (gap or 8)
	end
	return out
end

-- Soft oval contact shadow under an offer as it bobs: farther up means smaller, fainter and narrower.
-- phase is the bob offset in px (0 = rest, BOB_PX = highest). Returns { scale, transparency }.
function ShopSceneLayout.shadowFor(phase)
	local t = clamp((phase or 0) / ShopSceneLayout.BOB_PX, 0, 1)
	return { scale = 1 - 0.15 * t, transparency = 0.55 + 0.25 * t }
end

-- Bob offset in px for card i at time t (seconds), staggered; 0 when calm.
function ShopSceneLayout.bob(i, t, calm)
	if calm then return 0 end
	local s = math.sin((t / ShopSceneLayout.BOB_PERIOD) * 2 * math.pi + (i or 1) * 0.9)
	return (s * 0.5 + 0.5) * ShopSceneLayout.BOB_PX
end

return ShopSceneLayout
