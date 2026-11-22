--[[
	SetProgress.lua
	How much of one Card Set a player owns, shown as a small ring on the set's tile in the Card Sets room (Client/CardSetsRoom.lua).
	A set has two pieces: the set itself and its card back. Pure data and functions (needs only the two registries passed in), so tests can
	run them over all 14 sets. The ring is a circle of small ticks, lit in the set accent for the share owned; it is drawn still, so Calm
	mode and Reduce motion need nothing extra.

	count(set, cosmetics, CardBacks) -> owned, total
	ticks(owned, total) -> lit, TICKS
	tick(i, d) -> { x, y, w, h, rotation }   rect of tick i (1..TICKS) inside a d by d square, rotation in degrees
	colors(setId, CosmeticSets) -> { lit = {r,g,b}, unlit = {r,g,b} }   lit is 4.5:1 or better on BACKING
	line(owned, total) -> "Owned 1 of 2" style text for the tooltip
	diameter(picH) -> ring size in pixels for a tile picture of that height, or nil when it would not fit
]]

local SetProgress = {}

SetProgress.TICKS = 12
SetProgress.TICK_LEN = 6
SetProgress.TICK_W = 3
SetProgress.MAX_D = 34
SetProgress.MIN_D = 22
SetProgress.BACKING = { 20, 14, 10 } -- the dark disc under the ring
SetProgress.UNLIT = { 96, 78, 58 } -- an unowned tick: dim wood, still visible on the disc
SetProgress.CLASSIC = { 222, 182, 104 } -- classic brass

local function whole(n)
	return math.max(0, math.floor(tonumber(n) or 0))
end

local function has(list, id)
	for _, v in ipairs(list or {}) do
		if v == id then return true end
	end
	return false
end

-- How many of the set's two pieces the player has. `cosmetics` is state.cosmetics: { unlockedSetIds, unlockedCardBackIds }.
function SetProgress.count(set, cosmetics, CardBacks)
	if type(set) ~= "table" then return 0, 2 end
	cosmetics = cosmetics or {}
	local owned = 0
	local setOwned = set.id == "classic_tavern" or has(cosmetics.unlockedSetIds, set.id)
	if setOwned then owned = owned + 1 end
	local backId = set.cardBackId
	local back = backId and CardBacks and CardBacks.getById(backId) or nil
	local backOwned = backId == nil
		or (CardBacks ~= nil and backId == CardBacks.DefaultId)
		or has(cosmetics.unlockedCardBackIds, backId)
		or (setOwned and back ~= nil and back.setOnly == true)
	if backOwned then owned = owned + 1 end
	return owned, 2
end

function SetProgress.ticks(owned, total)
	total = math.max(1, whole(total))
	owned = math.min(whole(owned), total)
	return math.floor(owned / total * SetProgress.TICKS + 0.5), SetProgress.TICKS
end

-- Tick i sits on a circle of diameter d, pointing outward, the first at twelve o'clock and going clockwise.
function SetProgress.tick(i, d)
	local n = SetProgress.TICKS
	local angle = (i - 1) / n * 2 * math.pi
	local radius = d / 2 - SetProgress.TICK_LEN / 2
	local cx = d / 2 + radius * math.sin(angle)
	local cy = d / 2 - radius * math.cos(angle)
	return {
		x = cx - SetProgress.TICK_W / 2,
		y = cy - SetProgress.TICK_LEN / 2,
		w = SetProgress.TICK_W,
		h = SetProgress.TICK_LEN,
		rotation = math.floor(angle * 180 / math.pi + 0.5),
	}
end

local function mix(a, b, t)
	return {
		math.floor(a[1] + (b[1] - a[1]) * t + 0.5),
		math.floor(a[2] + (b[2] - a[2]) * t + 0.5),
		math.floor(a[3] + (b[3] - a[3]) * t + 0.5),
	}
end

function SetProgress.colors(setId, CosmeticSets)
	local base = CosmeticSets and CosmeticSets.ringColorOf(setId) or nil
	local lit = base or SetProgress.CLASSIC
	local guard = 0
	while CosmeticSets.contrastRatio(lit, SetProgress.BACKING) < 4.5 and guard < 30 do
		lit = mix(lit, { 255, 255, 255 }, 0.15)
		guard = guard + 1
	end
	return { lit = lit, unlit = SetProgress.UNLIT }
end

function SetProgress.line(owned, total)
	if whole(owned) >= whole(total) then
		return "You own every piece of this set"
	end
	return "Owned " .. whole(owned) .. " of " .. whole(total) .. " pieces: the set and its card back"
end

-- The ring only appears when the tile picture can hold it with 5 px to spare on each side.
function SetProgress.diameter(picH)
	local d = math.min(SetProgress.MAX_D, math.floor((tonumber(picH) or 0) - 10))
	if d < SetProgress.MIN_D then return nil end
	return d
end

return SetProgress
