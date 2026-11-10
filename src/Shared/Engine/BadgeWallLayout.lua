--[[
	Engine/BadgeWallLayout.lua
	Pure layout and ordering maths for the Badges trophy wall (Client/BadgeWall.lua, Client/BadgesPanel.lua). No Roblox
	APIs, unit tested. Each shelf tab has its own furniture and its own badge arrangement:
	  All      glass trophy cabinet: three shelves, every badge
	  Roads    map board: first-clear road badges pinned in one straight row in road order, string lines between neighbours
	  Masters  velvet board: seven road masters in a row on brass pins, the Master Tavern badge larger at the centre
	  Night    night sky: each Night badge is a star in a constellation line
	  Special  curio shelf: two rows of hooks
	Badge sizes are squares in px; every item also reserves NAMEPLATE_H px under the badge for its brass nameplate.
]]

local Badges = require(script.Parent.Badges)

local Wall = {}

Wall.NAMEPLATE_H = 24
Wall.FURNITURE = { All = "cabinet", Roads = "map_board", Masters = "velvet_board", Night = "night_sky", Special = "curio_shelf" }
-- art keys (Engine/BadgeWallArt.lua) used by each furniture piece
Wall.FURNITURE_ART = { cabinet = "badge_cabinet", map_board = "badge_map_board", velvet_board = "badge_velvet_board", night_sky = "badge_night_sky", curio_shelf = "badge_curio_shelf" }

local ROAD_ORDER = { "meadow", "river", "peaks", "desert", "swamp", "snow", "coast", "tavern" }

-- Badge definitions that belong on a tab, in display order (the registry order, or road order on Roads and Masters).
function Wall.members(chip, defs)
	defs = defs or Badges.Definitions
	local out = {}
	if chip == "Roads" or chip == "Masters" then
		local tier = chip == "Roads" and "first" or "master"
		for _, region in ipairs(ROAD_ORDER) do
			for _, d in ipairs(defs) do
				if d.tier == tier and d.region == region then out[#out + 1] = d end
			end
		end
		return out
	end
	for _, d in ipairs(defs) do
		if chip == "All" or Badges.chipOf(d) == chip then out[#out + 1] = d end
	end
	return out
end

-- Rows of items: n items spread over `rows` shelves. Returns { x, y, size } per item (top-left px).
local function rowsLayout(n, rows, w, h, top, bottom)
	local perRow = math.ceil(n / rows)
	local cellW = (w * 0.9) / perRow
	local rowH = (h - top - bottom) / rows
	local size = math.floor(math.max(16, math.min(cellW * 0.86, rowH - Wall.NAMEPLATE_H - 10)))
	local out = {}
	for i = 1, n do
		local r = (i - 1) // perRow
		local c = (i - 1) % perRow
		local x0 = (w - perRow * cellW) / 2 -- every row shares the same columns
		out[i] = { x = math.floor(x0 + c * cellW + (cellW - size) / 2), y = math.floor(top + r * rowH + 4), size = size }
	end
	return out
end

-- Item rectangles for a tab on a board of w x h px. Returns { items = { {id, x, y, size, big} }, shelves = {y...} }.
-- `shelves` are the y positions (px) where a plank or hook rail is drawn under a row.
function Wall.layout(chip, defs, w, h)
	local list = Wall.members(chip, defs)
	local items = {}
	local shelves = {}
	if chip == "Roads" then
		local n = #list
		local step = (w * 0.94) / math.max(1, n)
		local size = math.floor(math.max(16, math.min(step * 0.88, h - Wall.NAMEPLATE_H - 24)))
		local y = math.floor((h - size - Wall.NAMEPLATE_H) / 2) -- one straight row, centred
		for i, d in ipairs(list) do
			items[i] = { id = d.id, x = math.floor(w * 0.03 + (i - 1) * step + (step - size) / 2), y = y, size = size }
		end
	elseif chip == "Masters" then
		local row = {}
		local tavern
		for _, d in ipairs(list) do
			if d.region == "tavern" then tavern = d else row[#row + 1] = d end
		end
		local step = (w * 0.94) / math.max(1, #row)
		local size = math.floor(math.min(step * 0.88, h * 0.24))
		local big = math.floor(math.min(h * 0.34, w * 0.3))
		if tavern then
			items[#items + 1] = { id = tavern.id, x = math.floor((w - big) / 2), y = math.floor(h * 0.05), size = big, big = true }
		end
		for i, d in ipairs(row) do
			items[#items + 1] = { id = d.id, x = math.floor(w * 0.03 + (i - 1) * step + (step - size) / 2), y = math.floor(h * 0.62), size = size }
		end
	elseif chip == "Night" then
		local n = #list
		local ys = { 0.5, 0.2, 0.46, 0.14, 0.4, 0.22 }
		local size = math.floor(math.min(w * 0.9 / math.max(1, n) * 0.7, h * 0.3))
		for i, d in ipairs(list) do
			local cx = w * (0.12 + 0.76 * (n > 1 and (i - 1) / (n - 1) or 0.5))
			items[i] = { id = d.id, x = math.floor(cx - size / 2), y = math.floor(h * (ys[(i - 1) % #ys + 1]) + 0), size = size }
		end
	else
		local rows = chip == "All" and 3 or 2
		local pos = rowsLayout(#list, rows, w, h, h * 0.04, h * 0.04)
		local perRow = math.ceil(#list / rows)
		for i, d in ipairs(list) do
			items[i] = { id = d.id, x = pos[i].x, y = pos[i].y, size = pos[i].size }
		end
		local rowH = (h - h * 0.08) / rows
		for r = 1, rows do
			if (r - 1) * perRow < #list then shelves[#shelves + 1] = math.floor(h * 0.04 + r * rowH - 6) end
		end
	end
	return { items = items, shelves = shelves }
end

-- Rectangle of an item including its nameplate, { x, y, w, h }.
function Wall.footprint(item)
	return { x = item.x, y = item.y, w = item.size, h = item.size + Wall.NAMEPLATE_H }
end

-- String / constellation segments for a tab: { { a = id, b = id, lit = bool } } between consecutive badges in order.
-- Only Roads (road order) and Night (Night order) have lines. A segment is lit when both ends are earned.
function Wall.lines(chip, defs, have)
	local out = {}
	if chip ~= "Roads" and chip ~= "Night" then return out end
	local list = Wall.members(chip, defs)
	for i = 1, #list - 1 do
		out[#out + 1] = { a = list[i].id, b = list[i + 1].id, lit = have[list[i].id] == true and have[list[i + 1].id] == true }
	end
	return out
end

local RARITY = { common = 1, uncommon = 2, rare = 3, epic = 4, legendary = 5 }

-- The badge to nudge towards ("Next up"): the first locked badge on the tab, easiest rarity first, then registry order.
-- (Per-badge progress is not on the client, so rarity stands in for "closest".) Nil when everything is earned.
function Wall.nextUp(chip, defs, have)
	local best, bestKey
	for i, d in ipairs(Wall.members(chip, defs)) do
		if not have[d.id] then
			local key = (RARITY[d.rarity] or 9) * 1000 + i
			if not best or key < bestKey then best, bestKey = d, key end
		end
	end
	return best and best.id or nil
end

-- Badges earned since the last time the wall was looked at (`seen` is a set; the first view passes nil and sparkles nothing).
function Wall.fresh(seen, have)
	local out = {}
	if not seen then return out end
	for id, flag in pairs(have) do
		if flag == true and not seen[id] then out[#out + 1] = id end
	end
	table.sort(out)
	return out
end

-- "x of y earned" and the progress fraction.
function Wall.progress(have)
	local total, earned = #Badges.Definitions, 0
	for _, d in ipairs(Badges.Definitions) do
		if have[d.id] == true then earned = earned + 1 end
	end
	return earned, total, total > 0 and earned / total or 0
end

-- Short nameplate text: the badge name when earned, else the requirement hint.
function Wall.plateText(def, owned)
	return owned and def.name or def.hint
end

-- Constellation line between two item centres: { x, y, length, rotation } for a thin Frame centred on the midpoint.
function Wall.segment(ax, ay, bx, by)
	local dx, dy = bx - ax, by - ay
	return { x = (ax + bx) / 2, y = (ay + by) / 2, length = math.sqrt(dx * dx + dy * dy), rotation = math.deg(math.atan(dy, dx)) }
end

return Wall
