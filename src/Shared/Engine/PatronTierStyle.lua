--[[
	Engine/PatronTierStyle.lua
	Gameplay v2 Patron cards: a Patron's power is readable at a glance, in SHAPE and size, not only colour (it must read in
	greyscale). One table per tier, pure data and small helpers so Client/PatronTierFX, Gameplay2Layout and the tests agree.

	style(tier)                    -> the tier's table (tier is "common".."legendary", any case; unknown reads as common)
	frameRect(tier, w, h)          -> { x, y, w, h } of the tier frame relative to a w x h card slot; it grows UP (and out for Legendary),
	                                  so a taller card never moves its neighbours
	discDiameter(w)                -> the gold power disc, bottom centre, half of it hangs below the card
	numeral(valueText)             -> the big power number text: one plus at most, "" when there is none
	distinct()                     -> true when every tier differs in frame shape and size
	collisions(patrons)            -> list of "tier|portraitKey" groups shared by two Patrons (needs portraitKey on each entry)
	Animation is driven by the shared FxLoop heartbeat (Client/PatronTierFX), static in Calm mode and Reduce motion.
]]

local M = {}

M.ORDER = { "common", "uncommon", "rare", "epic", "legendary" }

-- shape: the silhouette of the frame; grow: extra size as a fraction of the card (taller grows upward)
-- pulse / shimmer / float are seconds or pixels (0 = none); sparks and rays are counts
M.TIERS = {
	common = { shape = "plain", rgb = { 58, 38, 20 }, trimRgb = nil, thickness = 4, gem = nil, coverGem = true, growW = 0, growH = 0, glow = 0, pulse = 0,
		studs = 0, crown = false, halo = false, sparks = 0, rays = 0, float = 0, shimmer = 0, breakOut = 0, tint = { 196, 192, 186 } }, -- about 25 percent toward grey
	uncommon = { shape = "trim", rgb = { 120, 150, 120 }, trimRgb = { 190, 210, 190 }, thickness = 3, gem = { 70, 190, 100 }, growW = 0, growH = 0, glow = 0.25, pulse = 0,
		studs = 0, crown = false, halo = false, sparks = 0, rays = 0, float = 0, shimmer = 0, breakOut = 0, tint = { 255, 255, 255 } },
	rare = { shape = "studs", rgb = { 70, 110, 170 }, trimRgb = { 150, 180, 220 }, thickness = 4, growW = 0, growH = 0, glow = 0.35, pulse = 3,
		studs = 4, crown = false, halo = false, sparks = 0, rays = 0, float = 0, shimmer = 0, breakOut = 0, tint = { 255, 255, 255 } },
	epic = { shape = "crown", rgb = { 120, 70, 160 }, trimRgb = { 230, 190, 90 }, thickness = 4, growW = 0, growH = 0.06, glow = 0.4, pulse = 0,
		studs = 0, crown = true, halo = true, sparks = 4, rays = 0, float = 0, shimmer = 0, breakOut = 0, tint = { 255, 255, 255 } },
	legendary = { shape = "full", rgb = { 235, 190, 70 }, trimRgb = { 255, 230, 140 }, thickness = 6, growW = 0.12, growH = 0.12, glow = 0.5, pulse = 0,
		studs = 0, crown = false, halo = true, sparks = 3, rays = 8, float = 4, shimmer = 5, breakOut = 0.06, tint = { 255, 255, 255 } },
}

-- the power disc: bronze gold fill so the cream numeral is 4.5:1 or better, a bright gold ring, a dark outline on the numeral
M.DISC = { fill = { 130, 88, 18 }, ring = { 246, 196, 70 }, text = { 250, 240, 220 }, outline = { 30, 18, 8 } }

local function norm(tier)
	tier = tostring(tier or ""):lower()
	return M.TIERS[tier] and tier or "common"
end

function M.style(tier) return M.TIERS[norm(tier)] end

-- the tiny corner icon on a seat: one capital letter on a tier coloured chip, so rarity is never colour alone
M.LETTERS = { common = "C", uncommon = "U", rare = "R", epic = "E", legendary = "L" }
function M.letter(tier) return M.LETTERS[norm(tier)] end
M.CORNER_ICON = 18 -- chip size in px, the letter is 14 px

local function round(n) return math.floor(n + 0.5) end

function M.frameRect(tier, w, h)
	local s = M.style(tier)
	local gw, gh = round(w * s.growW), round(h * s.growH)
	-- wider tiers grow half each side; every tier grows upward from the bottom edge, never down
	return { x = -math.floor(gw / 2), y = -gh, w = w + gw, h = h + gh }
end

-- the power disc scales with the card: 48 px on a roomy card (140 px wide, 1920x1080), 40 px from 70 px, 28 px on very narrow
-- cards, in the card's bottom right corner, 40 percent of it outside the frame
M.DISC_SIZE, M.DISC_BIG, M.DISC_OVERLAP = 40, 48, 0.5
M.DISC_TINY_FROM, M.DISC_TINY = 62, 22
M.DISC_OVERLAP_X = 0.5 -- the disc overlaps the card's bottom right corner by half in both directions, as in the reference
function M.discDiameter(w)
	w = tonumber(w) or 0
	if w >= 140 then return M.DISC_BIG end
	if w >= 70 then return M.DISC_SIZE end
	return w >= M.DISC_TINY_FROM and M.DISC_TINY or 28 -- the 66 px seats of 800x450 take a 22 px coin so a 9 px name keeps its 6 px gap
end

-- Bottom right corner of the card: half of the disc inside the frame, half outside (right and below).
function M.discRect(w, h)
	local d = M.discDiameter(w)
	local out = math.floor(d * M.DISC_OVERLAP + 0.5)
	local outX = math.floor(d * M.DISC_OVERLAP_X + 0.5)
	return { x = w - d + outX, y = h - d + out, w = d, h = d }
end

-- Height under the card that the disc's overhang owns; the rarity label starts under it
M.DISC_BAND = 0.5 -- the label rows start under the disc, which overhangs by half
function M.discBand(w) return math.floor(M.discDiameter(w) * M.DISC_BAND + 0.5) + 2 end

function M.unitText(valueText)
	local t = tostring(valueText or ""):gsub("^%s+", ""):gsub("%s+$", "")
	local rest = t:match("^[%+%-xX]?%d[%d%.,]*%%?%s+(.+)$")
	return rest or t
end

-- the figure only ("+4", "x1.1", "+15", "+100"), never the unit word: "+1 Chips" -> "+1". At most 5 characters so it always fits the disc.
M.NUMERAL_MAX = 5
function M.numeral(valueText)
	local t = tostring(valueText or ""):gsub("^%s+", ""):gsub("%s+$", "")
	if t == "" then return "" end
	t = t:gsub("^%++", "+")
	local figure = t:match("^[%+%-xX]?%d[%d%.,]*%%?")
	if figure then t = figure end
	if #t > M.NUMERAL_MAX then t = t:sub(1, M.NUMERAL_MAX) end
	return t
end

-- tiers differ in frame shape AND in size or ornament count, so no two read the same in greyscale
function M.distinct()
	local seen = {}
	for _, name in ipairs(M.ORDER) do
		local s = M.TIERS[name]
		if seen[s.shape] then return false end
		seen[s.shape] = true
	end
	local sizes = {}
	for _, name in ipairs(M.ORDER) do
		local s = M.TIERS[name]
		local sig = table.concat({ s.growW, s.growH, s.studs, s.rays, s.sparks, s.crown and 1 or 0, s.thickness }, ",")
		if sizes[sig] then return false end
		sizes[sig] = true
	end
	return true
end

-- Data check: two Patrons of one tier must not share a dominant portrait colour and pose tag. The registry has no portraitKey yet
-- (it is "<dominant colour>:<pose>" filled by an art review), so entries without one are skipped and reported by the caller.
function M.collisions(patrons)
	local groups, out = {}, {}
	for _, p in ipairs(patrons or {}) do
		if p.portraitKey then
			local key = norm(p.tier) .. "|" .. p.portraitKey
			groups[key] = (groups[key] or 0) + 1
			if groups[key] == 2 then out[#out + 1] = key end
		end
	end
	table.sort(out)
	return out
end

return M
