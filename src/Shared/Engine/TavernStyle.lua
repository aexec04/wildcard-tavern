--[[
	Engine/TavernStyle.lua
	The numbers behind claude/STYLE-TAVERN.md, taken from the two screens the project treats as the look to match: the main menu
	(Client/Wordmark, MenuPlayButton, VisualHelpers.polishPanel) and the Night screen (Client/RoundSelect). Pure data and small
	helpers so Client/TavernKit and the tests read one table. Colors are {r, g, b} 0..255.
]]

local M = {}

M.COLORS = {
	plateFill = { 40, 30, 22 },       -- RoundSelect frame, Palette.panelBg
	plateFillLight = { 55, 42, 30 },  -- Night card panel
	plateDark = { 30, 22, 16 },       -- Target box and room label fill
	woodChip = { 92, 62, 34 },        -- Tips chip, secondary wood
	goldTrim = { 200, 165, 90 },      -- polishPanel and polishButton stroke
	goldTrimPlate = { 150, 118, 66 }, -- wood plate edge (chips, room labels)
	goldBright = { 222, 182, 104 },   -- VisualHelpers GOLD
	cream = { 250, 240, 220 },        -- titles and button text
	creamSoft = { 220, 205, 185 },    -- subtitles
	creamChip = { 245, 232, 200 },    -- chip text
	green = { 70, 130, 70 },          -- Night screen Select fill (cream on it is 4.0:1, so the kit uses greenDeep)
	greenDeep = { 48, 102, 52 },      -- primary button fill in the kit, 4.5:1 with cream even at the gradient top
	brown = { 90, 60, 30 },           -- Skip, the secondary button
	targetText = { 120, 170, 255 },   -- Night Target box number
	gold = { 230, 184, 70 },          -- cleared medal
	titleGoldTop = { 236, 205, 134 }, -- Wordmark gradient
	titleGoldBottom = { 184, 146, 80 },
	outline = { 46, 30, 14 },         -- Wordmark outline
	buttonStroke = { 30, 60, 20 },    -- green button text stroke
}

M.FONTS = { title = "Fondamento", ui = "GothamBold", body = "Gotham" }

M.RADIUS = { panel = 6, button = 6, card = 14, chip = 8, pill = 999 }
M.STROKE = { plate = 2, button = 1.5, card = 3, boss = 4, transparency = 0.15 }
M.TEXT = { title = 34, subtitle = 18, button = 16, chip = 17, box = 18, min = 14 }
M.SIZES = { primaryH = 44, secondaryH = 40, boxH = 36, chipH = 34, pillH = 22, minTouch = 44 }

M.HOVER_LIFT = 2      -- px a button rises on hover
M.PRESS_SCALE = 0.97  -- scale while pressed
M.FEEL_SECONDS = 0.08

function M.rgb(name)
	local c = M.COLORS[name]
	assert(c, "unknown tavern color " .. tostring(name))
	return c
end

-- Relative luminance and contrast, same maths as RarityPillSpec.
local function lin(v)
	v = v / 255
	if v <= 0.03928 then return v / 12.92 end
	return ((v + 0.055) / 1.055) ^ 2.4
end
local function lum(c) return 0.2126 * lin(c[1]) + 0.7152 * lin(c[2]) + 0.0722 * lin(c[3]) end
function M.contrast(a, b)
	local la, lb = lum(a), lum(b)
	if la < lb then la, lb = lb, la end
	return (la + 0.05) / (lb + 0.05)
end

-- Button kinds: fill, text, stroke, height. The only two the style allows.
M.BUTTONS = {
	primary = { fill = "greenDeep", text = "cream", stroke = "goldTrim", height = M.SIZES.primaryH },
	secondary = { fill = "brown", text = "cream", stroke = "goldTrim", height = M.SIZES.secondaryH },
}

-- Pill colors (fill names), text is always cream or dark by contrast.
M.PILLS = {
	wood = { 92, 62, 34 }, green = { 45, 120, 70 }, blue = { 45, 85, 150 }, purple = { 100, 55, 140 }, gold = { 150, 110, 30 },
}

-- Hover and press numbers; calm is true for Calm mode, Reduce motion or Fast speed: then nothing moves at all.
function M.feel(calm)
	if calm then return { lift = 0, press = 1, seconds = 0 } end
	return { lift = M.HOVER_LIFT, press = M.PRESS_SCALE, seconds = M.FEEL_SECONDS }
end

-- Painted UI kit: the ONE place that maps a plate kind to its painted frame (art ids come from Engine/PaintedKitArt, generated).
-- `art` is the key in PaintedKitArt, `src` the trimmed picture size in px, `inset` the nine-slice corner sizes in source px (nil = the
-- picture is drawn whole, Fit; full = true: drawn at the plate's full height scale, not the 10 to 14 px border clamp). TavernKit.painted draws it as a SIBLING behind the plate and puts the flat look back if it does not load.
M.PAINTED = {
	wood_plate = { art = "pk_wood_plate", src = { 1412, 549 }, inset = { l = 140, t = 100, r = 140, b = 100 } },
	parchment = { art = "pk_parchment", full = true, src = { 1350, 637 }, inset = { l = 100, t = 150, r = 100, b = 80 } },
	btn_green = { art = "pk_btn_green_p", src = { 1244, 443 }, inset = { l = 120, t = 110, r = 120, b = 110 } }, -- _p: side flourishes cut off, so both caps are alike (tools/painted_kit_plain.py)
	btn_dark = { art = "pk_btn_dark_p", src = { 1218, 430 }, inset = { l = 120, t = 110, r = 120, b = 110 } },
	icon_round = { art = "pk_icon_round", src = { 800, 800 } },
	count_tab = { art = "pk_count_tab", src = { 860, 244 }, inset = { l = 110, t = 80, r = 110, b = 80 } },
	patron_slot = { art = "pk_patron_slot", src = { 657, 953 }, inset = { l = 90, t = 90, r = 90, b = 90 } },
	score_frame = { art = "pk_score_frame", src = { 1485, 410 }, inset = { l = 170, t = 100, r = 170, b = 100 } },
	-- ornate set (dark wood, carved gold trim, scrolled corners and studs, like claude/reference/concept-table-reference.png)
	orn_wide = { art = "pk_orn_pill_wide", full = true, src = { 1418, 514 }, inset = { l = 170, t = 150, r = 170, b = 150 } },
	orn_small = { art = "pk_orn_pill_small", full = true, src = { 1291, 616 }, inset = { l = 190, t = 170, r = 190, b = 170 } },
	orn_square = { art = "pk_orn_square", full = true, src = { 905, 906 }, inset = { l = 230, t = 230, r = 230, b = 230 } },
	orn_score = { art = "pk_orn_score", full = true, src = { 1502, 563 }, inset = { l = 200, t = 170, r = 200, b = 150 } },
	orn_target = { art = "pk_w_target", full = true, src = { 1470, 348 }, inset = { l = 200, t = 130, r = 200, b = 130 } }, -- the table Target plate cut as a nine-slice: all four corners alike, nothing hangs outside
	orn_btn_dark = { art = "pk_orn_btn_dark", full = true, src = { 1398, 616 }, inset = { l = 190, t = 170, r = 190, b = 170 } },
	orn_btn_green = { art = "pk_orn_btn_green", full = true, src = { 1348, 562 }, inset = { l = 170, t = 150, r = 170, b = 150 } },
	-- whole-picture set (Nov 19): each plate is ONE finished picture generated at the aspect it is shown at, drawn Stretch with no nine-slice
	-- (`whole = true`, no inset), so the carved trim, corner scrolls, wax seal and crown medallion are never stretched into mush
	wh_target = { art = "pk_w_target", whole = true, src = { 1470, 348 } },
	wh_scroll = { art = "pk_w_scroll", whole = true, src = { 1423, 358 } },
	wh_score = { art = "pk_w_score", whole = true, src = { 1482, 362 } },
	wh_small = { art = "pk_w_pill_small", whole = true, src = { 1336, 386 } },
	wh_btn_dark = { art = "pk_w_btn_dark", whole = true, src = { 1382, 402 } },
	-- Golden Gala palace plates: same sizes, insets and text safe area as the classic pieces (tools/_gala_plate_fit.py), so only the picture differs
	gala_wh_btn_dark = { art = "pk_gala_btn_dark", whole = true, src = { 1382, 402 } },
	gala_wh_btn_green = { art = "pk_gala_btn_green", whole = true, src = { 1498, 410 } },
	gala_orn_btn_green = { art = "pk_gala_orn_btn_green", full = true, src = { 1348, 562 }, inset = { l = 170, t = 150, r = 170, b = 150 } },
	-- Frosted Garden, Mountain Festival and Closing Time plates: same sizes as the classic dark and green plates (tools/_gala_plate_fit.py)
	frost_wh_btn_dark = { art = "pk_frost_btn_dark", whole = true, src = { 1382, 402 } },
	frost_wh_btn_green = { art = "pk_frost_btn_green", whole = true, src = { 1498, 410 } },
	fest_wh_btn_dark = { art = "pk_fest_btn_dark", whole = true, src = { 1382, 402 } },
	fest_wh_btn_green = { art = "pk_fest_btn_green", whole = true, src = { 1498, 410 } },
	close_wh_btn_dark = { art = "pk_close_btn_dark", whole = true, src = { 1382, 402 } },
	close_wh_btn_green = { art = "pk_close_btn_green", whole = true, src = { 1498, 410 } },
	-- ten more sets: same sizes as the classic dark and green plates
	dune_wh_btn_dark = { art = "pk_dune_btn_dark", whole = true, src = { 1382, 402 } },
	dune_wh_btn_green = { art = "pk_dune_btn_green", whole = true, src = { 1498, 410 } },
	marsh_wh_btn_dark = { art = "pk_marsh_btn_dark", whole = true, src = { 1382, 402 } },
	marsh_wh_btn_green = { art = "pk_marsh_btn_green", whole = true, src = { 1498, 410 } },
	hearth_wh_btn_dark = { art = "pk_hearth_btn_dark", whole = true, src = { 1382, 402 } },
	hearth_wh_btn_green = { art = "pk_hearth_btn_green", whole = true, src = { 1498, 410 } },
	harbor_wh_btn_dark = { art = "pk_harbor_btn_dark", whole = true, src = { 1382, 402 } },
	harbor_wh_btn_green = { art = "pk_harbor_btn_green", whole = true, src = { 1498, 410 } },
	feast_wh_btn_dark = { art = "pk_feast_btn_dark", whole = true, src = { 1382, 402 } },
	feast_wh_btn_green = { art = "pk_feast_btn_green", whole = true, src = { 1498, 410 } },
	harvest_wh_btn_dark = { art = "pk_harvest_btn_dark", whole = true, src = { 1382, 402 } },
	harvest_wh_btn_green = { art = "pk_harvest_btn_green", whole = true, src = { 1498, 410 } },
	wtable_wh_btn_dark = { art = "pk_wtable_btn_dark", whole = true, src = { 1382, 402 } },
	wtable_wh_btn_green = { art = "pk_wtable_btn_green", whole = true, src = { 1498, 410 } },
	meadow_wh_btn_dark = { art = "pk_meadow_btn_dark", whole = true, src = { 1382, 402 } },
	meadow_wh_btn_green = { art = "pk_meadow_btn_green", whole = true, src = { 1498, 410 } },
	river_wh_btn_dark = { art = "pk_river_btn_dark", whole = true, src = { 1382, 402 } },
	river_wh_btn_green = { art = "pk_river_btn_green", whole = true, src = { 1498, 410 } },
	summit_wh_btn_dark = { art = "pk_summit_btn_dark", whole = true, src = { 1382, 402 } },
	summit_wh_btn_green = { art = "pk_summit_btn_green", whole = true, src = { 1498, 410 } },
	wh_btn_green = { art = "pk_w_btn_green", whole = true, src = { 1498, 410 } },
	wh_btn_sq = { art = "pk_w_btn_sq", whole = true, src = { 1329, 652 } },
	wh_count = { art = "pk_w_count", whole = true, src = { 1443, 425 } },
	wh_hint = { art = "pk_w_hint", whole = true, src = { 1408, 543 } },
}
M.PAINTED_LOAD_WAIT = 4 -- seconds an image may take to load before the flat look comes back

-- nine-slice numbers for a plate drawn w x h px: SliceCenter rect (source px) and SliceScale, so the corner ornaments keep their shape
-- and only the middle stretches. Returns nil for a whole-picture piece (icon_round) or an unknown piece.
function M.paintedSlice(piece, w, h)
	local p = M.PAINTED[piece]
	if not p or not p.inset or w <= 0 or h <= 0 then return nil end
	local sw, sh = p.src[1], p.src[2]
	local i = p.inset
	-- the plate's border is drawn about EDGE px thick (10 to 14, by plate height), so a corner ornament never balloons into a thick bar
	-- on a small button; the picture's own height is never stretched past 1:1 and both corner columns always fit inside the plate
	if p.full then -- ornate pieces draw at full scale (the whole picture fits the plate height, the middle stretches sideways), so the carved trim,
		-- corner scrolls, studs and the wax seal stay readable instead of shrinking to a 10 to 14 px hairline
		local sc = math.min(h / sh, (w * 0.9) / (i.l + i.r), (h * 0.9) / (i.t + i.b))
		return { left = i.l, top = i.t, right = sw - i.r, bottom = sh - i.b, scale = math.max(0.01, sc) }
	end
	local edge = math.max(M.PAINTED_EDGE_MIN, math.min(M.PAINTED_EDGE_MAX, h * 0.22))
	local scale = edge / math.max(i.l, i.r, i.t, i.b)
	scale = math.min(scale, h / sh, (w * 0.9) / (i.l + i.r), (h * 0.9) / (i.t + i.b))
	scale = math.max(0.01, scale)
	return { left = i.l, top = i.t, right = sw - i.r, bottom = sh - i.b, scale = scale }
end
-- Roblox keeps an uploaded picture at 1024 px on its longer side at most, so SliceCenter is read in THAT texture, not in the source
-- file: a 1470 px wide plate sliced at source numbers lost its whole right edge (the right slice line sat past the texture). This turns
-- a paintedSlice result into texture numbers: the rect shrinks by the factor and SliceScale grows by it, so the plate keeps its size.
M.TEX_MAX = 1024
function M.paintedTexSlice(piece, w, h)
	local sl, p = M.paintedSlice(piece, w, h), M.PAINTED[piece]
	if not sl then return nil end
	local k = math.min(1, M.TEX_MAX / math.max(p.src[1], p.src[2]))
	return { left = sl.left * k, top = sl.top * k, right = sl.right * k, bottom = sl.bottom * k, scale = sl.scale / k }
end
M.PAINTED_EDGE_MIN = 10
M.PAINTED_EDGE_MAX = 14

-- Audit of every painted plate: the slice numbers TavernKit hands to Roblox (texture pixels, after the 1024 clamp) must leave a centre
-- inside the texture, and the scaled corner columns and rows must fit the plate drawn at w x h, otherwise a corner or an edge is cropped.
-- Returns a list of problem strings (empty = every plate and size is fine). TavernKit prints it once as `[PlateSlices]`.
M.AUDIT_SIZES = { { 300, 124 }, { 380, 155 }, { 620, 48 }, { 900, 44 }, { 120, 34 }, { 44, 44 }, { 1920, 80 }, { 200, 200 } }
function M.plateAudit(sizes)
	local bad = {}
	for piece, def in pairs(M.PAINTED) do
		local i = def.inset
		if i then
			if i.l + i.r >= def.src[1] or i.t + i.b >= def.src[2] then
				bad[#bad + 1] = piece .. ": inset larger than the picture"
			end
			for _, s in ipairs(sizes or M.AUDIT_SIZES) do
				local t = M.paintedTexSlice(piece, s[1], s[2])
				local k = math.min(1, M.TEX_MAX / math.max(def.src[1], def.src[2]))
				local tw, th = def.src[1] * k, def.src[2] * k
				local tag = piece .. " at " .. s[1] .. "x" .. s[2]
				if not t or t.left >= t.right or t.top >= t.bottom or t.right > tw + 1e-6 or t.bottom > th + 1e-6 then
					bad[#bad + 1] = tag .. ": slice centre outside the " .. math.floor(tw) .. "x" .. math.floor(th) .. " texture"
				else
					-- rendered corner columns and rows (texture px x SliceScale) against the plate
					local cols, rows = (t.left + (tw - t.right)) * t.scale, (t.top + (th - t.bottom)) * t.scale
					if cols > s[1] + 1e-6 then bad[#bad + 1] = tag .. ": corner columns " .. math.floor(cols) .. " px wider than the plate" end
					if rows > s[2] + 1e-6 then bad[#bad + 1] = tag .. ": corner rows " .. math.floor(rows) .. " px taller than the plate" end
				end
			end
		end
	end
	table.sort(bad)
	return bad
end

-- One ornate button family for every screen (Counter, Night map, Run Over, pause): kind "primary" is the green plate, "secondary" the dark
-- wood one. A button near the whole-picture aspect (2.6 to 5.2 wide for 1) wears the finished wh_btn picture; any other shape (a full width
-- Select bar, a square icon button, an unmeasured plate) wears the ornate nine-slice of the same family, so nothing stretches.
M.BUTTON_ASPECT = { min = 2.6, max = 5.2 }
function M.buttonPiece(kind, w, h, setId)
	local green = kind ~= "secondary"
	local piece
	if not (w and h and w > 1 and h > 1) then
		piece = green and "wh_btn_green" or "wh_btn_dark" -- not laid out yet: the whole picture (a 0 aspect used to pick the thin nine-slice, which read flat)
	else
		local a = w / h
		if a >= M.BUTTON_ASPECT.min and a <= M.BUTTON_ASPECT.max then
			piece = green and "wh_btn_green" or "wh_btn_dark"
		else
			piece = green and "orn_btn_green" or "orn_btn_dark"
		end
	end
	return M.setPiece(piece, setId)
end

-- A Card Set's own plate for a classic piece name (golden_gala: palace velvet and emerald). Every other set, and any piece the set does not
-- repaint (the dark nine-slice), keeps the classic piece, so classic is unchanged.
M.SET_PLATES = {
	golden_gala = { wh_btn_dark = "gala_wh_btn_dark", wh_btn_green = "gala_wh_btn_green", orn_btn_green = "gala_orn_btn_green" },
	winter_evening = { wh_btn_dark = "frost_wh_btn_dark", wh_btn_green = "frost_wh_btn_green" },
	festival_night = { wh_btn_dark = "fest_wh_btn_dark", wh_btn_green = "fest_wh_btn_green" },
	closing_time = { wh_btn_dark = "close_wh_btn_dark", wh_btn_green = "close_wh_btn_green" },
	dune_market = { wh_btn_dark = "dune_wh_btn_dark", wh_btn_green = "dune_wh_btn_green" },
	marsh_lanterns = { wh_btn_dark = "marsh_wh_btn_dark", wh_btn_green = "marsh_wh_btn_green" },
	snowy_hearth = { wh_btn_dark = "hearth_wh_btn_dark", wh_btn_green = "hearth_wh_btn_green" },
	harbor_lights = { wh_btn_dark = "harbor_wh_btn_dark", wh_btn_green = "harbor_wh_btn_green" },
	tavern_feast = { wh_btn_dark = "feast_wh_btn_dark", wh_btn_green = "feast_wh_btn_green" },
	harvest_table = { wh_btn_dark = "harvest_wh_btn_dark", wh_btn_green = "harvest_wh_btn_green" },
	winter_table = { wh_btn_dark = "wtable_wh_btn_dark", wh_btn_green = "wtable_wh_btn_green" },
	meadow_picnic = { wh_btn_dark = "meadow_wh_btn_dark", wh_btn_green = "meadow_wh_btn_green" },
	riverside_evening = { wh_btn_dark = "river_wh_btn_dark", wh_btn_green = "river_wh_btn_green" },
	summit_camp = { wh_btn_dark = "summit_wh_btn_dark", wh_btn_green = "summit_wh_btn_green" },
}
-- The table HUD plates (Play Hand, Discard, Rank, Suit, Hands, Discards, deck count) all wear the equipped Card Set the way Play Hand and
-- Discard do. Play Hand is the green family, every other plate the dark one; both resolve through buttonPiece, so a set's own plate wins and a
-- set without one keeps the classic picture (the client tints it with setTint).
M.HUD_PLATE_SLOTS = { "play", "discard", "rank", "suit", "hands", "discards", "deck" }
function M.hudPlate(slot, w, h, setId)
	return M.buttonPiece(slot == "play" and "primary" or "secondary", w, h, setId)
end

-- The plate a result screen button (Victory Continue, Skip) wears: the equipped Card Set's own plate when it has one, nil for classic or a set
-- without plates (the screen keeps its own purple plate then). Primary is the green family, secondary the dark one.
function M.resultPlate(kind, w, h, setId)
	if not (setId and M.SET_PLATES[setId]) then return nil end
	return M.setPiece(kind == "secondary" and "wh_btn_dark" or "wh_btn_green", setId) -- always the finished whole picture: a result button is near 2.7 wide for 1
end

-- The plate a tab wears: the lit tab is the set's green plate, the others its dark one; nil for classic (tabs keep their flat browns).
function M.tabPlate(active, setId)
	return M.resultPlate(active and "primary" or "secondary", 0, 0, setId)
end

-- A set's hue for a classic plate picture it has no own art for (Tips, Next boss, round buttons): white pulled toward the set accent
-- and multiplied over the picture. nil for classic or an unknown set, so classic is untouched. Light enough to keep gold trim readable.
function M.isSetPiece(piece)
	for _, map in pairs(M.SET_PLATES) do
		for _, mine in pairs(map) do if mine == piece then return true end end
	end
	return false
end

function M.setTint(setId, accent)
	if not (setId and M.SET_PLATES[setId] and type(accent) == "table" and #accent >= 3) then return nil end
	local out = {}
	for i = 1, 3 do out[i] = math.floor(255 + (accent[i] - 255) * 0.55 + 0.5) end
	return out
end

function M.setPiece(piece, setId)
	local map = setId and M.SET_PLATES[setId]
	return (map and map[piece]) or piece
end

-- Plate size clamp: a plate is never smaller than its padding needs.
function M.plateSize(w, h)
	return math.max(math.floor(w), 2 * M.RADIUS.panel + 8), math.max(math.floor(h), 2 * M.RADIUS.panel + 8)
end

return M
