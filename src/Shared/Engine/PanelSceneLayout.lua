--[[
	Shared/Engine/PanelSceneLayout.lua
	Pure geometry shared by the painted panel rooms (art category `panel_scene`: Legend, Card Sets, Stats; the Flair room has its own
	older copy in FlairSceneLayout). A DEF holds the picture size and its slots, read off the PNG in the picture's own pixels:
	  { w, h, margin = 8, pad = 14, groups = { name = { rect, rect, ... } }, min = { name = { w, h } } }
	place(def, areaW, areaH) turns them into the area's pixels. The picture is cover-fitted into the area and shrinks below cover so every
	slot keeps `margin` px of clear room; it is never stretched. ok is false when a slot would be too small to read (the caller keeps the
	plain layout). edgeFill(def, p, areaW, areaH) lists eight 4 px slices of the picture's own edge that cover whatever the picture does
	not, so the painting reads as the whole body of the panel (the caller draws them under the picture, 1 px of overlap).

	place -> { ok, scale, image = {x,y,w,h}, groups = { name = { rect, ... } } }
	edgeFill -> { { name, rect = {x,y,w,h} (area px), src = {x,y,w,h} (picture px) }, ... }
]]

local M = {}

M.EDGE = 4

local function clampRange(v, lo, hi)
	if lo > hi then return (lo + hi) / 2 end
	return math.max(lo, math.min(hi, v))
end

-- offset of the picture along one axis: centred, covering the view when it can, keeping b0..b1 (picture px) inside
local function offset(viewLen, picLen, s, b0, b1)
	local o = (viewLen - picLen * s) / 2
	local lo, hi
	if picLen * s >= viewLen then lo, hi = viewLen - picLen * s, 0 else lo, hi = o, o end
	local lo2, hi2 = -b0 * s, viewLen - b1 * s
	local a, b = math.max(lo, lo2), math.min(hi, hi2)
	if a > b then return clampRange(o, lo2, hi2) end
	return clampRange(o, a, b)
end

function M.bounds(def)
	local x0, y0, x1, y1 = math.huge, math.huge, -math.huge, -math.huge
	for _, list in pairs(def.groups) do
		for _, r in ipairs(list) do
			x0, y0 = math.min(x0, r[1]), math.min(y0, r[2])
			x1, y1 = math.max(x1, r[1] + r[3]), math.max(y1, r[2] + r[4])
		end
	end
	local pad = def.pad or 14
	return x0 - pad, y0 - pad, x1 + pad, y1 + pad
end

function M.place(def, areaW, areaH)
	local mg = def.margin or 8
	local x0, y0, x1, y1 = M.bounds(def)
	local W, H = math.max(1, areaW), math.max(1, areaH)
	local cover = math.max(W / def.w, H / def.h)
	local fit = math.min((W - 2 * mg) / (x1 - x0), (H - 2 * mg) / (y1 - y0))
	local s = math.min(cover, fit)
	local ix, iy = offset(W, def.w, s, x0 - mg / s, x1 + mg / s), offset(H, def.h, s, y0 - mg / s, y1 + mg / s)
	local out = { image = { x = ix, y = iy, w = def.w * s, h = def.h * s }, groups = {}, ok = true, scale = s }
	for name, list in pairs(def.groups) do
		local mapped = {}
		local need = def.min and def.min[name]
		for i, r in ipairs(list) do
			local m = { x = math.floor(ix + r[1] * s), y = math.floor(iy + r[2] * s), w = math.floor(r[3] * s), h = math.floor(r[4] * s) }
			mapped[i] = m
			if need and (m.w < need[1] or m.h < need[2]) then out.ok = false end
		end
		out.groups[name] = mapped
	end
	return out
end

function M.edgeFill(def, p, areaW, areaH)
	local I, e = p.image, M.EDGE
	local W, H = def.w, def.h
	local out = {}
	local x1, y1 = I.x + I.w, I.y + I.h
	local function add(name, x, y, w, h, sx, sy, sw, sh)
		if w > 0.5 and h > 0.5 then
			out[#out + 1] = { name = name, rect = { x = math.floor(x), y = math.floor(y), w = math.ceil(w), h = math.ceil(h) }, src = { x = sx, y = sy, w = sw, h = sh } }
		end
	end
	local midY0, midY1 = math.max(0, I.y), math.min(areaH, y1)
	local midX0, midX1 = math.max(0, I.x), math.min(areaW, x1)
	add("Left", 0, midY0, I.x + 1, midY1 - midY0, 0, 0, e, H)
	add("Right", x1 - 1, midY0, areaW - x1 + 1, midY1 - midY0, W - e, 0, e, H)
	add("Top", midX0, 0, midX1 - midX0, I.y + 1, 0, 0, W, e)
	add("Bottom", midX0, y1 - 1, midX1 - midX0, areaH - y1 + 1, 0, H - e, W, e)
	add("TopLeft", 0, 0, I.x + 1, I.y + 1, 0, 0, e, e)
	add("TopRight", x1 - 1, 0, areaW - x1 + 1, I.y + 1, W - e, 0, e, e)
	add("BottomLeft", 0, y1 - 1, I.x + 1, areaH - y1 + 1, 0, H - e, e, e)
	add("BottomRight", x1 - 1, y1 - 1, areaW - x1 + 1, areaH - y1 + 1, W - e, H - e, e, e)
	return out
end

-- Size a scene panel asks for on a screen: a fraction of the screen up to a cap (so the body is tall enough for the picture's slots).
function M.panelSize(screenW, screenH, fracW, fracH, maxW, maxH)
	return math.floor(math.min(screenW * fracW, maxW)), math.floor(math.min(screenH * fracH, maxH))
end

return M
