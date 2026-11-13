--[[
	Shared/Engine/BossBubbleLayout.lua
	Pure placement (tested) for the boss speech bubble: it hangs beside the boss portrait (or the banner plate when the
	portrait is hidden), with a tail pointing at the speaker, and keeps clear of everything in `keepOut`.

	  BossBubbleLayout.place(bounds, anchor, size, keepOut, opts) -> nil | { rect = {x,y,w,h}, side, tail = {x,y} }
	    bounds   { x, y, w, h } the area the bubble must stay inside (same coordinate space as everything else)
	    anchor   { x, y, w, h } the speaker (portrait frame or banner plate)
	    size     { w, h } of the bubble
	    keepOut  list of { x, y, w, h } (Patron Nook, hand, dock, ...), each padded by opts.clear (default 12)
	    opts     { gap = 12 (bubble to speaker, tail included), margin = 8 (to the bounds), clear = 12 }
	  side is "right", "left", "below" or "above" of the speaker; tail is the point on the bubble's edge facing the
	  speaker (the tail's base centre, clamped 16 px from the corners). nil means nothing fits: the caller skips the line.
]]

local M = {}

M.GAP, M.MARGIN, M.CLEAR, M.TAIL = 12, 8, 12, 10

local function overlaps(a, b, pad)
	return a.x < b.x + b.w + pad and b.x < a.x + a.w + pad and a.y < b.y + b.h + pad and b.y < a.y + a.h + pad
end

local function clamp(v, lo, hi)
	if lo > hi then return (lo + hi) / 2 end
	return math.max(lo, math.min(hi, v))
end

function M.place(bounds, anchor, size, keepOut, opts)
	if not bounds or not anchor or not size then return nil end
	local gap = opts and opts.gap or M.GAP
	local mg = opts and opts.margin or M.MARGIN
	local clear = opts and opts.clear or M.CLEAR
	local w, h = size.w, size.h
	local minX, maxX = bounds.x + mg, bounds.x + bounds.w - mg - w
	local minY, maxY = bounds.y + mg, bounds.y + bounds.h - mg - h
	if maxX < minX or maxY < minY then return nil end
	local acx, acy = anchor.x + anchor.w / 2, anchor.y + anchor.h / 2
	local tries = {
		{ side = "right", x = anchor.x + anchor.w + gap, y = anchor.y },
		{ side = "left", x = anchor.x - gap - w, y = anchor.y },
		{ side = "below", x = acx - w / 2, y = anchor.y + anchor.h + gap },
		{ side = "above", x = acx - w / 2, y = anchor.y - gap - h },
	}
	for _, t in ipairs(tries) do
		local x, y = clamp(t.x, minX, maxX), clamp(t.y, minY, maxY)
		x, y = math.floor(x + 0.5), math.floor(y + 0.5)
		local rect = { x = x, y = y, w = w, h = h }
		local ok = not overlaps(rect, anchor, gap - M.TAIL - 1 > 0 and gap - M.TAIL - 1 or 0)
		if ok then
			for _, k in ipairs(keepOut or {}) do
				if overlaps(rect, k, clear) then ok = false break end
			end
		end
		if ok then
			local tail
			if t.side == "right" then tail = { x = x, y = clamp(acy, y + 16, y + h - 16) }
			elseif t.side == "left" then tail = { x = x + w, y = clamp(acy, y + 16, y + h - 16) }
			elseif t.side == "below" then tail = { x = clamp(acx, x + 16, x + w - 16), y = y }
			else tail = { x = clamp(acx, x + 16, x + w - 16), y = y + h } end
			return { rect = rect, side = t.side, tail = tail }
		end
	end
	return nil
end

return M
