--[[
	Shared/Engine/IconLabelLayout.lua
	Where a plate's small icon and its word go: the icon stands at the left (14 px in), a square 0.53 of the plate height, centred
	vertically; the word starts 6 px right of the icon and ends 8 px before the right edge. The two rects never touch.
	IconLabelLayout.place(w, h) -> { icon = {x,y,w,h}, label = {x,y,w,h} }   (plate pixels, whole numbers)
]]
local M = {}
M.LEFT, M.GAP, M.RIGHT, M.ICON_K, M.MIN_ICON = 14, 6, 8, 0.53, 8

function M.place(w, h)
	w, h = math.max(1, math.floor(w)), math.max(1, math.floor(h))
	local s = math.max(M.MIN_ICON, math.floor(h * M.ICON_K + 0.5))
	local lx = M.LEFT + s + M.GAP
	return {
		icon = { x = M.LEFT, y = math.floor((h - s) / 2), w = s, h = s },
		label = { x = lx, y = 0, w = math.max(0, w - lx - M.RIGHT), h = h },
	}
end

M.SIDE = 14 -- clear air on each side of the icon plus word group

-- The icon, the 6 px gap and the word as ONE group centred in the plate, at least SIDE px from each edge. textW is the word's measured
-- width at `size`; when the group does not fit, the word shrinks (size * room / textW, floored, never under minSize) and the group fills the room.
-- Returns { icon, label, size, fits } (label is the group's word box, left aligned).
function M.group(w, h, textW, size, minSize)
	w, h = math.max(1, math.floor(w)), math.max(1, math.floor(h))
	local s = math.max(M.MIN_ICON, math.floor(h * M.ICON_K + 0.5))
	local room = math.max(0, w - 2 * M.SIDE - s - M.GAP) -- what the word may take
	textW = math.ceil(math.max(0, textW or 0))
	local newSize, fits = size, true
	if textW > room and textW > 0 then
		fits = false
		newSize = math.max(minSize or 14, math.floor((size or 14) * room / textW))
		textW = math.floor(textW * newSize / (size or newSize)) -- the width at the new size
		if textW > room then textW = room end
	end
	local total = s + M.GAP + textW
	local x0 = math.max(M.SIDE, math.floor((w - total) / 2))
	return {
		icon = { x = x0, y = math.floor((h - s) / 2), w = s, h = s },
		label = { x = x0 + s + M.GAP, y = 0, w = textW, h = h },
		size = newSize,
		fits = fits,
	}
end

-- Keeps the icon and the word inside a plate of w x h whatever the caller measured: a rect that starts left of 0 or ends past w is pulled
-- back in (the word box shrinks, the group slides left). Pure, used by TavernKit.icon after place/group. Returns the same table.
function M.clampInside(w, h, g)
	w, h = math.max(1, math.floor(w)), math.max(1, math.floor(h))
	local i, l = g.icon, g.label
	if i.w > w then i.w = w; i.h = math.min(i.h, w) end
	if i.x < 0 or i.x + i.w > w or l.x + l.w > w then -- a group measured against the wrong width: pack it again from the left edge
		i.x = math.min(M.SIDE, math.max(0, w - i.w))
		l.x = math.min(w, i.x + i.w + M.GAP)
		l.w = math.min(l.w, math.max(0, w - l.x - M.SIDE))
	end
	if l.x < i.x + i.w then l.x = math.min(w, i.x + i.w) end
	if l.x + l.w > w then l.w = math.max(0, w - l.x) end
	if i.y < 0 then i.y = 0 end
	if i.y + i.h > h then i.y = math.max(0, h - i.h) end
	return g
end

-- true when both rects lie inside the plate (Studio warns when this is false)
function M.inside(w, h, g)
	local function ok(r) return r.x >= 0 and r.y >= 0 and r.x + r.w <= w and r.y + r.h <= h end
	return ok(g.icon) and ok(g.label)
end

return M
