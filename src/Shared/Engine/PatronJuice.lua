--[[
	Engine/PatronJuice.lua
	Gameplay v2: what a Patron's trigger looks like, by tier. Pure numbers, tested. Client/PatronJuiceFX draws it on the shared
	FxLoop heartbeat (no per particle tweens). Presentation only, it never changes a score.

	  Common      6 px hop and a cream floating pill
	  Uncommon    adds a green ring pulse
	  Rare        adds a blue glow sweep across the frame
	  Epic        adds purple sparks (6 particles) and a short crown flash
	  Legendary   adds gold rays for 0.5 s and a soft glow on the screen edge

	tierOf(rarity)               -> "common".."legendary" (anything above Legendary reads as Legendary, unknown as Common)
	spec(tier, calm, fast)       -> { hop, ring, sweep, sparks, crown, rays, edge, dur, pill = { rise, dur } }; calm (Calm mode or
	                                Reduce motion) keeps only the pill text, with rise 0 and no effect; fast halves every duration
	pillText(kind, amount)       -> "+N Chips", "+N Mult", "xN" (kind chips | mult | xmult); "" when it cannot be said
	order(ownedIds, firedIds)    -> the fired ids in Patron row order (left to right)
	delayOf(index)               -> seconds after the first beat for the index-th fired Patron, 0.12 apart
	particle(i, n, p)            -> x, y offsets in 0..1 of the card for spark i of n at progress p (0..1), a gentle rise
]]

local M = {}

M.SPACING = 0.12
M.PILL_RISE, M.PILL_DUR = 24, 0.6

local ORDER = { common = 1, uncommon = 2, rare = 3, epic = 4, legendary = 5 }

function M.tierOf(rarity)
	local r = tostring(rarity or ""):lower()
	if ORDER[r] then return r end
	if r == "mythical" or r == "mythic" then return "legendary" end
	return "common"
end

function M.rank(tier) return ORDER[M.tierOf(tier)] end

function M.spec(tier, calm, fast)
	local t = M.tierOf(tier)
	local n = ORDER[t]
	if calm then
		return { hop = 0, ring = 0, sweep = 0, sparks = 0, crown = 0, rays = 0, edge = 0, dur = 0, static = true,
			pill = { rise = 0, dur = 0.4 } }
	end
	local k = fast and 0.5 or 1
	return {
		hop = 6 * (n >= 1 and 1 or 0),
		ring = n >= 2 and 0.3 * k or 0,
		sweep = n >= 3 and 0.4 * k or 0,
		sparks = n >= 4 and 6 or 0,
		crown = n >= 4 and 0.2 * k or 0,
		rays = n >= 5 and 0.5 * k or 0,
		edge = n >= 5 and 0.5 * k or 0,
		dur = (n >= 5 and 0.5 or n >= 4 and 0.5 or n >= 3 and 0.4 or n >= 2 and 0.3 or 0.2) * k,
		static = false,
		pill = { rise = M.PILL_RISE, dur = M.PILL_DUR * k },
	}
end

local function num(n)
	n = tonumber(n)
	if not n then return nil end
	n = math.floor(n * 100 + 0.5) / 100
	if n == math.floor(n) then return string.format("%d", math.floor(n)) end
	return string.format("%.2f", n):gsub("0+$", "")
end

function M.pillText(kind, amount)
	local s = num(amount)
	if not s then return "" end
	if kind == "chips" then return "+" .. s .. " Chips" end
	if kind == "mult" then return "+" .. s .. " Mult" end
	if kind == "xmult" then return "x" .. s end
	if kind == "money" then return "+$" .. s end
	return ""
end

function M.order(ownedIds, firedIds)
	local fired = {}
	for _, id in ipairs(firedIds or {}) do fired[id] = true end
	local out = {}
	for _, id in ipairs(ownedIds or {}) do
		if fired[id] then out[#out + 1] = id end
	end
	return out
end

function M.delayOf(index)
	return math.max(0, (index or 1) - 1) * M.SPACING
end

function M.particle(i, n, p)
	p = math.max(0, math.min(1, p or 0))
	local x = (i - 0.5) / math.max(1, n) + 0.06 * math.sin(i * 2.1 + p * 4)
	local y = 0.8 - 0.7 * p
	return x, y
end

-- The trigger effect never grows past 1.2x of the seat card and stays inside the band under the top bar and above the Score plate.
-- slot = { x, y, w, h } the seat card; limits = { top, bottom } root pixels. Returns { x, y, w, h }.
M.POP_SCALE = 1.2
function M.popBox(slot, limits)
	local w, h = slot.w * M.POP_SCALE, slot.h * M.POP_SCALE
	local x, y = slot.x + slot.w / 2 - w / 2, slot.y + slot.h / 2 - h / 2
	if limits then
		h = math.min(h, limits.bottom - limits.top)
		y = math.max(limits.top, math.min(y, limits.bottom - h))
	end
	return { x = x, y = y, w = w, h = h }
end

-- ray length as a share of the card height: a ray from the centre ends inside the pop box (half of 1.2 = 0.6)
M.RAY_LEN = 0.5

-- The ray length (share of the card height) that keeps the widest ray (75 degrees off vertical) inside POP_SCALE times the seat
-- width and the tallest inside the seat's own height, so a Legendary pop never grows past 1.2x of the seat or over the top bar.
function M.rayLen(w, h)
	local side = math.sin(math.rad(75))
	return math.min(M.RAY_LEN, (M.POP_SCALE * w / 2) / (math.max(1, h) * side))
end

return M
