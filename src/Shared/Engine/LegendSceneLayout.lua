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
	min = { alcove = { 200, 250 }, plaques = { 92, 56 }, shelves = { 112, 60 } },
}
M.PANEL_FRAC = { 0.9, 0.94 }
M.PANEL_MAX = { 1180, 800 }
M.TOP, M.BOTTOM = 78, 60 -- header (title, hint) above and Close below the body

function M.panel(screenW, screenH)
	return PS.panelSize(screenW, screenH, M.PANEL_FRAC[1], M.PANEL_FRAC[2], M.PANEL_MAX[1], M.PANEL_MAX[2])
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
