--[[
	Shared/Engine/CollectionSceneLayout.lua
	Pure layout maths for the Collection Gallery (the Collection as the tavern's back room). No Roblox calls, so it is
	unit tested. Rects are { x, y, w, h } in the Collection panel's local pixels. Look only: nothing here knows about
	filters, counts, milestones or remotes.

	content(W, H)             the area under the header that holds the tile grid (matches the panel's scrim)
	grid(W, H, kind, n)       { cells = { rect... }, frame = { w, h }, plate = rect-of-name-plate-inside-a-cell-offset }
	                          kind = "frames" | "cork" | "shelf" | "rack" | "plates"
	furniture(W, H, kind)     the painted furniture band for a tab (drawn behind the cells), inside content
	chest(W, H)               milestone chest on the floor, bottom right, clear of the grid
	newIds(before, after)     ids present in `after` but not in `before` (the "New" tag and drop-in set)
	flicker(t, calm)          lantern brightness multiplier, 1 +/- 0.03, exactly 1 in calm mode
	dropOffset(t, calm, fast) vertical drop-in offset in px for a newly acquired frame (0 when done or skipped)
]]

local CollectionSceneLayout = {}

CollectionSceneLayout.FRAME_RATIO = 0.75   -- width / height of collection_frame_owned (3:4)
CollectionSceneLayout.MAX_ANIMATED = 10    -- cap on animated objects (lanterns, motes, moth, drop-ins, chest)
CollectionSceneLayout.DROP_PX = 24
CollectionSceneLayout.DROP_TIME = 0.5
CollectionSceneLayout.GAP = 10
CollectionSceneLayout.MIN_W, CollectionSceneLayout.MIN_H = 320, 300

-- how many cells per row at the given width, per kind (a cell is one hung item)
local CELL = {
	frames = { w = 120, h = 160 },
	cork = { w = 110, h = 110 },
	shelf = { w = 150, h = 120 },
	rack = { w = 120, h = 140 },
	plates = { w = 170, h = 56 },
}

function CollectionSceneLayout.content(W, H)
	return { x = 15, y = 138, w = math.max(0, W - 30), h = math.max(0, H - 196) }
end

function CollectionSceneLayout.grid(W, H, kind, n)
	local c = CollectionSceneLayout.content(W, H)
	local spec = CELL[kind] or CELL.frames
	local gap = CollectionSceneLayout.GAP
	n = math.max(0, math.floor(n or 0))
	local cols = math.max(1, math.floor((c.w + gap) / (spec.w + gap)))
	-- chest corner: keep the bottom right clear for it
	local cw, ch = spec.w, spec.h
	local cells = {}
	local usedW = cols * cw + (cols - 1) * gap
	local x0 = c.x + math.floor((c.w - usedW) / 2)
	for i = 0, n - 1 do
		local col, row = i % cols, math.floor(i / cols)
		cells[#cells + 1] = { x = x0 + col * (cw + gap), y = c.y + row * (ch + gap), w = cw, h = ch }
	end
	local rows = math.ceil(n / cols)
	local plateH = math.max(16, math.floor(ch * 0.16))
	return {
		cells = cells, cols = cols, rows = rows,
		frame = { w = cw, h = ch },
		-- name plate sits on the lower edge of the item, inside the cell
		plate = { x = 0.08 * cw, y = ch - plateH - 4, w = 0.84 * cw, h = plateH },
		height = rows * ch + math.max(0, rows - 1) * gap,
	}
end

function CollectionSceneLayout.furniture(W, H, kind)
	local c = CollectionSceneLayout.content(W, H)
	if kind == "cork" then
		return { x = c.x, y = c.y, w = c.w, h = c.h }
	end
	-- shelves, racks and plates are bands the full width of the content, a little shorter than it
	return { x = c.x, y = c.y, w = c.w, h = math.floor(c.h * 0.96) }
end

function CollectionSceneLayout.chest(W, H)
	local c = CollectionSceneLayout.content(W, H)
	local s = math.max(40, math.min(72, math.floor(c.h * 0.18)))
	return { x = c.x + c.w - s - 6, y = c.y + c.h - s - 4, w = s, h = s }
end

function CollectionSceneLayout.newIds(before, after)
	local seen, out = {}, {}
	for _, id in ipairs(before or {}) do
		seen[id] = true
	end
	for _, id in ipairs(after or {}) do
		if not seen[id] then
			out[#out + 1] = id
		end
	end
	return out
end

function CollectionSceneLayout.flicker(t, calm)
	if calm then
		return 1
	end
	return 1 + 0.03 * math.sin(t * 1.7) * math.sin(t * 0.43 + 1)
end

function CollectionSceneLayout.dropOffset(t, calm, fast)
	if calm or fast or t >= CollectionSceneLayout.DROP_TIME then
		return 0
	end
	local u = math.max(0, t) / CollectionSceneLayout.DROP_TIME
	-- falls 24 px above to 0 with a soft bounce (one overshoot)
	local e = 1 - (1 - u) * (1 - u)
	local bounce = math.sin(u * math.pi) * 0.12
	return -CollectionSceneLayout.DROP_PX * (1 - e) + CollectionSceneLayout.DROP_PX * bounce * (1 - u)
end

return CollectionSceneLayout
