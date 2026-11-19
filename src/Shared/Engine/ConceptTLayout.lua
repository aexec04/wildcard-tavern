--[[
	Engine/ConceptTLayout.lua
	Pure, tested rectangles for the Concept T play screen (the painted tavern from claude/reference/concept_t/full_reference.png).
	Every rect is a fraction box of a 1536x1024 frame, so one function gives the live layout and the tests.
	Client/ConceptTPlay.lua is the only user.

	rects(w, h)     -> { name = {x, y, w, h} } in pixels (rounded), for a screen w x h
	frac            -> the raw fractions { name = {x0, y0, x1, y1} }
	fits(w, h)      -> true when the screen is wide enough for this layout (phones keep the old play screen)
	overlaps(rects) -> list of "a|b" pairs of rects that overlap (the tests expect none)
	tierFrame(rarity) -> frame colour name for a Patron rarity (used by the Patron cards task)
	frameRect(w, h) -> the largest centred 3:2 area of a screen; rectsIn(w, h) -> rects inside it (plus the frame) for odd viewports
	fan(i, n)       -> rotation (degrees, -12 to +12) and edge dip 0..1 of card i of n in the fanned hand
	textRect(rect, key) -> where the live number sits on a plate (clear of the baked icon)
	cleanValue(text)    -> one leading plus only ("++30" becomes "+30")
	progress(score, target) -> 0..1 fill of the round bar
]]

local M = {}

local function round(n) return math.floor(n + 0.5) end

M.REF_W, M.REF_H = 1536, 1024
M.MIN_W, M.MIN_H = 640, 360

M.frac = {
	coins = { 0.013, 0.027, 0.115, 0.092 },
	hands = { 0.116, 0.027, 0.211, 0.092 },
	round = { 0.375, 0.006, 0.621, 0.084 },
	gear = { 0.919, 0.012, 0.984, 0.107 },
	patrons = { 0.185, 0.162, 0.810, 0.404 },
	stage = { 0.350, 0.550, 0.650, 0.680 },
	hand = { 0.190, 0.700, 0.800, 0.875 }, -- the reference fan reaches y 0.91; the last 3.5 percent is tucked under the buttons, so the hand frame stops where they start
	play = { 0.300, 0.875, 0.530, 0.985 },
	discard = { 0.537, 0.882, 0.689, 0.980 },
	deck = { 0.806, 0.650, 0.978, 0.880 },
	deckCount = { 0.853, 0.865, 0.965, 0.925 },
}

-- the bar track inside the round banner (fractions of the banner itself)
M.barInBanner = { 0.20, 0.60, 0.80, 0.84 }

function M.fits(w, h)
	return (tonumber(w) or 0) >= M.MIN_W and (tonumber(h) or 0) >= M.MIN_H
end

function M.rects(w, h)
	local out = {}
	for name, f in pairs(M.frac) do
		local x0, y0, x1, y1 = round(f[1] * w), round(f[2] * h), round(f[3] * w), round(f[4] * h)
		out[name] = { x = x0, y = y0, w = x1 - x0, h = y1 - y0 }
	end
	return out
end

-- the bar track rect in pixels, inside the round banner
function M.bar(rects)
	local r, b = rects.round, M.barInBanner
	return {
		x = r.x + round(r.w * b[1]), y = r.y + round(r.h * b[2]),
		w = round(r.w * (b[3] - b[1])), h = round(r.h * (b[4] - b[2])),
	}
end

local function intersects(a, b)
	return a.x < b.x + b.w and b.x < a.x + a.w and a.y < b.y + b.h and b.y < a.y + a.h
end

-- the largest 3:2 area, centred (the reference scene and the pixel match are 3:2; the rest of a wider window is bars)
function M.frameRect(w, h)
	local fw, fh = w, math.floor(w * 2 / 3)
	if fh > h then fh = h; fw = math.floor(h * 3 / 2) end
	return { x = math.floor((w - fw) / 2), y = math.floor((h - fh) / 2), w = fw, h = fh }
end

function M.rectsIn(w, h)
	local f = M.frameRect(w, h)
	local r = M.rects(f.w, f.h)
	for _, rect in pairs(r) do rect.x = rect.x + f.x; rect.y = rect.y + f.y end
	return r, f
end

-- the fanned hand: cards overlap in a tight arc, left leans -12, right +12, the middle stands highest
M.FAN = { deg = 12, dipFrac = 0.022, tuckFrac = 0.006 }

function M.fan(i, n)
	if n <= 1 then return 0, 0 end
	local t = ((i - 1) / (n - 1)) * 2 - 1
	return t * M.FAN.deg, t * t
end

-- PlayMotion.FAN numbers for a screen of height h (the real hand uses the same arc as the reference scene)
function M.fanProfile(h)
	return { deg = M.FAN.deg, dip = round(h * M.FAN.dipFrac), tuck = round(h * M.FAN.tuckFrac), endScale = 1 }
end

-- where the live number goes on a plate, as fractions of the plate (right of the coin or hand icon, centred in what is left)
M.textBox = {
	coins = { 0.36, 0.06, 0.94, 0.94 }, hands = { 0.36, 0.06, 0.94, 0.94 },
	round = { 0.10, 0.04, 0.90, 0.54 }, deckCount = { 0.06, 0.06, 0.94, 0.94 },
}

function M.textRect(rect, key)
	local b = M.textBox[key] or { 0, 0, 1, 1 }
	return {
		x = rect.x + round(rect.w * b[1]), y = rect.y + round(rect.h * b[2]),
		w = round(rect.w * (b[3] - b[1])), h = round(rect.h * (b[4] - b[2])),
	}
end

-- an effect value shows exactly one leading plus
function M.cleanValue(text)
	text = tostring(text or "")
	return (text:gsub("^%++", function(p) return #p > 0 and "+" or "" end))
end

-- the count plate hangs on the bottom of the deck pile on purpose
M.ALLOWED = { ["deck|deckCount"] = true }

function M.overlaps(rects)
	local names = {}
	for name in pairs(rects) do names[#names + 1] = name end
	table.sort(names)
	local out = {}
	for i = 1, #names do
		for j = i + 1, #names do
			local key = names[i] .. "|" .. names[j]
			if intersects(rects[names[i]], rects[names[j]]) and not M.ALLOWED[key] then out[#out + 1] = key end
		end
	end
	return out
end

function M.progress(score, target)
	score, target = tonumber(score) or 0, tonumber(target) or 0
	if target <= 0 then return 0 end
	return math.max(0, math.min(1, score / target))
end

-- rarity (Patrons.lua names) -> the frame colour and the pill colour the concept uses
M.TIERS = {
	Common = { frame = "bronze", pill = "green" },
	Uncommon = { frame = "green", pill = "green" },
	Rare = { frame = "blue", pill = "blue" },
	Epic = { frame = "purple", pill = "purple" },
	Legendary = { frame = "gold", pill = "gold" },
}

local function norm(rarity)
	rarity = tostring(rarity or ""):lower()
	return rarity:sub(1, 1):upper() .. rarity:sub(2)
end

-- tier names arrive as "common" (CollectionBook) or "Common" (Patrons): both work
function M.tierFrame(rarity)
	local t = M.TIERS[norm(rarity)]
	return t and t.frame or "bronze"
end

-- Image keys in ConceptTArt for the rarity label pill and the effect pill under a Patron card
function M.labelKey(rarity)
	return "ct_label_" .. (M.TIERS[norm(rarity)] and norm(rarity):lower() or "common")
end

-- the pill with its number painted out (the game draws the live value on it)
function M.blankPillKey(rarity)
	return M.pillKey(rarity) .. "_blank"
end

function M.pillKey(rarity)
	local t = M.TIERS[norm(rarity)]
	return "ct_pill_" .. (t and t.pill or "green")
end

return M
