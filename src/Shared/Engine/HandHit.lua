--[[
	HandHit: which hand card a click lands on (pure, no Roblox calls).

	HandHit.pick(cards, x, y) -> index or nil
	    cards: array of { index, cx, cy, w, h, rot (degrees), order } where (cx, cy) is the card centre, rot its fan tilt
	    and order its draw order (higher draws on top). Returns the index of the topmost card whose tilted rectangle holds
	    the point, the same card Roblox gives the click.
	HandHit.visiblePoint(cards, i) -> x, y   a point of card i that no later card covers (nil when it is fully hidden)
]]
local HandHit = {}

local function inside(c, x, y)
	local a = math.rad(-(c.rot or 0))
	local dx, dy = x - c.cx, y - c.cy
	local lx = dx * math.cos(a) - dy * math.sin(a)
	local ly = dx * math.sin(a) + dy * math.cos(a)
	return math.abs(lx) <= c.w / 2 and math.abs(ly) <= c.h / 2
end

function HandHit.pick(cards, x, y)
	local best
	for _, c in ipairs(cards) do
		if inside(c, x, y) and (not best or (c.order or c.index) > (best.order or best.index)) then best = c end
	end
	return best and best.index or nil
end

function HandHit.visiblePoint(cards, i)
	local me
	for _, c in ipairs(cards) do if c.index == i then me = c end end
	if not me then return nil end
	local a = math.rad(me.rot or 0)
	for step = 0, 20 do -- the card's own axes, middle outward then the sides
		for _, fx in ipairs({ 0, -0.3, 0.3, -0.45, 0.45 }) do
			local lx, ly = fx * me.w, (0.5 - step / 20) * me.h * 0.9
			local x = me.cx + lx * math.cos(a) - ly * math.sin(a)
			local y = me.cy + lx * math.sin(a) + ly * math.cos(a)
			if HandHit.pick(cards, x, y) == i then return x, y end
		end
	end
	return nil
end

return HandHit
