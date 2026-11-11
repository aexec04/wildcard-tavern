--[[
	Shared/Engine/SeatFit.lua
	Pure sizing for the left HUD Patron seats (tested). Seats share ONE row: with 5 seats or fewer they keep
	their full size, with more they shrink (never below `minSize`) so the Patrons plate never wraps to a
	second row and never grows into the plates below it.

	  SeatFit.size(count, usableWidth, gap, maxSize, minSize) -> seat size in px (integer)
	  SeatFit.rowWidth(count, size, gap) -> width the row needs
]]

local SeatFit = {}

function SeatFit.rowWidth(count, size, gap)
	if count <= 0 then return 0 end
	return count * size + (count - 1) * gap
end

function SeatFit.size(count, usableWidth, gap, maxSize, minSize)
	if count <= 1 then return maxSize end
	local fit = math.floor((usableWidth - (count - 1) * gap) / count)
	return math.max(minSize, math.min(maxSize, fit))
end

return SeatFit
