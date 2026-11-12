--[[
	Shared/Engine/NewsSceneLayout.lua
	The painted Tavern News notice board (art `panel_scene`, key news_room_a, 1024x1024; drawn by Client/NewsPanel.lua through the shared
	Client/PanelScene). Slots were read off the PNG in the picture's own pixels (geometry in Engine/PanelSceneLayout.lua): the hanging
	banner (title), the parchment strip under it (subtitle), three pinned paper notes in a row and the plaque on the shelf (Close).

	panel(W, H)          -> { x, y, w, h }  a square board centred on the screen
	place(side)          -> PanelSceneLayout.place result with banner, strip, notes (3), close rects (panel pixels), or nil when too small
	canShow(count)       -> true when `count` events fit the painted notes (MAX_NOTES painted; more use the plain cork board)
	MAX_SLOTS            the most event notes the screen layout ever lists (5); the painted board shows the first MAX_NOTES of them
]]

local PS = require(script.Parent.PanelSceneLayout)

local M = {}

M.ART_KEY = "news_room_a"
M.MAX_NOTES = 3 -- pinned papers painted into the picture
M.MAX_SLOTS = 5 -- more than this never appear on any News layout
M.DEF = {
	w = 1024, h = 1024, margin = 8, pad = 14,
	groups = {
		banner = { { 250, 112, 534, 132 } },
		strip = { { 244, 292, 552, 80 } },
		notes = { { 122, 408, 232, 352 }, { 398, 408, 234, 352 }, { 672, 408, 236, 352 } },
		close = { { 330, 792, 364, 80 } },
	},
	-- smallest sizes (px) at which text stays readable (nothing under 14)
	min = { banner = { 200, 44 }, strip = { 200, 36 }, notes = { 140, 190 }, close = { 120, 36 } },
}

M.COLORS = { ink = { 60, 40, 22 }, inkSoft = { 110, 78, 40 }, plaqueInk = { 250, 236, 204 }, plaqueShadow = { 30, 18, 8 } }

-- the board is a square (as the picture), as large as the screen allows
function M.panel(W, H)
	local side = math.floor(math.min(960, W * 0.9, H * 0.94))
	return { x = math.floor((W - side) / 2), y = math.floor((H - side) / 2), w = side, h = side }
end

function M.place(side)
	local p = PS.place(M.DEF, side, side)
	if not p.ok then return nil end
	p.banner, p.strip, p.notes, p.close = p.groups.banner[1], p.groups.strip[1], p.groups.notes, p.groups.close[1]
	return p
end

function M.canShow(count)
	return count >= 1 and count <= M.MAX_NOTES
end

return M
