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

-- ===== framed portraits (Patrons tab): the gilt frame art cropped to the frame, hung on the wall =====
-- Crops of collection_frame_owned / collection_frame_empty (1024x1536 art) in art pixels, and the opening inside each crop
-- (fractions of it). The crop is applied with a clipping frame and a scaled image (not ImageRect), so it holds whatever size
-- Roblox stores. Owned = the lit frame without its chain; locked (empty) = the frame under its grey dust cloth, without its chain.
CollectionSceneLayout.FRAMES = {
	owned = { imgW = 1024, imgH = 1536, x = 88, y = 350, w = 849, h = 986, opening = { x = 0.223, y = 0.264, w = 0.553, h = 0.556 } },
	empty = { imgW = 1024, imgH = 1536, x = 40, y = 318, w = 955, h = 1013, opening = { x = 0.215, y = 0.204, w = 0.565, h = 0.657 } },
}
CollectionSceneLayout.FRAME_CROP = CollectionSceneLayout.FRAMES.owned
CollectionSceneLayout.FRAME_OPENING = CollectionSceneLayout.FRAMES.owned.opening
-- one cell: the frame on top, a brass plate attached across its bottom edge, room for the chain above (inside the vertical gap)
CollectionSceneLayout.FRAMED_CELL = { w = 92, h = 136, frameH = 108, plateH = 22, plateOverlap = 6 }
CollectionSceneLayout.FRAMED_GAP = { x = 16, y = 28 } -- wider than the plain tiles so chains and shadows fit
CollectionSceneLayout.CHAIN_H = 22 -- how far above the frame the brass nail sits
CollectionSceneLayout.SHADOW = { dx = 3, dy = 5, transparency = 0.65 } -- dark, 35 percent, down and to the right
CollectionSceneLayout.HANG = { dyMax = 3, tiltMax = 1.5 } -- per-Patron hand-hung offset and tilt

-- image size and position (as scale of the clipping frame) that show only the crop
function CollectionSceneLayout.cropPlacement(kind)
	local c = CollectionSceneLayout.FRAMES[kind or "owned"]
	return { sizeX = c.imgW / c.w, sizeY = c.imgH / c.h, posX = -c.x / c.w, posY = -c.y / c.h }
end

-- icon well centred in the frame opening, the frame, and the brass plate hanging over its bottom edge, in cell pixels
function CollectionSceneLayout.framedParts(kind)
	local cell = CollectionSceneLayout.FRAMED_CELL
	local o = CollectionSceneLayout.FRAMES[kind or "owned"].opening
	local size = math.floor(math.min(cell.w * o.w, cell.frameH * o.h)) - 2
	local cx = cell.w * (o.x + o.w / 2)
	local cy = cell.frameH * (o.y + o.h / 2)
	return {
		icon = { x = math.floor(cx - size / 2), y = math.floor(cy - size / 2), w = size, h = size },
		frame = { x = 0, y = 0, w = cell.w, h = cell.frameH },
		plate = { x = 6, y = cell.frameH - cell.plateOverlap, w = cell.w - 12, h = cell.plateH },
		cell = cell,
	}
end

-- the two short chains from the brass nail down to the frame's top corners, in cell pixels (y is negative above the frame):
-- { nail = { x, y }, lines = { { cx, cy, len, angle }, ... } } where each line is a thin box centred on (cx, cy)
function CollectionSceneLayout.chain()
	local cell = CollectionSceneLayout.FRAMED_CELL
	local nail = { x = cell.w / 2, y = -CollectionSceneLayout.CHAIN_H }
	local lines = {}
	for _, fx in ipairs({ 0.24, 0.76 }) do
		local ex, ey = cell.w * fx, 3
		local dx, dy = ex - nail.x, ey - nail.y
		local angle = math.deg((math.atan2 or math.atan)(dy, dx)) -- atan2 in Luau, two-argument atan in plain Lua
		if angle > 90 then angle = angle - 180 elseif angle <= -90 then angle = angle + 180 end -- a box looks the same turned half a circle
		lines[#lines + 1] = { cx = (nail.x + ex) / 2, cy = (nail.y + ey) / 2, len = math.sqrt(dx * dx + dy * dy), angle = angle }
	end
	return { nail = nail, lines = lines }
end

-- stable pseudo-random offset and tilt for one Patron id: { dy = 0..3 px, tilt = -1.5..1.5 degrees }
function CollectionSceneLayout.hang(id)
	local h = 5381
	for i = 1, #tostring(id) do h = (h * 33 + tostring(id):byte(i)) % 2147483647 end
	local a = (h % 1000) / 999
	local b = ((h // 1000) % 1000) / 999
	local H = CollectionSceneLayout.HANG
	return { dy = math.floor(a * H.dyMax + 0.5), tilt = math.floor((b * 2 - 1) * H.tiltMax * 10 + 0.5) / 10 }
end

CollectionSceneLayout.FURNITURE_MARGIN = 10 -- the board or shelf shows this far outside the scrolling grid on every side
CollectionSceneLayout.CARD_TILT = 2 -- cork-board cards tilt at most 2 degrees, fixed per card

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
