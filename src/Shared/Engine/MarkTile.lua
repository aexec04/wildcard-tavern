--[[
	MarkTile.lua
	What the Counter Mark pack tile and the Tavern Map Market tile look like, as data, so both are drawn the same and a test can hold the
	rules on all Card Sets and four screen sizes. Pure Lua, no Roblox APIs. Static (no tween), so Calm mode and Reduce motion need nothing.

	MarkTile.style(setId)         -> { plate, edge, ink } : the set's dark plate, edge and cream ink at 7:1 (CosmeticSets.hintStyleOf);
	                                 classic gets the dark brown plate with the brass edge, the same as the mark badge
	MarkTile.icon(markId)         -> { imageKey = markId, letter } : the painted badge (ContentArt "mark_badges") with the drawn letter as the fallback
	MarkTile.lines(kind, markId, price)
	                              -> { title, body, price, action }; kind is "pack" (Counter) or "market" (Tavern Map). Exactly the mark you get.
	MarkTile.layout(areaW, areaH) -> { w, h, pad, icon, titleSize, bodySize, priceSize, actionH } or nil when the area is too small
]]

local Card = require(script.Parent.Card)
local CosmeticSets = require(script.Parent.CosmeticSets)
local MarkBadge = require(script.Parent.MarkBadge)

local MarkTile = {}

MarkTile.MIN_TEXT = 14
MarkTile.ACTION_H = 44
MarkTile.MIN_INK_CONTRAST = 7
MarkTile.MIN_EDGE_CONTRAST = 3
MarkTile.CLASSIC = { plate = { 36, 24, 16 }, edge = { 214, 170, 78 }, ink = { 255, 244, 222 } }

function MarkTile.style(setId)
	local s = CosmeticSets.hintStyleOf(setId)
	if not s then
		local c = MarkTile.CLASSIC
		return { plate = { c.plate[1], c.plate[2], c.plate[3] }, edge = { c.edge[1], c.edge[2], c.edge[3] }, ink = { c.ink[1], c.ink[2], c.ink[3] } }
	end
	-- some set edges are dim on their own plate (Closing Time): lift the edge until it reads at 3:1, as the mark badge does
	local edge = { s.edge[1], s.edge[2], s.edge[3] }
	local guard = 0
	while CosmeticSets.contrastRatio(edge, s.plate) < MarkTile.MIN_EDGE_CONTRAST and guard < 12 do
		edge = { math.min(255, edge[1] + 24), math.min(255, edge[2] + 24), math.min(255, edge[3] + 24) }
		guard = guard + 1
	end
	return { plate = s.plate, edge = edge, ink = s.ink }
end

function MarkTile.icon(markId)
	local def = type(markId) == "string" and Card.Marks[markId] or nil
	if not def then return nil end
	return { imageKey = markId, letter = def.icon }
end

function MarkTile.lines(kind, markId, price)
	local def = type(markId) == "string" and Card.Marks[markId] or nil
	if not def then return nil end
	local n = math.floor(tonumber(price) or 0)
	return {
		title = def.name .. " Mark",
		body = def.description,
		price = n .. " Tips",
		action = kind == "market" and "Choose a card" or "Pick a card",
	}
end

local function clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end

-- Tile size inside the area it must fit in (the Counter offer row or the Round Select side panel). Never taller than the area, never
-- narrower than the text needs; the action plate is 44 px so a thumb can hit it.
function MarkTile.layout(areaW, areaH)
	areaW, areaH = tonumber(areaW) or 0, tonumber(areaH) or 0
	local pad = 8
	local w = clamp(math.floor(areaW * 0.26), 150, 240)
	local h = clamp(math.floor(areaH * 0.30), 164, 230)
	if w > areaW or h > areaH then return nil end
	local icon = clamp(math.floor(w * 0.22), 28, 48)
	return { w = w, h = h, pad = pad, icon = icon, titleSize = 16, bodySize = MarkTile.MIN_TEXT, priceSize = 16, actionH = MarkTile.ACTION_H }
end

-- The height the stacked parts need at the least: pad, title row (icon tall), two body lines, price, action, pad.
function MarkTile.minHeight(layout)
	return layout.pad + layout.icon + 2 * (layout.bodySize + 2) + layout.priceSize + 4 + layout.actionH + layout.pad
end

MarkTile.badgeSpec = MarkBadge.spec

return MarkTile
