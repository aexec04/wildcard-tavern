--[[
	Engine/PanelBorder.lua
	Pure geometry for the code-drawn panel border that Client/SetSkin.lua draws on every panel (and the sidebar). It always
	fits: the same thickness at every panel size, drawn inside the panel, with tiny corner brackets. Layers, outside in:
	a dark outer line, a gap, an accent inner line, and four L-shaped corner brackets in the accent colour.
	Illustrated panel art is NOT used for this; slice-friendly art may be supplied later through the SetSkinArt slot
	panelFrame9 (see PanelBorder.sliceable).
]]

local PanelBorder = {}

PanelBorder.THICK = 8 -- px, the border band on panels with a short side of at least SMALL_SIDE
PanelBorder.THICK_SMALL = 6
PanelBorder.SMALL_SIDE = 240
PanelBorder.OUTER_LINE = 3 -- dark outer line, px
PanelBorder.INNER_LINE = 2 -- accent inner line, px
PanelBorder.BRACKET_LEN = 16
PanelBorder.BRACKET_THICK = 3

-- Border band thickness for a panel of w x h px (6 to 10 px, identical for every normal-sized panel).
function PanelBorder.thickness(w, h)
	local short = math.min(w or 0, h or 0)
	if short < PanelBorder.SMALL_SIDE then return PanelBorder.THICK_SMALL end
	return PanelBorder.THICK
end

-- Layout in px relative to the panel: { thick, inner = {x, y, w, h}, brackets = { {x, y, w, h} x8 } }.
-- `inner` is the accent line rectangle (inset by the outer line plus a 1 px gap); content should be inset by `thick`.
function PanelBorder.layout(w, h)
	local t = PanelBorder.thickness(w, h)
	local o = PanelBorder.OUTER_LINE + 1
	local inner = { x = o, y = o, w = math.max(0, w - 2 * o), h = math.max(0, h - 2 * o) }
	local len, bt = PanelBorder.BRACKET_LEN, PanelBorder.BRACKET_THICK
	local ix, iy = o, o
	local rx, by = w - o, h - o
	local brackets = {
		{ x = ix, y = iy, w = len, h = bt }, { x = ix, y = iy, w = bt, h = len },
		{ x = rx - len, y = iy, w = len, h = bt }, { x = rx - bt, y = iy, w = bt, h = len },
		{ x = ix, y = by - bt, w = len, h = bt }, { x = ix, y = by - len, w = bt, h = len },
		{ x = rx - len, y = by - bt, w = len, h = bt }, { x = rx - bt, y = by - len, w = bt, h = len },
	}
	return { thick = t, inner = inner, brackets = brackets }
end

-- Content rectangle inside the border (px from the panel origin).
function PanelBorder.content(w, h)
	local t = PanelBorder.thickness(w, h)
	return { x = t, y = t, w = math.max(0, w - 2 * t), h = math.max(0, h - 2 * t) }
end

-- True when the skin supplies slice-friendly panel art (SetSkinArt slot panelFrame9); otherwise the code border is used.
function PanelBorder.sliceable(images)
	return images ~= nil and images.panelFrame9 ~= nil and images.panelFrame9 ~= ""
end

return PanelBorder
