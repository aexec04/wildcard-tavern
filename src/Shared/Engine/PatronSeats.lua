--[[
	Shared/Engine/PatronSeats.lua
	Pure numbers and words (tested) for the My Patrons tab: the Sell plate that shows what you get, the seat order strip with
	an order number per Patron and left / right buttons. Client/Shop reads it; RunState.movePatron does the move.

	PatronSeats.sellLabel(refund)      "Sell +3" (the value is the tips back, same number the confirm dialog says)
	PatronSeats.orderText(i, n)        "1 of 5"
	PatronSeats.canMove(i, n, dir)     dir -1 (left) or 1 (right); false at either end
	PatronSeats.stripSize(zoneW, n)    { groupW, btn, h } every control at least 44 px, groups share the width up to 200 px
	PatronSeats.MIN_TOUCH, PatronSeats.STRIP_H
]]

local M = {}

M.MIN_TOUCH = 44
M.STRIP_H = 48
M.MAX_GROUP_W = 200
M.GAP = 6

function M.sellLabel(refund)
	return string.format("Sell +%d", math.floor(tonumber(refund) or 0))
end

function M.orderText(i, n)
	return string.format("%d of %d", math.floor(i), math.floor(n))
end

function M.canMove(i, n, dir)
	if dir ~= -1 and dir ~= 1 then return false end
	local target = i + dir
	return target >= 1 and target <= n
end

-- The seat name on one line: { size, text }. Largest size 15 down to 11 that fits labelW minus 4 px each side, else clipped at 11.
function M.nameFit(name, labelW)
	local TextFit = require(script.Parent.TextFit)
	name = tostring(name or "")
	local w = math.max(1, labelW - 8)
	for s = 15, 11, -1 do
		if TextFit.width(name, s) <= w then return { size = s, text = name } end
	end
	return { size = 11, text = TextFit.clip(name, w, 11) }
end

function M.stripSize(zoneW, n)
	n = math.max(1, math.floor(n))
	local group = math.floor((zoneW - (n - 1) * M.GAP) / n)
	group = math.max(M.MIN_TOUCH * 2 + 20, math.min(M.MAX_GROUP_W, group))
	return { groupW = group, btn = M.MIN_TOUCH, h = M.STRIP_H, total = n * group + (n - 1) * M.GAP }
end

return M
