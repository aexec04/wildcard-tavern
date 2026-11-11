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

Wall.NAMEPLATE_H = 42 -- two lines of 15 px name text on a solid plate, never truncated
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

-- Every badge sits in a round socket (a waypost, bracket, niche or star node) that is concentric with it and a little
-- larger, so the rim overlaps the badge edge. SOCKET is the socket diameter divided by the badge size.
Wall.SOCKET = 1.18
Wall.PLANK_H = 8
Wall.PIN_ROOM = 22 -- room above a socket for its pin and string
Wall.PIN = 10
Wall.SHELF_DROP = 6 -- extra room under a shelf row so the nameplate hangs below the plank
Wall.SOCKET_KIND = { All = "shelf", Special = "shelf", Roads = "road", Masters = "niche", Night = "star" }
-- art keys (Engine/BadgeSocketArt.lua) for each socket kind
Wall.SOCKET_ART = { road = "badge_socket_road", shelf = "badge_socket_shelf", niche = "badge_socket_niche", star = "badge_socket_star" }

-- How far a socket sticks out past its badge on every side.
function Wall.pad(size)
	return math.floor(size * (Wall.SOCKET - 1) / 2 + 0.5)
end

-- Socket diameter: the medal times 1.18, to the nearest whole pixel (a whole-pixel pad on each side).
function Wall.socketDiameter(size)
	return size + 2 * Wall.pad(size)
end

-- Socket square { x, y, w, h } of an item, concentric with its badge.
function Wall.socketRect(item)
	local p = Wall.pad(item.size)
	return { x = item.x - p, y = item.y - p, w = item.size + 2 * p, h = item.size + 2 * p }
end

-- Rows of items: n items spread over `rows` shelves. Returns { x, y, size } per item (top-left px).
local function rowsLayout(n, rows, w, h, top, bottom)
	local perRow = math.ceil(n / rows)
	local cellW = (w * 0.9) / perRow
	local rowH = (h - top - bottom) / rows
	local fit = (rowH - Wall.NAMEPLATE_H - Wall.SHELF_DROP - 8) / Wall.SOCKET
	local size = math.floor(math.max(16, math.min(cellW * 0.76, fit)))
	local pad = Wall.pad(size)
	local out = {}
	for i = 1, n do
		local r = (i - 1) // perRow
		local c = (i - 1) % perRow
		local x0 = (w - perRow * cellW) / 2 -- every row shares the same columns
		out[i] = { x = math.floor(x0 + c * cellW + (cellW - size) / 2), y = math.floor(top + r * rowH + 2 + pad), size = size, cell = cellW }
	end
	return out
end

-- Item rectangles for a tab on a board of w x h px. Returns { items = { {id, x, y, size, big, socket} }, shelves = {y...} }.
-- `shelves` are the y positions (px) of the plank top under each row of a shelf tab (the row rests on it).
-- Roads: one winding path (badges alternate up and down), Masters: niches in a wall grid with a larger centre niche,
-- Night: star nodes in a constellation, All and Special: strict rows on shelf planks.
function Wall.layout(chip, defs, w, h)
	local list = Wall.members(chip, defs)
	local items = {}
	local shelves = {}
	if chip == "Roads" then
		-- one straight row with equal spacing, low on the map so the painted figure above stays clear; a pin and a short string
		-- hang directly above every medal (Wall.pinFor)
		local n = #list
		local step = (w * 0.94) / math.max(1, n)
		local size = math.floor(math.max(16, math.min(step * 0.76, (h * 0.62 - Wall.NAMEPLATE_H - Wall.PIN_ROOM) / Wall.SOCKET)))
		local pad = Wall.pad(size)
		local top = math.floor(h - 14 - Wall.NAMEPLATE_H - size - pad) -- badge top: the nameplate ends 14 px above the board bottom
		for i, d in ipairs(list) do
			items[i] = { id = d.id, x = math.floor(w * 0.03 + (i - 1) * step + (step - size) / 2), y = top, size = size, cell = step }
		end
	elseif chip == "Masters" then
		local row = {}
		local tavern
		for _, d in ipairs(list) do
			if d.region == "tavern" then tavern = d else row[#row + 1] = d end
		end
		local step = (w * 0.94) / math.max(1, #row)
		local size = math.floor(math.min(step * 0.76, h * 0.24))
		local big = math.floor(math.min(h * 0.34, w * 0.3))
		if tavern then
			items[#items + 1] = { id = tavern.id, x = math.floor((w - big) / 2), y = math.floor(h * 0.05), size = big, big = true, cell = big }
		end
		for i, d in ipairs(row) do
			items[#items + 1] = { id = d.id, x = math.floor(w * 0.03 + (i - 1) * step + (step - size) / 2), y = math.floor(h * 0.62), size = size, cell = step }
		end
	elseif chip == "Night" then
		local n = #list
		-- a gentle constellation line: the stars rise and fall along one slow wave, spaced evenly
		local size = math.floor(math.min(w * 0.76 / math.max(1, n) * 0.7, h * 0.26))
		for i, d in ipairs(list) do
			local k = n > 1 and (i - 1) / (n - 1) or 0.5
			local cx = w * (0.12 + 0.76 * k)
			local cy = h * (0.42 + 0.1 * math.sin(k * math.pi * 2))
			items[i] = { id = d.id, x = math.floor(cx - size / 2), y = math.floor(cy - size / 2), size = size, cell = w * 0.76 / math.max(1, n) }
		end
	else
		local rows = chip == "All" and 3 or 2		local pos = rowsLayout(#list, rows, w, h, h * 0.04, h * 0.04)
		local perRow = math.ceil(#list / rows)
		for i, d in ipairs(list) do
			items[i] = { id = d.id, x = pos[i].x, y = pos[i].y, size = pos[i].size, drop = Wall.SHELF_DROP, cell = pos[i].cell }
		end
		for r = 1, rows do
			local first = items[(r - 1) * perRow + 1]
			if first then shelves[#shelves + 1] = first.y + first.size + Wall.pad(first.size) - 3 end
		end
	end
	local kind = Wall.SOCKET_KIND[chip] or "shelf"
	for _, it in ipairs(items) do it.socket = kind end
	return { items = items, shelves = shelves }
end

-- The pin above a Roads medal and the string from it down to the socket top: { x = centre, y = pin centre, y2 = string end }.
function Wall.pinFor(item)
	local top = item.y - Wall.pad(item.size)
	return { x = item.x + item.size / 2, y = top - 14, y2 = top }
end

-- Tiny stars between neighbouring Night stars: two per gap, on the line's side, never inside a socket. { x, y, size }.
function Wall.tinyStars(items)
	local out = {}
	for i = 1, #items - 1 do
		local a, b = items[i], items[i + 1]
		local ax, ay, bx, by = a.x + a.size / 2, a.y + a.size / 2, b.x + b.size / 2, b.y + b.size / 2
		local ra, rb = Wall.socketDiameter(a.size) / 2, Wall.socketDiameter(b.size) / 2
		local t = Wall.trim(ax, ay, bx, by, ra + 6, rb + 6)
		if t then
			for k, f in ipairs({ 0.35, 0.7 }) do
				local x, y = t.x1 + (t.x2 - t.x1) * f, t.y1 + (t.y2 - t.y1) * f
				out[#out + 1] = { x = x, y = y + (k == 1 and -9 or 9), size = k == 1 and 3 or 4 }
			end
		end
	end
	return out
end

-- Rectangle of an item including its socket and nameplate, { x, y, w, h }.
function Wall.footprint(item)
	local p = Wall.pad(item.size)
	return { x = item.x - p, y = item.y - p, w = item.size + 2 * p, h = item.size + 2 * p + Wall.NAMEPLATE_H + (item.drop or 0) }
end

-- Where a nameplate hangs under a badge (relative to the badge top-left): below the socket, and below the plank on a shelf.
function Wall.plateY(item)
	return item.size + Wall.pad(item.size) + 3 + (item.drop or 0)
end

-- A line between two badge centres cut back to the socket edges, so it joins the sockets and never pokes through them.
function Wall.trim(ax, ay, bx, by, ra, rb)
	local dx, dy = bx - ax, by - ay
	local len = math.sqrt(dx * dx + dy * dy)
	if len <= ra + rb then return nil end
	local ux, uy = dx / len, dy / len
	return { x1 = ax + ux * ra, y1 = ay + uy * ra, x2 = bx - ux * rb, y2 = by - uy * rb }
end

-- Evenly spaced dots (or path tiles) along a trimmed segment; always at least two when the segment is long enough.
function Wall.dots(ax, ay, bx, by, ra, rb, spacing)
	local t = Wall.trim(ax, ay, bx, by, ra, rb)
	if not t then return {} end
	local dx, dy = t.x2 - t.x1, t.y2 - t.y1
	local len = math.sqrt(dx * dx + dy * dy)
	local n = math.max(2, math.floor(len / spacing))
	local out = {}
	for i = 0, n do
		local k = i / n
		out[#out + 1] = { x = t.x1 + dx * k, y = t.y1 + dy * k }
	end
	return out
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

-- Nameplate text: the badge name (earned or not) without the redundant " Badge" suffix on Master badges, so the whole
-- name fits two lines; the tooltip and detail card keep the full name and the requirement.
function Wall.plateText(def, owned)
	if def.tier == "master" then
		return (def.name:gsub("%s+Badge$", ""))
	end
	return def.name
end

-- Estimated wrapped line count for text in a plate of width w at text size `size` (greedy word wrap, 0.52 em per
-- character, close to a typical sans face; Studio's TextService is the real measure).
function Wall.plateLines(text, w, size)
	local perLine = math.max(1, math.floor((w - 6) / (size * 0.52)))
	local lines, cur = 1, 0
	for word in text:gmatch("%S+") do
		local len = #word
		if cur == 0 then cur = len
		elseif cur + 1 + len <= perLine then cur = cur + 1 + len
		else lines, cur = lines + 1, len end
		while cur > perLine do lines, cur = lines + 1, cur - perLine end
	end
	return lines
end

-- Nameplate rectangle relative to the badge's top-left: as wide as the item's own column (so two lines of name fit), never
-- narrower than the badge plus 8 px, with a 4 px gap to its neighbours. { x, w, h }.
function Wall.plateRect(item)
	local w = math.max(item.size + 8, math.floor((item.cell or (item.size + 8)) - 4))
	return { x = math.floor((item.size - w) / 2), w = w, h = Wall.NAMEPLATE_H - 4 }
end

-- Constellation line between two item centres: { x, y, length, rotation } for a thin Frame centred on the midpoint.
function Wall.segment(ax, ay, bx, by)
	local dx, dy = bx - ax, by - ay
	return { x = (ax + bx) / 2, y = (ay + by) / 2, length = math.sqrt(dx * dx + dy * dy), rotation = math.deg(math.atan(dy, dx)) }
end

-- Header plate of the Badges panel: a solid plate with the title, the count line and a slim progress bar inside it.
-- Rects are in the panel's local pixels; no art is stretched (the plate is a flat colour with a gold line).
function Wall.header(panelW, panelH)
	local plateW = math.floor(panelW * 0.6)
	local plateH = 62
	local pad = 14
	return {
		plate = { x = math.floor((panelW - plateW) / 2), y = 6, w = plateW, h = plateH },
		title = { x = 0, y = 4, w = plateW, h = 24 },
		count = { x = 0, y = 28, w = plateW, h = 18 },
		bar = { x = pad, y = 50, w = plateW - 2 * pad, h = 6 },
		heightFraction = plateH / panelH,
	}
end

return Wall
