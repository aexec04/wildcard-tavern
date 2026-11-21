--[[
	Shared/Engine/MapFitRules.lua
	Pure layout of the Night route on the Tavern Map so the whole route (start, Nights, boss) fits the frame at the default zoom, like the
	reference: nodes about 110 px at 1920x957, the boss about 150 px, the road a gentle zigzag that stays under the header and above the lower
	left panel. Client/JourneyMapView draws exactly these numbers. No Roblox types.

	layout(sw, sh, names, nightCap) -> { viewH, nodeSize, bossSize, leftPad, rightPad, spacing, canvasW, canvasH, mid, amp, labelW, fits, posX, posY }
	  sw, sh = the map frame (the whole screen); names = every node name in order (Nights, then Endless and its milestones)
	boxes(res, names, nightCap)     -> { { x0, x1, y0, y1 } } circle and label (name, type tag, reward tag) box of each node, canvas pixels
	frameOffset                     -> the scroll view's top left inside the frame (8, 6): canvas y = screen y - 6
]]

local HeaderRules = require(script.Parent.MapHeaderRules)

local M = {}

M.NODE_FRACTION = 0.14 -- node diameter as a share of the view height (131 px at 1920x957, like the reference)
M.NODE_MIN, M.NODE_MAX = 64, 140
M.BOSS_SCALE = 1.42 -- 186 px beside a 131 px node
M.LABEL_GAP, M.NAME_H, M.TYPE_H, M.REWARD_H = 10, 23, 20, 24
M.BELOW = M.LABEL_GAP + M.NAME_H + 2 + M.TYPE_H + 8 + M.REWARD_H -- from a node's lower edge to the bottom of its reward tag
M.FRAME_X, M.FRAME_Y = 8, 6
M.MARGIN = 10

local function clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end

local RouteRules = require(script.Parent.MapRouteRules)

-- the name plate: text plus 24, never wider than 180 px (longer names wrap to two lines, the room is in the hidden reward row)
local function labelWidth(name, spacing)
	local cap = clamp(math.floor(spacing * 0.85), 150, RouteRules.PLATE_MAX)
	return math.min(RouteRules.plate(name, 17, RouteRules.PLATE_MAX).w, cap)
end

local function positions(count, leftPad, spacing, mid, amp)
	local xs, ys = {}, {}
	for i = 1, count do
		-- a gentle S: one slow sine along the route (neighbours differ by well under the spacing), not an up and down zigzag
		xs[i] = leftPad + (i - 1) * spacing
		ys[i] = mid + amp * math.sin((i - 1) * 1.05)
	end
	return xs, ys
end

function M.boxes(res, names, nightCap)
	local out = {}
	for i = 1, #names do
		local size = (i == nightCap) and res.bossSize or res.nodeSize
		local x, y = res.posX[i], res.posY[i]
		local w = labelWidth(names[i], res.spacing)
		out[i] = {
			circle = { x0 = x - size / 2, x1 = x + size / 2, y0 = y - size / 2, y1 = y + size / 2 },
			label = { x0 = x - w / 2, x1 = x + w / 2, y0 = y + size / 2 + M.LABEL_GAP, y1 = y + size / 2 + M.BELOW },
		}
	end
	return out
end

local function overlap(a, b) return a.x0 < b.x1 and b.x0 < a.x1 and a.y0 < b.y1 and b.y0 < a.y1 end

-- true when no node's circle or label touches another node's circle or label
function M.clear(res, names, nightCap)
	local bx = M.boxes(res, names, nightCap)
	for i = 1, #bx do
		for j = i + 1, #bx do
			if overlap(bx[i].circle, bx[j].circle) or overlap(bx[i].circle, bx[j].label) or overlap(bx[i].label, bx[j].circle) or overlap(bx[i].label, bx[j].label) then
				return false
			end
		end
	end
	return true
end

function M.layout(sw, sh, names, nightCap)
	nightCap = nightCap or 8
	local count = #names
	local viewW, viewH = math.max(10, sw - 2 * M.FRAME_X), math.max(260, sh - 2 * M.FRAME_Y - 4)
	local nodeSize = clamp(math.floor(viewH * M.NODE_FRACTION), M.NODE_MIN, M.NODE_MAX)
	local bossSize = math.floor(nodeSize * M.BOSS_SCALE)
	local H = HeaderRules.layout(sw, sh)
	-- vertical room for a node stack: under the header, above the lower left panel (canvas y = screen y - FRAME_Y)
	local yMin = H.bar.h + M.MARGIN + math.floor(bossSize / 2) - M.FRAME_Y
	local yMax = H.panelZone.y - M.MARGIN - math.floor(nodeSize / 2) - M.BELOW - M.FRAME_Y
	local mid, amp
	if yMax > yMin then
		mid = (yMin + yMax) / 2
		amp = math.min(viewH * 0.07, (yMax - yMin) / 2) -- about 66 px each way: a 130 px swing over the route
	else
		mid, amp = yMin, 0
	end
	local leftPad = math.max(64, math.floor(sw * 0.085))
	local rightPad = math.max(math.floor(sw * 0.05), math.floor(bossSize / 2) + 20)
	local first = math.max(1, nightCap - 1)
	local spacing = (viewW - leftPad - rightPad) / first
	local res = { nodeSize = nodeSize, bossSize = bossSize, leftPad = leftPad, rightPad = rightPad, mid = mid, amp = amp, viewH = viewH }
	-- widen the spacing until neighbours do not touch (long names on small screens may need to scroll a little)
	local s = math.max(spacing, nodeSize + 8)
	while true do
		res.spacing = s
		res.posX, res.posY = positions(count, leftPad, s, mid, amp)
		if s >= 420 or M.clear(res, names, nightCap) then break end
		s = s + 4
	end
	local labelW = clamp(math.floor(res.spacing * 0.85), 150, 230)
	res.labelW = labelW
	res.canvasW = math.floor(leftPad + (count - 1) * res.spacing + rightPad)
	res.canvasH = viewH -- one screen tall: the whole route is in view
	local lastX = res.posX[math.min(nightCap, count)] or 0
	res.fits = lastX + math.max(bossSize / 2, labelW / 2) <= viewW
	return res
end

return M
