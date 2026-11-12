--[[
	Shared/Engine/LegendSceneLayout.lua
	The painted Legend trophy hall (art `panel_scene`, key legend_room_a, 1024x1024; Client/LegendPanel.lua). Slots were read off the PNG
	(art-wip/panel_scene/legend_room_slots.py draws them on debug_legend_room_a.png), in the picture's own pixels; geometry is in
	Engine/PanelSceneLayout.lua.

	LegendSceneLayout.place(areaW, areaH) -> { ok, scale, image, alcove = rect, plaques = { rect x5 }, shelves = { rect x3 } } in the area's pixels
	LegendSceneLayout.alcoveParts(alcove) -> { crest = rect, back = rect (2:3 card back), next = rect }, rects relative to the alcove
	LegendSceneLayout.pairs(levels) -> { { 1, 2 }, { 3, 4 } ... } which two Legend levels each plaque holds
	LegendSceneLayout.plaqueParts(plaque) -> { { medal = rect, num = rect }, { ... } } (relative to the plaque)
	LegendSceneLayout.panel(screenW, screenH) -> panel w, h the scene wants on that screen
]]

local PS = require(script.Parent.PanelSceneLayout)

local M = {}

M.ART_KEY = "legend_room_a"
M.DEF = {
	w = 1024, h = 1024, margin = 8, pad = 14,
	groups = {
		alcove = { { 252, 247, 318, 372 } },
		plaques = { { 95, 748, 140, 82 }, { 275, 748, 134, 82 }, { 449, 748, 131, 82 }, { 619, 748, 135, 82 }, { 796, 748, 164, 82 } },
		shelves = { { 726, 222, 192, 106 }, { 726, 366, 192, 108 }, { 726, 508, 192, 112 } },
	},
	-- smallest sizes (px) at which text stays readable (nothing under 14)
	min = { alcove = { 200, 250 }, plaques = { 92, 56 }, shelves = { 112, 72 } },
}
M.PANEL_FRAC = { 0.9, 0.94 }
M.PANEL_MAX = { 1180, 800 }
M.TOP, M.BOTTOM = 78, 60 -- header (title, hint) above and Close below the body

-- The picture is square, so the panel is only as wide as the picture comes out at the height-limited scale: no band is left at the sides.
function M.panel(screenW, screenH)
	local fw, fh = PS.panelSize(screenW, screenH, M.PANEL_FRAC[1], M.PANEL_FRAC[2], M.PANEL_MAX[1], M.PANEL_MAX[2])
	local x0, y0, x1, y1 = PS.bounds(M.DEF)
	local s = (fh - M.TOP - M.BOTTOM - 2 * (M.DEF.margin or 8)) / (y1 - y0)
	local w = math.max(640, math.min(fw, math.ceil(M.DEF.w * s)))
	return w, fh
end

-- Colours (rgb) with their contrast, tested at 4.5:1 or better: the level labels are cream on a dark pill (cream on the brass plaque
-- alone is only about 3.8:1), the shelf texts are dark ink on a small parchment strip, the panel frame is the dark wood of the other
-- Tome panels instead of maroon.
M.COLORS = {
	lvInk = { 250, 235, 200 }, lvPill = { 40, 26, 16 },
	shelfInk = { 52, 32, 16 }, shelfStrip = { 222, 204, 164 },
	frame = { 50, 34, 22 }, frameLine = { 190, 146, 78 }, closeButton = { 96, 64, 36 },
}

-- the parchment strip behind one shelf's text: centred in the shelf, inset 6 px, at most 60 px tall (relative to the shelf)
function M.shelfStrip(shelf)
	local h = math.min(shelf.h - 12, 60)
	return { x = 6, y = math.floor((shelf.h - h) / 2), w = shelf.w - 12, h = h }
end

function M.place(areaW, areaH)
	local p = PS.place(M.DEF, areaW, areaH)
	p.alcove, p.plaques, p.shelves = p.groups.alcove[1], p.groups.plaques, p.groups.shelves
	return p
end

function M.alcoveParts(a)
	local crestH, nextH, gap = 28, 36, 6
	local backH = math.max(60, a.h - crestH - nextH - 3 * gap)
	local backW = math.floor(backH * 2 / 3)
	if backW > a.w - 16 then backW = a.w - 16; backH = math.floor(backW * 3 / 2) end
	return {
		crest = { x = 4, y = gap, w = a.w - 8, h = crestH },
		back = { x = math.floor((a.w - backW) / 2), y = gap + crestH + gap, w = backW, h = backH },
		next = { x = 6, y = a.h - nextH - gap, w = a.w - 12, h = nextH },
	}
end

function M.pairs(levels)
	local out = {}
	for i = 1, levels, 2 do out[#out + 1] = { i, math.min(i + 1, levels) } end
	return out
end

function M.plaqueParts(pl)
	local colW = math.floor(pl.w / 2)
	local numH = 16
	local d = math.max(20, math.min(colW - 10, pl.h - numH - 10))
	local out = {}
	for c = 0, 1 do
		local cx = c * colW + math.floor((colW - d) / 2)
		out[#out + 1] = { medal = { x = cx, y = 4, w = d, h = d }, num = { x = c * colW, y = 4 + d + 1, w = colW, h = numH } }
	end
	return out
end

return M
