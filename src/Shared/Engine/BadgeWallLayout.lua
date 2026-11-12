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

-- Where each road stop sits ON the pinned map, as fractions { x, y } of the board (the centre of its medal). The road runs from the
-- Meadow at the left to the Tavern at the right, zigzagging between an upper and a lower row.
Wall.ROAD_UPPER, Wall.ROAD_LOWER = 0.30, 0.66
Wall.ROAD_MEDAL = 140 -- Roads medals grow to this many px when the board has room
Wall.PLATE_EXTRA = 40 -- a Roads plate is at most the medal width plus this
Wall.ROAD_STOPS = {
	meadow = { 0.12, Wall.ROAD_LOWER }, river = { 0.2286, Wall.ROAD_UPPER }, peaks = { 0.3371, Wall.ROAD_LOWER },
	desert = { 0.4457, Wall.ROAD_UPPER }, swamp = { 0.5543, Wall.ROAD_LOWER }, snow = { 0.6629, Wall.ROAD_UPPER },
	coast = { 0.7714, Wall.ROAD_LOWER }, tavern = { 0.88, Wall.ROAD_UPPER },
}

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
	local p = item.noSocket and 0 or Wall.pad(item.size)
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
		-- The road map: every stop is a pin ON the map at its place in Wall.ROAD_STOPS (fractions of the board), the medal hanging from
		-- it on a short string (Wall.pinFor) with its name plate under it. The stops zigzag between an upper and a lower row, so a
		-- plate never touches a neighbour's socket, and a dotted trail runs from stop to stop.
		local stops = {}
		for i, d in ipairs(list) do stops[i] = Wall.ROAD_STOPS[d.region] or { 0.5, 0.5 } end
		local n = #list
		local stepX = n > 1 and (stops[n][1] - stops[1][1]) * w / (n - 1) or w * 0.2
		local rowSep = h * (Wall.ROAD_LOWER - Wall.ROAD_UPPER)
		local size = math.floor(math.max(16, math.min(Wall.ROAD_MEDAL, stepX * 0.95, (rowSep - Wall.NAMEPLATE_H - 6) / Wall.SOCKET)))
		for i, d in ipairs(list) do
			-- the plate fits its text (12 px padding each side) and is never wider than the medal plus 40 px, so neighbours never touch
			local plateW = math.max(size, math.min(size + Wall.PLATE_EXTRA, math.floor(#Wall.plateText(d, false) * 8 + 24)))
			items[i] = { id = d.id, x = math.floor(w * stops[i][1] - size / 2), y = math.floor(h * stops[i][2] - size / 2), size = size, cell = 2 * stepX, plateW = plateW }
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

-- ===== painted scenes (Masters, Night, Special) =====
-- Each tab has a painted picture with a socket for every badge. A slot is { cx, cy, d } = the socket centre as fractions of the
-- picture's width and height, and the badge diameter as a fraction of its width (a little under the hole, so the painted rim shows).
-- Special's name plates are painted on the shelf front: `py` is the plate row's centre as a fraction of the picture height.
-- Measured from art-wip/badge_wall/badge_scene_*.png (1536x1024). Until the picture's Image id is recorded in
-- Engine/BadgeWallArt.lua the older drawn layout (Wall.layout) stays.
Wall.SCENE_ASPECT = 1.5
Wall.SCENE_PLATE_H = 22 -- one line of 14 px name text
Wall.SCENES = {
	Masters = { art = "badge_scene_masters", pitch = 0.1085, slots = {
		{ 0.505, 0.323, 0.098 }, -- the Master Tavern badge, large, on top
		{ 0.180, 0.602, 0.060 }, { 0.287, 0.602, 0.060 }, { 0.395, 0.602, 0.060 }, { 0.504, 0.602, 0.060 },
		{ 0.613, 0.602, 0.060 }, { 0.723, 0.602, 0.060 }, { 0.831, 0.602, 0.060 },
	} },
	Night = { art = "badge_scene_night", pitch = 0.22, slots = {
		-- centres of the ring OPENINGS (above the rings' outer centres, perspective); d is about 80 percent of the opening height
		{ 0.153, 0.676, 0.074 }, { 0.374, 0.676, 0.074 }, { 0.594, 0.676, 0.074 }, { 0.813, 0.676, 0.074 },
	},
	-- v2: four round carved recesses (inner diameter 229 px of 1536, centres measured from the PNG), badge at 85 percent of the recess;
	-- the painted plates sit under them at y 0.801. Used instead of the ring picture once its Image id is recorded.
	v2 = { art = "badge_scene_night_b", pitch = 0.2, plateRows = { 0.801, 0.801 }, plateMargin = 14, slots = {
		{ 0.190, 0.598, 0.127 }, { 0.392, 0.598, 0.127 }, { 0.596, 0.598, 0.127 }, { 0.799, 0.598, 0.127 },
	} } },
	-- Roads: the painted route map, two rows of 4 round pinned stops (road order, left to right, top row first), plate rows under them
	Roads = { art = "badge_scene_roads", pitch = 0.173, plateRows = { 0.420, 0.672 }, plateExtra = 40, plateMargin = 24, slots = {
		{ 0.241, 0.339, 0.084 }, { 0.415, 0.339, 0.084 }, { 0.590, 0.339, 0.084 }, { 0.762, 0.339, 0.084 },
		{ 0.241, 0.587, 0.084 }, { 0.415, 0.587, 0.084 }, { 0.590, 0.587, 0.084 }, { 0.762, 0.587, 0.084 },
	} },
	Special = { art = "badge_scene_special", pitch = 0.136, plateRows = { 0.488, 0.796 }, slots = {
		{ 0.169, 0.350, 0.098 }, { 0.306, 0.350, 0.098 }, { 0.441, 0.350, 0.098 }, { 0.576, 0.350, 0.098 }, { 0.712, 0.350, 0.098 }, { 0.840, 0.350, 0.098 },
		{ 0.164, 0.652, 0.098 }, { 0.305, 0.652, 0.098 }, { 0.439, 0.652, 0.098 }, { 0.573, 0.652, 0.098 }, { 0.710, 0.652, 0.098 }, { 0.844, 0.652, 0.098 },
	} },
}

-- The scene of a tab when its picture is recorded in `art` (the BadgeWallArt map), else nil.
function Wall.sceneOf(chip, art)
	local sc = Wall.SCENES[chip]
	if not sc then return nil end
	local function has(k) local id = art and art[k]; return type(id) == "string" and id ~= "" end
	if sc.v2 and has(sc.v2.art) then return sc.v2 end
	if not has(sc.art) then return nil end
	return sc
end

-- Layout of a tab on its painted scene: the picture is cover-fitted into the w x h board (never stretched) and every badge sits in its
-- slot with a small name plate under it (on the painted plate row where there is one). Returns { items, shelves = {}, image, scene } or
-- nil when the crop would cut a slot or a plate, and the caller keeps the drawn layout. Master Tavern takes the large slot.
function Wall.sceneLayout(chip, defs, w, h, scene)
	local sc = scene or Wall.SCENES[chip]
	if not sc then return nil end
	local list = Wall.members(chip, defs)
	local order = {}
	if chip == "Masters" then -- the Tavern master badge first (large slot), then the roads in road order
		for _, d in ipairs(list) do if d.region == "tavern" then order[#order + 1] = d end end
		for _, d in ipairs(list) do if d.region ~= "tavern" then order[#order + 1] = d end end
	else
		order = list
	end
	if #order ~= #sc.slots then return nil end
	local iw, ih
	if w / h > Wall.SCENE_ASPECT then iw, ih = w, w / Wall.SCENE_ASPECT else iw, ih = h * Wall.SCENE_ASPECT, h end
	local ix, iy = (w - iw) / 2, (h - ih) / 2
	local items = {}
	for i, slot in ipairs(sc.slots) do
		local d = order[i]
		local size = math.floor(slot[3] * iw)
		local cx, cy = ix + slot[1] * iw, iy + slot[2] * ih
		local x, y = math.floor(cx - size / 2), math.floor(cy - size / 2)
		local maxW = math.floor(sc.pitch * iw) - 6
		local text = Wall.plateText(d, false)
		local single = math.floor(#text * 8 + (sc.plateMargin or 14))
		if sc.plateExtra then maxW = math.min(maxW, size + sc.plateExtra) end
		local plateW = math.max(size, math.min(maxW, single))
		local plateH = Wall.plateLines(text, plateW, 14) > 1 and (Wall.NAMEPLATE_H - 4) or Wall.SCENE_PLATE_H
		local top = y + size + 6 -- plate top, below the socket
		if sc.plateRows then -- the painted plate row under this slot's shelf
			top = math.max(math.floor(iy + sc.plateRows[slot[2] < 0.5 and 1 or 2] * ih - plateH / 2), y + size + 3) -- never over its own badge
		end
		items[i] = { id = d.id, x = x, y = y, size = size, cell = size + 12, noSocket = true, scene = true, big = (chip == "Masters" and i == 1) or nil,
			plateW = plateW, plateH = plateH, drop = top - (y + size) - 3 }
		items[i].socket = "scene"
	end
	for _, it in ipairs(items) do
		local f = Wall.footprint(it)
		local pr = Wall.plateRect(it)
		local plate = { x = it.x + pr.x, y = it.y + Wall.plateY(it), w = pr.w, h = pr.h }
		if f.x < 0 or f.y < 0 or f.x + f.w > w or plate.x < 0 or plate.y < 0 or plate.x + plate.w > w or plate.y + plate.h > h or f.y + it.size > h then
			return nil
		end
	end
	return { items = items, shelves = {}, image = { x = ix, y = iy, w = iw, h = ih }, scene = sc }
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
	local p = item.noSocket and 0 or Wall.pad(item.size)
	return { x = item.x - p, y = item.y - p, w = item.size + 2 * p, h = item.size + 2 * p + Wall.NAMEPLATE_H + (item.drop or 0) }
end

-- Where a nameplate hangs under a badge (relative to the badge top-left): below the socket, and below the plank on a shelf.
function Wall.plateY(item)
	return item.size + (item.noSocket and 0 or Wall.pad(item.size)) + 3 + (item.drop or 0)
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
	local w = item.plateW or math.max(item.size + 8, math.floor((item.cell or (item.size + 8)) - 4))
	return { x = math.floor((item.size - w) / 2), w = w, h = item.plateH or (Wall.NAMEPLATE_H - 4) }
end

-- Constellation line between two item centres: { x, y, length, rotation } for a thin Frame centred on the midpoint.
function Wall.segment(ax, ay, bx, by)
	local dx, dy = bx - ax, by - ay
	return { x = (ax + bx) / 2, y = (ay + by) / 2, length = math.sqrt(dx * dx + dy * dy), rotation = math.deg(math.atan(dy, dx)) }
end

-- Header plaque of the Badges panel: a small wooden plaque with the title, the count line and a slim progress bar inside it.
-- Rects are in the panel's local pixels; no art is stretched (the plaque is a flat colour with a brass line).
function Wall.header(panelW, panelH)
	local plateW = math.min(360, math.floor(panelW * 0.6))
	local plateH = 48
	local pad = 14
	return {
		plate = { x = math.floor((panelW - plateW) / 2), y = 6, w = plateW, h = plateH },
		title = { x = 0, y = 1, w = plateW, h = 22 },
		count = { x = 0, y = 23, w = plateW, h = 17 },
		bar = { x = pad, y = 41, w = plateW - 2 * pad, h = 5 },
		heightFraction = plateH / panelH,
	}
end

-- Earned and total per shelf of the trophy room ("Roads 2/8"): { Roads = { found, total }, Masters, Night, Special }.
function Wall.sectionCounts(have)
	local out = {}
	for _, chip in ipairs({ "Roads", "Masters", "Night", "Special" }) do
		local list, found = Wall.members(chip), 0
		for _, d in ipairs(list) do
			if have[d.id] == true then found = found + 1 end
		end
		out[chip] = { found = found, total = #list }
	end
	return out
end

return Wall
