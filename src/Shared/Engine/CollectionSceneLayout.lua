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

-- ===== painted wall: where the two lanterns are (fractions of the 1536x1024 wall art) =====
CollectionSceneLayout.WALL = { w = 1536, h = 1024, lanterns = { { x = 0.267, y = 0.39 }, { x = 0.865, y = 0.39 } } }

-- pixel position of lantern i in a W x H panel when the wall is drawn with ScaleType Crop (cover, centred)
function CollectionSceneLayout.lanternPx(W, H, i)
	local wall = CollectionSceneLayout.WALL
	local scale = math.max(W / wall.w, H / wall.h)
	local dw, dh = wall.w * scale, wall.h * scale
	local l = wall.lanterns[i]
	return (W - dw) / 2 + l.x * dw, (H - dh) / 2 + l.y * dh
end

-- ===== framed portraits (Patrons tab): the gilt frame art cropped to the frame without its chain =====
-- Crop of collection_frame_owned / collection_frame_empty (1024x1536 art) in art pixels, and the opening inside it.
-- The crop is applied with a clipping frame and a scaled image (not ImageRect), so it holds whatever size Roblox stores.
CollectionSceneLayout.FRAME_CROP = { imgW = 1024, imgH = 1536, x = 88, y = 350, w = 849, h = 986 }
CollectionSceneLayout.FRAME_OPENING = { x = 0.223, y = 0.264, w = 0.553, h = 0.556 } -- fractions of the crop
CollectionSceneLayout.FRAMED_CELL = { w = 92, h = 132, frameH = 108, plateH = 20 }

-- image size and position (as scale of the clipping frame) that show only the crop
function CollectionSceneLayout.cropPlacement()
	local c = CollectionSceneLayout.FRAME_CROP
	return { sizeX = c.imgW / c.w, sizeY = c.imgH / c.h, posX = -c.x / c.w, posY = -c.y / c.h }
end

-- icon well centred in the frame opening, and the name plate under the frame, in cell pixels
function CollectionSceneLayout.framedParts()
	local cell, o = CollectionSceneLayout.FRAMED_CELL, CollectionSceneLayout.FRAME_OPENING
	local size = math.floor(math.min(cell.w * o.w, cell.frameH * o.h)) - 2
	local cx = cell.w * (o.x + o.w / 2)
	local cy = cell.frameH * (o.y + o.h / 2)
	return {
		icon = { x = math.floor(cx - size / 2), y = math.floor(cy - size / 2), w = size, h = size },
		frame = { x = 0, y = 0, w = cell.w, h = cell.frameH },
		plate = { x = 4, y = cell.h - cell.plateH - 2, w = cell.w - 8, h = cell.plateH },
		cell = cell,
	}
end

-- orbit of the one moth around a lantern: only seen for MOTH_SHOW seconds of every MOTH_CYCLE, never in calm mode
CollectionSceneLayout.MOTH_CYCLE, CollectionSceneLayout.MOTH_SHOW = 40, 12
function CollectionSceneLayout.mothVisible(t, calm)
	return not calm and (t % CollectionSceneLayout.MOTH_CYCLE) < CollectionSceneLayout.MOTH_SHOW
end
function CollectionSceneLayout.mothPos(t, cx, cy, radius)
	local a = t * 1.1
	return cx + math.cos(a) * radius * (1 + 0.15 * math.sin(a * 2.3)), cy + math.sin(a * 1.3) * radius * 0.7
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
