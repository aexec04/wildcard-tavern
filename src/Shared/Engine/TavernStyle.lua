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
	orn_btn_dark = { art = "pk_orn_btn_dark", full = true, src = { 1398, 616 }, inset = { l = 190, t = 170, r = 190, b = 170 } },
	orn_btn_green = { art = "pk_orn_btn_green", full = true, src = { 1348, 562 }, inset = { l = 170, t = 150, r = 170, b = 150 } },
	-- whole-picture set (Nov 19): each plate is ONE finished picture generated at the aspect it is shown at, drawn Stretch with no nine-slice
	-- (`whole = true`, no inset), so the carved trim, corner scrolls, wax seal and crown medallion are never stretched into mush
	wh_target = { art = "pk_w_target", whole = true, src = { 1470, 348 } },
	wh_scroll = { art = "pk_w_scroll", whole = true, src = { 1423, 358 } },
	wh_score = { art = "pk_w_score", whole = true, src = { 1482, 362 } },
	wh_small = { art = "pk_w_pill_small", whole = true, src = { 1336, 386 } },
	wh_btn_dark = { art = "pk_w_btn_dark", whole = true, src = { 1382, 402 } },
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
M.PAINTED_EDGE_MIN = 10
M.PAINTED_EDGE_MAX = 14

-- Plate size clamp: a plate is never smaller than its padding needs.
function M.plateSize(w, h)
	return math.max(math.floor(w), 2 * M.RADIUS.panel + 8), math.max(math.floor(h), 2 * M.RADIUS.panel + 8)
end

return M
