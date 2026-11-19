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

-- Plate size clamp: a plate is never smaller than its padding needs.
function M.plateSize(w, h)
	return math.max(math.floor(w), 2 * M.RADIUS.panel + 8), math.max(math.floor(h), 2 * M.RADIUS.panel + 8)
end

return M
