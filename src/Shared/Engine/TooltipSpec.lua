--[[
	Shared/Engine/TooltipSpec.lua
	The one shared tooltip's look and placement rules (pure, tested). Client/Tooltip.lua draws it.

	A tooltip has exactly ONE border (the outer UIStroke) and padding inside it, so no line can ever run
	through the text: the old tooltip used polishPanel, which adds a gold ring AND an inner rim frame, and that
	inner rim cut through the text lines.

	Spec fields: borders (outer strokes, must be 1), innerRim (must be false), stroke (px), padX, padY,
	maxWidth (text wraps beyond it), gap (to the target), margin (to the screen edge).

	place(pos, size, tip, screen, align) -> x, y
	    pos/size = the target's AbsolutePosition/AbsoluteSize ({X,Y} tables), tip = tooltip size, screen = screen size.
	    Above the target with `gap`, below when there is no room above, clamped inside the screen by `margin`.
	    align "left": the tooltip's right edge lines up with the target's right edge (buttons on the right side).
	textClear(spec) -> true when the padding is wider than the border plus a 4px breathing space on every side.
	placeRow(...)    Counter offers: below or above the whole offer row.
	placeBeside(...) Counter packs: beside the pack row, clear of the offers and every control (Client/ShopTips feeds it).
	correct(...)     absorbs a shift between the written and the live position.
]]

local TooltipSpec = {}

TooltipSpec.Spec = {
	borders = 1,
	innerRim = false,
	stroke = 1.5,
	padX = 12,
	padY = 8,
	maxWidth = 280,
	gap = 8,
	sideGap = 12, -- Counter pack tooltips: distance from the pack row
	margin = 6,
	textSize = 16, -- never below 16: the painted serif size for every tooltip
	fontName = "Merriweather", -- Enum.Font name, the same serif as the plates and toggles
	textColor = { 235, 220, 190 }, -- cream on brown, the shared plate colours
	backColor = { 60, 42, 26 },
}

function TooltipSpec.textClear(spec)
	spec = spec or TooltipSpec.Spec
	return spec.borders == 1 and spec.innerRim == false
		and spec.padX >= spec.stroke + 4 and spec.padY >= spec.stroke + 4
end

function TooltipSpec.place(pos, size, tip, screen, align, spec)
	spec = spec or TooltipSpec.Spec
	if align == "right" then
		-- left HUD tooltips: to the right of the target (gap px away), top aligned with it, clamped on screen. It never
		-- sits over the target; with no room on the right it goes above the target's column instead.
		local x = pos.X + size.X + spec.gap
		if x + tip.X <= screen.X - spec.margin then
			local y = math.max(spec.margin, math.min(pos.Y, screen.Y - tip.Y - spec.margin))
			return x, y
		end
		align = nil
	end
	if align == "below" then
		-- under the target (pack picks: free space under the name plates), clamped on screen
		local bx = math.max(spec.margin, math.min(pos.X + size.X / 2 - tip.X / 2, screen.X - tip.X - spec.margin))
		local by = pos.Y + size.Y + spec.gap
		if by + tip.Y > screen.Y - spec.margin then
			-- no room under the target: go above it rather than being clamped up over its name plate
			by = math.max(spec.margin, pos.Y - tip.Y - spec.gap)
		end
		return bx, by
	end
	local x
	if align == "left" then
		x = pos.X + size.X - tip.X
	else
		x = pos.X + size.X / 2 - tip.X / 2
	end
	local y = pos.Y - tip.Y - spec.gap
	if y < spec.margin then
		y = pos.Y + size.Y + spec.gap
	end
	x = math.max(spec.margin, math.min(x, screen.X - tip.X - spec.margin))
	y = math.max(spec.margin, math.min(y, screen.Y - tip.Y - spec.margin))
	return x, y
end

-- placeRow(card, row, tip, screen) -> x, y
-- Counter offers: card = the hovered card's rect, row = the whole offer row's rect ({X,Y} tables, same space).
-- The tip sits centred on the card but entirely BELOW the row (so it covers no neighbouring plate, price tag or Buy
-- drawer), or entirely ABOVE the row when there is no room below, clamped inside the screen. With room on neither
-- side it goes below the row anyway, clamped (the row's own bottom edge is the last resort).
function TooltipSpec.placeRow(card, row, tip, screen, spec)
	spec = spec or TooltipSpec.Spec
	local x = math.max(spec.margin, math.min(card.X + card.W / 2 - tip.X / 2, screen.X - tip.X - spec.margin))
	local below = row.Y + row.H + spec.gap
	if below + tip.Y <= screen.Y - spec.margin then
		return x, below
	end
	local above = row.Y - tip.Y - spec.gap
	if above >= spec.margin then
		return x, above
	end
	return x, math.max(spec.margin, math.min(below, screen.Y - tip.Y - spec.margin))
end

local function overlapArea(a, b)
	local w = math.min(a.X + a.W, b.X + b.W) - math.max(a.X, b.X)
	local h = math.min(a.Y + a.H, b.Y + b.H) - math.max(a.Y, b.Y)
	if w <= 0 or h <= 0 then return 0 end
	return w * h
end

-- placeBeside(card, packs, blockers, tip, screen) -> x, y, info
-- Counter PACKS. Every rect is { X, Y, W, H } in screen space, tip and screen are { X, Y } sizes.
--   card     the hovered pack's slot
--   packs    every slot in the pack row (the hovered one included)
--   blockers rects the tip must never cover: the offer cards and their name plates, Haggle, Reroll, Next Round, the tabs
-- The tip opens SIDEWAYS: its left edge Spec.sideGap (12) px right of the last pack, centred on the hovered pack
-- vertically, clamped inside the screen. With no clear spot on the right it opens the same way on the left of the first
-- pack; only then does it slide up or down (at most one pack height) to dodge something standing beside the row,
-- right side first. It is never placed above or below the row. If nothing is clear, the spot that covers the least wins.
-- info = { side = "right" | "left", area = px covered (0 = clear), slid = true when it moved off centre }
function TooltipSpec.placeBeside(card, packs, blockers, tip, screen, spec)
	spec = spec or TooltipSpec.Spec
	local gap, margin = spec.sideGap, spec.margin
	local x0, x1 = card.X, card.X + card.W
	local avoid = {}
	for _, p in ipairs(packs) do
		x0, x1 = math.min(x0, p.X), math.max(x1, p.X + p.W)
		avoid[#avoid + 1] = p
	end
	for _, b in ipairs(blockers) do avoid[#avoid + 1] = b end

	local function clampY(y) return math.max(margin, math.min(y, math.max(margin, screen.Y - tip.Y - margin))) end
	local function xFor(side)
		local x = (side == "right") and (x1 + gap) or (x0 - gap - tip.X)
		return math.max(margin, math.min(x, screen.X - tip.X - margin))
	end
	local centre = clampY(card.Y + card.H / 2 - tip.Y / 2)

	-- candidates in order: right then left at the centre, then right then left slid beside whatever stands in the column
	local candidates = { { "right", xFor("right"), centre }, { "left", xFor("left"), centre } }
	for _, side in ipairs({ "right", "left" }) do
		local x = xFor(side)
		local slides = {}
		for _, b in ipairs(avoid) do
			if b.X < x + tip.X and x < b.X + b.W then
				slides[#slides + 1] = clampY(b.Y - gap - tip.Y)
				slides[#slides + 1] = clampY(b.Y + b.H + gap)
			end
		end
		table.sort(slides, function(a, c) return math.abs(a - centre) < math.abs(c - centre) end)
		for _, y in ipairs(slides) do
			if y ~= centre and math.abs(y - centre) <= card.H then candidates[#candidates + 1] = { side, x, y } end
		end
	end

	local best
	for _, c in ipairs(candidates) do
		local rect = { X = c[2], Y = c[3], W = tip.X, H = tip.Y }
		local area = 0
		for _, a in ipairs(avoid) do area = area + overlapArea(rect, a) end
		if not best or area < best.area then
			best = { x = c[2], y = c[3], area = area, info = { side = c[1], area = area, slid = c[3] ~= centre } }
			if area == 0 then break end
		end
	end
	return best.x, best.y, best.info
end

-- correct(target, actual, offset) -> new offset (x, y), tolerance 1 px.
-- target = where the tip should be on screen, actual = the frame's live AbsolutePosition after writing Position,
-- offset = the offset (Position minus target) that is currently applied. If something outside our writes (an inset,
-- a scale, a stray anchor) shifts the frame, the offset absorbs the error so the live rect lands on the target.
-- Returns offsetX, offsetY, corrected (true when it changed).
function TooltipSpec.correct(target, actual, offset)
	local ex, ey = actual.X - target.X, actual.Y - target.Y
	if math.abs(ex) <= 1 and math.abs(ey) <= 1 then
		return offset.X, offset.Y, false
	end
	return offset.X - ex, offset.Y - ey, true
end

return TooltipSpec
