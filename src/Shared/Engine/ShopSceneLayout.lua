--[[
	Shared/Engine/ShopSceneLayout.lua
	Pure layout maths for the Counter v2 scene (the Shop overlay as a tavern counter with Marlo behind it). No Roblox
	calls, so it is unit tested. Rects are { x, y, w, h } in the play area's local pixels (the shop frame, right of the
	sidebar). Look only: nothing here knows about prices, offers or remotes.

	rects(W, H, counts) -> {
	  phone, area, wall, counter, surfaceY,          surfaceY = the counter's worn top surface line (items rest on it)
	  marlo,                                         painted Marlo (3:4), feet hidden behind the counter
	  offers = { rect... },                          Patron cards, hover HOVER_PX above surfaceY, one gentle arc
	  shadows = { rect... },                         soft oval contact shadow per offer, on the counter surface
	  packs = { rect... },                           packs rest ON the counter in front of the Patrons (no hover)
	  props = { bell, ledger, mug, candle },         bell = Reroll, ledger = Haggle; mug and candle are decor (nil on phones)
	  table,                                         the round card table every offer and pack lies on (nil on phones)
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
ShopSceneLayout.TABLE_PAD = 8        -- felt around the spread on the round card table

-- A hand-dealt look: every card lies at its own small fixed angle (degrees, at most 2), the same every visit. Offers use
-- index 1 to n, packs n + 1 on, so neighbours never lean the same way.
local TILTS = { -1.6, 1.1, -0.7, 1.7, -1.2, 0.8, -1.9, 1.4 }
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

local function lerpArc(i, n, amp)
	if n <= 1 then return -amp end
	local mid = (n + 1) / 2
	local t = (i - mid) / (mid - 1)
	return -amp * (1 - t * t) -- centre cards ride higher, the ends sit lower
end

function ShopSceneLayout.rects(W, H, counts)
	W, H = math.max(W, 1), math.max(H, 1)
	local nOffers = (counts and counts.offers) or 3
	local nPacks = (counts and counts.packs) or 2
	local phone = ShopSceneLayout.isPhone(W, H)
	local out = { phone = phone, area = rect(0, 0, W, H), wall = rect(0, 0, W, H) }

	-- controls along the top
	local tabsW = phone and (W - 16) or clamp(W * 0.5, 300, 560)
	out.tabs = rect((W - tabsW) / 2, 8, tabsW, 34)
	local bossW = clamp(tabsW * 0.8, 240, 460)
	out.nextBoss = rect((W - bossW) / 2, 46, bossW, 24)
	local tabsBottom = out.nextBoss.y + out.nextBoss.h

	local leaveW, leaveH = clamp(W * 0.14, 110, 180), 44
	out.leave = rect(W - leaveW - 12, H - leaveH - 12, leaveW, leaveH)

	local counterH = H * (phone and 0.50 or 0.34)
	local counterY = H - counterH
	out.counter = rect(0, counterY, W, counterH)
	out.surfaceY = math.floor(counterY + counterH * (phone and 0.12 or 0.32) + 0.5)

	local p = clamp(H * 0.08, 40, 100) -- prop size
	out.offers, out.shadows, out.packs = {}, {}, {}

	if not phone then
		local marloH = H * 0.62
		local marloW = marloH * ShopSceneLayout.MARLO_RATIO
		out.marlo = rect(W * 0.03, counterY + counterH * 0.10 - marloH, marloW, marloH)

		-- offers start right of Marlo's rect (his hand reaches the edge of it), never over him
		local x0 = out.marlo.x + out.marlo.w + 8
		local x1 = W * 0.86
		if counts and counts.noMarlo then
			-- no painted Marlo: centre offers and packs on the whole stage width
			x0, x1 = W * 0.08, W * 0.92
		end
		out.bandX0, out.bandX1 = math.floor(x0 + 0.5), math.floor(x1 + 0.5)
		-- Client/ShopCards lists cards with 16 px between them and 14 px padding at each end of the row, so the cards
		-- must fit the band minus that padding or the last one is clipped.
		local gap, pad = ShopSceneLayout.ROW_GAP, ShopSceneLayout.ROW_PAD
		local maxCardH = H * 0.42
		local n = math.max(nOffers, 1)
		local cardW = math.min((x1 - x0 - 2 * pad - gap * (n - 1)) / n, maxCardH * ShopSceneLayout.CARD_RATIO)
		local cardH = cardW / ShopSceneLayout.CARD_RATIO
		local rowW = cardW * n + gap * (n - 1)
		local startX = x0 + ((x1 - x0) - rowW) / 2
		local amp = H * 0.015
		for i = 1, nOffers do
			local x = startX + (i - 1) * (cardW + gap)
			local y = out.surfaceY - ShopSceneLayout.HOVER_PX - cardH + lerpArc(i, nOffers, amp)
			out.offers[i] = rect(x, y, cardW, cardH)
			out.shadows[i] = rect(x + cardW * 0.1, out.surfaceY - 4, cardW * 0.8, 10)
		end
		-- packs rest on the counter in front of the Patrons
		local packH = counterH * 0.5
		local packW = math.min(packH * 0.8, (x1 - x0 - 2 * pad - gap * (math.max(nPacks, 1) - 1)) / math.max(nPacks, 1))
		packH = packW / 0.8
		local packRow = packW * nPacks + gap * (math.max(nPacks, 1) - 1)
		local px = x0 + ((x1 - x0) - packRow) / 2
		for i = 1, nPacks do
			out.packs[i] = rect(px + (i - 1) * (packW + gap), out.surfaceY - 2, packW, packH)
		end
		-- props: ledger and mug at the left end, bell and candle at the far right, resting on the surface
		local propY = out.surfaceY + counterH * 0.08
		local lw = p * 1.25
		out.props = {
			ledger = rect(W * 0.02, propY - p * 0.7, lw, p * 0.8),
			mug = rect(W * 0.02 + lw + 8, propY - p * 0.85, p * 0.9, p * 0.95),
			bell = rect(W * 0.875, propY - p * 0.8, p, p * 0.85),
			candle = rect(W * 0.875 + p + 6, propY - p * 1.05, p * 0.7, p * 1.1),
		}
		out.light = rect(x0, out.surfaceY - counterH * 0.1, x1 - x0, counterH * 0.55)
		-- the round card table: the whole spread (every offer and every pack) lies on it with a little felt around, between
		-- Marlo and the bell, under the tabs and Next boss strip, above the foot of the screen
		local top, bottom, left, right = math.huge, 0, math.huge, 0
		for _, r in ipairs(out.offers) do
			top, left, right = math.min(top, r.y), math.min(left, r.x), math.max(right, r.x + r.w)
		end
		for _, r in ipairs(out.packs) do
			bottom, left, right = math.max(bottom, r.y + r.h), math.min(left, r.x), math.max(right, r.x + r.w)
		end
		if #out.offers > 0 then
			local leftLimit = (counts and counts.noMarlo) and 4 or (out.marlo.x + out.marlo.w + 2)
			local tx0 = math.max(left - ShopSceneLayout.TABLE_PAD, leftLimit)
			local tx1 = math.min(right + ShopSceneLayout.TABLE_PAD, out.props.bell.x - 6)
			local ty0 = math.max(top - ShopSceneLayout.TABLE_PAD, tabsBottom + 6)
			local ty1 = math.min(math.max(bottom, out.surfaceY) + ShopSceneLayout.TABLE_PAD, H - 6)
			if ty1 > out.leave.y - 4 and tx1 > out.leave.x - 6 then
				tx1 = math.max(right + 2, out.leave.x - 6) -- the Next Round sign stands at the table's corner: cut back, never through a card
			end
			out.table = rect(tx0, ty0, tx1 - tx0, ty1 - ty0)
		end
		-- speech plate near Marlo's shoulder, above the offers
		local bubbleW, bubbleH = clamp(W * 0.22, 180, 320), 54
		out.bubble = rect(out.marlo.x + out.marlo.w * 0.7, tabsBottom + 10, bubbleW, bubbleH)
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
		out.bubble = rect(bx, out.marlo.y, W - bx - 8, 54)
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
	if badgeW and badgeW > 0 then
		out.badge = { x = 12, y = y, w = badgeW, h = 22 }
		y = y + 28
	end
	for i, cw in ipairs(chipWidths or {}) do
		out.chips[i] = { x = 12, y = y, w = cw, h = 24 }
		y = y + 28
	end
	out.price = { x = W - 12 - ShopSceneLayout.TAG_W, y = bannerTop - 4 - ShopSceneLayout.TAG_H,
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
		local s = math.min(rc.w / baseW, (rc.h - 36) / baseArt)
		return clamp(s, ShopSceneLayout.SCALE_MIN, ShopSceneLayout.SCALE_MAX)
	end
	local patron = fit(r.offers[1], 220, 250) or 1
	local pack = fit(r.packs[1], 220, 210) or patron
	return { patron = patron, pack = pack }
end

-- Rects of the two scrolling card rows (transparent containers; the cards inside are centred). A row is the cards
-- plus 16 px headroom above and 12 below (Client/ShopCards). Patron cards float HOVER_PX above the surface.
-- hP and hK are the row heights ShopCards.rowHeight reports.
function ShopSceneLayout.rows(r, hP, hK)
	local out = {}
	local x0, x1 = r.bandX0 or 8, r.bandX1 or (r.area.w - 8)
	if r.offers[1] then
		local y = r.phone and (r.offers[1].y - 16) or (r.surfaceY - ShopSceneLayout.HOVER_PX - (hP - 12))
		out.patron = rect(x0, y, x1 - x0, hP)
	end
	if r.packs[1] then
		out.pack = rect(x0, r.packs[1].y - 16, x1 - x0, hK)
	end
	return out
end

-- Free zone for the My Patrons / My Recipes tabs: right of Marlo, below the tab bar, above Next Round.
-- Coordinates are in shopFrame space; the lists live in a content area at (10, 84).
ShopSceneLayout.TAB_TOP, ShopSceneLayout.TAB_BOTTOM_RESERVE = 84, 64
function ShopSceneLayout.tabZone(W, H, noMarlo)
	local r = ShopSceneLayout.rects(W, H, { offers = 1, packs = 0, noMarlo = noMarlo })
	local x0 = 10
	if r.marlo and not noMarlo then x0 = r.marlo.x + r.marlo.w + 12 end
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
