--[[
	Engine/HudStyle.lua
	Pure numbers and colours for the code-drawn, Card Set themed HUD (drawn by Client/HudTheme, SortToggle,
	DeckWidgetSkin and ClassicCardFrame). Nothing here touches Roblox instances.

	  HudStyle.buttonPalette(colors, role)  fill, gradient stops, rings, hover and pressed fills, text colour
	                                        ("play" | "discard" | "sort"); text reaches 4.5:1 on every stop
	  HudStyle.iconPalette(colors)          ring, glow, disc and motif colours for the round top-right buttons
	  HudStyle.deckPalette(colors)          bracket, count plate and count text colours for the draw pile
	  HudStyle.pileLook(setId)              per-set tilt and offset of the card backs stacked behind the pile
	  HudStyle.classicFrame(w, h)           rectangles of the Classic Tavern card frame (oak band, brass line, caps)

	`colors` is CosmeticSets.skinOf(set).colors (nil for the neutral default set, which keeps the tavern wood and brass).
]]

local CosmeticSets = require(script.Parent.CosmeticSets)

local HudStyle = {}

HudStyle.MIN_CONTRAST = 4.5
HudStyle.NEUTRAL = { accent = { 214, 172, 88 }, base = { 56, 37, 20 } }
HudStyle.DARK_RING = { 20, 12, 6 }

local function mix(a, b, t)
	return {
		math.floor(a[1] + (b[1] - a[1]) * t + 0.5),
		math.floor(a[2] + (b[2] - a[2]) * t + 0.5),
		math.floor(a[3] + (b[3] - a[3]) * t + 0.5),
	}
end
HudStyle.mix = mix

local WHITE = { 255, 255, 255 }
local BLACK = { 0, 0, 0 }

-- Accent and base fill for a set (colors.border / colors.button), or the neutral wood and brass.
local function basics(colors)
	if colors then return colors.border, colors.button end
	return HudStyle.NEUTRAL.accent, HudStyle.NEUTRAL.base
end

-- Darken `fill` until the text colour chosen for it reads at 4.5:1 on fill, its lighter gradient top and its hover fill.
local function readableFill(fill, lift)
	local steps = 0
	while steps < 14 do
		local text = CosmeticSets.buttonTextColor(fill)
		local worst = math.min(
			CosmeticSets.contrastRatio(text, fill),
			CosmeticSets.contrastRatio(text, mix(fill, WHITE, lift)),
			CosmeticSets.contrastRatio(text, mix(fill, WHITE, lift * 1.6)),
			CosmeticSets.contrastRatio(text, mix(fill, BLACK, 0.11))) -- the gradient's darker end
		if worst >= HudStyle.MIN_CONTRAST then break end
		fill = mix(fill, BLACK, 0.12)
		steps = steps + 1
	end
	return fill
end

local ROLE_TINT = { play = nil, discard = { 70, 84, 110 }, sort = nil }

-- Palette for one code-drawn button. All colours are { r, g, b }.
function HudStyle.buttonPalette(colors, role)
	local accent, base = basics(colors)
	local fill = base
	local cool = ROLE_TINT[role]
	if cool then fill = mix(fill, cool, 0.3) end
	fill = readableFill(fill, 0.12)
	local text = CosmeticSets.buttonTextColor(fill)
	return {
		fill = fill,
		bottom = mix(fill, BLACK, 0.11), -- darker end of the Color-only gradient (never Transparency)
		hover = mix(fill, WHITE, 0.1),
		pressed = mix(fill, BLACK, 0.2),
		inner = accent,
		innerHover = mix(accent, WHITE, 0.3),
		outer = HudStyle.DARK_RING,
		text = text,
		active = mix(accent, WHITE, 0.15), -- segmented toggle: the picked half
		activeText = CosmeticSets.buttonTextColor(mix(accent, WHITE, 0.15)),
	}
end

-- Round icon buttons: dark disc tinted by the set, accent ring, soft glow and a small diamond motif.
function HudStyle.iconPalette(colors)
	local accent, base = basics(colors)
	local disc = readableFill(mix(base, accent, 0.12), 0)
	local tint = mix(WHITE, accent, 0.5)
	if CosmeticSets.contrastRatio(tint, disc) < 4.5 then -- a light disc needs a darker icon
		local text = CosmeticSets.buttonTextColor(disc) -- always 4.5:1 on the disc
		tint = mix(text, accent, 0.25)
		if CosmeticSets.contrastRatio(tint, disc) < 4.5 then tint = text end
	end
	return {
		disc = disc,
		ring = accent,
		glow = mix(accent, WHITE, 0.25),
		motif = mix(accent, WHITE, 0.35),
		outer = HudStyle.DARK_RING,
		text = CosmeticSets.buttonTextColor(disc),
		tint = tint, -- multiplies the painted icon so it takes the set's hue
		tintHover = mix(tint, WHITE, 0.2),
	}
end

-- Draw pile: bracket accent, themed count plate and a count colour that reads on it.
function HudStyle.deckPalette(colors)
	local accent, base = basics(colors)
	local plate = readableFill(mix(base, BLACK, 0.25), 0)
	return {
		bracket = accent,
		plate = plate,
		plateRing = accent,
		text = CosmeticSets.buttonTextColor(plate),
	}
end

-- Left HUD panel (Client/SidebarTheme): paper surface, inset plates, header plate, score bar and ink, all derived from the
-- set's own paper, border and panel colours. nil for the neutral set so Classic Tavern keeps the painted parchment exactly.
-- Every ink reaches 4.5:1 on the paper and on the inset; the header text reaches it on the header plate.
function HudStyle.panelPalette(colors)
	if not colors then return nil end
	local accent = colors.border
	local paper = mix(colors.paper, accent, 0.1)
	local inset = mix(paper, BLACK, 0.08)
	local ink = mix(colors.panel, BLACK, 0.45)
	local steps = 0
	local padWorst = mix(paper, BLACK, 0.12) -- the label pad (12 percent see-through) over the darkest plate art
	while steps < 16 and (CosmeticSets.contrastRatio(ink, inset) < HudStyle.MIN_CONTRAST
		or CosmeticSets.contrastRatio(ink, padWorst) < HudStyle.MIN_CONTRAST
		or CosmeticSets.contrastRatio(ink, paper) < HudStyle.MIN_CONTRAST) do
		ink = mix(ink, BLACK, 0.2)
		steps = steps + 1
	end
	local header = readableFill(mix(colors.panel, BLACK, 0.3), 0)
	return {
		paper = paper,
		tag = mix(paper, WHITE, 0.15), -- small name tags
		inset = inset,
		edge = mix(accent, BLACK, 0.2), -- inset and ring strokes
		accent = accent,
		ink = ink,
		stroke = mix(paper, WHITE, 0.35), -- faint halo behind ink text
		header = header,
		headerGrainTop = mix(header, WHITE, 0.08),
		headerGrainBottom = mix(header, BLACK, 0.12),
		headerText = CosmeticSets.buttonTextColor(header),
		track = mix(colors.panel, BLACK, 0.25),
		fill = mix(accent, WHITE, 0.2),
		medallion = mix(inset, BLACK, 0.06),
		-- kit sets: solid dark plate under the round header text, soft parchment pad between a painted plate and its label
		headerPlate = { 20, 14, 8 }, headerPlateAlpha = 0.15, headerPlateText = { 250, 244, 226 },
		pad = paper, padAlpha = 0.12, padWorst = padWorst,
	}
end

local function hash(id)
	local h = 5381
	for i = 1, #tostring(id) do
		h = (h * 33 + string.byte(tostring(id), i)) % 2147483629
	end
	return h
end

-- Three card backs behind the pile top. Tilt (degrees) and offset (px) come from the set id, so every set has its own
-- stack and the look never changes between sessions. Returns { { rot, dx, dy } x3 }.
function HudStyle.pileLook(setId)
	local h = hash(setId or "classic_tavern")
	local out = {}
	local rots, dxs, dys = {}, {}, {}
	local seed = h % 2147483646 + 1
	local function nextInt(n)
		seed = (seed * 16807) % 2147483647 -- stays under 2^53, so Lua and Luau agree
		return math.floor(seed / 4096) % n
	end
	for i = 1, 3 do
		local rot = nextInt(13) - 6 -- -6 .. 6 degrees
		if rot == 0 then rot = (i % 2 == 0) and 2 or -2 end
		rots[i] = rot
		dxs[i] = nextInt(9) - 4 -- -4 .. 4 px
		dys[i] = 2 + nextInt(4) + (i - 1) -- 2 .. 8 px, lower cards peek further
	end
	for i = 1, 3 do
		out[i] = { rot = rots[i], dx = dxs[i], dy = dys[i] }
	end
	return out
end

-- Classic Tavern card frame: dark oak band on all four edges, a brass line just inside it, and small brass corner caps.
-- The band is BAND of the card WIDTH on every side (the same pixel width left, right, top and bottom).
HudStyle.CLASSIC_BAND = 0.07
HudStyle.CLASSIC_OAK = { 74, 46, 24 }
HudStyle.CLASSIC_OAK_LIGHT = { 104, 68, 36 }
HudStyle.CLASSIC_BRASS = { 214, 172, 88 }
HudStyle.CLASSIC_CAP = { 236, 200, 118 }

-- Rectangles in px relative to the card: { band = {top,bottom,left,right}, line = {top,bottom,left,right},
-- caps = {4 squares}, t = band px }. Each rect is { x, y, w, h }.
function HudStyle.classicFrame(w, h)
	local t = math.max(2, math.floor(w * HudStyle.CLASSIC_BAND + 0.5))
	local lt = math.max(1, math.floor(t * 0.22 + 0.5))
	local cap = math.floor(t * 1.7 + 0.5)
	local band = {
		top = { x = 0, y = 0, w = w, h = t },
		bottom = { x = 0, y = h - t, w = w, h = t },
		left = { x = 0, y = 0, w = t, h = h },
		right = { x = w - t, y = 0, w = t, h = h },
	}
	local ix, iy, iw, ih = t, t, w - 2 * t, h - 2 * t
	local line = {
		top = { x = ix, y = iy, w = iw, h = lt },
		bottom = { x = ix, y = iy + ih - lt, w = iw, h = lt },
		left = { x = ix, y = iy, w = lt, h = ih },
		right = { x = ix + iw - lt, y = iy, w = lt, h = ih },
	}
	local caps = {
		{ x = 0, y = 0, w = cap, h = cap }, { x = w - cap, y = 0, w = cap, h = cap },
		{ x = 0, y = h - cap, w = cap, h = cap }, { x = w - cap, y = h - cap, w = cap, h = cap },
	}
	return { t = t, band = band, line = line, caps = caps }
end

return HudStyle
