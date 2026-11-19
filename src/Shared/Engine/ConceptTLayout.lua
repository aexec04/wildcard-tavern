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
M.MIN_TOUCH = 44 -- smallest button height in px (phone landscape 844 x 390 and the like)

M.frac = {
	coins = { 0.013, 0.027, 0.115, 0.092 },
	hands = { 0.116, 0.027, 0.211, 0.092 },
	round = { 0.375, 0.006, 0.621, 0.084 },
	gear = { 0.919, 0.012, 0.984, 0.107 },
	patrons = { 0.185, 0.162, 0.810, 0.404 },
	stage = { 0.358, 0.553, 0.673, 0.675 }, -- pass 6 align report: centre moved right 24 px and down 27 px of 1536 x 1024, about 5 percent larger; the ring now overlaps the top of the hand on purpose (ALLOWED)
	hand = { 0.183, 0.658, 0.768, 0.848 }, -- pass 6: fan 18 px left and 3 px up, cards (sized from the frame height) about 5 percent smaller; -- raised 25 px in pass 5 so the cards end above the buttons; measured from the reference: card centres x 375 to 1120, middle card bottoms at 0.874, the outer cards dip to about 0.908 and overlap the button row a little, as in the reference
	play = { 0.300, 0.875, 0.530, 0.985 },
	discard = { 0.537, 0.882, 0.689, 0.980 },
	deck = { 0.790, 0.630, 0.990, 0.940 }, -- the ct_deck_a cut canvas (307 x 317) at its reference origin (1213, 645), so the book is its full reference size (about 261 x 230 of the frame)
	deckCount = { 0.853, 0.865, 0.965, 0.925 },
}

-- The five Patron cards of the reference: each about 0.112 x 0.236 of the frame, centred on the label pill under it
-- (card centres measured from full_reference.png: 374, 568, 760, 953, 1146 of 1536). The label pill and the effect pill hang tight under the card.
M.patronCard = { w = 0.112, h = 0.236, y = 0.166, centers = { 0.2435, 0.3698, 0.4948, 0.6204, 0.7461 } }
M.patronLabel = { w = 0.082, h = 0.036, y = 0.405 }
M.patronPill = { w = 0.082, h = 0.046, y = 0.444 }

-- pixel rects { card, label, pill } for n (up to 5) Patron slots in a w x h frame, in the order of the reference
function M.patronSlots(w, h, n)
	local out = {}
	for i = 1, math.min(n or 5, #M.patronCard.centers) do
		local cx = M.patronCard.centers[i] * w
		local function box(wFrac, y, hFrac)
			return { x = round(cx - wFrac * w / 2), y = round(y * h), w = round(wFrac * w), h = round(hFrac * h) }
		end
		out[i] = {
			card = box(M.patronCard.w, M.patronCard.y, M.patronCard.h),
			label = box(M.patronLabel.w, M.patronLabel.y, M.patronLabel.h),
			pill = box(M.patronPill.w, M.patronPill.y, M.patronPill.h),
		}
	end
	return out
end

-- the bar track inside the round banner (fractions of the banner itself)
-- the banner title is a warm cream serif (Merriweather bold), smaller than the HUD numbers: ROUND_TEXT
M.ROUND_TEXT = { r = 255, g = 240, b = 205 }
M.barInBanner = { 0.125, 0.545, 0.875, 0.80 } -- the reference track spans about 0.11 to 0.89 of the banner width

function M.fits(w, h)
	return (tonumber(w) or 0) >= M.MIN_W and (tonumber(h) or 0) >= M.MIN_H
end

function M.rects(w, h)
	local out = {}
	for name, f in pairs(M.frac) do
		local x0, y0, x1, y1 = round(f[1] * w), round(f[2] * h), round(f[3] * w), round(f[4] * h)
		out[name] = { x = x0, y = y0, w = x1 - x0, h = y1 - y0 }
	end
	-- touch targets: Play Hand and Discard are at least MIN_TOUCH px tall on short screens (they grow down toward the screen edge)
	for _, name in ipairs({ "play", "discard" }) do
		local b = out[name]
		if b.h < M.MIN_TOUCH then b.h = math.min(M.MIN_TOUCH, h - b.y) end
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
M.FAN = { deg = 11, dipFrac = 0.028, tuckFrac = 0.006 }

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

-- HUD text sizes as a fraction of the frame height, so the numbers fill their plates like the reference (about 28 px at 1024 high);
-- never under 15 px
M.TEXT_FRAC = { coins = 0.027, hands = 0.027, round = 0.027, deckCount = 0.028, pill = 0.028 }

function M.textSize(key, frameH)
	local f = M.TEXT_FRAC[key] or 0.02
	return math.max(15, round((tonumber(frameH) or M.REF_H) * f))
end

-- an effect value shows exactly one leading plus
function M.cleanValue(text)
	text = tostring(text or "")
	return (text:gsub("^%++", function(p) return #p > 0 and "+" or "" end))
end

-- the count plate hangs on the bottom of the deck pile on purpose
M.ALLOWED = { ["deck|deckCount"] = true, ["hand|stage"] = true } -- the glow ring is drawn in front of the top of the hand, as in the reference

-- scene stage text and ring centres (fractions of the frame height), moved with the stage rect in pass 6; STAGE_SCALE sizes the type and ring
M.STAGE_Y = { name = 0.5976, total = 0.6566, ring = 0.6724 }
M.STAGE_SCALE = 1.05
M.HAND_CARD_W = 0.0817 -- scene card width as a fraction of the frame width (0.086 before pass 6)

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
