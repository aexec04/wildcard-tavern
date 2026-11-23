--[[
	Shared/Engine/SellUndo.lua
	The 5 second Undo window after selling a Patron. Pure: the server stamps the sale with its own clock and checks it again on Undo.

	SellUndo.WINDOW        5 seconds
	SellUndo.GRACE         1 second of network slack the server allows on top
	SellUndo.line(refund)  "Sold for +3 Tips" (40 characters or less)
	SellUndo.button(left)  "Undo (5)" with whole seconds left
	SellUndo.remaining(sale, now)   seconds left (0 when expired or no sale)
	SellUndo.valid(sale, now)       true while the server still honours the Undo
	SellUndo.layout(w, h)  { x, y, w, h } of the plate: bottom centre, 44 px high, always on screen
]]

local SellUndo = {}

SellUndo.WINDOW = 5
SellUndo.GRACE = 1
SellUndo.PLATE_H = 44
SellUndo.PLATE_W = 300

function SellUndo.line(refund)
	return string.format("Sold for +%d Tips", math.max(0, math.floor(tonumber(refund) or 0)))
end

function SellUndo.button(left)
	return string.format("Undo (%d)", math.max(0, math.ceil(tonumber(left) or 0)))
end

function SellUndo.remaining(sale, now)
	if type(sale) ~= "table" or type(sale.at) ~= "number" or type(now) ~= "number" then return 0 end
	return math.max(0, SellUndo.WINDOW - (now - sale.at))
end

function SellUndo.valid(sale, now)
	if type(sale) ~= "table" or type(sale.at) ~= "number" or type(now) ~= "number" then return false end
	local age = now - sale.at
	return age >= 0 and age <= SellUndo.WINDOW + SellUndo.GRACE
end

function SellUndo.layout(w, h)
	w, h = math.max(1, math.floor(w)), math.max(1, math.floor(h))
	local pw = math.min(SellUndo.PLATE_W, w - 16)
	local ph = SellUndo.PLATE_H
	return { x = math.floor((w - pw) / 2), y = math.max(0, h - ph - 24), w = pw, h = ph }
end

return SellUndo
