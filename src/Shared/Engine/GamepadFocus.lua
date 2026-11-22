--[[
	Shared/Engine/GamepadFocus.lua
	Pure rules for D-pad focus on menu screens (Menu, Settings, Store, Collection and every popup). No Roblox APIs.

	GamepadFocus.DIRS                       D-pad key name -> { dx, dy }
	GamepadFocus.RING                       the focus ring: gold, 3 px
	GamepadFocus.next(items, current, dir)  items = list of { id, x, y, w, h } (pixels, visible and enabled buttons of the one active
	                                        screen); current = id or nil; dir = "DPadLeft" | "DPadRight" | "DPadUp" | "DPadDown".
	                                        Returns the id to focus: the nearest item in that direction (axis distance plus half the
	                                        sideways offset), wrapping to the far side when nothing lies ahead, and the first item
	                                        (top left) when nothing is focused yet. nil only when items is empty.
	GamepadFocus.reachable(items, w, h)     true when every item can be reached from the first one with D-pad moves (no stranded button)
]]

local M = {}

M.DIRS = { DPadLeft = { -1, 0 }, DPadRight = { 1, 0 }, DPadUp = { 0, -1 }, DPadDown = { 0, 1 } }
M.RING = { color = { 246, 196, 70 }, thickness = 3 }

local function centre(it) return it.x + it.w / 2, it.y + it.h / 2 end

local function first(items)
	local best
	for _, it in ipairs(items) do
		local cx, cy = centre(it)
		if not best or cy < best.cy - 4 or (math.abs(cy - best.cy) <= 4 and cx < best.cx) then best = { id = it.id, cx = cx, cy = cy } end
	end
	return best and best.id or nil
end

function M.next(items, current, dir)
	if type(items) ~= "table" or #items == 0 then return nil end
	local d = M.DIRS[dir]
	local from
	for _, it in ipairs(items) do if it.id == current then from = it end end
	if not d or not from then return first(items) end
	local fx, fy = centre(from)
	local best, bestScore, far, farScore
	for _, it in ipairs(items) do
		if it.id ~= from.id then
			local cx, cy = centre(it)
			local along = (cx - fx) * d[1] + (cy - fy) * d[2]
			local side = math.abs((cx - fx) * d[2]) + math.abs((cy - fy) * d[1])
			if along > 0 then
				local score = along + side * 0.5
				if not bestScore or score < bestScore then best, bestScore = it.id, score end
			elseif along < 0 then -- wrap: the item farthest back, closest to this row or column
				local score = -along - side * 0.5
				if not farScore or score > farScore then far, farScore = it.id, score end
			end
		end
	end
	return best or far or from.id
end

function M.reachable(items)
	if #items <= 1 then return true end
	local seen, stack = {}, { first(items) }
	seen[stack[1]] = true
	local n = 1
	while #stack > 0 do
		local id = table.remove(stack)
		for dir in pairs(M.DIRS) do
			local nxt = M.next(items, id, dir)
			if nxt and not seen[nxt] then seen[nxt] = true; n = n + 1; stack[#stack + 1] = nxt end
		end
	end
	return n == #items
end

return M
