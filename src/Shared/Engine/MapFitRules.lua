--[[
	Shared/Engine/MapFitRules.lua
	Pure layout of the Night route on the Tavern Map so the whole route (start, Nights, boss) fits the frame at the default zoom, like the
	reference: nodes about 110 px at 1920x957, the boss about 150 px, the road a gentle zigzag that stays under the header and above the lower
	left panel. Client/JourneyMapView draws exactly these numbers. No Roblox types.

	layout(sw, sh, names, nightCap, shown) -> { viewH, nodeSize, bossSize, leftPad, rightPad, spacing, canvasW, canvasH, mid, amp, labelW, fits, posX, posY }
	  sw, sh = the map frame (the whole screen); names = every node name in order (Nights, then Endless and its milestones)
	boxes(res, names, nightCap)     -> { { x0, x1, y0, y1 } } circle and label (name, type tag, reward tag) box of each node, canvas pixels
	frameOffset                     -> the scroll view's top left inside the frame (8, 6): canvas y = screen y - 6
]]

local HeaderRules = require(script.Parent.MapHeaderRules)

local M = {}

M.NODE_FRACTION = 0.14 -- node diameter as a share of the view height (131 px at 1920x957, like the reference)
M.NODE_MIN, M.NODE_MAX = 64, 140
M.BOSS_SCALE = 1.42 -- 186 px beside a 131 px node
M.CURRENT_SCALE = 1.3 -- the node the hero stands on: 170 px beside a 131 px node
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

-- slot of each node along the route: a Night that is drawn takes the next slot, one that is hidden shares the gap before the next drawn one,
-- and nodes past the Night cap (Endless) simply follow. shown = list of booleans by index (nil = every node drawn).
function M.slots(count, nightCap, shown)
	local slots, n = {}, 0
	for i = 1, count do
		if shown == nil or shown[i] or i == nightCap then
			slots[i] = n
			n = n + 1
		elseif i > nightCap then
			slots[i] = math.max(0, n - 1) -- an Endless stop that is not drawn yet takes no road: it sits on the last drawn stop
		else
			slots[i] = n - 0.5
		end
	end
	return slots, n
end

M.MAX_GAP_NODES = 1.6 -- Endless stops past the boss sit at most this many node widths apart (never under 200 px so plates stay clear)

local function positions(count, leftPad, spacing, mid, amp, slots, nightCap, nodeSize)
	local xs, ys = {}, {}
	local endSpacing = math.min(spacing, math.max(M.MAX_GAP_NODES * nodeSize, 200))
	for i = 1, count do
		-- a gentle S: one slow sine along the route (neighbours differ by well under the spacing), not an up and down zigzag
		local k = slots[i]
		xs[i] = leftPad + k * spacing
		if nightCap and i > nightCap and slots[nightCap] then
			xs[i] = leftPad + slots[nightCap] * spacing + (k - slots[nightCap]) * endSpacing
		end
		ys[i] = mid + amp * math.sin(k * 1.05)
	end
	return xs, ys
end

-- drawn diameter of node i: the boss is largest, the current node (res.current) next, the rest nodeSize
function M.sizeOf(res, i, nightCap)
	if i == nightCap then return res.bossSize end
	if i == res.current then return res.currentSize end
	return res.nodeSize
end

function M.boxes(res, names, nightCap)
	local out = {}
	for i = 1, #names do
		local size = M.sizeOf(res, i, nightCap)
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
	local function drawn(i) return res.shown == nil or i == nightCap or res.shown[i] == true end
	for i = 1, #bx do
		for j = i + 1, #bx do
			if drawn(i) and drawn(j) and (overlap(bx[i].circle, bx[j].circle) or overlap(bx[i].circle, bx[j].label) or overlap(bx[i].label, bx[j].circle) or overlap(bx[i].label, bx[j].label)) then
				return false
			end
		end
	end
	return true
end

function M.layout(sw, sh, names, nightCap, shown, current)
	nightCap = nightCap or 8
	local count = #names
	local viewW, viewH = math.max(10, sw - 2 * M.FRAME_X), math.max(260, sh - 2 * M.FRAME_Y - 4)
	local nodeSize = clamp(math.floor(viewH * M.NODE_FRACTION), M.NODE_MIN, M.NODE_MAX)
	local bossSize = math.floor(nodeSize * M.BOSS_SCALE)
	local currentSize = math.floor(nodeSize * M.CURRENT_SCALE)
	local H = HeaderRules.layout(sw, sh)
	-- vertical room for a node stack: under the header, above the lower left panel (canvas y = screen y - FRAME_Y)
	local yMin = H.bar.h + M.MARGIN + math.floor(bossSize / 2) - M.FRAME_Y
	local yMax = H.panelZone.y - M.MARGIN - math.floor(currentSize / 2) - M.BELOW - M.FRAME_Y
	local mid, amp
	if yMax > yMin then
		mid = (yMin + yMax) / 2
		amp = math.min(viewH * 0.07, (yMax - yMin) / 2) -- about 66 px each way: a 130 px swing over the route
	else
		mid, amp = yMin, 0
	end
	local leftPad = math.max(64, math.floor(sw * 0.085))
	local rightPad = math.max(math.floor(sw * 0.05), math.floor(bossSize / 2) + 20, RouteRules.PLATE_MAX / 2 + 4) -- room for the boss and its plate
	local slots, _ = M.slots(count, nightCap, shown)
	local first = math.max(1, (slots[math.min(nightCap, count)] or (nightCap - 1))) -- gaps from the start to the boss: the drawn nodes spread over the width
	local spacing = (viewW - leftPad - rightPad) / first
	local res = { shown = shown, current = current, currentSize = currentSize, nodeSize = nodeSize, bossSize = bossSize, leftPad = leftPad, rightPad = rightPad, mid = mid, amp = amp, viewH = viewH }
	-- widen the spacing until neighbours do not touch (long names on small screens may need to scroll a little)
	local s = math.max(spacing, currentSize + 8)
	while true do
		res.spacing = s
		res.posX, res.posY = positions(count, leftPad, s, mid, amp, slots, nightCap, nodeSize)
		if s >= 420 or M.clear(res, names, nightCap) then break end
		s = s + 4
	end
	local labelW = clamp(math.floor(res.spacing * 0.85), 150, 230)
	res.labelW = labelW
	local lastDrawnX = 0
	for i = 1, count do
		if shown == nil or shown[i] or i == nightCap then lastDrawnX = math.max(lastDrawnX, res.posX[i]) end
	end
	res.canvasW = math.floor(lastDrawnX + rightPad)
	res.canvasH = viewH -- one screen tall: the whole route is in view
	local lastX = res.posX[math.min(nightCap, count)] or 0
	res.fits = lastX + math.max(bossSize / 2, math.min(labelW, RouteRules.PLATE_MAX) / 2) <= viewW
	return res
end

-- scroll x (canvas x of the view's left edge) that keeps the canvas filled and the current stop, or else the next stop, in view
function M.clampScroll(x, viewW, canvasW, currentX, nextX, margin)
	margin = margin or 60
	local maxX = math.max(0, canvasW - viewW)
	x = clamp(x, 0, maxX)
	local anchor = currentX or nextX
	if not anchor then return x end
	local lo = math.max(0, anchor + margin - viewW) -- the anchor stays inside [x + margin, x + viewW - margin]
	local hi = math.min(maxX, anchor - margin)
	if lo > hi then return clamp(anchor - viewW / 2, 0, maxX) end
	return clamp(x, lo, hi)
end

-- true when no two consecutive drawn stops are more than maxGap px apart (returns false and the offending index otherwise)
function M.gapsOk(res, count, nightCap, shown, maxGap)
	local prev
	for i = 1, count do
		if shown == nil or shown[i] or i == nightCap then
			if prev and res.posX[i] - res.posX[prev] > maxGap then return false, i end
			prev = i
		end
	end
	return true
end

return M
