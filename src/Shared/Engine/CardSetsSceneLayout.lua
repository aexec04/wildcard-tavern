--[[
	Shared/Engine/CardSetsSceneLayout.lua
	The painted Card Sets shelf wall (art `panel_scene`, key cardsets_room_a, 1024x1024; Client/CardSetsRoom.lua, used by
	Client/CosmeticSetsPanel.lua). Slots were read off the PNG (art-wip/panel_scene/cardsets_room_slots.py draws them on
	debug_cardsets_room_a.png), in the picture's own pixels; geometry is in Engine/PanelSceneLayout.lua.

	CardSetsSceneLayout.place(areaW, areaH) -> { ok, scale, image, plates = { rect x5 }, frames = { rect x10, row by row },
	                                              plaques = { rect x10, same order } } in the area's pixels
	CardSetsSceneLayout.tileParts(frame) -> { cardW, cardH, face, back, name, preview, single } rects relative to a frame
	CardSetsSceneLayout.pageCount(n) / pageSlice(list, page) -> paging of PER_PAGE entries
	CardSetsSceneLayout.panel(screenW, screenH) -> panel w, h the scene wants on that screen
	CardSetsSceneLayout.TOP, BOTTOM   header (title, hint) above and Close below the body
]]

local PS = require(script.Parent.PanelSceneLayout)

local M = {}

M.ART_KEY = "cardsets_room_a"
M.PER_PAGE = 10
-- the velvet openings inside the wooden frames (the frame border, about 12 px, is left out)
local COLS = { { 112, 125 }, { 279, 125 }, { 447, 125 }, { 615, 125 }, { 784, 125 } }
local ROWS = { { 312, 196 }, { 610, 182 } }
local PLAQUE_COLS = { { 118, 103 }, { 288, 102 }, { 457, 103 }, { 627, 101 }, { 798, 103 } }
local PLAQUE_ROWS = { { 531, 29 }, { 817, 29 } }
local function frames()
	local out = {}
	for _, r in ipairs(ROWS) do for _, c in ipairs(COLS) do out[#out + 1] = { c[1], r[1], c[2], r[2] } end end
	return out
end
local function plaques()
	local out = {}
	for _, r in ipairs(PLAQUE_ROWS) do for _, c in ipairs(PLAQUE_COLS) do out[#out + 1] = { c[1], r[1], c[2], r[2] } end end
	return out
end
M.DEF = {
	w = 1024, h = 1024, margin = 8, pad = 14,
	groups = {
		plates = { { 85, 168, 152, 72 }, { 255, 168, 150, 72 }, { 424, 168, 158, 72 }, { 600, 168, 170, 72 }, { 786, 168, 150, 72 } },
		frames = frames(),
		plaques = plaques(),
	},
	-- smallest sizes (px) at which text stays readable (nothing under 14)
	min = { plates = { 96, 40 }, frames = { 96, 140 }, plaques = { 76, 22 } },
}
M.PANEL_FRAC = { 0.92, 0.94 }
M.PANEL_MAX = { 1200, 900 }
M.TOP, M.BOTTOM = 62, 46

function M.panel(screenW, screenH)
	return PS.panelSize(screenW, screenH, M.PANEL_FRAC[1], M.PANEL_FRAC[2], M.PANEL_MAX[1], M.PANEL_MAX[2])
end

function M.place(areaW, areaH)
	local p = PS.place(M.DEF, areaW, areaH)
	p.plates, p.frames, p.plaques = p.groups.plates, p.groups.frames, p.groups.plaques
	return p
end

-- inside one frame: two cards side by side (a sample face and the back, for a set) or one big back (single), the name on two lines
-- (38 px: Roblox only fits two 14 px lines in 36 or more) and a Preview plate at the foot
function M.tileParts(f)
	local pad, gap = 6, 6
	local nameH, btnH = 38, 26
	local cardH = math.max(60, f.h - (pad + 4 + nameH + 4 + btnH + pad))
	local cardW = math.floor(math.min((f.w - 2 * pad - gap) / 2, cardH * 2 / 3))
	cardH = math.floor(cardW * 3 / 2)
	local top = pad
	local rowW = cardW * 2 + gap
	local x0 = math.floor((f.w - rowW) / 2)
	local nameY = top + cardH + 4
	local single = { x = math.floor((f.w - cardW) / 2), y = top, w = cardW, h = cardH }
	return {
		cardW = cardW, cardH = cardH,
		face = { x = x0, y = top, w = cardW, h = cardH },
		back = { x = x0 + cardW + gap, y = top, w = cardW, h = cardH },
		single = single,
		name = { x = 4, y = nameY, w = f.w - 8, h = nameH },
		preview = { x = 8, y = f.h - pad - btnH, w = f.w - 16, h = btnH },
	}
end

function M.pageCount(n)
	return math.max(1, math.ceil(n / M.PER_PAGE))
end

function M.pageSlice(list, page)
	local pages = M.pageCount(#list)
	page = math.max(1, math.min(pages, page))
	local out = {}
	for i = (page - 1) * M.PER_PAGE + 1, math.min(#list, page * M.PER_PAGE) do out[#out + 1] = list[i] end
	return out, page, pages
end

return M
