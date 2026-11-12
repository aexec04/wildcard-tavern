--[[
	Shared/Engine/RegularsLayout.lua
	Where the Tavern Regulars hang on the Menu: small framed portraits on the chimney stone above the fireplace of the painted Menu room
	(menu_scene_a, the free wall above the mantel; measured with art-wip/menu_scene/debug_regulars_candidates.png). The spot is a
	rectangle of the PICTURE mapped through the same cover crop as the room (Engine/MenuRoomLayout.cover), so the frames keep their place
	on the wall at every screen size. Pure Lua, tested in EngineTests ("RegularsLayout").

	RegularsLayout.compute(W, H, count)   { frames = { { x, y, w, h, tilt, cord }, ... }, fallback = bool, spot = { x, y, w, h } }
	    at most 6 frames (3 on a narrow screen), each at least 44 px on a side, never over a Menu hotspot. When the chimney is cropped
	    away by the screen shape (phones) the frames hang in one short row at the top left instead.
]]

local MenuRoomLayout = require(script.Parent.MenuRoomLayout)

local RegularsLayout = {}

RegularsLayout.SPOT = { l = 0.02, t = 0.12, r = 0.20, b = 0.27 } -- picture fractions: the stone above the mantel, left of the lantern
RegularsLayout.MAX = 6
RegularsLayout.MAX_NARROW = 3
RegularsLayout.NARROW_BELOW = 900
RegularsLayout.MIN_SIDE = 44
RegularsLayout.GAP = 8
RegularsLayout.ASPECT = 0.8 -- frame width over height (a portrait)
RegularsLayout.CORD = 8 -- px of cord between the nail and the frame
RegularsLayout.SIZES = { 1, 0.92, 0.97, 0.95, 1, 0.9 } -- each frame a little different
RegularsLayout.TILTS = { -1.5, 1, -1, 1.5, -0.5, 1 } -- degrees, at most 2

function RegularsLayout.compute(W, H, count)
	local out = { frames = {}, fallback = false }
	local n = math.min(count or 0, W >= RegularsLayout.NARROW_BELOW and RegularsLayout.MAX or RegularsLayout.MAX_NARROW)
	if n <= 0 then return out end
	local S = RegularsLayout.SPOT
	local pw, ph, ox, oy = MenuRoomLayout.cover(W, H)
	local sx, sy = ox + S.l * pw, oy + S.t * ph
	local sw, sh = (S.r - S.l) * pw, (S.b - S.t) * ph
	local M = RegularsLayout.MIN_SIDE
	local gap = RegularsLayout.GAP
	local cols, rows = math.min(3, n), math.ceil(n / 3)
	-- the chimney must be on screen with room for the frames, else they hang at the top left
	local needW, needH = cols * M + (cols - 1) * gap, rows * math.ceil(M / RegularsLayout.ASPECT) + (rows - 1) * gap
	local visible = sx >= 0 and sy >= 0 and sx + sw <= W and sy + sh <= H and sw >= needW * 0.9 and sh >= needH * 0.9
	if not visible then
		out.fallback = true
		cols, rows = n, 1
		local side = 52
		sx, sy, sw, sh = 12, 64, cols * side + (cols - 1) * gap, math.ceil(side / RegularsLayout.ASPECT)
	end
	out.spot = { x = sx, y = sy, w = sw, h = sh }
	local cellW = (sw - (cols - 1) * gap) / cols
	local cellH = (sh - (rows - 1) * gap) / rows
	for i = 1, n do
		local col, row = (i - 1) % cols, math.floor((i - 1) / cols)
		local base = math.max(M, math.min(cellW, cellH * RegularsLayout.ASPECT))
		local fw = math.max(M, math.floor(base * RegularsLayout.SIZES[i] + 0.5))
		local fh = math.ceil(fw / RegularsLayout.ASPECT)
		-- centred in its cell (cells keep at least the minimum size, so a tight spot spills a few px rather than shrinking a frame)
		local cx = sx + col * (cellW + gap) + cellW / 2
		local cy = sy + row * (cellH + gap) + cellH / 2
		if cellW < M then cx = sx + col * (M + gap) + M / 2 end
		if cellH < fh then cy = sy + row * (fh + gap) + fh / 2 end
		out.frames[i] = {
			x = math.floor(cx - fw / 2 + 0.5), y = math.floor(cy - fh / 2 + 0.5), w = fw, h = fh,
			tilt = RegularsLayout.TILTS[i], cord = RegularsLayout.CORD,
		}
	end
	return out
end

return RegularsLayout
