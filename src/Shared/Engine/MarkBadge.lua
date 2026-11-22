--[[
	MarkBadge.lua
	What the small corner badge of a marked card looks like, as data, so the Deck tracker, the hand and the Counter draw the same
	one and a test can hold the colours to 4.5:1. Pure Lua, no Roblox APIs. The badge is code drawn (a rounded square with one
	letter, no picture), static, so Calm mode and Reduce motion need nothing.

	MarkBadge.spec(markId, accent)  ->  { letter, fill, ink, edge } or nil for no mark.
	  letter  one capital letter (G, L, V) so it reads without colour
	  fill    dark plate, always (so cream ink reads on light and dark card faces alike)
	  ink     cream
	  edge    the Card Set accent (3 numbers, or a fallback gold), lifted until it reads against the fill at 3:1
	MarkBadge.caption(markId)       one line for the tracker: "Gilded: +30 Chips when this card scores."
]]

local Card = require(script.Parent.Card)
local CosmeticSets = require(script.Parent.CosmeticSets)

local MarkBadge = {}

MarkBadge.FILL = { 36, 24, 16 }
MarkBadge.INK = { 255, 244, 222 }
MarkBadge.FALLBACK_EDGE = { 214, 170, 78 }
MarkBadge.EDGE_MIN_CONTRAST = 3

local function lift(c)
	return { math.min(255, c[1] + 24), math.min(255, c[2] + 24), math.min(255, c[3] + 24) }
end

function MarkBadge.spec(markId, accent)
	local def = type(markId) == "string" and Card.Marks[markId] or nil
	if not def then return nil end
	local edge = (type(accent) == "table" and #accent == 3) and { accent[1], accent[2], accent[3] } or { MarkBadge.FALLBACK_EDGE[1], MarkBadge.FALLBACK_EDGE[2], MarkBadge.FALLBACK_EDGE[3] }
	local guard = 0
	while CosmeticSets.contrastRatio(edge, MarkBadge.FILL) < MarkBadge.EDGE_MIN_CONTRAST and guard < 12 do
		edge = lift(edge)
		guard = guard + 1
	end
	return { letter = def.icon, fill = MarkBadge.FILL, ink = MarkBadge.INK, edge = edge }
end

function MarkBadge.caption(markId)
	local def = type(markId) == "string" and Card.Marks[markId] or nil
	if not def then return "" end
	return def.name .. ": " .. def.description
end

return MarkBadge
