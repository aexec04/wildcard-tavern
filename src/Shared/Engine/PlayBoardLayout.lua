--[[
	Shared/Engine/PlayBoardLayout.lua
	Pure geometry for the painted left HUD board (art key play_board_a, 1024x1536, hangs from ropes). Slot rects are measured
	from the PNG (art-wip/play_scene/debug_board.png) in picture pixels; `map` scales them to a panel rect.

	PlayBoardLayout.size(screenW, screenH) -> w, h : the board fits the screen height at its 2:3 ratio, width at most 24 percent of the screen
	PlayBoardLayout.map(w, h)  -> { title, target, wide, hands, discards, rings = { {cx, cy, d} x5 }, ringInset }
	PlayBoardLayout.usable(screenW)  false under MIN_W: use the old layout
]]

local M = {}

M.IMG_W, M.IMG_H = 1024, 1536
M.MIN_W = 900
M.MAX_WIDTH_FRACTION = 0.24

M.SLOTS = {
	title = { x = 280, y = 388, w = 462, h = 110 }, -- Night 1/8 and Round
	target = { x = 232, y = 538, w = 560, h = 204 }, -- target and score, bar, Reward
	wide = { x = 236, y = 784, w = 554, h = 154 }, -- Tips and the round rule
	hands = { x = 232, y = 974, w = 264, h = 144 },
	discards = { x = 528, y = 974, w = 264, h = 144 },
}
-- The five brass rings, measured from play_board_a (art-wip/play_scene/ring_measure: the dark hole of each ring, area equivalent
-- diameter 72 px, bbox 73 to 76; debug overlay art-wip/play_scene/debug_rings_measured.png). RING_D is the outer brass diameter.
M.RING_Y, M.RING_D, M.HOLE_D = 1205, 100, 72
M.RING_X = { 281, 394, 510, 625, 738 }
M.SEAT_FILL = 0.84 -- a Patron portrait is 84 percent of the hole, so it never touches the brass
-- Seats beyond the five painted rings sit on the wooden base under the board, each in a matching brass ring drawn in code
-- (hole 56, outer 1.375 times the hole like the painted ones), in one centred row; they shrink when there are many.
M.EXTRA = { y = 1352, hole = 56, centre = 512, span = 370, pitch = 92, ringRatio = 1.375 }

function M.usable(screenW)
	return screenW >= M.MIN_W
end

function M.size(screenW, screenH)
	local h = screenH
	local w = h * M.IMG_W / M.IMG_H
	local maxW = screenW * M.MAX_WIDTH_FRACTION
	if w > maxW then
		w = maxW
		h = w * M.IMG_H / M.IMG_W
	end
	return math.floor(w), math.floor(h)
end

-- The painted board's rect on screen: top left, 2:3, nil when the window is too narrow (old flat panel stays).
function M.placement(screenW, screenH)
	if not M.usable(screenW) then return nil end
	local w, h = M.size(screenW, screenH)
	if w < 100 or h < 150 then return nil end
	return { x = 0, y = 0, w = w, h = h }
end

function M.map(w, h)
	local sx, sy = w / M.IMG_W, h / M.IMG_H
	local function r(s)
		return { x = math.floor(s.x * sx + 0.5), y = math.floor(s.y * sy + 0.5), w = math.floor(s.w * sx + 0.5), h = math.floor(s.h * sy + 0.5) }
	end
	local out = { rings = {}, seatFill = M.SEAT_FILL }
	for k, s in pairs(M.SLOTS) do
		out[k] = r(s)
	end
	for i, cx in ipairs(M.RING_X) do
		out.rings[i] = { cx = math.floor(cx * sx + 0.5), cy = math.floor(M.RING_Y * sy + 0.5), d = math.floor(M.RING_D * sx + 0.5), hole = math.floor(M.HOLE_D * sx + 0.5) }
	end
	return out
end

-- Where the live HUD rows go on a board of w x h px (board coordinates, top left origin). The round title gets the width of the
-- target slot (about 200 px at 1506x751), the round rule has the whole wide slot (Tips has no slot: it goes on the plate under the
-- board), Hands and Discards keep their two slots (their union is the box that holds both columns); the Patron seats sit on the
-- five rings, or spread over the ring span when there are more than five. Tested: everything inside the board, seats never overlap.
function M.hud(w, h)
	local m = M.map(w, h)
	local s = w / M.IMG_W
	local gap = math.max(2, math.floor(6 * s + 0.5))
	local out = {
		title = { x = m.target.x, y = m.title.y, w = m.target.w, h = m.title.h }, target = m.target,
		rule = m.wide,
		hands = m.hands, discards = m.discards,
		handsDiscards = { x = m.hands.x, y = m.hands.y, w = m.discards.x + m.discards.w - m.hands.x, h = m.hands.h },
	}
	local d = m.rings[1].d
	out.ringRow = { x = m.target.x, y = m.rings[1].cy - math.floor(d / 2) - gap, w = m.target.w, h = d + 2 * gap }
	return out
end

-- Seat rects (top left x, y and size in board coordinates) for n Patron seats. Seats 1 to 5 sit in the painted ring holes, each
-- centred on its hole at 84 percent of the hole's diameter. A sixth seat and beyond sit in one centred row on the wooden base under the
-- board, with `extra = true` and `ring = { cx, cy, d }` for the brass ring the client draws around them.
function M.seats(w, h, n)
	local m = M.map(w, h)
	local sx, sy = w / M.IMG_W, h / M.IMG_H
	local out = {}
	if n <= 0 then return out end
	for i = 1, math.min(n, #m.rings) do
		local r = m.rings[i]
		local size = math.max(12, math.floor(r.hole * M.SEAT_FILL + 0.5))
		out[i] = { x = r.cx - math.floor(size / 2), y = r.cy - math.floor(size / 2), w = size, h = size }
	end
	local k = n - #m.rings
	if k > 0 then
		local E = M.EXTRA
		local pitch = math.min(E.pitch, E.span / k)
		local hole = math.max(16, math.min(E.hole, math.floor(pitch) - 8))
		for j = 1, k do
			local cx = (E.centre + (j - (k + 1) / 2) * pitch) * sx
			local cy = E.y * sy
			local size = math.max(12, math.floor(hole * sx * M.SEAT_FILL + 0.5))
			out[#m.rings + j] = {
				x = math.floor(cx - size / 2 + 0.5), y = math.floor(cy - size / 2 + 0.5), w = size, h = size, extra = true,
				ring = { cx = math.floor(cx + 0.5), cy = math.floor(cy + 0.5), d = math.max(size + 4, math.floor(hole * E.ringRatio * sx + 0.5)) },
			}
		end
	end
	return out
end

return M
